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
from services import bank, casino, topic1  # noqa: E402
from services.txn import handle_scan  # noqa: E402

db.Base.metadata.create_all(db.engine)
S = db.SessionLocal


def fresh_state(market_open=1, day="D2"):
    with S.begin() as s:
        s.query(models.GameState).delete()
        s.add(models.GameState(id=1, current_day=day, market_open=market_open,
                               settlement_count=0, settled_days="[]"))


def add_student(uid, seed=500, group=None):
    with S.begin() as s:
        if s.get(models.Student, uid):
            return
        s.add(models.Student(uid=uid, card_uid=uid, name="測試", seed_amount=seed,
                            balance=seed, group=group))


def scan(**kw):
    with S.begin() as s:
        return handle_scan(s, ScanReq(**kw)).model_dump()


def test_debit_and_insufficient():
    fresh_state(); add_student("A", 100)
    assert scan(uid="A", stall_id="grocery", action="debit", amount=30)["balance"] == 70
    r = scan(uid="A", stall_id="grocery", action="debit", amount=999)
    assert r["ok"] is False and r["balance"] == 70  # 不足不扣


def test_exchange_points():
    fresh_state(); add_student("B", 800)
    r = scan(uid="B", stall_id="exchange", action="exchange_points", tier=400)
    assert r["points"] == TIER_MAP[400] == 500 and r["balance"] == 400
    # 100 小檔（1.0）
    r2 = scan(uid="B", stall_id="exchange", action="exchange_points", tier=100)
    assert r2["points"] == 500 + TIER_MAP[100] == 600 and r2["balance"] == 300


def test_exchange_points_large_tiers():
    fresh_state(); add_student("B2", 5000)
    r = scan(uid="B2", stall_id="exchange", action="exchange_points", tier=3000)
    assert r["points"] == TIER_MAP[3000] == 4000 and r["balance"] == 2000
    r2 = scan(uid="B2", stall_id="exchange", action="exchange_points", tier=1500)
    assert r2["points"] == 4000 + TIER_MAP[1500] == 6000 and r2["balance"] == 500


def test_donate_kp_no_d3_bonus():
    fresh_state(day="D3"); add_student("C", 500)
    r = scan(uid="C", stall_id="donation", action="donate", amount=100)
    assert r["kingdom_points"] == 100 and r["balance"] == 400  # 二三天同算法，無 bonus
    assert r["points"] == 50  # 同時 0.5x 轉積分
    r2 = scan(uid="C", stall_id="donation", action="donate", amount=100)
    assert r2["kingdom_points"] == 200 and r2["points"] == 100


def test_witness_dedup():
    fresh_state(); add_student("D", 500)
    assert scan(uid="D", stall_id="witness", action="credit_kp", staff_uid="S1")["kingdom_points"] == 100
    assert scan(uid="D", stall_id="witness", action="credit_kp", staff_uid="S1")["ok"] is False
    assert scan(uid="D", stall_id="witness", action="credit_kp", staff_uid="S2")["kingdom_points"] == 200


def test_mail_kp_no_cap():
    fresh_state(); add_student("E", 500)
    assert scan(uid="E", stall_id="mail", action="mail_kp", cards=2)["kingdom_points"] == 200
    r = scan(uid="E", stall_id="mail", action="mail_kp", cards=5)  # 不限張數
    assert r["kingdom_points"] == 700  # 200 + 500


def test_deposit_interest_compound():
    fresh_state(day="D1"); add_student("F", 500)
    scan(uid="F", stall_id="bank", action="deposit", amount=100)
    for d in ("D1", "D2", "D3"):
        with S.begin() as s:
            bank.settle_interest(s, d)
    with S.begin() as s:
        # 100 -> 120 -> 144 -> 172 (floor(172.8))
        assert s.get(models.Student, "F").deposit_balance == 172


