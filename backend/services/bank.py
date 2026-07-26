"""銀行利息與市場關閉 / 全域狀態 — docs/app/31 §5（管理操作）。"""
import json
import math
from datetime import datetime, timezone

from sqlalchemy import delete, select

from constants import DEPOSIT_RATE, MARKET_CLOSE_RATE, MAX_SETTLEMENTS, TASK_TIMEOUT_MIN
from models import (CasinoBet, CasinoRound, GameState, GuildTask, Student,
                    Transaction, WitnessLog)
from services.txn import get_state, lock_student, write_txn


def set_day(session, day: str) -> dict:
    if day not in ("D1", "D2", "D3"):
        return {"ok": False, "message": "day 需 D1/D2/D3"}
    st = get_state(session)
    st.current_day = day
    # 換日 = 新的一場開始：自動重新開市（最終關市後除外）、清 5 分鐘提醒
    if not st.final_closed:
        st.market_open = 1
    st.closing_soon = 0
    return {"ok": True, "current_day": day, "market_open": bool(st.market_open)}


def day_close(session) -> dict:
    """當日截止：凍結交易（不折現、不算名次），換日或按「重新開市」即恢復。"""
    st = get_state(session)
    if not st.market_open:
        return {"ok": False, "message": "市場已是關閉狀態"}
    st.market_open = 0
    st.closing_soon = 0
    return {"ok": True, "market_open": False}


def day_open(session) -> dict:
    """重新開市（當日截止的反向操作）。最終關市後不可再開。"""
    st = get_state(session)
    if st.final_closed:
        return {"ok": False, "message": "已最終關市（D3 折現），不可重新開市"}
    if st.market_open:
        return {"ok": False, "message": "市場已是開啟狀態"}
    st.market_open = 1
    st.closing_soon = 0
    return {"ok": True, "market_open": True}


def notify_closing(session) -> dict:
    """5 分鐘結束提醒：設旗標，各攤 App 輪詢到會跳提醒給關主。"""
    st = get_state(session)
    if not st.market_open:
        return {"ok": False, "message": "市場已關閉，不需提醒"}
    st.closing_soon = 1
    return {"ok": True, "closing_soon": True}


def settle_interest(session, day: str) -> dict:
    """每場末按一次。複利 20%，捨去整數。settlement_count<3 且 day 未結過。"""
    st = get_state(session)
    settled = set(json.loads(st.settled_days or "[]"))
    if st.settlement_count >= MAX_SETTLEMENTS:
        return {"ok": False, "message": f"已達結息上限 {MAX_SETTLEMENTS} 次"}
    if day in settled:
        return {"ok": False, "message": f"{day} 已結過息"}
    count = 0
    for s in session.scalars(select(Student).where(Student.deposit_balance > 0)):
        interest = math.floor(s.deposit_balance * DEPOSIT_RATE)
        if interest <= 0:
            continue
        s.deposit_balance += interest
        write_txn(session, s, "bank", "interest", interest, day, {"rate": DEPOSIT_RATE})
        count += 1
    settled.add(day)
    st.settled_days = json.dumps(sorted(settled))
    st.settlement_count += 1
    return {"ok": True, "day": day, "students_settled": count,
            "settlement_count": st.settlement_count}


def transfer(session, from_uid: str, to_uid: str, amount: int) -> dict:
    """服務三：兩學生一起找銀行，指定把錢從 A 轉到 B。無手續費、無金額上限。
    A（轉出方）金額 1:1 轉天國點數，算在 A 頭上（docx v2.3）。"""
    st = get_state(session)
    if not st.market_open:
        return {"ok": False, "message": "市場已關閉，僅能查詢"}
    if amount <= 0:
        return {"ok": False, "message": "金額需 > 0"}
    if from_uid == to_uid:
        return {"ok": False, "message": "不能轉給自己"}
    # 依 uid 排序上鎖，固定順序避免兩張卡互轉時 deadlock
    uid_a, uid_b = sorted((from_uid, to_uid))
    locked = {uid_a: lock_student(session, uid_a), uid_b: lock_student(session, uid_b)}
    src, dst = locked[from_uid], locked[to_uid]
    if src is None or dst is None:
        return {"ok": False, "message": "查無此卡"}
    if src.balance < amount:
        return {"ok": False, "message": f"餘額不足（需 ${amount}，有 ${src.balance}）"}
    src.balance -= amount
    dst.balance += amount
    src.kingdom_points += amount  # A 金額 1:1 轉天國點數
    write_txn(session, src, "bank", "transfer_out", -amount, st.current_day, {"to": dst.uid, "kp": amount})
    write_txn(session, dst, "bank", "transfer_in", amount, st.current_day, {"from": src.uid})
    return {"ok": True, "from": {"uid": src.uid, "name": src.name, "balance": src.balance,
                                "kingdom_points": src.kingdom_points},
            "to": {"uid": dst.uid, "name": dst.name, "balance": dst.balance}, "amount": amount}


def market_close(session) -> dict:
    """D3 10:25 突襲。未兌換現金 + 定存本利 ×0.1 計入積分，歸零，鎖市場。"""
    st = get_state(session)
    if not st.market_open:
        return {"ok": False, "message": "市場已關閉"}
    affected = 0
    for s in session.scalars(select(Student).where(Student.card_uid.is_not(None))):
        taxable = s.balance + s.deposit_balance
        converted = math.floor(taxable * MARKET_CLOSE_RATE)
        s.points += converted
        s.balance = 0
        s.deposit_balance = 0
        write_txn(session, s, "system", "market_close", converted, st.current_day,
                  {"taxable": taxable})
        affected += 1
    st.market_open = 0
    st.final_closed = 1
    st.closing_soon = 0
    return {"ok": True, "students": affected, "market_open": False}


