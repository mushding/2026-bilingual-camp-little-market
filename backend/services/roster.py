"""預先名單 / 大量綁卡：全部操作單一 Student 表。未綁卡 = card_uid IS NULL。"""
import uuid
from datetime import datetime, timezone

from sqlalchemy import select

from models import Student, Transaction


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def list_all(s) -> dict:
    """全名單（含綁卡狀態），依 group / seat_no / name 排序。"""
    rows = s.scalars(select(Student).order_by(Student.group, Student.seat_no,
                                               Student.name)).all()
    entries = [{
        "uid": r.uid, "name": r.name, "group": r.group or "", "seat_no": r.seat_no or "",
        "seed_amount": r.seed_amount, "card_uid": r.card_uid, "bound": r.card_uid is not None,
    } for r in rows]
    bound = sum(1 for e in entries if e["bound"])
    return {"total": len(entries), "bound": bound, "unbound": len(entries) - bound,
            "entries": entries}


def add(s, entries: list) -> dict:
    """批量新增名單（同名不擋——營隊可能真的有同名，靠組別/座號消歧）。尚未綁卡。"""
    added = 0
    for e in entries:
        name = e.name.strip()
        if not name:
            continue
        s.add(Student(uid=uuid.uuid4().hex, name=name,
                      group=(e.group or "").strip() or None,
                      seat_no=(e.seat_no or "").strip() or None,
                      seed_amount=e.seed_amount, balance=e.seed_amount,
                      card_uid=None, created_at=_now()))
        added += 1
    return {"ok": True, "added": added}


def bind(s, uid: str, card_uid: str) -> dict:
    """綁卡：名單裡的人 + 掃到的卡 UID → 寫回 Student.card_uid。"""
    card_uid = card_uid.strip()
    stu = s.get(Student, uid)
    if stu is None:
        return {"ok": False, "message": "查無此名單項目"}
    if stu.card_uid:
        return {"ok": False, "message": f"{stu.name} 已綁過卡（{stu.card_uid}），請先解綁"}
    other = s.scalars(select(Student).where(Student.card_uid == card_uid)).first()
    if other:
        return {"ok": False, "message": f"這張卡已綁給 {other.name}"}
    stu.card_uid = card_uid
    return {"ok": True, "uid": stu.uid, "name": stu.name, "card_uid": card_uid}


def set_group(s, uid: str, group: str | None) -> dict:
    """改組別（未分組/分組皆可）。"""
    stu = s.get(Student, uid)
    if stu is None:
        return {"ok": False, "message": "查無此名單項目"}
    g = (group or "").strip() or None
    stu.group = g
    return {"ok": True, "uid": stu.uid, "name": stu.name, "group": g or ""}


def set_seed(s, uid: str, seed_amount: int) -> dict:
    """改起始金（開賽前修正用）。已有交易紀錄則拒絕。"""
    stu = s.get(Student, uid)
    if stu is None:
        return {"ok": False, "message": "查無此名單項目"}
    txn = s.scalars(select(Transaction).where(Transaction.uid == uid).limit(1)).first()
    if txn:
        return {"ok": False, "message": f"{stu.name} 已有交易紀錄，不可改起始金"}
    stu.seed_amount = seed_amount
    stu.balance = seed_amount
    return {"ok": True, "uid": stu.uid, "name": stu.name, "seed_amount": seed_amount}


def unbind(s, uid: str) -> dict:
    """解綁（營會前修正用）：清 card_uid，身分保留。已有交易紀錄則拒絕。"""
    stu = s.get(Student, uid)
    if stu is None:
        return {"ok": False, "message": "查無此名單項目"}
    if not stu.card_uid:
        return {"ok": False, "message": f"{stu.name} 尚未綁卡"}
    txn = s.scalars(select(Transaction).where(Transaction.uid == uid).limit(1)).first()
    if txn:
        return {"ok": False, "message": f"{stu.name} 已有交易紀錄，不可解綁"}
    old = stu.card_uid
    stu.card_uid = None
    return {"ok": True, "uid": stu.uid, "name": stu.name, "unbound_card_uid": old}


def delete(s, uid: str) -> dict:
    stu = s.get(Student, uid)
    if stu is None:
        return {"ok": False, "message": "查無此名單項目"}
    if stu.card_uid:
        return {"ok": False, "message": f"{stu.name} 已綁卡，請先解綁再刪除"}
    s.delete(stu)
    return {"ok": True, "deleted": uid}


# ── QR 貼紙列印頁（A4，瀏覽器 Ctrl+P → PDF/印出裁切） ──────────────────────
def qr_sheet(s) -> str:
    """所有已綁卡學生一人一張 QR 貼紙（內容=卡片 UID，同 NFC 讀出格式）。"""
    import qrcode
    import qrcode.image.svg

    studs = s.scalars(select(Student).where(Student.card_uid.is_not(None))
                       .order_by(Student.group, Student.seat_no, Student.name)).all()
    cells = []
    for x in studs:
        img = qrcode.make(x.card_uid, image_factory=qrcode.image.svg.SvgPathImage,
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
