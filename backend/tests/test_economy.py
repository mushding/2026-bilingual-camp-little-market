"""核心金流自我檢查。跑：cd backend && python -m pytest tests/ -q
（或直接 python tests/test_economy.py 跑 assert）

用 in-memory SQLite，不需起 server。
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ["DATABASE_URL"] = "sqlite://"  # in-memory

import db  # noqa: E402
from sqlalchemy import StaticPool, create_engine  # noqa: E402
from sqlalchemy.orm import sessionmaker  # noqa: E402

# in-memory 單一連線（多 session 共用同一 DB）
db.engine = create_engine("sqlite://", connect_args={"check_same_thread": False},
                          poolclass=StaticPool, future=True)
db.SessionLocal = sessionmaker(bind=db.engine, expire_on_commit=False, future=True)

import models  # noqa: E402
from constants import TIER_MAP  # noqa: E402
from schemas import ScanReq  # noqa: E402
from services import bank, casino  # noqa: E402
from services.txn import handle_scan  # noqa: E402

db.Base.metadata.create_all(db.engine)
S = db.SessionLocal


def fresh_state(market_open=1, day="D2"):
    with S.begin() as s:
        s.query(models.GameState).delete()
        s.add(models.GameState(id=1, current_day=day, market_open=market_open,
                               settlement_count=0, settled_days="[]"))


def add_student(uid, seed=500):
    with S.begin() as s:
        if s.get(models.Student, uid):
            return
        s.add(models.Student(uid=uid, name="測試", seed_amount=seed, balance=seed))


def scan(**kw):
    with S.begin() as s:
        return handle_scan(s, ScanReq(**kw)).model_dump()


def test_debit_and_insufficient():
    fresh_state(); add_student("A", 100)
    assert scan(uid="A", stall_id="grocery", action="debit", amount=30)["balance"] == 70
    r = scan(uid="A", stall_id="grocery", action="debit", amount=999)
    assert r["ok"] is False and r["balance"] == 70  # 不足不扣


def test_exchange_points():
    fresh_state(); add_student("B", 1000)
    r = scan(uid="B", stall_id="exchange", action="exchange_points", tier=750)
    assert r["points"] == TIER_MAP[750] == 1000 and r["balance"] == 250


def test_donate_kp_no_d3_bonus():
    fresh_state(day="D3"); add_student("C", 500)
    r = scan(uid="C", stall_id="donation", action="donate", amount=100)
    assert r["kingdom_points"] == 100 and r["balance"] == 400  # 二三天同算法，無 bonus
    r2 = scan(uid="C", stall_id="donation", action="donate", amount=100)
    assert r2["kingdom_points"] == 200


def test_witness_dedup():
    fresh_state(); add_student("D", 500)
    assert scan(uid="D", stall_id="witness", action="credit_kp", staff_uid="S1")["kingdom_points"] == 100
    assert scan(uid="D", stall_id="witness", action="credit_kp", staff_uid="S1")["ok"] is False
    assert scan(uid="D", stall_id="witness", action="credit_kp", staff_uid="S2")["kingdom_points"] == 200


def test_mail_kp_no_cap():
    fresh_state(); add_student("E", 500)
    assert scan(uid="E", stall_id="mail", action="mail_kp", cards=2)["kingdom_points"] == 40
    r = scan(uid="E", stall_id="mail", action="mail_kp", cards=5)  # 不限張數
    assert r["kingdom_points"] == 140  # 40 + 100


def test_deposit_interest_compound():
    fresh_state(day="D1"); add_student("F", 500)
    scan(uid="F", stall_id="bank", action="deposit", amount=100)
    for d in ("D1", "D2", "D3"):
        with S.begin() as s:
            bank.settle_interest(s, d)
    with S.begin() as s:
        # 100 -> 120 -> 144 -> 172 (floor(172.8))
        assert s.get(models.Student, "F").deposit_balance == 172


def test_market_close_x01():
    fresh_state(day="D3"); add_student("G", 500)
    scan(uid="G", stall_id="bank", action="deposit", amount=100)  # bal 400, dep 100
    with S.begin() as s:
        bank.market_close(s)
    with S.begin() as s:
        g = s.get(models.Student, "G")
        assert g.balance == 0 and g.deposit_balance == 0
        assert g.points == 50  # floor((400+100)*0.1)
    # 關市後僅 lookup
    assert scan(uid="G", stall_id="grocery", action="debit", amount=1)["ok"] is False


def test_dice_seven_payout():
    fresh_state(); add_student("H", 500)
    with S.begin() as s:
        rid = casino.open_round(s, "dice", "casino_dice")["round_id"]
    with S.begin() as s:
        casino.bet(s, rid, "H", "seven", 10)
    with S.begin() as s:
        res = casino.settle(s, rid, dice=[3, 4])  # sum 7
    with S.begin() as s:
        # 凍結 -10，命中 seven 賠 5x = +50，淨 +40 → 500-10+50=540
        assert s.get(models.Student, "H").balance == 540


def test_guild_draw_fee_and_pending():
    fresh_state(); add_student("I", 500)
    r = scan(uid="I", stall_id="guild", action="guild_draw")
    assert r["balance"] == 470 and r["assigned_game"]  # 扣 30
    assert len(r["pending_tasks"]) == 1


def test_guild_max_3_tasks():
    fresh_state(); add_student("J", 500)
    for _ in range(3):
        scan(uid="J", stall_id="guild", action="guild_draw")
    r4 = scan(uid="J", stall_id="guild", action="guild_draw")  # 第 4 次被擋
    assert r4["ok"] is False and r4["balance"] == 410  # 只扣了 3 次 30


def test_guild_task_timeout_penalty():
    import models
    from datetime import datetime, timedelta, timezone
    fresh_state(); add_student("K", 500)
    scan(uid="K", stall_id="guild", action="guild_draw")  # bal 470, 1 task
    # 把 drawn_at 改成 11 分鐘前
    from sqlalchemy import select as _sel
    past = (datetime.now(timezone.utc) - timedelta(minutes=11)).isoformat(timespec="seconds")
    with S.begin() as s:
        t = s.scalars(_sel(models.GuildTask).where(models.GuildTask.uid == "K")).first()
        t.drawn_at = past
    r = scan(uid="K", stall_id="bank", action="lookup")  # 掃卡觸發 sweep
    assert r["balance"] == 450 and len(r["pending_tasks"]) == 0  # 逾時 −20、作廢


def test_guild_complete_matches_stall():
    import models
    from datetime import datetime, timezone
    from services import guild
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    fresh_state(); add_student("L", 500)
    with S.begin() as s:  # 直接塞一個 game_basketball 的 pending
        s.add(models.GuildTask(uid="L", game_key="game_basketball", difficulty="mid",
                               reward=90, status="pending", drawn_at=now))
    with S.begin() as s:
        lst = guild.pending(s, "game_basketball")  # 修正前這裡會是空（bug）
    assert any(x["student_uid"] == "L" for x in lst)
    with S.begin() as s:
        r = guild.complete(s, "L", "game_basketball", "dev").model_dump()
    assert r["ok"] is True and r["balance"] == 590  # +90


def test_reset_all():
    import models
    from services import bank
    fresh_state(day="D3"); add_student("RST", 500)
    scan(uid="RST", stall_id="grocery", action="debit", amount=100)  # bal 400
    scan(uid="RST", stall_id="donation", action="donate", amount=50)  # kp 50
    with S.begin() as s:
        out = bank.reset_all(s)
    assert out["ok"] and out["students_reset"] >= 1
    with S.begin() as s:
        r = s.get(models.Student, "RST")
        assert r.balance == 500 and r.points == 0 and r.kingdom_points == 0
        st = s.get(models.GameState, 1)
        assert st.current_day == "D1" and st.market_open == 1
        assert s.scalars(__import__("sqlalchemy").select(models.Transaction)).first() is None


def test_auth_enroll_verify_revoke():
    import auth
    with S.begin() as s:
        bad = auth.enroll(s, "wrong-code")
        assert bad["ok"] is False
        a = auth.enroll(s, "dev-admin-code", "總控機")
        st = auth.enroll(s, "dev-staff-code", "銀行攤")
    assert a["scope"] == "admin" and st["scope"] == "staff"
    with S.begin() as s:
        assert auth.verify(s, a["token"]) == "admin"
        assert auth.verify(s, st["token"]) == "staff"
        assert auth.verify(s, "garbage") is None
    with S.begin() as s:
        auth.revoke(s, label="銀行攤")
    with S.begin() as s:
        assert auth.verify(s, st["token"]) is None   # 撤銷後失效
        assert auth.verify(s, a["token"]) == "admin"  # 其他不受影響


if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for fn in fns:
        fn()
        print(f"ok  {fn.__name__}")
    print(f"\nALL {len(fns)} PASS")