def test_meal_ignores_market_closed():
    fresh_state(market_open=0); add_student("MM", 500)
    assert scan(uid="MM", stall_id="meal", action="meal", amount=160)["balance"] == 340
    assert scan(uid="MM", stall_id="grocery", action="debit", amount=10)["ok"] is False  # 其它照擋


def test_tag_excludes_non_students_from_awards():
    fresh_state(); add_student("TS", 500); add_student("TC", 500)
    from services import report as report_svc
    with S.begin() as s:
        s.get(models.Student, "TC").tag = "輔導"
        s.get(models.Student, "TC").points = 99999   # 輔導分數最高也不入榜
        s.get(models.Student, "TS").points = 1
    with S.begin() as s:
        a = bank.awards(s)
        assert "TC" not in [x["uid"] for x in a["points_top3"]]
        assert report_svc.live_ranks(s, "TC") == (None, None)  # 輔導無名次
        rp, _ = report_svc.live_ranks(s, "TS")
        assert rp is not None


def test_interest_tick():
    # 注意：測試共用同一顆 in-memory DB，前面測試的學生若還有定存也會被 tick 到，
    # 所以只對 IT 一人斷言，不看全體 total。
    fresh_state(day="D1"); add_student("IT", 500)
    scan(uid="IT", stall_id="bank", action="deposit", amount=200)
    with S.begin() as s:
        assert bank.interest_tick(s)["ticked"] is False   # 首呼叫只設基準
        assert bank.interest_tick(s, force=True)["ticked"] is True  # 預設 3%
    with S.begin() as s:
        assert s.get(models.Student, "IT").deposit_balance == 206  # floor(200*1.03)
    with S.begin() as s:                                  # 可調 config
        assert bank.set_interest_config(s, 4.0, 5)["ok"] is True
        bank.interest_tick(s, force=True)
    with S.begin() as s:
        assert s.get(models.Student, "IT").deposit_balance == 214  # 206+floor(206*0.04)
    with S.begin() as s:                                  # 市場關閉不跳息
        bank.day_close(s)
        assert bank.interest_tick(s, force=True)["ticked"] is False
    with S.begin() as s:
        row = next(r for r in bank.interest_dashboard(s)["rows"] if r["uid"] == "IT")
        assert row["earned"] == 14 and row["deposit"] == 214


def test_market_close_then_settle():
    fresh_state(day="D3"); add_student("G", 500)
    scan(uid="G", stall_id="bank", action="deposit", amount=100)  # bal 400, dep 100
    with S.begin() as s:
        bank.market_close(s)          # 只凍結市場，不折算
    # 關市後：攤位停、餐費照收（D3 午餐）
    assert scan(uid="G", stall_id="grocery", action="debit", amount=1)["ok"] is False
    assert scan(uid="G", stall_id="meal", action="meal", amount=100)["balance"] == 300
    with S.begin() as s:
        assert bank.settle_final(s)["ok"] is True
        assert bank.settle_final(s)["ok"] is False   # 只可一次
    with S.begin() as s:
        g = s.get(models.Student, "G")
        assert g.balance == 0 and g.deposit_balance == 0
        assert g.points == 40  # floor((300+100)*0.1)，午餐已先扣走 100
    with S.begin() as s:                              # 沒關市不能結算
        st = s.get(models.GameState, 1); st.final_closed = 0; st.final_settled = 0
    with S.begin() as s:
        assert bank.settle_final(s)["ok"] is False


def test_meal_charge_all():
    fresh_state()
    with S.begin() as s:  # 清掉其他測試留下的學員（bulk 扣全體，需乾淨名單）
        s.query(models.Student).delete()
    add_student("M1", 500)
    add_student("M2", 60)   # 不足，只扣到 0
    add_student("M3", 0)    # 沒錢，跳過但列入不足
    with S.begin() as s:
        r = bank.meal_charge_all(s, 100)
    assert r["ok"] is True and r["count"] == 2 and r["total"] == 160 and r["short"] == 2
    with S.begin() as s:
        assert s.get(models.Student, "M1").balance == 400
        assert s.get(models.Student, "M2").balance == 0
        assert s.get(models.Student, "M3").balance == 0
    with S.begin() as s:
        bad = bank.meal_charge_all(s, 0)
    assert bad["ok"] is False


