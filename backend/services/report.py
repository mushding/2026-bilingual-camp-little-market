"""營後報表 — docs/app/31 §7。只讀 transactions（單一真相），重算保證對帳。

曲線採後端內嵌 SVG（無外部依賴，弱網/批印安全）。
"""
import html
import json
from datetime import datetime, timedelta, timezone

from sqlalchemy import select

from models import Student, Transaction

TAIPEI = timezone(timedelta(hours=8))  # 台灣全年 UTC+8，無日光節約，免查 zoneinfo


def _local(ts: str) -> str:
    """UTC ISO 字串（now_iso() 寫入的格式）→ 台灣時間 'MM-DD HH:MM'（給報表顯示用）。
    資料庫一律存 UTC；只有這裡、顯示當下才轉時區——不要去改 GCE 系統時區，
    程式裡 datetime.now(timezone.utc) 不受 OS 時區設定影響，改了也沒用。"""
    try:
        dt = datetime.fromisoformat(ts).astimezone(TAIPEI)
    except (ValueError, TypeError):
        return ts[5:16].replace("T", " ") if ts else ""
    return dt.strftime("%m-%d %H:%M")

# 入帳類 / 出帳類 action 分類（casino_bet/cancel 排除：只是凍結/退款，僅影響餘額曲線）
# v2.15：轉帳（純移轉）與積分兌換（現金→積分轉換）不計收入/花費，
# 避免互轉刷「最會賺錢/刺激經濟」、換積分灌花費。
INCOME_ACTIONS = {"credit", "guild_complete", "interest", "topic1_credit"}
EXPENSE_ACTIONS = {"debit", "meal", "donate", "guild_draw", "task_expired"}
KP_ACTIONS = {"donate", "credit_kp", "mail_kp", "transfer_out"}

# stall_id → 中文攤位名（對齊 lib/data/stalls.dart）
STALL_NAMES = {
    "day1_doll": "賣娃娃", "day1_ring": "套圈圈", "day1_dart": "射飛鏢",
    "day1_bingo": "麻將賓果", "bank": "銀行", "meal": "餐費",
    "witness": "聊天聽見證", "donation": "舊鞋救命", "exchange": "積分兌換",
    "grocery": "雜貨店", "mail": "郵政", "casino_21": "玩 10點半遊戲",
    "casino_dice": "玩 骰子遊戲", "guild": "公會台",
    "game_color": "顏色分類", "game_password": "終極密碼", "game_moving": "搬家人工",
    "game_basketball": "疊杯子", "game_plane": "丟紙飛機", "game_balloon": "拍氣球",
    "game_charades": "比手畫腳", "game_memory": "記憶翻牌", "game_tangram": "七巧板",
    "topic1": "主題一：大地遊戲", "system": "系統",
}
# action → 中文動作名
ACTION_NAMES = {
    "credit": "入帳", "debit": "消費", "deposit": "定存存入", "withdraw": "定存提領",
    "meal": "餐費", "donate": "奉獻", "exchange_points": "積分兌換",
    "guild_draw": "公會抽任務", "guild_complete": "完成任務", "interest": "定存利息",
    "game_settle": "遊戲結算", "casino_bet": "參與遊戲", "casino_payout": "遊戲獎金",
    "casino_cancel": "退還遊戲金", "credit_kp": "天國點數", "mail_kp": "感謝卡核銷",
    "task_expired": "任務逾時", "market_close": "市場結算折現",
    "interest_tick": "利息計算",
    "adjust_transfer_points": "積分補正（轉帳回收）", "adjust_transfer_kp": "KP 補正（轉帳回收）",
    "transfer_out": "轉帳轉出", "transfer_in": "轉帳轉入",
    "topic1_credit": "主題一：闖關獎金",
}
def _stall_zh(sid): return STALL_NAMES.get(sid or "", sid or "—")
def _action_zh(a): return ACTION_NAMES.get(a, a)


