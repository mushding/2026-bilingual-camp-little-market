"""壓測資料灌入。獨立 DB（loadtest.db），跑完可整個刪，不碰正式資料。

用法：
    cd backend
    python loadtest/seed.py
    # 另開 terminal：
    DATABASE_URL=sqlite:///./loadtest.db uvicorn app:app --host 0.0.0.0 --port 8000
"""
import json
import os
import sys
from datetime import datetime, timezone

DB_PATH = os.path.join(os.path.dirname(__file__), "..", "loadtest.db")
os.environ["DATABASE_URL"] = f"sqlite:///{os.path.abspath(DB_PATH)}"

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import auth  # noqa: E402
from constants import GAMES  # noqa: E402
from db import SessionLocal, init_db  # noqa: E402
from models import Student  # noqa: E402
from services import bank  # noqa: E402

N_STUDENTS = 200
N_STAFF_TOKENS = 5
SEED_BALANCE = 200_000  # 壓測用，夠撐長時間 debit/credit 循環，不代表正式起始金


def main() -> None:
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    for suffix in ("-wal", "-shm"):
        p = DB_PATH + suffix
        if os.path.exists(p):
            os.remove(p)

    init_db()

    data = {"uids": [], "stall_ids": list(GAMES.keys()) + ["bank", "casino_dice", "casino_21"]}

    with SessionLocal.begin() as s:
        enroll = auth.enroll(s, auth.ADMIN_CODE, "loadtest-admin")
        data["admin_token"] = enroll["token"]

        data["staff_tokens"] = []
        for i in range(N_STAFF_TOKENS):
            r = auth.enroll(s, auth.STAFF_CODE, f"loadtest-staff-{i}")
            data["staff_tokens"].append(r["token"])

        now = datetime.now(timezone.utc).isoformat(timespec="seconds")
        for i in range(1, N_STUDENTS + 1):
            uid = f"stu{i:03d}"
            s.add(Student(uid=uid, name=f"壓測生{i:03d}", seed_amount=SEED_BALANCE,
                          balance=SEED_BALANCE, group=f"G{(i % 10) + 1}",
                          seat_no=str(i), created_at=now))
            data["uids"].append(uid)

    with SessionLocal.begin() as s:
        bank.set_day(s, "D1")  # market_open 已在 init_db 預設 1

    out_path = os.path.join(os.path.dirname(__file__), "lib", "data.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    print(f"seeded {N_STUDENTS} students, {N_STAFF_TOKENS} staff tokens -> {out_path}")
    print(f"DB: {DB_PATH}")
    print()
    print("啟動 server：")
    print(f'  DATABASE_URL=sqlite:///{os.path.abspath(DB_PATH)} '
          f'uvicorn app:app --host 0.0.0.0 --port 8000')


if __name__ == "__main__":
    main()