def reset_all(session) -> dict:
    """測試用全重置：學員回起始金、清空所有帳本/任務/賭局/見證、天數回 D1、市場重開。
    保留學員名單與裝置註冊（device_tokens）。不可復原。"""
    n = 0
    for s in session.scalars(select(Student).where(Student.card_uid.is_not(None))):
        s.balance = s.seed_amount
        s.points = 0
        s.kingdom_points = 0
        s.deposit_balance = 0
        s.card_count = 0
        s.d3_donate_bonus = 0
        s.response_card = 0
        s.final_rank_points = None
        s.final_rank_kp = None
        n += 1
    for model in (Transaction, GuildTask, CasinoBet, CasinoRound, WitnessLog):
        session.execute(delete(model))
    st = get_state(session)
    st.current_day = "D1"
    st.market_open = 1
    st.settlement_count = 0
    st.settled_days = "[]"
    st.closing_soon = 0
    st.final_closed = 0
    return {"ok": True, "students_reset": n}


def admin_state(session) -> dict:
    st = get_state(session)
    return {"current_day": st.current_day, "market_open": bool(st.market_open),
            "settlement_count": st.settlement_count,
            "settled_days": json.loads(st.settled_days or "[]"),
            "closing_soon": bool(st.closing_soon),
            "final_closed": bool(st.final_closed)}


def dashboard(session) -> dict:
    """後台即時總覽：全域狀態 + 每位已綁卡學生現況 + 彙總。未綁卡者不算入（尚未真的上場）。"""
    studs = session.scalars(select(Student).where(Student.card_uid.is_not(None))
                            .order_by(Student.points.desc())).all()
    # 公會任務：每人的 pending 任務數 + 各別剩餘秒數（一次查全部，避免 N+1）
    now = datetime.now(timezone.utc)
    guild_remaining: dict[str, list[int]] = {}
    for t in session.scalars(select(GuildTask).where(GuildTask.status == "pending")):
        try:
            drawn = datetime.fromisoformat(t.drawn_at)
            remaining = max(TASK_TIMEOUT_MIN * 60 - int((now - drawn).total_seconds()), 0)
        except (ValueError, TypeError):
            remaining = 0
        guild_remaining.setdefault(t.uid, []).append(remaining)
    for secs in guild_remaining.values():
        secs.sort()
    rows = [{
        "uid": s.uid, "name": s.name, "group": s.group, "seat_no": s.seat_no,
        "seed": s.seed_amount, "balance": s.balance, "deposit": s.deposit_balance,
        "asset": s.balance + s.deposit_balance,
        "points": s.points, "kingdom_points": s.kingdom_points,
        "card_count": s.card_count,
        "guild_task_count": len(guild_remaining.get(s.uid, [])),
        "guild_task_remaining": guild_remaining.get(s.uid, []),
    } for s in studs]
    total_asset = sum(r["asset"] for r in rows)
    return {
        "state": admin_state(session),
        "students": rows,
        "summary": {
            "n_students": len(rows),
            "total_asset": total_asset,
            "total_points": sum(r["points"] for r in rows),
            "total_kp": sum(r["kingdom_points"] for r in rows),
        },
    }


def awards(session) -> dict:
    """頒獎榜：積分榜/管家榜前三名 + 最會賺錢／勤奮工作／刺激經濟三個單一得主。
    即時算，不寫回任何欄位（可以在任何時間點按，重複按結果一樣只是即時值）。"""
    from services.report import bulk_expense_income

    studs = session.scalars(select(Student).where(Student.card_uid.is_not(None))).all()
    if not studs:
        return {"points_top3": [], "kp_top3": [], "best_earner": None,
                "hardest_worker": None, "big_spender": None}

    def brief(s, **extra):
        d = {"uid": s.uid, "name": s.name, "group": s.group or ""}
        d.update(extra)
        return d

    points_top3 = sorted(studs, key=lambda x: x.points, reverse=True)[:3]
    kp_top3 = sorted(studs, key=lambda x: x.kingdom_points, reverse=True)[:3]

    earner = max(studs, key=lambda x: (x.balance + x.deposit_balance) - x.seed_amount)
    earner_diff = (earner.balance + earner.deposit_balance) - earner.seed_amount

    completed: dict[str, int] = {}
    for t in session.scalars(select(GuildTask).where(GuildTask.status == "completed")):
        completed[t.uid] = completed.get(t.uid, 0) + 1
    hardest_worker = None
    if completed:
        top_uid = max(completed, key=lambda u: completed[u])
        if completed[top_uid] > 0:
            match = next((x for x in studs if x.uid == top_uid), None)
            if match:
                hardest_worker = brief(match, count=completed[top_uid])

    inc_exp = bulk_expense_income(session)
    spender = max(studs, key=lambda x: inc_exp.get(x.uid, (0, 0))[1])
    spender_expense = inc_exp.get(spender.uid, (0, 0))[1]

    return {
        "points_top3": [brief(s, points=s.points) for s in points_top3],
        "kp_top3": [brief(s, kingdom_points=s.kingdom_points) for s in kp_top3],
        "best_earner": brief(earner, diff=earner_diff),
        "hardest_worker": hardest_worker,
        "big_spender": brief(spender, expense=spender_expense),
    }