def build_data(session, uid: str) -> dict | None:
    s = session.get(Student, uid)
    if s is None:
        return None
    txns = session.scalars(select(Transaction).where(Transaction.uid == uid)
                           .order_by(Transaction.created_at, Transaction.id)).all()

    total_income = 0
    total_expense = 0
    exchanged_points = 0
    residual = 0
    balance_curve, points_curve, kp_curve, ledger = [], [], [], []

    for t in txns:
        meta = json.loads(t.meta or "{}")
        a = t.action
        if a == "game_settle":
            total_expense += meta.get("cost", 0)
            total_income += meta.get("reward", 0)
        elif a == "casino_payout":
            net = meta.get("net", 0)
            if net >= 0:
                total_income += net
            else:
                total_expense += -net
        elif a in INCOME_ACTIONS:
            total_income += abs(t.amount)
        elif a in EXPENSE_ACTIONS:
            total_expense += abs(t.amount)
        elif a == "exchange_points":  # 不計花費，仍統計已兌換積分
            exchanged_points += meta.get("points", 0)
        elif a == "market_close":
            residual = t.amount  # 折算進積分的部分

        balance_curve.append({"ts": t.created_at, "balance": t.balance_after,
                              "deposit": t.deposit_after})
        points_curve.append({"ts": t.created_at, "points": t.points_after})
        kp_curve.append({"ts": t.created_at, "kp": t.kp_after})
        # 賭場輸的那筆 casino_payout：下注當下已扣款，這筆本身不再變動餘額，
        # 只是為了讓總花費/ROI 統計正確而寫的紀錄——印在明細表只會讓人誤以為扣兩次錢，跳過不顯示。
        if a == "casino_payout" and not meta.get("win", True):
            continue
        ledger.append({"ts": _local(t.created_at), "stall": t.stall_id, "action": a,
                       "amount": t.amount, "balance_after": t.balance_after,
                       "day": t.day})

    seed = s.seed_amount or 0
    roi = round((total_income - total_expense) / seed * 100, 1) if seed else 0.0
    rank_points, rank_kp = live_ranks(session, s.uid)

    return {
        "uid": s.uid, "card_uid": s.card_uid, "name": s.name, "seed": seed,
        "final_points": s.points, "kingdom_points": s.kingdom_points,
        "rank_points": rank_points, "rank_kp": rank_kp,
        "total_income": total_income, "total_expense": total_expense,
        "roi_pct": roi, "exchanged_points": exchanged_points,
        "residual_cash_to_points": residual, "deposit_final": s.deposit_balance,
        "balance_curve": balance_curve, "points_curve": points_curve,
        "kp_curve": kp_curve, "ledger": ledger,
    }


def bulk_expense_income(session) -> dict[str, tuple[int, int]]:
    """全體學生的 (total_income, total_expense)，一次查完給頒獎榜用。
    分類邏輯同 build_data()，只是攤平到所有人一次算，不逐人重查 Transaction。"""
    from collections import defaultdict
    totals: dict[str, list[int]] = defaultdict(lambda: [0, 0])
    for t in session.scalars(select(Transaction)):
        meta = json.loads(t.meta or "{}")
        a = t.action
        row = totals[t.uid]
        if a == "game_settle":
            row[1] += meta.get("cost", 0)
            row[0] += meta.get("reward", 0)
        elif a == "casino_payout":
            net = meta.get("net", 0)
            if net >= 0:
                row[0] += net
            else:
                row[1] += -net
        elif a in INCOME_ACTIONS:
            row[0] += abs(t.amount)
        elif a in EXPENSE_ACTIONS:
            row[1] += abs(t.amount)
    return {uid: (v[0], v[1]) for uid, v in totals.items()}


def live_ranks(session, uid: str) -> tuple[int | None, int | None]:
    """即時名次（積分榜／管家獎），依目前全體已綁卡「學員」現況即算即回，不等 market_close。
    輔導/測試不入榜（tag != 學員 → 名次 None）。"""
    studs = session.scalars(select(Student).where(
        Student.card_uid.is_not(None), Student.tag == "學員")).all()
    by_points = sorted(studs, key=lambda x: x.points, reverse=True)
    by_kp = sorted(studs, key=lambda x: x.kingdom_points, reverse=True)
    rp = next((i for i, x in enumerate(by_points, 1) if x.uid == uid), None)
    rk = next((i for i, x in enumerate(by_kp, 1) if x.uid == uid), None)
    return rp, rk


def compute_ranks(session):
    """market_close 後把名次「凍結」寫回快取（供 dashboard 等其他頁面顯示定案排名）。
    report 本身已改用 live_ranks() 即時算，不依賴這裡的快取。"""
    studs = session.scalars(select(Student).where(
        Student.card_uid.is_not(None), Student.tag == "學員")).all()
    for i, s in enumerate(sorted(studs, key=lambda x: x.points, reverse=True), 1):
        s.final_rank_points = i
    for i, s in enumerate(sorted(studs, key=lambda x: x.kingdom_points, reverse=True), 1):
        s.final_rank_kp = i


