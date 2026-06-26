"""Pydantic request/response — 對應 docs/app/31 §1–2。"""
from pydantic import BaseModel


class StudentState(BaseModel):
    uid: str
    student_name: str
    group: str = ""             # 組別
    balance: int
    points: int
    kingdom_points: int
    deposit_balance: int
    stall: str = ""
    action: str = ""
    message: str = ""
    ok: bool = True
    # 選用：公會抽派發遊戲
    assigned_game: str | None = None
    # 目前待完成的公會任務（含倒數秒數）
    pending_tasks: list[dict] = []


class ScanReq(BaseModel):
    uid: str
    stall_id: str
    action: str = "lookup"
    amount: int = 0
    cost: int = 0
    reward: int = 0
    tier: int | None = None
    cards: int = 0
    sender_name: str | None = None
    staff_uid: str | None = None


class BindReq(BaseModel):
    uid: str
    name: str
    seed_amount: int
    group: str | None = None
    seat_no: str | None = None


class GuildCompleteReq(BaseModel):
    student_uid: str
    stall_id: str
    staff_uid: str | None = None


class CasinoOpenReq(BaseModel):
    table: str  # '21' | 'dice'
    stall_id: str = ""


class CasinoBetReq(BaseModel):
    round_id: int
    uid: str
    bet_type: str  # '21:play' | 'big' | 'small' | 'seven'
    amount: int


class CasinoCancelReq(BaseModel):
    round_id: int
    uid: str


class CasinoSettleReq(BaseModel):
    round_id: int
    dice: list[int] | None = None              # dice 桌
    results: list[dict] | None = None          # 21 桌 [{uid, win}]


class DayReq(BaseModel):
    day: str  # 'D1'|'D2'|'D3'


class SettleReq(BaseModel):
    day: str


class UidReq(BaseModel):
    uid: str


class EnrollReq(BaseModel):
    code: str
    label: str | None = None


class RevokeReq(BaseModel):
    label: str | None = None
    token: str | None = None
