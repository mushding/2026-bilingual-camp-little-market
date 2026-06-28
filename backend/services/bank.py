"""銀行利息與市場關閉 / 全域狀態 — docs/app/31 §5（管理操作）。"""
import json
import math

from sqlalchemy import delete, select

from constants import DEPOSIT_RATE, MARKET_CLOSE_RATE, MAX_SETTLEMENTS
from models import (CasinoBet, CasinoRound, GameState, GuildTask, Student,
                    Transaction, WitnessLog)
from services.txn import get_state, write_txn


def set_day(session, day: str) -> dict:
    if day not in ("D1", "D2", "D3"):
        return {"ok": False, "message": "day 需 D1/D2/D3"}
    st = get_state(session)
    st.current_day = day
    return {"ok": True, "current_day": day}


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


def market_close(session) -> dict:
    """D3 10:25 突襲。未兌換現金 + 定存本利 ×0.1 計入積分，歸零，鎖市場。"""
    st = get_state(session)
    if not st.market_open:
        return {"ok": False, "message": "市場已關閉"}
    affected = 0
    for s in session.scalars(select(Student)):
        taxable = s.balance + s.deposit_balance
        converted = math.floor(taxable * MARKET_CLOSE_RATE)
        s.points += converted
        s.balance = 0
        s.deposit_balance = 0
        write_txn(session, s, "system", "market_close", converted, st.current_day,
                  {"taxable": taxable})
        affected += 1
    st.market_open = 0
    return {"ok": True, "students": affected, "market_open": False}


def reset_all(session) -> dict:
    """測試用全重置：學員回起始金、清空所有帳本/任務/賭局/見證、天數回 D1、市場重開。
    保留學員名單與裝置註冊（device_tokens）。不可復原。"""
    n = 0
    for s in session.scalars(select(Student)):
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
    return {"ok": True, "students_reset": n}


def admin_state(session) -> dict:
    st = get_state(session)
    return {"current_day": st.current_day, "market_open": bool(st.market_open),
            "settlement_count": st.settlement_count,
            "settled_days": json.loads(st.settled_days or "[]")}


def dashboard(session) -> dict:
    """後台即時總覽：全域狀態 + 每位學生現況 + 彙總。"""
    studs = session.scalars(select(Student).order_by(Student.points.desc())).all()
    # pending 任務數（一次查全部，避免 N+1）
    pend: dict[str, int] = {}
    for t in session.scalars(select(GuildTask).where(GuildTask.status == "pending")):
        pend[t.uid] = pend.get(t.uid, 0) + 1
    rows = [{
        "uid": s.uid, "name": s.name, "group": s.group, "seat_no": s.seat_no,
        "seed": s.seed_amount, "balance": s.balance, "deposit": s.deposit_balance,
        "asset": s.balance + s.deposit_balance,
        "points": s.points, "kingdom_points": s.kingdom_points,
        "card_count": s.card_count, "pending_tasks": pend.get(s.uid, 0),
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