def test_dice_seven_payout():
    fresh_state(); add_student("H", 500)
    with S.begin() as s:
        rid = casino.open_round(s, "dice", "casino_dice")["round_id"]
    with S.begin() as s:
        casino.bet(s, rid, "H", "seven", 50)
    with S.begin() as s:
        res = casino.settle(s, rid, dice=[3, 4])  # sum 7
    with S.begin() as s:
        # 凍結 -50，命中 seven 賠 5x = +250，淨 +200 → 500-50+250=700
        assert s.get(models.Student, "H").balance == 700


def test_guild_draw_no_fee_and_n_tasks():
    fresh_state(); add_student("I", 2000)
    r = scan(uid="I", stall_id="guild", action="guild_draw", amount=2)
    assert r["balance"] == 2000 and r["assigned_game"]  # 免手續費
    assert len(r["pending_tasks"]) == 2


def test_guild_draw_no_duplicates_and_pool_cap():
    fresh_state(); add_student("J", 2000)
    r = scan(uid="J", stall_id="guild", action="guild_draw", amount=9)  # 整池 9 款
    assert r["ok"] is True and len(r["pending_tasks"]) == 9
    game_keys = {t["game_key"] for t in r["pending_tasks"]}
    assert len(game_keys) == 9  # 不重複
    r2 = scan(uid="J", stall_id="guild", action="guild_draw", amount=1)  # 池已抽光
    assert r2["ok"] is False and r2["balance"] == 2000


def test_guild_weighted_draw():
    from constants import GUILD_POOL, GUILD_WEIGHTS
    from services.guild import _weighted_sample
    # 抽滿整池仍不重複
    full = _weighted_sample(GUILD_POOL, len(GUILD_POOL))
    assert sorted(full) == sorted(GUILD_POOL)
    # 統計：權重 2 的關抽中率應明顯高於權重 1（單抽 2/15 vs 1/15）
    import random
    random.seed(42)
    hits = {g: 0 for g in GUILD_POOL}
    for _ in range(6000):
        hits[_weighted_sample(GUILD_POOL, 1)[0]] += 1
    for g1 in GUILD_WEIGHTS:            # 權重 1：期望 6000/15=400
        assert 280 < hits[g1] < 520, (g1, hits[g1])
    for g2 in set(GUILD_POOL) - set(GUILD_WEIGHTS):  # 權重 2：期望 800
        assert 650 < hits[g2] < 950, (g2, hits[g2])


def test_guild_task_timeout_penalty():
    import models
    from datetime import datetime, timedelta, timezone
    fresh_state(); add_student("K", 2000)
    scan(uid="K", stall_id="guild", action="guild_draw", amount=1)  # bal 2000, 1 task
    # 把 drawn_at 改成逾時線後 1 分鐘（跟著 TASK_TIMEOUT_MIN 走，改常數不用改測試）
    from constants import TASK_TIMEOUT_MIN
    from sqlalchemy import select as _sel
    past = (datetime.now(timezone.utc)
            - timedelta(minutes=TASK_TIMEOUT_MIN + 1)).isoformat(timespec="seconds")
    with S.begin() as s:
        t = s.scalars(_sel(models.GuildTask).where(models.GuildTask.uid == "K")).first()
        t.drawn_at = past
    r = scan(uid="K", stall_id="bank", action="lookup")  # 掃卡觸發 sweep
    assert r["balance"] == 1900 and len(r["pending_tasks"]) == 0  # 逾時扣 100