# ── SVG 折線（含面積填色，A4 列印友善） ──────────────────────────────────
def _svg_line(points: list[int], color: str, w=460, h=96, pad=14) -> str:
    lo, hi = (min(points), max(points)) if points else (0, 0)
    span = (hi - lo) or 1
    n = len(points)
    dx = (w - 2 * pad) / max(n - 1, 1)
    coords = [(pad + i * dx, h - pad - (v - lo) / span * (h - 2 * pad))
              for i, v in enumerate(points)] or [(pad, h - pad)]
    line = " ".join(f"{x:.1f},{y:.1f}" for x, y in coords)
    area = (f"M{coords[0][0]:.1f},{h-pad:.1f} "
            + " ".join(f"L{x:.1f},{y:.1f}" for x, y in coords)
            + f" L{coords[-1][0]:.1f},{h-pad:.1f} Z")
    gid = f"g{abs(hash((color, n, hi, lo))) % 100000}"
    return (
        f'<svg viewBox="0 0 {w} {h}" width="100%" preserveAspectRatio="none" '
        f'style="display:block">'
        f'<defs><linearGradient id="{gid}" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" stop-color="{color}" stop-opacity="0.22"/>'
        f'<stop offset="1" stop-color="{color}" stop-opacity="0"/></linearGradient></defs>'
        f'<line x1="{pad}" y1="{h-pad:.1f}" x2="{w-pad}" y2="{h-pad:.1f}" '
        f'stroke="#e6ddc9" stroke-width="1"/>'
        f'<path d="{area}" fill="url(#{gid})"/>'
        f'<polyline fill="none" stroke="{color}" stroke-width="2.2" '
        f'stroke-linejoin="round" stroke-linecap="round" points="{line}"/>'
        f'<text x="{pad}" y="12" font-size="9" fill="#a99">max {hi}</text>'
        f'<text x="{pad}" y="{h-3}" font-size="9" fill="#a99">min {lo}</text></svg>')


