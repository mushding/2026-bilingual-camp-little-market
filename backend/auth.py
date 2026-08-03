"""手機 App 驗證 — 只有總控（admin）需要註冊；一般關主（staff）免註冊即可用。

Practice 對應（internal 工具，非對外服務，無惡意使用威脅模型）：
- 一般操作（掃卡記帳等）不需 Bearer，預設視為 staff scope，降低現場設定摩擦。
- /api/admin/* 與報表仍需 admin scope；總控裝置一次性設定碼換隨機 token，
  存手機 Keychain/Keystore，token 只存 sha256（DB 外洩也拿不到原 token），可撤銷。

設定碼走環境變數（不進 repo）：
    ENROLL_ADMIN_CODE  總控設定碼
未設時用開發預設值（部署務必覆蓋）。
"""
import hashlib
import hmac
import os
import secrets
from datetime import datetime, timezone

from sqlalchemy import select

from models import DeviceToken

ADMIN_CODE = os.getenv("ENROLL_ADMIN_CODE", "dev-admin-code")

# 免驗證路徑（前綴比對）
PUBLIC_PATHS = ("/health", "/api/auth/enroll")


def _hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def enroll(session, code: str, label: str = "") -> dict:
    """設定碼 → 發 admin token（只有總控需要註冊）。回 {ok, token, scope}。"""
    if not hmac.compare_digest(code, ADMIN_CODE):
        return {"ok": False, "message": "設定碼錯誤"}
    token = secrets.token_urlsafe(32)
    session.add(DeviceToken(
        token_hash=_hash(token), scope="admin", label=label, revoked=0,
        created_at=datetime.now(timezone.utc).isoformat(timespec="seconds")))
    return {"ok": True, "token": token, "scope": "admin"}


def verify(session, token: str) -> str | None:
    """回 scope（'admin'/'staff'）或 None。"""
    if not token:
        return None
    row = session.scalars(select(DeviceToken).where(
        DeviceToken.token_hash == _hash(token), DeviceToken.revoked == 0)).first()
    return row.scope if row else None


def revoke(session, label: str | None = None, token: str | None = None) -> dict:
    """撤銷：依 label 或原 token。"""
    q = select(DeviceToken).where(DeviceToken.revoked == 0)
    if token:
        q = q.where(DeviceToken.token_hash == _hash(token))
    elif label:
        q = q.where(DeviceToken.label == label)
    else:
        return {"ok": False, "message": "需 label 或 token"}
    rows = session.scalars(q).all()
    for r in rows:
        r.revoked = 1
    return {"ok": True, "revoked": len(rows)}
