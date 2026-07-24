"""預先名單 / 綁卡 / QR 貼紙自我檢查。跑：cd backend && python -m pytest tests/ -q"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ["DATABASE_URL"] = "sqlite://"

import db  # noqa: E402
from sqlalchemy import StaticPool, create_engine  # noqa: E402
from sqlalchemy.orm import sessionmaker  # noqa: E402

db.engine = create_engine("sqlite://", connect_args={"check_same_thread": False},
                          poolclass=StaticPool, future=True)
db.SessionLocal = sessionmaker(bind=db.engine, expire_on_commit=False, future=True)

import models  # noqa: E402
from schemas import RosterEntry, ScanReq  # noqa: E402
from services import roster  # noqa: E402
from services.txn import handle_scan  # noqa: E402

db.Base.metadata.create_all(db.engine)
S = db.SessionLocal

UID = "04:AA:BB:CC:DD:EE:FF"


def test_roster_flow():
    with S.begin() as s:
        s.add(models.GameState(id=1))
        assert roster.add(s, [
            RosterEntry(name="王小明", group="A", seat_no="1"),
            RosterEntry(name="李小華", group="A", seat_no="2", seed_amount=5000),
            RosterEntry(name="陳大文", group="B"),
        ])["added"] == 3

    # 綁卡 → Student.card_uid 寫入、餘額=起始金（Student 早在 add() 就建好了）
    with S.begin() as s:
        lst = roster.list_all(s)
        assert lst["total"] == 3 and lst["unbound"] == 3
        li_uid = next(e["uid"] for e in lst["entries"] if e["name"] == "李小華")
        r = roster.bind(s, li_uid, UID)
        assert r["ok"], r
        stu = s.get(models.Student, li_uid)
        assert stu.balance == 5000 and stu.group == "A" and stu.card_uid == UID

        # 同一張卡不能綁第二人
        wang_uid = next(e["uid"] for e in roster.list_all(s)["entries"] if e["name"] == "王小明")
        assert not roster.bind(s, wang_uid, UID)["ok"]
        # 同一人不能重綁
        assert not roster.bind(s, li_uid, "04:99:99:99:99:99:99")["ok"]

    # QR 貼紙頁：含 UID 與姓名
    with S() as s:
        html = roster.qr_sheet(s)
        assert "<svg" in html and "李小華" in html

    # 解綁：無交易可解（身分保留、只清 card_uid）、有交易拒絕
    with S.begin() as s:
        li_uid = next(e["uid"] for e in roster.list_all(s)["entries"] if e["name"] == "李小華")
        assert roster.unbind(s, li_uid)["ok"]
        s.flush()
        assert s.get(models.Student, li_uid).card_uid is None
        assert roster.bind(s, li_uid, UID)["ok"]  # 重綁回來
        handle_scan(s, ScanReq(uid=UID, stall_id="grocery", action="debit", amount=10))
        assert not roster.unbind(s, li_uid)["ok"]  # 已有交易 → 拒絕

    # 改組別
    with S.begin() as s:
        li_uid = next(e["uid"] for e in roster.list_all(s)["entries"] if e["name"] == "李小華")
        assert roster.set_group(s, li_uid, "C")["ok"]
        assert s.get(models.Student, li_uid).group == "C"

    # 刪除：已綁不可刪、未綁可刪
    with S.begin() as s:
        entries = roster.list_all(s)["entries"]
        bound_uid = next(e["uid"] for e in entries if e["bound"])
        free_uid = next(e["uid"] for e in entries if not e["bound"])
        assert not roster.delete(s, bound_uid)["ok"]
        assert roster.delete(s, free_uid)["ok"]
        assert roster.list_all(s)["total"] == 2


if __name__ == "__main__":
    test_roster_flow()
    print("ok")
