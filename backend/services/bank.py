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


def interest_config(session) -> dict:
    """定存 tick 設定與狀態（admin 定存頁）。"""
    st = get_state(session)
    return {"ok": True, "rate_pct": st.interest_rate_pct,
            "tick_min": st.interest_tick_min,
            "tick_count": st.interest_tick_count,
            "last_tick": st.interest_last_tick,
            "market_open": bool(st.market_open),
            "final_closed": bool(st.final_closed)}


def set_interest_config(session, rate_pct: float, tick_min: int) -> dict:
    if not 0 <= rate_pct <= 100:
        return {"ok": False, "message": "rate_pct 需 0–100"}
    if not 1 <= tick_min <= 120:
        return {"ok": False, "message": "tick_min 需 1–120"}
    st = get_state(session)
    st.interest_rate_pct = float(rate_pct)
    st.interest_tick_min = int(tick_min)
    return {"ok": True, "rate_pct": st.interest_rate_pct, "tick_min": st.interest_tick_min}


def interest_tick(session, force: bool = False) -> dict:
    """定存 tick（v2.7）：市場開放時每 tick_min 分鐘對所有定存 +rate_pct%（捨去整數）。
    scheduler 高頻呼叫，未到時間 no-op。市場關閉時滑動 last_tick 基準——重開市後
    要再等滿一個完整 tick 才會發息，關市期間不累積。"""
    st = get_state(session)
    now = datetime.now(timezone.utc)
    now_s = now.isoformat(timespec="seconds")
    if st.market_open != 1 or st.final_closed:
        st.interest_last_tick = now_s
        return {"ok": True, "ticked": False, "reason": "market_closed"}
    last = None
    if st.interest_last_tick:
        try:
            last = datetime.fromisoformat(st.interest_last_tick)
        except ValueError:
            last = None
    if last is None:
        st.interest_last_tick = now_s
        return {"ok": True, "ticked": False, "reason": "baseline"}
    if not force and (now - last).total_seconds() < st.interest_tick_min * 60:
        return {"ok": True, "ticked": False, "reason": "not_due"}
    rate = st.interest_rate_pct / 100.0
    count = total = 0
    for s in session.scalars(select(Student).where(Student.deposit_balance > 0)):
        interest = math.floor(s.deposit_balance * rate)
        if interest <= 0:
            continue
        s.deposit_balance += interest
        write_txn(session, s, "bank", "interest_tick", interest, st.current_day,
                  {"rate_pct": st.interest_rate_pct, "tick": st.interest_tick_count + 1})
        count += 1
        total += interest
    st.interest_last_tick = now_s
    st.interest_tick_count += 1
    return {"ok": True, "ticked": True, "tick": st.interest_tick_count,
            "students": count, "total_interest": total}


def interest_dashboard(session) -> dict:
    """定存動態 dashboard：每人目前定存 + 歷來利息收入（含 legacy 手動結息）。"""
    from sqlalchemy import func
    st = get_state(session)
    earned = dict(session.execute(
        select(Transaction.uid, func.sum(Transaction.amount))
        .where(Transaction.stall_id == "bank",
               Transaction.action.in_(("interest", "interest_tick")))
        .group_by(Transaction.uid)).all())
    rows = []
    for s in session.scalars(select(Student).where(Student.card_uid.is_not(None))):
        e = int(earned.get(s.uid) or 0)
        if s.deposit_balance <= 0 and e <= 0:
            continue
        rows.append({"uid": s.uid, "name": s.name, "group": s.group or "",
                     "deposit": s.deposit_balance, "earned": e})
    rows.sort(key=lambda r: (-r["earned"], -r["deposit"]))
    next_tick_sec = None
    if st.market_open == 1 and not st.final_closed and st.interest_last_tick:
        try:
            last = datetime.fromisoformat(st.interest_last_tick)
            next_tick_sec = max(0, int(st.interest_tick_min * 60 -
                                       (datetime.now(timezone.utc) - last).total_seconds()))
        except ValueError:
            pass
    return {"ok": True, "rate_pct": st.interest_rate_pct,
            "tick_min": st.interest_tick_min, "tick_count": st.interest_tick_count,
            "market_open": bool(st.market_open), "final_closed": bool(st.final_closed),
            "next_tick_sec": next_tick_sec,
            "total_deposit": sum(r["deposit"] for r in rows),
            "total_earned": sum(r["earned"] for r in rows), "rows": rows}


