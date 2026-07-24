"""模擬「學員抽了公會任務、玩到一半忘記回來核銷」——直接把 drawn_at 改成 9 分鐘前
（TASK_TIMEOUT_MIN=8），逼出 sweep_expired 的逾時扣款路徑。跟 server 用同一顆 loadtest.db
（WAL 模式，另開 process 短暫寫入安全）。

用法（server 已在跑的前提下）：
    python loadtest/inject_expired_task.py
會印出目標 uid + game_key，供 edge_cases.js 讀（寫進 lib/data.json 補一個欄位）。
"""
import json
import os
import sys
from datetime import datetime, timedelta, timezone

DB_PATH = os.path.join(os.path.dirname(__file__), "..", "loadtest.db")
os.environ["DATABASE_URL"] = f"sqlite:///{os.path.abspath(DB_PATH)}"
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from constants import TASK_TIMEOUT_MIN  # noqa: E402
from db import SessionLocal  # noqa: E402
from models import GuildTask  # noqa: E402

TARGET_UID = "stu009"
GAME_KEY = "game_password"


def main() -> None:
    stale_time = datetime.now(timezone.utc) - timedelta(minutes=TASK_TIMEOUT_MIN + 1)
    with SessionLocal.begin() as s:
        s.add(GuildTask(uid=TARGET_UID, game_key=GAME_KEY, difficulty="low", reward=30,
                        status="pending", drawn_at=stale_time.isoformat(timespec="seconds")))

    data_path = os.path.join(os.path.dirname(__file__), "lib", "data.json")
    with open(data_path, encoding="utf-8") as f:
        data = json.load(f)
    data["expired_task_uid"] = TARGET_UID
    data["expired_task_game_key"] = GAME_KEY
    with open(data_path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

    print(f"injected expired task: uid={TARGET_UID} game_key={GAME_KEY} drawn_at={stale_time.isoformat()}")


if __name__ == "__main__":
    main()
