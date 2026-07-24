"""一次性遷移：砍掉獨立 roster 表，統一併入 students（card_uid 表示是否已綁卡）。

用法：cd backend && python migrate_unify_roster.py
可重複執行不報錯（等冪）。用完即可刪除本檔。
"""
import uuid
from datetime import datetime, timezone

from sqlalchemy import inspect, text

from db import SessionLocal, engine, init_db


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def main():
    init_db()  # 確保 students 表存在（沿用既有 schema，不會建 roster）
    insp = inspect(engine)
    student_cols = {c["name"] for c in insp.get_columns("students")}

    with engine.begin() as conn:
        if "card_uid" not in student_cols:
            conn.execute(text("ALTER TABLE students ADD COLUMN card_uid TEXT"))
            conn.execute(text(
                "CREATE UNIQUE INDEX IF NOT EXISTS ix_students_card_uid ON students(card_uid)"))
        conn.execute(text("UPDATE students SET card_uid = uid WHERE card_uid IS NULL"))

    if "roster" in insp.get_table_names():
        with SessionLocal.begin() as s:
            rows = s.execute(text(
                "SELECT name, \"group\", seat_no, seed_amount FROM roster WHERE uid IS NULL"
            )).all()
            for name, group, seat_no, seed_amount in rows:
                s.execute(text(
                    "INSERT INTO students (uid, name, seed_amount, balance, points, "
                    "kingdom_points, deposit_balance, card_count, d3_donate_bonus, "
                    "response_card, \"group\", seat_no, card_uid, created_at) VALUES "
                    "(:uid, :name, :seed, :seed, 0, 0, 0, 0, 0, 0, :group, :seat_no, NULL, :now)"
                ), {"uid": uuid.uuid4().hex, "name": name, "seed": seed_amount,
                    "group": group, "seat_no": seat_no, "now": _now()})
            print(f"migrated {len(rows)} unbound roster entries into students")

        with engine.begin() as conn:
            conn.execute(text("DROP TABLE roster"))
            print("dropped roster table")
    else:
        print("roster table already gone, nothing to migrate")


if __name__ == "__main__":
    main()