# 主題色票 — 2026 理財島之好管家主視覺（奶油底／湖水綠／沙金／珊瑚橘）。改配色只動這裡。
# 變數名沿用 green/gold/purple，值已對齊主視覺：green=湖水綠、gold=沙金、purple=珊瑚橘。
_STYLE = """
:root {
  --ink:#3a3326; --muted:#9a8f76; --paper:#f7f0d8; --panel:#fffdf5;
  --green:#2f8a80; --green-soft:#e2efe9; --gold:#cf9a2f; --gold-soft:#f7ecc8;
  --purple:#e07b3f; --purple-soft:#fbe6d6; --line:#e6dcc0; --pos:#2f8a80; --neg:#c0492b;
}
* { box-sizing:border-box; }
@page { size:A4; margin:11mm; }
body { font-family:-apple-system,"PingFang TC","Microsoft JhengHei",sans-serif;
       color:var(--ink); margin:0; background:var(--paper);
       -webkit-print-color-adjust:exact; print-color-adjust:exact; }
.page { background:var(--paper); padding:4mm 2mm 28mm; position:relative; }
.page + .page { page-break-before:always; }
.deco { position:absolute; z-index:0; pointer-events:none; }
.deco.tr { top:2mm; right:3mm; opacity:.55; }
.deco.bl { bottom:2mm; left:0; opacity:.95; }
.deco.br { bottom:2mm; right:0; opacity:.95; }
.content { position:relative; z-index:1; }

.hd { display:flex; justify-content:space-between; align-items:flex-end;
      border-bottom:2.5px solid var(--green); padding-bottom:8px; }
.hd .camp { font-size:12px; letter-spacing:3px; color:var(--green); font-weight:700; }
.hd .name { font-size:26px; font-weight:800; margin:2px 0 0; }
.hd .name small { font-size:13px; font-weight:500; color:var(--muted); letter-spacing:1px; }
.hd .meta { text-align:right; font-size:11px; color:var(--muted); line-height:1.6; }
.hd .theme { font-size:13px; color:var(--gold); font-weight:700; }

.tracks { display:flex; gap:12px; margin:14px 0; }
.track { flex:1; border-radius:12px; padding:14px 16px; position:relative;
         background:var(--green-soft); border:1.5px solid var(--green); }
.track.kp { background:var(--purple-soft); border-color:var(--purple); }
.track .l { font-size:12px; color:var(--green); font-weight:700; }
.track.kp .l { color:var(--purple); }
.track .big { font-size:38px; font-weight:800; line-height:1.05; margin-top:2px; }
.track .rk { position:absolute; top:14px; right:16px; font-size:12px; font-weight:700;
             background:#fff; border:1px solid var(--line); border-radius:20px; padding:2px 10px; }

.kpis { display:grid; grid-template-columns:repeat(6,1fr); gap:8px; margin:12px 0; }
.kpi { background:var(--panel); border:1px solid var(--line); border-radius:10px; padding:9px 11px; }
.kpi .l { font-size:10.5px; color:var(--muted); }
.kpi .v { font-size:19px; font-weight:700; margin-top:1px; font-variant-numeric:tabular-nums; }

.charts { display:grid; grid-template-columns:1fr 1fr; gap:10px 14px; margin:8px 0 4px; }
.chart { background:var(--panel); border:1px solid var(--line); border-radius:10px; padding:8px 10px; }
.chart h3 { font-size:12px; margin:0 0 2px; color:var(--ink); font-weight:700; }
.chart h3 .dot { display:inline-block; width:8px; height:8px; border-radius:50%; margin-right:5px; }

.ledger-h { font-size:12px; font-weight:700; margin:12px 0 4px; color:var(--green); }
table { border-collapse:collapse; width:100%; font-size:10.5px; }
th,td { padding:4px 8px; border-bottom:1px solid var(--line); }
th { background:var(--green); color:#fff; text-align:left; font-weight:600; }
tbody tr:nth-child(even) { background:#fdfaf2; }
/* 帳本長 → 瀏覽器自動換頁；表頭每頁重複、列不被切半（雙面列印友善） */
thead { display:table-header-group; }
tr { page-break-inside:avoid; break-inside:avoid; }
.hd,.tracks,.kpis,.charts,.msg { break-inside:avoid; }
.print-color { background:var(--green); color:#fff; } /* 強制保留表頭底色於列印 */
td.r,th.r { text-align:right; font-variant-numeric:tabular-nums; }
.tag { font-size:9.5px; padding:1px 7px; border-radius:10px; background:var(--gold-soft);
       color:var(--gold); white-space:nowrap; }

.msg { margin-top:14px; padding:12px 16px; background:var(--gold-soft);
       border-left:4px solid var(--gold); border-radius:0 8px 8px 0; font-size:12.5px; line-height:1.7; }
.msg b { color:var(--green); }
"""

# 省紙精簡版（左右並排：一張 A4 橫放塞兩人）。字級/間距等比縮小約 0.6～0.65，
# 裝飾插圖縮小騰出空間。只加在 render_all(compact=True) 之後，靠 CSS cascade
# 覆蓋 _STYLE，不用另外維護一份版面。兩人一組包一個 .sheet（見 _pair_bodies），
# .sheet 之間才換頁；.sheet 內兩個 .page 用 flex 並排，需覆蓋掉基本樣式的
# `.page + .page { page-break-before:always }`（否則右邊那份會被擠去下一頁）。
_COMPACT_STYLE = """
@page { size:A4 landscape; margin:8mm; }
.sheet { display:flex; gap:8mm; align-items:flex-start; }
.sheet + .sheet { page-break-before:always; }
.sheet .page { flex:1 1 0; min-width:0; padding:2mm 2mm 4mm; }
.sheet .page + .page { page-break-before:auto; border-left:1px dashed var(--line); padding-left:4mm; }
.deco { transform:scale(.55); }
.deco.tr { top:-3mm; right:-3mm; }
.deco.bl { bottom:-3mm; left:-3mm; }
.deco.br { bottom:-3mm; right:-3mm; }
.hd { padding-bottom:5px; }
.hd .camp { font-size:8px; letter-spacing:2px; }
.hd .name { font-size:17px; }
.hd .name small { font-size:9px; }
.hd .meta { font-size:8px; }
.hd .theme { font-size:9px; }
.tracks { gap:7px; margin:8px 0; }
.track { padding:8px 10px; border-radius:8px; }
.track .l { font-size:8px; }
.track .big { font-size:23px; }
.track .rk { top:8px; right:10px; font-size:8px; padding:1px 6px; }
.kpis { grid-template-columns:repeat(3,1fr); gap:5px; margin:7px 0; }
.kpi { padding:5px 7px; border-radius:7px; }
.kpi .l { font-size:7px; }
.kpi .v { font-size:12.5px; }
.charts { gap:5px 7px; margin:5px 0 3px; }
.chart { padding:4px 6px; border-radius:7px; }
.chart h3 { font-size:7.5px; }
.chart h3 .dot { width:5px; height:5px; margin-right:3px; }
.ledger-h { font-size:8px; margin:7px 0 3px; }
table { font-size:6.5px; }
th,td { padding:2px 4px; }
.tag { font-size:6px; padding:0 4px; }
.msg { margin-top:8px; padding:6px 9px; font-size:7.8px; border-left-width:3px; }
"""