def test_guild_complete_matches_stall():
    import models
    from datetime import datetime, timezone
    from services import guild
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    fresh_state(); add_student("L", 500)
    with S.begin() as s:  # 直接塞一個 game_basketball 的 pending
        s.add(models.GuildTask(uid="L", game_key="game_basketball", difficulty="mid",
                               reward=900, status="pending", drawn_at=now))
    with S.begin() as s:
        lst = guild.pending(s, "game_basketball")  # 修正前這裡會是空（bug）
    assert any(x["student_uid"] == "L" for x in lst)
    with S.begin() as s:
        r = guild.complete(s, "L", "game_basketball", "dev").model_dump()
    assert r["ok"] is True and r["balance"] == 1400  # +900


def test_donate_no_floor():
    fresh_state(); add_student("DON", 500)
    r = scan(uid="DON", stall_id="donation", action="donate", amount=1)
    assert r["ok"] is True and r["kingdom_points"] == 1 and r["balance"] == 499
    r0 = scan(uid="DON", stall_id="donation", action="donate", amount=0)
    assert r0["ok"] is False  # 0 元仍擋


def test_bank_transfer():
    fresh_state(); add_student("TA", 500); add_student("TB", 100)
    with S.begin() as s:
        out = bank.transfer(s, "TA", "TB", 200)
    assert out["ok"] is True and out["from"]["balance"] == 300 and out["to"]["balance"] == 300
    assert out["from"]["kingdom_points"] == 200  # A 金額 1:1 轉天國點數
    assert out["from"]["points"] == 100  # 同時 0.5x 轉積分
    with S.begin() as s:
        bad_self = bank.transfer(s, "TA", "TA", 10)
    assert bad_self["ok"] is False
    with S.begin() as s:
        bad_insufficient = bank.transfer(s, "TB", "TA", 99999)
    assert bad_insufficient["ok"] is False
    fresh_state()  # market_open=1 預設，先關市場再測試阻擋
    with S.begin() as s:
        s.query(models.GameState).delete()
        s.add(models.GameState(id=1, current_day="D2", market_open=0,
                               settlement_count=0, settled_days="[]"))
    with S.begin() as s:
        blocked = bank.transfer(s, "TA", "TB", 10)
    assert blocked["ok"] is False


def test_topic1_group_credit():
    fresh_state()
    add_student("G1A", 1000, group="1")
    add_student("G1B", 2000, group="1")
    add_student("G2A", 5000, group="2")
    with S.begin() as s:
        groups = topic1.list_groups(s)
    assert {"group": "1", "count": 2} in groups and {"group": "2", "count": 1} in groups
    with S.begin() as s:
        out = topic1.group_credit(s, "1", 300, "島嶼變裝祭")
    assert out["ok"] is True and out["count"] == 2
    with S.begin() as s:
        assert s.get(models.Student, "G1A").balance == 1300
        assert s.get(models.Student, "G1B").balance == 2300
        assert s.get(models.Student, "G2A").balance == 5000  # 其他組不受影響
    with S.begin() as s:
        bad = topic1.group_credit(s, "no-such-group", 100)
    assert bad["ok"] is False
    with S.begin() as s:
        zero = topic1.group_credit(s, "1", 0)
    assert zero["ok"] is False


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
    """只有 admin 需要註冊；一般 staff 操作免設定碼（見 app.py middleware 預設 scope）。"""
    import auth
    with S.begin() as s:
        bad = auth.enroll(s, "wrong-code")
        assert bad["ok"] is False
        a = auth.enroll(s, "dev-admin-code", "總控機")
    assert a["scope"] == "admin"
    with S.begin() as s:
        assert auth.verify(s, a["token"]) == "admin"
        assert auth.verify(s, "garbage") is None
    with S.begin() as s:
        auth.revoke(s, label="總控機")
    with S.begin() as s:
        assert auth.verify(s, a["token"]) is None   # 撤銷後失效


if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for fn in fns:
        fn()
        print(f"ok  {fn.__name__}")
    print(f"\nALL {len(fns)} PASS")