def transfer(session, from_uid: str, to_uid: str, amount: int) -> dict:
    """服務三：兩學生一起找銀行，指定把錢從 A 轉到 B。無手續費、無金額上限。
    A（轉出方）金額 1:1 轉天國點數 + 0.5x 轉積分，算在 A 頭上（docx v2.3；積分
    比例是給關主一個對外說法，天國點數本身不對外公告）。"""
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
    gained_points = amount // 2
    src.balance -= amount
    dst.balance += amount
    src.kingdom_points += amount  # A 金額 1:1 轉天國點數
    src.points += gained_points  # 同時 0.5x 轉積分
    write_txn(session, src, "bank", "transfer_out", -amount, st.current_day,
              {"to": dst.uid, "kp": amount, "points": gained_points})
    write_txn(session, dst, "bank", "transfer_in", amount, st.current_day, {"from": src.uid})
    return {"ok": True, "from": {"uid": src.uid, "name": src.name, "balance": src.balance,
                                "points": src.points, "kingdom_points": src.kingdom_points},
            "to": {"uid": dst.uid, "name": dst.name, "balance": dst.balance}, "amount": amount}


def meal_charge_all(session, amount: int) -> dict:
    """全體扣餐費（D2 晚餐／D3 午餐不擺攤，總控輸入單價一鍵統一扣）。
    只扣已綁卡學員；餘額不足者扣到 0（餐照供，保證水槽——不是沒錢就沒飯）。
    不檢查 market_open：通常在當日截止後才收餐費，屬總控權限。"""
    if amount <= 0:
        return {"ok": False, "message": "金額需 > 0"}
    st = get_state(session)
    count, total, short = 0, 0, 0
    for s in session.scalars(select(Student).where(Student.card_uid.is_not(None))):
        charged = min(amount, s.balance)
        if charged < amount:
            short += 1
        if charged <= 0:
            continue
        s.balance -= charged
        write_txn(session, s, "meal", "meal", -charged, st.current_day,
                  {"bulk": True, "asked": amount})
        count += 1
        total += charged
    msg = f"全體扣餐費 ${amount}：{count} 人共扣 ${total}"
    if short:
        msg += f"（{short} 人餘額不足，只扣到 0）"
    return {"ok": True, "message": msg, "count": count, "total": total, "short": short}


def market_close(session) -> dict:
    """D3 10:25 突襲：凍結市場（攤位全停、只剩 meal 可扣）。
    ×0.1 折算移到 settle_final()——關市後還要收 D3 午餐，扣完午餐才結算。"""
    st = get_state(session)
    if not st.market_open:
        return {"ok": False, "message": "市場已關閉"}
    st.market_open = 0
    st.final_closed = 1
    st.closing_soon = 0
    return {"ok": True, "market_open": False,
            "message": "市場已凍結；收完 D3 午餐後再按「結算」"}


def settle_final(session) -> dict:
    """D3 結算（市場關閉 → 全體扣午餐 → 按這顆）：
    未兌換現金 + 定存本利 ×0.1 計入積分、歸零，凍結名次。只可按一次。"""
    st = get_state(session)
    if not st.final_closed:
        return {"ok": False, "message": "要先市場關閉才能結算"}
    if st.final_settled:
        return {"ok": False, "message": "已結算過"}
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
    st.final_settled = 1
    return {"ok": True, "students": affected}


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
    st.final_settled = 0
    return {"ok": True, "students_reset": n}


def admin_state(session) -> dict:
    st = get_state(session)
    return {"current_day": st.current_day, "market_open": bool(st.market_open),
            "settlement_count": st.settlement_count,
            "settled_days": json.loads(st.settled_days or "[]"),
            "closing_soon": bool(st.closing_soon),
            "final_closed": bool(st.final_closed),
            "final_settled": bool(st.final_settled)}


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
        "uid": s.uid, "name": s.name, "group": s.group, "tag": s.tag or "學員",
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

    # 只有 tag=學員 進頒獎榜；輔導/測試帳號玩歸玩，不佔名次
    studs = session.scalars(select(Student).where(
        Student.card_uid.is_not(None), Student.tag == "學員")).all()
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
    stud_uids = {x.uid for x in studs}
    for t in session.scalars(select(GuildTask).where(GuildTask.status == "completed")):
        if t.uid in stud_uids:  # 輔導/測試完成的任務不搶「勤奮工作」獎
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