_CAMP_TITLE = "2026 理財島之好管家 · 小市集"
_THEME = "忠心的好管家"

# 頁角小插圖（內嵌 SVG，對齊主視覺：湖水綠雲、椰子島、沙丘樹叢）。列印安全、無外部依賴。
_C = "#7cc1ba"   # 雲（淺湖水綠）
_TEAL = "#2f8a80"; _TEAL_D = "#247169"; _SAND = "#e3b340"; _TRUNK = "#8a5a3b"; _CORAL = "#d98b4a"

def _cloud(x, y, s):
    return (f'<g transform="translate({x},{y}) scale({s})" fill="{_C}">'
            f'<ellipse cx="22" cy="20" rx="22" ry="11"/><circle cx="12" cy="15" r="9"/>'
            f'<circle cx="26" cy="11" r="12"/><circle cx="38" cy="16" r="8"/></g>')

_DECO_CLOUDS = (f'<svg width="150" height="60" viewBox="0 0 150 60">'
                f'{_cloud(0,8,1.0)}{_cloud(70,0,0.7)}</svg>')

# 左下：椰子島
_DECO_ISLAND = f'''<svg width="170" height="92" viewBox="0 0 170 92">
<ellipse cx="70" cy="80" rx="62" ry="12" fill="{_CORAL}"/>
<ellipse cx="70" cy="78" rx="62" ry="7" fill="#e7a05c"/>
<path d="M52,80 C49,58 55,46 60,38" stroke="{_TRUNK}" stroke-width="5" fill="none" stroke-linecap="round"/>
<g fill="{_TEAL}"><path d="M60,38 C44,30 30,34 26,44 C40,40 52,42 60,46 Z"/>
<path d="M60,38 C76,30 90,36 92,46 C80,40 68,42 60,46 Z"/>
<path d="M60,40 C52,24 40,18 30,20 C44,24 54,32 60,46 Z"/>
<path d="M60,40 C70,24 84,20 92,24 C78,26 68,34 60,46 Z"/></g>
<path d="M104,80 C102,64 106,55 110,49" stroke="{_TRUNK}" stroke-width="4" fill="none" stroke-linecap="round"/>
<g fill="{_TEAL_D}"><path d="M110,49 C98,43 88,46 86,54 C97,50 105,52 110,55 Z"/>
<path d="M110,49 C122,43 132,47 133,55 C123,50 116,52 110,55 Z"/></g>
</svg>'''

# 右下：沙丘 + 樹叢 + 山洞
_DECO_DUNE = f'''<svg width="220" height="110" viewBox="0 0 220 110">
<path d="M0,110 C70,70 150,70 220,92 L220,110 Z" fill="{_SAND}"/>
<path d="M0,110 C70,78 150,78 220,98 L220,110 Z" fill="#edc863"/>
<path d="M150,98 C150,80 190,80 190,98 Z" fill="{_TRUNK}"/>
<ellipse cx="170" cy="98" rx="22" ry="10" fill="#6b4630"/>
<path d="M148,99 a22,20 0 0 1 44,0 Z" fill="#4a3020"/>
<rect x="118" y="60" width="7" height="34" rx="3" fill="{_TRUNK}"/>
<circle cx="121" cy="52" r="17" fill="{_TEAL}"/><circle cx="108" cy="60" r="12" fill="{_TEAL_D}"/>
<circle cx="134" cy="60" r="12" fill="{_TEAL_D}"/>
<rect x="198" y="56" width="6" height="40" rx="3" fill="{_TRUNK}"/>
<circle cx="201" cy="50" r="15" fill="{_TEAL_D}"/><circle cx="190" cy="58" r="10" fill="{_TEAL}"/>
</svg>'''


