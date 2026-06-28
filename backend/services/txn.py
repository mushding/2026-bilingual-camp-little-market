"""金流核心（atomic）— docs/app/31 §2。

每個 endpoint handler 自己開 `with SessionLocal.begin()`，呼叫這裡的 helper。
所有單學生交易回 StudentState。
"""
import json
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.orm import object_session

from constants import (GAMES, MAIL_KP, TASK_TIMEOUT_MIN, TIER_MAP, WITNESS_KP)
from models import GameState, GuildTask, Student, Transaction, WitnessLog
from schemas import StudentState


def pending_tasks_of(session, uid: str) -> list[dict]:
    """該生目前 pending 公會任務 + 倒數秒數（給學員卡顯示）。"""
    if session is None:
        return []
    rows = session.scalars(select(GuildTask).where(
        GuildTask.uid == uid, GuildTask.status == "pending")).all()
    out = []
    now = datetime.now(timezone.utc)
    for t in rows:
        try:
            drawn = datetime.fromisoformat(t.drawn_at)
        except (ValueError, TypeError):
            drawn = now
        remaining = TASK_TIMEOUT_MIN * 60 - int((now - drawn).total_seconds())
        name = GAMES.get(t.game_key, (t.game_key,))[0]
        out.append({"game_key": t.game_key, "game_name": name,
                    "reward": t.reward, "remaining_seconds": max(remaining, 0)})
    return out


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def get_state(session) -> GameState:
    return session.get(GameState, 1)


def state_to_out(s: Student, stall: str, action: str, message: str,
                 ok: bool = True, assigned_game: str | None = None) -> StudentState:
    sess = object_session(s)
    return StudentState(
        uid=s.uid, student_name=s.name, group=s.group or "",
        balance=s.balance, points=s.points,
        kingdom_points=s.kingdom_points, deposit_balance=s.deposit_balance,
        stall=stall, action=action, message=message, ok=ok, assigned_game=assigned_game,
        pending_tasks=pending_tasks_of(sess, s.uid),
    )


def err(stall: str, action: str, message: str) -> StudentState:
    # 學生不存在等：回最小 ok=false
    return StudentState(uid="", student_name="", balance=0, points=0,
                        kingdom_points=0, deposit_balance=0, stall=stall,
                        action=action, message=message, ok=False)


def lock_student(session, uid: str) -> Student | None:
    """行級鎖（Postgres FOR UPDATE；SQLite 由寫鎖序列化）。"""
    stmt = select(Student).where(Student.uid == uid)
    if session.bind.dialect.name != "sqlite":
        stmt = stmt.with_for_update()
    return session.scalars(stmt).first()


def write_txn(session, s: Student, stall: str, action: str, amount: int,
              day: str, meta: dict | None = None):
    session.add(Transaction(
        uid=s.uid, stall_id=stall, action=action, amount=amount,
        balance_after=s.balance, points_after=s.points,
        kp_after=s.kingdom_points, deposit_after=s.deposit_balance,
        day=day, meta=json.dumps(meta or {}, ensure_ascii=False), created_at=now_iso(),
    ))


# 需要 market_open 的 action（mail_kp 不需要 — 核銷可在關市後整理）
NEEDS_MARKET = {"debit", "meal", "credit", "game_settle", "deposit", "withdraw",
                "donate", "exchange_points", "guild_draw"}


