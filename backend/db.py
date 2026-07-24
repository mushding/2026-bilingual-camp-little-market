"""SQLAlchemy engine/session。SQLite + WAL；DATABASE_URL 可換 Postgres（schema 不變）。

寫入用 SessionLocal（BEGIN IMMEDIATE，逼真序列化，防雙花/雙重派彩）；
純讀用 ReadSessionLocal（保留 SQLite WAL 原本的並發讀，效能不受影響）。
兩個 sessionmaker 各自的 engine 都指到同一個 db 檔案，WAL 模式下多個連線互不干擾。
"""
import os

from sqlalchemy import create_engine, event
from sqlalchemy.orm import DeclarativeBase, sessionmaker

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./flyyoung.db")
_is_sqlite = DATABASE_URL.startswith("sqlite")
_connect_args = {"check_same_thread": False} if _is_sqlite else {}


def _make_engine():
    return create_engine(DATABASE_URL, connect_args=_connect_args, future=True)


engine = _make_engine()          # 讀專用（只呼叫 ReadSessionLocal()，不寫）
write_engine = _make_engine()    # 寫專用（只透過 SessionLocal.begin() 呼叫）

if _is_sqlite:
    def _set_sqlite_pragma(dbapi_conn, _):
        cur = dbapi_conn.cursor()
        cur.execute("PRAGMA journal_mode=WAL")
        cur.execute("PRAGMA foreign_keys=ON")
        cur.execute("PRAGMA busy_timeout=5000")  # 寫鎖序列化，等 5s 不直接報錯
        cur.close()

    event.listens_for(engine, "connect")(_set_sqlite_pragma)

    @event.listens_for(write_engine, "connect")
    def _set_sqlite_pragma_write(dbapi_conn, _):
        _set_sqlite_pragma(dbapi_conn, _)
        # pysqlite 預設會偷偷用自己的隱式交易規則（只有 DML 才 BEGIN，SELECT 不會）。
        # 關掉它、交給 SQLAlchemy 的 "begin" event 全權接管，下面的 BEGIN IMMEDIATE 才吃得到。
        dbapi_conn.isolation_level = None

    @event.listens_for(write_engine, "begin")
    def _begin_immediate(conn):
        # 預設 BEGIN 是 deferred：SELECT 不取鎖，多個 session 可能同時讀到同一份舊值，
        # 各自算完才各別 UPDATE，造成 lost update（雙花 / 賭局雙重派彩 / 孤兒注單）。
        # BEGIN IMMEDIATE 讓每個 write transaction 一開始（連第一個 SELECT 之前）就搶寫鎖，
        # 逼真序列化——同時間只有一個 transaction 能往下走，其餘照 busy_timeout 排隊等。
        # 只套在 write_engine：純讀（ReadSessionLocal）維持 WAL 原本的並發讀，效能不受影響。
        conn.exec_driver_sql("BEGIN IMMEDIATE")

ReadSessionLocal = sessionmaker(bind=engine, expire_on_commit=False, future=True)
SessionLocal = sessionmaker(bind=write_engine, expire_on_commit=False, future=True)


class Base(DeclarativeBase):
    pass


def init_db():
    from models import Student, GameState  # noqa: F401 — 確保 metadata 載入
    import models  # noqa: F401
    Base.metadata.create_all(write_engine)
    # 確保 game_state 單列存在
    with SessionLocal.begin() as s:
        if s.get(models.GameState, 1) is None:
            s.add(models.GameState(id=1, current_day="D1", market_open=1,
                                   settlement_count=0, settled_days="[]"))