def _render_body(data: dict) -> str:
    """單張成績單內容（不含 <html>/<head>），供單張與批次列印共用。"""
    esc = lambda x: html.escape(str(x))
    assets = [p["balance"] + p["deposit"] for p in data["balance_curve"]]
    deposits = [p["deposit"] for p in data["balance_curve"]]
    pts = [p["points"] for p in data["points_curve"]]
    kps = [p["kp"] for p in data["kp_curve"]]

    rows = "".join(
        f'<tr><td>{esc(l["ts"])}</td>'
        f'<td>{esc(l["day"])}</td>'
        f'<td><span class="tag">{esc(_stall_zh(l["stall"]))}</span></td>'
        f'<td>{esc(_action_zh(l["action"]))}</td>'
        f'<td class="r" style="color:{"var(--pos)" if l["amount"]>=0 else "var(--neg)"};font-weight:600">'
        f'{"+" if l["amount"]>=0 else ""}{l["amount"]}</td>'
        f'<td class="r">{l["balance_after"]}</td></tr>'
        for l in data["ledger"]
    )
    rp = data["rank_points"] or "—"
    rk = data["rank_kp"] or "—"

    def chart(title, color, series):
        return (f'<div class="chart"><h3><span class="dot" style="background:{color}"></span>'
                f'{title}</h3>{_svg_line(series, color)}</div>')

    return f"""<div class="page">
<div class="deco tr">{_DECO_CLOUDS}</div>
<div class="deco bl">{_DECO_ISLAND}</div>
<div class="deco br">{_DECO_DUNE}</div>
<div class="content">
<div class="hd">
  <div>
    <div class="camp">{_CAMP_TITLE}</div>
    <div class="name">{esc(data['name'])} <small>個人成績單</small></div>
  </div>
  <div class="meta">
    <div class="theme">主題 · {_THEME}</div>
    UID {esc(data['card_uid'] or '未綁卡')}<br>起始金 ${data['seed']}
  </div>
</div>

<div class="tracks">
  <div class="track"><span class="rk">名次 #{rp}</span>
    <div class="l">積分榜（地上總資產）</div><div class="big">{data['final_points']}</div></div>
  <div class="track kp"><span class="rk">名次 #{rk}</span>
    <div class="l">管家獎（天國點數）</div><div class="big">{data['kingdom_points']}</div></div>
</div>

<div class="kpis">
  <div class="kpi"><div class="l">總進帳</div><div class="v">{data['total_income']}</div></div>
  <div class="kpi"><div class="l">總花費</div><div class="v">{data['total_expense']}</div></div>
  <div class="kpi"><div class="l">ROI</div><div class="v">{data['roi_pct']}%</div></div>
  <div class="kpi"><div class="l">已兌換積分</div><div class="v">{data['exchanged_points']}</div></div>
  <div class="kpi"><div class="l">現金折算積分</div><div class="v">{data['residual_cash_to_points']}</div></div>
  <div class="kpi"><div class="l">定存本利</div><div class="v">{data['deposit_final']}</div></div>
</div>

<div class="charts">
  {chart('總資產（現金＋定存）', '#2f8a80', assets)}
  {chart('定存軌', '#3a7ca8', deposits)}
  {chart('積分變化', '#cf9a2f', pts)}
  {chart('天國點數變化', '#e07b3f', kps)}
</div>

<div class="ledger-h">交易明細</div>
<table><thead><tr><th>時間</th><th>天</th><th>攤位</th><th>動作</th>
<th class="r">金額</th><th class="r">餘額</th></tr></thead><tbody>
{rows}</tbody></table>

<div class="msg"><b>「敬虔加上知足的心便是大利了」</b>（提摩太前書 6:6）<br>
地上的財寶會朽壞、帶不走（市場關閉 ×0.1）；存在天上的（天國點數）卻存得住、帶得走。<br>
願你成為又良善又忠心的好管家。
</div>
</div>
</div>"""


def _wrap(title: str, body: str, extra_style: str = "") -> str:
    return (f'<!doctype html><html lang="zh-Hant"><head><meta charset="utf-8">'
            f'<title>{html.escape(title)}</title><style>{_STYLE}{extra_style}</style></head>'
            f'<body>{body}</body></html>')


