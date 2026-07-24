"""預先名單 roster：報名未定案前先建人 → 營會前大量綁卡 → QR 貼紙列印。"""
from datetime import datetime, timezone

from sqlalchemy import select

from models import Roster, Student, Transaction


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def list_all(s) -> dict:
    """全名單（含綁卡狀態），依 group / seat_no / name 排序。"""
    rows = s.scalars(select(Roster).order_by(Roster.group, Roster.seat_no, Roster.name)).all()
    entries = [{
        "id": r.id, "name": r.name, "group": r.group or "", "seat_no": r.seat_no or "",
        "seed_amount": r.seed_amount, "uid": r.uid, "bound": r.uid is not None,
    } for r in rows]
    bound = sum(1 for e in entries if e["bound"])
    return {"total": len(entries), "bound": bound, "unbound": len(entries) - bound,
            "entries": entries}


def add(s, entries: list) -> dict:
    """批量新增名單（同名不擋——營隊可能真的有同名，靠組別/座號消歧）。"""
    added = 0
    for e in entries:
        name = e.name.strip()
        if not name:
            continue
        s.add(Roster(name=name, group=(e.group or "").strip() or None,
                     seat_no=(e.seat_no or "").strip() or None,
                     seed_amount=e.seed_amount, created_at=_now()))
        added += 1
    return {"ok": True, "added": added}


def bind(s, roster_id: int, uid: str) -> dict:
    """綁卡：roster 的人 + 卡 UID → 建 Student、記回 roster.uid。"""
    uid = uid.strip()
    r = s.get(Roster, roster_id)
    if r is None:
        return {"ok": False, "message": "查無此名單項目"}
    if r.uid:
        return {"ok": False, "message": f"{r.name} 已綁過卡（{r.uid}），請先解綁"}
    if s.get(Student, uid):
        return {"ok": False, "message": "這張卡已綁定其他學生"}
    other = s.scalars(select(Roster).where(Roster.uid == uid)).first()
    if other:
        return {"ok": False, "message": f"這張卡已綁給 {other.name}"}
    s.add(Student(uid=uid, name=r.name, seed_amount=r.seed_amount, balance=r.seed_amount,
                  group=r.group, seat_no=r.seat_no, created_at=_now()))
    r.uid = uid
    return {"ok": True, "roster_id": r.id, "name": r.name, "uid": uid}


def unbind(s, roster_id: int) -> dict:
    """解綁（營會前修正用）：清 roster.uid、刪 Student。已有交易紀錄則拒絕。"""
    r = s.get(Roster, roster_id)
    if r is None:
        return {"ok": False, "message": "查無此名單項目"}
    if not r.uid:
        return {"ok": False, "message": f"{r.name} 尚未綁卡"}
    txn = s.scalars(select(Transaction).where(Transaction.uid == r.uid).limit(1)).first()
    if txn:
        return {"ok": False, "message": f"{r.name} 已有交易紀錄，不可解綁"}
    stu = s.get(Student, r.uid)
    if stu:
        s.delete(stu)
    old = r.uid
    r.uid = None
    return {"ok": True, "roster_id": r.id, "name": r.name, "unbound_uid": old}


def delete(s, roster_id: int) -> dict:
    r = s.get(Roster, roster_id)
    if r is None:
        return {"ok": False, "message": "查無此名單項目"}
    if r.uid:
        return {"ok": False, "message": f"{r.name} 已綁卡，請先解綁再刪除"}
    s.delete(r)
    return {"ok": True, "deleted": roster_id}


# ── QR 貼紙列印頁（A4，瀏覽器 Ctrl+P → PDF/印出裁切） ──────────────────────
def qr_sheet(s) -> str:
    """所有已綁卡學生一人一張 QR 貼紙（內容=UID，同 NFC 讀出格式）。"""
    import qrcode
    import qrcode.image.svg

    studs = s.scalars(select(Student).order_by(Student.group, Student.seat_no,
                                               Student.name)).all()
    cells = []
    for x in studs:
        img = qrcode.make(x.uid, image_factory=qrcode.image.svg.SvgPathImage,
                          border=1)
        svg = img.to_string().decode()
        sub = " / ".join(v for v in [x.group, x.seat_no] if v)
        cells.append(f'<div class="cell">{svg}'
                     f'<div class="nm">{x.name}</div>'
                     f'<div class="sb">{sub}</div></div>')
    return f"""<!doctype html><html lang="zh-Hant"><head><meta charset="utf-8">
<title>QR 貼紙（{len(cells)} 張）</title>
<style>
  @page {{ size: A4; margin: 8mm; }}
  body {{ margin: 0; font-family: -apple-system, "PingFang TC", sans-serif; }}
  .sheet {{ display: flex; flex-wrap: wrap; align-content: flex-start; }}
  .cell {{ width: 24mm; height: 28mm; border: 0.3mm dashed #aaa; text-align: center;
           overflow: hidden; page-break-inside: avoid; }}
  .cell svg {{ width: 17mm; height: 17mm; margin-top: 1mm; }}
  .nm {{ font-size: 9px; font-weight: 700; line-height: 1.1; }}
  .sb {{ font-size: 7px; color: #666; line-height: 1.1; }}
  .hint {{ font-size: 12px; color: #888; padding: 4mm; }}
  @media print {{ .hint {{ display: none; }} }}
</style></head><body>
<div class="hint">Ctrl/⌘+P 列印或存 PDF。共 {len(cells)} 張，沿虛線裁切、貼卡片角落。</div>
<div class="sheet">{''.join(cells)}</div>
</body></html>"""
