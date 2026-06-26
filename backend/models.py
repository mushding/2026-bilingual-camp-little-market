"""ORM models — 對應 docs/app/32 §1。"""
from sqlalchemy import Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from db import Base


class Student(Base):
    __tablename__ = "students"
    uid: Mapped[str] = mapped_column(String, primary_key=True)
    name: Mapped[str] = mapped_column(String, nullable=False)
    seed_amount: Mapped[int] = mapped_column(Integer, default=0)
    balance: Mapped[int] = mapped_column(Integer, default=0)
    points: Mapped[int] = mapped_column(Integer, default=0)
    kingdom_points: Mapped[int] = mapped_column(Integer, default=0)
    deposit_balance: Mapped[int] = mapped_column(Integer, default=0)
    card_count: Mapped[int] = mapped_column(Integer, default=0)
    d3_donate_bonus: Mapped[int] = mapped_column(Integer, default=0)
    response_card: Mapped[int] = mapped_column(Integer, default=0)
    final_rank_points: Mapped[int | None] = mapped_column(Integer, nullable=True)
    final_rank_kp: Mapped[int | None] = mapped_column(Integer, nullable=True)
    group: Mapped[str | None] = mapped_column(String, nullable=True)   # 小組（消歧）
    seat_no: Mapped[str | None] = mapped_column(String, nullable=True)  # 座號（消歧）
    created_at: Mapped[str] = mapped_column(String, default="")


class Transaction(Base):
    __tablename__ = "transactions"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    uid: Mapped[str] = mapped_column(String, index=True)
    stall_id: Mapped[str] = mapped_column(String, default="")
    action: Mapped[str] = mapped_column(String)
    amount: Mapped[int] = mapped_column(Integer, default=0)  # +入帳 / -出帳
    balance_after: Mapped[int] = mapped_column(Integer, default=0)
    points_after: Mapped[int] = mapped_column(Integer, default=0)
    kp_after: Mapped[int] = mapped_column(Integer, default=0)
    deposit_after: Mapped[int] = mapped_column(Integer, default=0)
    day: Mapped[str] = mapped_column(String, default="D1")
    meta: Mapped[str] = mapped_column(Text, default="{}")  # JSON
    created_at: Mapped[str] = mapped_column(String, default="")


class GuildTask(Base):
    __tablename__ = "guild_tasks"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    uid: Mapped[str] = mapped_column(String, index=True)
    game_key: Mapped[str] = mapped_column(String)
    difficulty: Mapped[str] = mapped_column(String)
    reward: Mapped[int] = mapped_column(Integer)
    status: Mapped[str] = mapped_column(String, default="pending")  # pending/completed/superseded
    drawn_at: Mapped[str] = mapped_column(String, default="")
    completed_at: Mapped[str | None] = mapped_column(String, nullable=True)
    completed_by: Mapped[str | None] = mapped_column(String, nullable=True)


class CasinoRound(Base):
    __tablename__ = "casino_rounds"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    table: Mapped[str] = mapped_column(String)  # '21'/'dice'
    stall_id: Mapped[str] = mapped_column(String, default="")
    status: Mapped[str] = mapped_column(String, default="open")  # open/settled/void
    dice: Mapped[str | None] = mapped_column(String, nullable=True)  # JSON [d1,d2]
    created_at: Mapped[str] = mapped_column(String, default="")
    settled_at: Mapped[str | None] = mapped_column(String, nullable=True)


class CasinoBet(Base):
    __tablename__ = "casino_bets"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    round_id: Mapped[int] = mapped_column(Integer, index=True)
    uid: Mapped[str] = mapped_column(String, index=True)
    bet_type: Mapped[str] = mapped_column(String)  # '21:play'/'big'/'small'/'seven'
    amount: Mapped[int] = mapped_column(Integer)
    status: Mapped[str] = mapped_column(String, default="placed")  # placed/won/lost/cancelled
    payout: Mapped[int] = mapped_column(Integer, default=0)


class WitnessLog(Base):
    __tablename__ = "witness_log"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    student_uid: Mapped[str] = mapped_column(String, index=True)
    staff_uid: Mapped[str] = mapped_column(String)
    day: Mapped[str] = mapped_column(String, default="")
    __table_args__ = (UniqueConstraint("student_uid", "staff_uid", name="uq_witness"),)


class DeviceToken(Base):
    """關主手機 enrollment token。存 token 的 sha256（不存明文）。"""
    __tablename__ = "device_tokens"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    token_hash: Mapped[str] = mapped_column(String, unique=True, index=True)
    scope: Mapped[str] = mapped_column(String)  # 'admin' | 'staff'
    label: Mapped[str] = mapped_column(String, default="")  # 哪支手機/攤位，方便撤銷
    revoked: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[str] = mapped_column(String, default="")


class GameState(Base):
    __tablename__ = "game_state"
    id: Mapped[int] = mapped_column(Integer, primary_key=True)  # =1
    current_day: Mapped[str] = mapped_column(String, default="D1")
    market_open: Mapped[int] = mapped_column(Integer, default=1)
    settlement_count: Mapped[int] = mapped_column(Integer, default=0)
    settled_days: Mapped[str] = mapped_column(Text, default="[]")  # JSON list
