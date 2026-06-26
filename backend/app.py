"""小市集 Backend — FastAPI 正式版。docs/app/31。

啟動：
    uvicorn app:app --host 0.0.0.0 --port 8000
所有寫入走 SessionLocal.begin() 單一 transaction（原子）。
"""
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Query, Request, UploadFile
from fastapi.responses import HTMLResponse, JSONResponse

import auth
import schemas
from db import SessionLocal, init_db
from services import bank, casino, guild, report
from services.txn import handle_scan


@asynccontextmanager
async def lifespan(_: FastAPI):
    init_db()
    yield


app = FastAPI(title="小市集 Backend v1.0", lifespan=lifespan)

# 需要 admin scope 的路徑前綴（admin 操作 + 報表含全體資料）
ADMIN_PREFIXES = ("/api/admin/", "/api/report")


@app.middleware("http")
async def require_token(request: Request, call_next):
    """Bearer token 驗證。/health 與 /api/auth/enroll 免驗；/api/admin/* 與報表需 admin。"""
    path = request.url.path
    if path in ("/health",) or path.startswith("/api/auth/enroll"):
        return await call_next(request)

    hdr = request.headers.get("authorization", "")
    token = hdr[7:] if hdr.lower().startswith("bearer ") else ""
    with SessionLocal() as s:
        scope = auth.verify(s, token)
    if scope is None:
        return JSONResponse({"ok": False, "message": "未授權（請重新註冊裝置）"}, status_code=401)
    if any(path.startswith(p) for p in ADMIN_PREFIXES) and scope != "admin":
        return JSONResponse({"ok": False, "message": "需總控權限"}, status_code=403)
    return await call_next(request)


# ── 裝置註冊 / 撤銷 ──────────────────────────────────────────────────────
@app.post("/api/auth/enroll")
def auth_enroll(req: schemas.EnrollReq):
    with SessionLocal.begin() as s:
        return auth.enroll(s, req.code, req.label or "")


@app.post("/api/admin/revoke")
def auth_revoke(req: schemas.RevokeReq):
    with SessionLocal.begin() as s:
        return auth.revoke(s, label=req.label, token=req.token)


@app.get("/")
def root():
    with SessionLocal() as s:
        return {"ok": True, **bank.admin_state(s)}


@app.get("/health")
def health():
    return {"ok": True}


# ── 單學生交易主入口 ─────────────────────────────────────────────────────
@app.post("/api/scan")
def scan(req: schemas.ScanReq):
    with SessionLocal.begin() as s:
        return handle_scan(s, req).model_dump()


# ── 郵政 by-name 反查 ───────────────────────────────────────────────────
@app.get("/api/students/search")
def students_search(name: str = Query(...)):
    from sqlalchemy import select
    from models import Student
    with SessionLocal() as s:
        rows = s.scalars(select(Student).where(Student.name == name)).all()
        return [{"uid": r.uid, "name": r.name, "group": r.group, "seat_no": r.seat_no}
                for r in rows]


# ── 公會 ────────────────────────────────────────────────────────────────
@app.get("/api/guild/pending")
def guild_pending(stall_id: str = Query(...)):
    with SessionLocal.begin() as s:  # pending 會掃描逾時任務（需可寫）
        return guild.pending(s, stall_id)


@app.post("/api/guild/complete")
def guild_complete(req: schemas.GuildCompleteReq):
    with SessionLocal.begin() as s:
        return guild.complete(s, req.student_uid, req.stall_id, req.staff_uid).model_dump()


# ── 賭場 ────────────────────────────────────────────────────────────────
@app.post("/api/casino/open")
def casino_open(req: schemas.CasinoOpenReq):
    with SessionLocal.begin() as s:
        return casino.open_round(s, req.table, req.stall_id)


@app.post("/api/casino/bet")
def casino_bet(req: schemas.CasinoBetReq):
    with SessionLocal.begin() as s:
        return casino.bet(s, req.round_id, req.uid, req.bet_type, req.amount)


@app.post("/api/casino/cancel")
def casino_cancel(req: schemas.CasinoCancelReq):
    with SessionLocal.begin() as s:
        return casino.cancel(s, req.round_id, req.uid)


@app.post("/api/casino/settle")
def casino_settle(req: schemas.CasinoSettleReq):
    with SessionLocal.begin() as s:
        return casino.settle(s, req.round_id, dice=req.dice, results=req.results)


@app.get("/api/casino/round/{round_id}")
def casino_round(round_id: int):
    with SessionLocal() as s:
        return casino.get_round(s, round_id)


# ── 管理（總控） ────────────────────────────────────────────────────────
@app.post("/api/admin/set_day")
def admin_set_day(req: schemas.DayReq):
    with SessionLocal.begin() as s:
        return bank.set_day(s, req.day)


@app.post("/api/admin/settle_interest")
def admin_settle_interest(req: schemas.SettleReq):
    with SessionLocal.begin() as s:
        return bank.settle_interest(s, req.day)


@app.post("/api/admin/market_close")
def admin_market_close():
    with SessionLocal.begin() as s:
        out = bank.market_close(s)
        if out.get("ok"):
            report.compute_ranks(s)  # 關市後凍結名次
        return out


@app.get("/api/admin/state")
def admin_get_state():
    with SessionLocal() as s:
        return bank.admin_state(s)


@app.post("/api/admin/bind")
def admin_bind(req: schemas.BindReq):
    from datetime import datetime, timezone
    from models import Student
    with SessionLocal.begin() as s:
        if s.get(Student, req.uid):
            return {"ok": False, "message": "UID 已綁定", "uid": req.uid}
        s.add(Student(uid=req.uid, name=req.name, seed_amount=req.seed_amount,
                      balance=req.seed_amount, group=req.group, seat_no=req.seat_no,
                      created_at=datetime.now(timezone.utc).isoformat(timespec="seconds")))
        return {"ok": True, "uid": req.uid, "name": req.name, "seed_amount": req.seed_amount}


@app.post("/api/admin/import")
async def admin_import(file: UploadFile):
    import csv
    import io
    from datetime import datetime, timezone
    from models import Student
    raw = (await file.read()).decode("utf-8-sig")
    reader = csv.DictReader(io.StringIO(raw))
    imported, skipped, errors = 0, 0, []
    with SessionLocal.begin() as s:
        for i, row in enumerate(reader, 1):
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
    return {"imported": imported, "skipped": skipped, "errors": errors}


# ── 報表 ────────────────────────────────────────────────────────────────
@app.get("/api/report/{uid}/data")
def report_data(uid: str):
    with SessionLocal() as s:
        data = report.build_data(s, uid)
        if data is None:
            raise HTTPException(404, "查無此學生")
        return data


@app.get("/api/report/{uid}", response_class=HTMLResponse)
def report_html(uid: str):
    with SessionLocal() as s:
        data = report.build_data(s, uid)
        if data is None:
            raise HTTPException(404, "查無此學生")
        return report.render_html(data)


@app.get("/api/report")
def report_all():
    """批次：列所有人 + report link。"""
    from sqlalchemy import select
    from models import Student
    with SessionLocal() as s:
        studs = s.scalars(select(Student)).all()
        return JSONResponse([
            {"uid": x.uid, "name": x.name, "final_points": x.points,
             "kingdom_points": x.kingdom_points, "report": f"/api/report/{x.uid}"}
            for x in studs])