def handle_scan(session, req) -> StudentState:
    """POST /api/scan 主入口。req: ScanReq。整段已在 session.begin() 內。"""
    st = get_state(session)
    day = st.current_day
    s = lock_student(session, req.uid)
    if s is None:
        return err(req.stall_id, req.action, "查無此卡")

    # 每次掃卡先掃描該生逾時的公會任務（逾時 −20、作廢）
    from services.guild import sweep_expired
    sweep_expired(session, s, day)

    if req.action in NEEDS_MARKET and not st.market_open:
        return state_to_out(s, req.stall_id, req.action, "市場已關閉，僅能查詢", ok=False)

    a = req.action

    if a == "lookup":
        return state_to_out(s, req.stall_id, a, "查詢成功")

    if a in ("debit", "meal"):
        if req.amount <= 0:
            return state_to_out(s, req.stall_id, a, "金額需 > 0", ok=False)
        if s.balance < req.amount:
            return state_to_out(s, req.stall_id, a, f"餘額不足（需 ${req.amount}，有 ${s.balance}）", ok=False)
        s.balance -= req.amount
        write_txn(session, s, req.stall_id, a, -req.amount, day)
        label = "付餐費" if a == "meal" else "付款"
        return state_to_out(s, req.stall_id, a, f"學員{label} ${req.amount}")

    if a == "credit":
        if req.amount <= 0:
            return state_to_out(s, req.stall_id, a, "金額需 > 0", ok=False)
        s.balance += req.amount
        write_txn(session, s, req.stall_id, a, req.amount, day)
        return state_to_out(s, req.stall_id, a, f"學員入帳 ${req.amount}")

    if a == "game_settle":
        cost, reward = req.cost, req.reward
        if cost < 0 or reward < 0:
            return state_to_out(s, req.stall_id, a, "cost/reward 不可為負", ok=False)
        if s.balance < cost:
            return state_to_out(s, req.stall_id, a, f"餘額不足（需 ${cost}）", ok=False)
        s.balance += (reward - cost)
        write_txn(session, s, req.stall_id, a, reward - cost, day,
                  {"cost": cost, "reward": reward})
        return state_to_out(s, req.stall_id, a,
                            f"收門票 ${cost}，學員賺 ${reward}" if reward
                            else f"收門票 ${cost}，學員沒中")

    if a == "deposit":
        if req.amount <= 0 or s.balance < req.amount:
            return state_to_out(s, req.stall_id, a, "餘額不足或金額無效", ok=False)
        s.balance -= req.amount
        s.deposit_balance += req.amount
        write_txn(session, s, req.stall_id, a, -req.amount, day)
        return state_to_out(s, req.stall_id, a, f"學員定存 ${req.amount}")

    if a == "withdraw":
        amt = s.deposit_balance if req.amount == -1 else req.amount
        if amt <= 0 or s.deposit_balance < amt:
            return state_to_out(s, req.stall_id, a, "定存不足或金額無效", ok=False)
        s.deposit_balance -= amt
        s.balance += amt
        write_txn(session, s, req.stall_id, a, amt, day)
        return state_to_out(s, req.stall_id, a, f"學員提領本利 ${amt}")

    if a == "credit_kp":  # 聽見證 +100，去重
        if not req.staff_uid:
            return state_to_out(s, req.stall_id, a, "缺 staff_uid", ok=False)
        dup = session.scalars(select(WitnessLog).where(
            WitnessLog.student_uid == s.uid, WitnessLog.staff_uid == req.staff_uid)).first()
        if dup:
            return state_to_out(s, req.stall_id, a, "此同工已給過見證點數", ok=False)
        s.kingdom_points += WITNESS_KP
        session.add(WitnessLog(student_uid=s.uid, staff_uid=req.staff_uid, day=day))
        write_txn(session, s, req.stall_id, a, WITNESS_KP, day, {"staff_uid": req.staff_uid})
        return state_to_out(s, req.stall_id, a, f"學員聽見證 +{WITNESS_KP} 天國點數")

    if a == "donate":  # 二三天同一套：1:1 轉 KP，無 D3 bonus
        if req.amount < 50:
            return state_to_out(s, req.stall_id, a, "奉獻下限 50", ok=False)
        if s.balance < req.amount:
            return state_to_out(s, req.stall_id, a, "餘額不足", ok=False)
        s.balance -= req.amount
        s.kingdom_points += req.amount
        write_txn(session, s, req.stall_id, a, -req.amount, day, {"kp": req.amount})
        return state_to_out(s, req.stall_id, a, f"學員奉獻 ${req.amount} → +{req.amount} KP")

    if a == "exchange_points":
        tier = req.tier
        if tier not in TIER_MAP:
            return state_to_out(s, req.stall_id, a, "兌換檔位無效", ok=False)
        if s.balance < tier:
            return state_to_out(s, req.stall_id, a, "餘額不足", ok=False)
        s.balance -= tier
        gained = TIER_MAP[tier]
        s.points += gained
        write_txn(session, s, req.stall_id, a, -tier, day, {"tier": tier, "points": gained})
        return state_to_out(s, req.stall_id, a, f"學員兌換 ${tier} → +{gained} 積分")

    if a == "mail_kp":  # 郵政感謝卡核銷，加給寄件人（不限張數，market 不需開）
        n = req.cards
        if n < 1:
            return state_to_out(s, req.stall_id, a, "卡數需 ≥ 1", ok=False)
        gained = MAIL_KP * n
        s.card_count += n
        s.kingdom_points += gained
        write_txn(session, s, req.stall_id, a, gained, day, {"cards": n})
        return state_to_out(s, req.stall_id, a, f"登記成功：{n} 張感謝卡 → +{gained} KP")

    if a == "guild_draw":
        from services.guild import draw  # 延遲匯入避免循環
        return draw(session, s, day)

    return state_to_out(s, req.stall_id, a, f"未知 action: {a}", ok=False)
