"""賭場 round — docs/app/31 §4。下注即凍結，結算只發彩金。"""
import json

from sqlalchemy import select

from constants import BET_MAX, BET_MIN, DICE_PAYOUT
from models import CasinoBet, CasinoRound, GameState, Student
from services.txn import lock_student, now_iso, write_txn

DICE_TYPES = {"big", "small", "seven"}


def open_round(session, table: str, stall_id: str) -> dict:
    if table not in ("21", "dice"):
        return {"ok": False, "message": "table 需 '21' 或 'dice'"}
    r = CasinoRound(table=table, stall_id=stall_id, status="open", created_at=now_iso())
    session.add(r)
    session.flush()
    return {"ok": True, "round_id": r.id, "status": "open"}


def _table_bets(session, round_id: int) -> list[dict]:
    rows = session.scalars(select(CasinoBet).where(
        CasinoBet.round_id == round_id, CasinoBet.status == "placed")).all()
    out = []
    for b in rows:
        st = session.get(Student, b.uid)
        out.append({"uid": b.uid, "name": st.name if st else "?",
                    "bet_type": b.bet_type, "amount": b.amount})
    return out


def bet(session, round_id: int, uid: str, bet_type: str, amount: int) -> dict:
    r = session.get(CasinoRound, round_id)
    if r is None or r.status != "open":
        return {"ok": False, "message": "局不存在或已封盤"}
    if not (BET_MIN <= amount <= BET_MAX):
        return {"ok": False, "message": f"桌限 {BET_MIN}–{BET_MAX}"}
    if r.table == "dice" and bet_type not in DICE_TYPES:
        return {"ok": False, "message": "注別需 big/small/seven"}
    if r.table == "21":
        bet_type = "21:play"
    st = get_state(session)
    if not st.market_open:
        return {"ok": False, "message": "市場已關閉"}
    s = lock_student(session, uid)
    if s is None:
        return {"ok": False, "message": "查無此卡"}
    # 同 round 同 uid 僅一注（除非先 cancel）
    dup = session.scalars(select(CasinoBet).where(
        CasinoBet.round_id == round_id, CasinoBet.uid == uid,
        CasinoBet.status == "placed")).first()
    if dup:
        return {"ok": False, "message": "已在桌上，改注請先取消"}
    if s.balance < amount:
        return {"ok": False, "message": "餘額不足"}
    s.balance -= amount  # 凍結
    session.add(CasinoBet(round_id=round_id, uid=uid, bet_type=bet_type,
                          amount=amount, status="placed"))
    write_txn(session, s, r.stall_id, "casino_bet", -amount, st.current_day,
              {"round_id": round_id, "bet_type": bet_type})
    return {"ok": True, "student_name": s.name, "balance": s.balance,
            "table_bets": _table_bets(session, round_id)}


def cancel(session, round_id: int, uid: str) -> dict:
    b = session.scalars(select(CasinoBet).where(
        CasinoBet.round_id == round_id, CasinoBet.uid == uid,
        CasinoBet.status == "placed")).first()
    if b is None:
        return {"ok": False, "message": "查無此注"}
    s = lock_student(session, uid)
    s.balance += b.amount  # 退款
    b.status = "cancelled"
    st = get_state(session)
    r = session.get(CasinoRound, round_id)
    write_txn(session, s, r.stall_id, "casino_cancel", b.amount, st.current_day,
              {"round_id": round_id})
    return {"ok": True, "balance": s.balance, "table_bets": _table_bets(session, round_id)}


def get_state(session) -> GameState:
    return session.get(GameState, 1)


def _dice_outcome(d1: int, d2: int) -> str:
    s = d1 + d2
    if s == 7:
        return "seven"
    return "small" if 2 <= s <= 6 else "big"  # big = 8–12


def settle(session, round_id: int, dice=None, results=None) -> dict:
    r = session.get(CasinoRound, round_id)
    if r is None or r.status != "open":
        return {"ok": False, "message": "局不存在或已結算"}
    st = get_state(session)
    day = st.current_day
    bets = session.scalars(select(CasinoBet).where(
        CasinoBet.round_id == round_id, CasinoBet.status == "placed")).all()
    out = []

    if r.table == "dice":
        if not dice or len(dice) != 2 or not all(1 <= d <= 6 for d in dice):
            return {"ok": False, "message": "需兩顆 1–6 骰點"}
        winning = _dice_outcome(dice[0], dice[1])
        r.dice = json.dumps(dice)
        for b in bets:
            s = lock_student(session, b.uid)
            if b.bet_type == winning:
                mult = DICE_PAYOUT[b.bet_type]      # small/big=2, seven=5（含退本金）
                b.payout = b.amount * mult
                b.status = "won"
                s.balance += b.payout
                delta = b.payout - b.amount
            else:
                b.payout = 0
                b.status = "lost"
                delta = -b.amount
            write_txn(session, s, r.stall_id, "casino_payout", delta, day,
                      {"round_id": round_id, "bet": b.bet_type, "win": b.status == "won",
                       "dice": dice, "net": delta})
            out.append({"uid": s.uid, "name": s.name, "bet": b.bet_type,
                        "delta": delta, "balance": s.balance})

    else:  # '21' — 關主手動標 win/lose
        wins = {row["uid"]: bool(row.get("win")) for row in (results or [])}
        for b in bets:
            s = lock_student(session, b.uid)
            win = wins.get(b.uid, False)  # 平手/未標 = 莊家通吃 = 輸
            if win:
                b.payout = b.amount * 2     # 退本金 + 1:1 彩金
                b.status = "won"
                s.balance += b.payout
                delta = b.amount
            else:
                b.payout = 0
                b.status = "lost"
                delta = -b.amount
            write_txn(session, s, r.stall_id, "casino_payout", delta, day,
                      {"round_id": round_id, "bet": "21:play", "win": win, "net": delta})
            out.append({"uid": s.uid, "name": s.name, "bet": "21:play",
                        "delta": delta, "balance": s.balance})

    r.status = "settled"
    r.settled_at = now_iso()
    return {"ok": True, "round_id": round_id, "status": "settled", "results": out}


def get_round(session, round_id: int) -> dict:
    r = session.get(CasinoRound, round_id)
    if r is None:
        return {"ok": False, "message": "查無此局"}
    return {"ok": True, "round_id": r.id, "table": r.table, "status": r.status,
            "dice": json.loads(r.dice) if r.dice else None,
            "table_bets": _table_bets(session, round_id)}
