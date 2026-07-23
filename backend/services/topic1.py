"""主題一：Day1 大地遊戲 — 關主依小組整組加錢（非個人掃卡）。

企劃：2026FY主題一.docx。6 關（4 PK 關贏500/輸200、2 單組別關完成300），
關主在手機上選組別、選金額，該組全員一次入帳，不用逐一掃卡。
"""
import json
from datetime import datetime, timezone

from sqlalchemy import func, select

from models import GameState, Student, Transaction


def list_groups(session) -> list[dict]:
    rows = session.execute(
        select(Student.group, func.count()).where(
            Student.group.isnot(None), Student.group != "",
        ).group_by(Student.group)
    ).all()
    groups = sorted(rows, key=lambda r: (len(r[0]), r[0]))
    return [{"group": g, "count": c} for g, c in groups]


def group_credit(session, group: str, amount: int, game_label: str = "") -> dict:
    if amount <= 0:
        return {"ok": False, "message": "金額需 > 0"}
    students = session.scalars(select(Student).where(Student.group == group)).all()
    if not students:
        return {"ok": False, "message": f"找不到組別「{group}」的學員"}

    day = session.get(GameState, 1).current_day
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    for st in students:
        st.balance += amount
        session.add(Transaction(
            uid=st.uid, stall_id="topic1", action="topic1_credit", amount=amount,
            balance_after=st.balance, points_after=st.points, kp_after=st.kingdom_points,
            deposit_after=st.deposit_balance, day=day,
            meta=json.dumps({"group": group, "game": game_label}, ensure_ascii=False),
            created_at=now,
        ))
    return {"ok": True, "message": f"第 {group} 組 {len(students)} 人各 +{amount}",
            "group": group, "amount": amount, "count": len(students)}