def render_html(data: dict) -> str:
    return _wrap(f"{data['name']} · 小市集成績單", _render_body(data))


def _pair_bodies(datas: list[dict]) -> str:
    """省紙版排版：兩人一組包成 .sheet，靠 flex 在同一張 A4 橫放紙上左右並排。"""
    sheets = []
    for i in range(0, len(datas), 2):
        pair = datas[i:i + 2]
        sheets.append('<div class="sheet">' + "".join(_render_body(d) for d in pair) + "</div>")
    return "".join(sheets)


def render_all(datas: list[dict], compact: bool = False) -> str:
    """批次列印：每位學生一張（page-break）。瀏覽器 Ctrl+P 直接印或存 PDF。
    compact=True → 省紙版，一張 A4 橫放並排印兩人，同樣內容約省一半紙張。"""
    if not datas:
        return _wrap("小市集成績單（批次）", '<p style="padding:20px">尚無學生資料</p>')
    body = _pair_bodies(datas) if compact else "".join(_render_body(d) for d in datas)
    title = f"小市集成績單批次（{len(datas)} 人{'・省紙版' if compact else ''}）"
    return _wrap(title, body, _COMPACT_STYLE if compact else "")


# ── 頒獎典禮投影片（16:9 橫式，每項一頁，瀏覽器 Ctrl+P → 存 PDF 上台用） ──────
_SLIDE_STYLE = """
:root {
  --ink:#3a3326; --muted:#9a8f76; --paper:#f7f0d8;
  --green:#2f8a80; --gold:#cf9a2f; --purple:#e07b3f;
  --silver:#9aa3ad; --bronze:#b9773e; --line:#e6dcc0;
}
* { box-sizing:border-box; }
@page { size:297mm 167mm; margin:0; }
html, body { margin:0; background:var(--paper);
       -webkit-print-color-adjust:exact; print-color-adjust:exact; }
body { font-family:-apple-system,"PingFang TC","Microsoft JhengHei",sans-serif; color:var(--ink); }
.slide { width:297mm; height:167mm; position:relative; overflow:hidden;
         display:flex; flex-direction:column; align-items:center; justify-content:center;
         text-align:center; page-break-after:always; }
.slide:last-child { page-break-after:auto; }
.deco { position:absolute; z-index:0; pointer-events:none; }
.deco.tr { top:6mm; right:8mm; opacity:.55; transform:scale(1.6); }
.deco.bl { bottom:0; left:0; opacity:.9; transform:scale(1.7); transform-origin:bottom left; }
.deco.br { bottom:0; right:0; opacity:.9; transform:scale(1.7); transform-origin:bottom right; }
.slideContent { position:relative; z-index:1; }
.slideKicker { font-size:22px; letter-spacing:6px; color:var(--green); font-weight:700; }
.slideTitle { font-size:56px; font-weight:800; margin:8px 0 28px; color:var(--ink); }
.slideMedal { font-size:120px; line-height:1; margin-bottom:8px; }
.slideName { font-size:88px; font-weight:800; color:var(--ink); }
.slideGroup { font-size:26px; color:var(--muted); margin-top:6px; }
.slideMetric { font-size:34px; font-weight:700; margin-top:26px; padding:10px 32px;
               border-radius:999px; display:inline-block; }
.slideMetric.gold { background:#f7ecc8; color:var(--gold); }
.slideMetric.green { background:#e2efe9; color:var(--green); }
.slideMetric.purple { background:#fbe6d6; color:var(--purple); }
.rank1 .slideName { color:var(--gold); }
.rank2 .slideName { color:var(--silver); }
.rank3 .slideName { color:var(--bronze); }
.rankLabel { font-size:30px; font-weight:700; letter-spacing:3px; margin-bottom:6px; }
.rank1 .rankLabel { color:var(--gold); }
.rank2 .rankLabel { color:var(--silver); }
.rank3 .rankLabel { color:var(--bronze); }
"""

_RANK_LABEL = {1: "第一名", 2: "第二名", 3: "第三名"}
_RANK_MEDAL = {1: "🥇", 2: "🥈", 3: "🥉"}


