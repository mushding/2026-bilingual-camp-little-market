"""營前建表 CLI：python seed_import.py students.csv

CSV 欄位：name,uid,seed_amount[,group,seat_no]
"""
import csv
import sys
from datetime import datetime, timezone

from db import SessionLocal, init_db
from models import Student


def main(path: str):
    init_db()
    imported = skipped = 0
    errors = []
    with open(path, encoding="utf-8-sig") as f, SessionLocal.begin() as s:
        for i, row in enumerate(csv.DictReader(f), 1):
            try:
                uid = row["uid"].strip()
                if not uid or s.get(Student, uid):
                    skipped += 1
                    continue
                seed = int(row["seed_amount"])
                s.add(Student(uid=uid, name=row["name"].strip(), seed_amount=seed,
                              balance=seed, group=row.get("group"), seat_no=row.get("seat_no"),
                              created_at=datetime.now(timezone.utc).isoformat(timespec="seconds")))
                imported += 1
            except Exception as e:  # noqa: BLE001
                errors.append(f"row {i}: {e}")
    print(f"imported={imported} skipped={skipped} errors={errors}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: python seed_import.py students.csv")
        sys.exit(1)
    main(sys.argv[1])
