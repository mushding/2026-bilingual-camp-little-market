"""SQLAlchemy engine/session。SQLite + WAL；DATABASE_URL 可換 Postgres（schema 不變）。"""
import os

from sqlalchemy import create_engine, event
from sqlalchemy.orm import DeclarativeBase, sessionmaker

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./flyyoung.db")

_connect_args = {"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {}
engine = create_engine(DATABASE_URL, connect_args=_connect_args, future=True)

if DATABASE_URL.startswith("sqlite"):
    @event.listens_for(engine, "connect")
    def _set_sqlite_pragma(dbapi_conn, _):
        cur = dbapi_conn.cursor()
        cur.execute("PRAGMA journal_mode=WAL")
        cur.execute("PRAGMA foreign_keys=ON")
        cur.execute("PRAGMA busy_timeout=5000")  # 寫鎖序列化，等 5s 不直接報錯
        cur.close()

SessionLocal = sessionmaker(bind=engine, expire_on_commit=False, future=True)


class Base(DeclarativeBase):
    pass


def init_db():
    from models import Student, GameState  # noqa: F401 — 確保 metadata 載入
    import models  # noqa: F401
    Base.metadata.create_all(engine)
    # 確保 game_state 單列存在
    with SessionLocal.begin() as s:
        if s.get(models.GameState, 1) is None:
            s.add(models.GameState(id=1, current_day="D1", market_open=1,
                                   settlement_count=0, settled_days="[]"))