def _slide(kicker, title, body_html, rank_class=""):
    return f"""<div class="slide {rank_class}">
<div class="deco tr">{_DECO_CLOUDS}</div>
<div class="deco bl">{_DECO_ISLAND}</div>
<div class="deco br">{_DECO_DUNE}</div>
<div class="slideContent">
<div class="slideKicker">{kicker}</div>
<div class="slideTitle">{title}</div>
{body_html}
</div>
</div>"""


def _teaser_slide(kicker, title):
    """揭曉前一頁：只有獎項名稱，吊胃口用（上台先停這頁講規則/描述，再翻下一頁公布名字）。"""
    return _slide(kicker, title, "")


def _rank_teaser_slide(kicker, rank):
    """名次揭曉前一頁：只有名次+獎牌，不露名字。"""
    body = f'<div class="rankLabel">{_RANK_LABEL[rank]}</div><div class="slideMedal">{_RANK_MEDAL[rank]}</div>'
    return _slide(kicker, "", body, rank_class=f"rank{rank}")


def _winner_slide(kicker, title, entry, metric_html, color):
    esc = lambda x: html.escape(str(x))
    if not entry:
        body = '<div class="slideName" style="color:var(--muted)">（尚無資料）</div>'
    else:
        group = f'<div class="slideGroup">[{esc(entry["group"])}]</div>' if entry.get("group") else ""
        body = (f'<div class="slideName">{esc(entry["name"])}</div>{group}'
                f'<div class="slideMetric {color}">{metric_html}</div>')
    return _slide(kicker, title, body)


def _rank_slide(kicker, entry, rank, unit):
    esc = lambda x: html.escape(str(x))
    if not entry:
        body = '<div class="slideName" style="color:var(--muted)">（尚無資料）</div>'
    else:
        group = f'<div class="slideGroup">[{esc(entry["group"])}]</div>' if entry.get("group") else ""
        val = entry.get("points", entry.get("kingdom_points"))
        body = (f'<div class="rankLabel">{_RANK_LABEL[rank]}</div>'
                f'<div class="slideMedal">{_RANK_MEDAL[rank]}</div>'
                f'<div class="slideName">{esc(entry["name"])}</div>{group}'
                f'<div class="slideMetric gold">{val} {unit}</div>')
    return _slide(kicker, "", body, rank_class=f"rank{rank}")


def render_award_slides(a: dict) -> str:
    """頒獎投影片，順序：最會賺錢 → 勤奮工作 → 刺激經濟 → 積分 3/2/1 → 管家 3/2/1。
    每個公布名字的頁面前都先一頁只有獎項/名次（吊胃口用）。
    16:9 橫式，瀏覽器 Ctrl+P → 存 PDF，上台簡報用（Preview/Acrobat 全螢幕翻頁）。"""
    e = a.get("best_earner")
    slides = [_teaser_slide("💰 頒獎", "最會賺錢獎")]
    slides.append(_winner_slide("💰 頒獎", "最會賺錢獎", e,
                                f'總收入 ${e["diff"]}' if e else "", "gold"))

    w = a.get("hardest_worker")
    slides.append(_teaser_slide("💪 頒獎", "勤奮工作獎"))
    slides.append(_winner_slide("💪 頒獎", "勤奮工作獎", w,
                                f'完成 {w["count"]} 個公會任務' if w else "", "green"))

    sp = a.get("big_spender")
    slides.append(_teaser_slide("🎉 頒獎", "刺激經濟獎"))
    slides.append(_winner_slide("🎉 頒獎", "刺激經濟獎", sp,
                                f'雜貨店消費 ${sp["expense"]}' if sp else "", "purple"))

    points_top3 = a.get("points_top3") or []
    for rank in (3, 2, 1):
        entry = points_top3[rank - 1] if len(points_top3) >= rank else None
        slides.append(_rank_teaser_slide("🥇 積分榜", rank))
        slides.append(_rank_slide("🥇 積分榜", entry, rank, "分"))

    kp_top3 = a.get("kp_top3") or []
    for rank in (3, 2, 1):
        entry = kp_top3[rank - 1] if len(kp_top3) >= rank else None
        slides.append(_rank_teaser_slide("👑 管家獎", rank))
        slides.append(_rank_slide("👑 管家獎", entry, rank, "點"))

    body = "".join(slides)
    return (f'<!doctype html><html lang="zh-Hant"><head><meta charset="utf-8">'
            f'<title>頒獎典禮</title><style>{_SLIDE_STYLE}</style></head>'
            f'<body>{body}</body></html>')
