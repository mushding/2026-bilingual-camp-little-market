"""營後報表 — docs/app/31 §7。只讀 transactions（單一真相），重算保證對帳。

曲線採後端內嵌 SVG（無外部依賴，弱網/批印安全）。
"""
import html
import json

from sqlalchemy import select

from models import Student, Transaction

# 入帳類 / 出帳類 action 分類（casino_bet/cancel 排除：只是凍結/退款，僅影響餘額曲線）
INCOME_ACTIONS = {"credit", "guild_complete", "interest"}
EXPENSE_ACTIONS = {"debit", "meal", "donate", "exchange_points", "guild_draw", "task_expired"}
KP_ACTIONS = {"donate", "credit_kp", "mail_kp"}

# stall_id → 中文攤位名（對齊 lib/data/stalls.dart）
STALL_NAMES = {
    "day1_doll": "賣娃娃", "day1_ring": "套圈圈", "day1_dart": "射飛鏢",
    "day1_bingo": "麻將賓果", "bank": "銀行", "meal": "餐費",
    "witness": "聊天聽見證", "donation": "舊鞋救命", "exchange": "積分兌換",
    "grocery": "雜貨店", "mail": "郵政", "casino_21": "賭場21點",
    "casino_dice": "賭場大小骰子", "guild": "公會台",
    "game_color": "顏色分類", "game_password": "終極密碼", "game_moving": "搬家人工",
    "game_basketball": "投籃高手", "game_plane": "丟紙飛機", "game_balloon": "拍氣球",
    "game_charades": "比手畫腳", "game_memory": "記憶翻牌", "game_tangram": "七巧板",
    "system": "系統",
}
# action → 中文動作名
ACTION_NAMES = {
    "credit": "入帳", "debit": "消費", "deposit": "定存存入", "withdraw": "定存提領",
    "meal": "餐費", "donate": "奉獻", "exchange_points": "積分兌換",
    "guild_draw": "公會抽任務", "guild_complete": "完成任務", "interest": "定存利息",
    "game_settle": "遊戲結算", "casino_bet": "賭場下注", "casino_payout": "賭場賠付",
    "casino_cancel": "賭場退注", "credit_kp": "天國點數", "mail_kp": "感謝卡核銷",
    "task_expired": "任務逾時", "market_close": "市場結算折現",
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
            if a == "exchange_points":
                exchanged_points += meta.get("points", 0)
        elif a == "market_close":
            residual = t.amount  # 折算進積分的部分

        balance_curve.append({"ts": t.created_at, "balance": t.balance_after,
                              "deposit": t.deposit_after})
        points_curve.append({"ts": t.created_at, "points": t.points_after})
        kp_curve.append({"ts": t.created_at, "kp": t.kp_after})
        ledger.append({"ts": t.created_at, "stall": t.stall_id, "action": a,
                       "amount": t.amount, "balance_after": t.balance_after,
                       "day": t.day})

    seed = s.seed_amount or 0
    roi = round((total_income - total_expense) / seed * 100, 1) if seed else 0.0

    return {
        "uid": s.uid, "name": s.name, "seed": seed,
        "final_points": s.points, "kingdom_points": s.kingdom_points,
        "rank_points": s.final_rank_points, "rank_kp": s.final_rank_kp,
        "total_income": total_income, "total_expense": total_expense,
        "roi_pct": roi, "exchanged_points": exchanged_points,
        "residual_cash_to_points": residual, "deposit_final": s.deposit_balance,
        "balance_curve": balance_curve, "points_curve": points_curve,
        "kp_curve": kp_curve, "ledger": ledger,
    }


def compute_ranks(session):
    """market_close 後一次性算名次寫回快取。"""
    studs = session.scalars(select(Student)).all()
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
.page { background:var(--paper); padding:4mm 2mm; }
.page + .page { page-break-before:always; }

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
td.r,th.r { text-align:right; font-variant-numeric:tabular-nums; }
.tag { font-size:9.5px; padding:1px 7px; border-radius:10px; background:var(--gold-soft);
       color:var(--gold); white-space:nowrap; }

.msg { margin-top:14px; padding:12px 16px; background:var(--gold-soft);
       border-left:4px solid var(--gold); border-radius:0 8px 8px 0; font-size:12.5px; line-height:1.7; }
.msg b { color:var(--green); }
"""

_CAMP_TITLE = "2026 理財島之好管家 · 小市集"
_THEME = "忠心的好管家"


def _render_body(data: dict) -> str:
    """單張成績單內容（不含 <html>/<head>），供單張與批次列印共用。"""
    esc = lambda x: html.escape(str(x))
    assets = [p["balance"] + p["deposit"] for p in data["balance_curve"]]
    deposits = [p["deposit"] for p in data["balance_curve"]]
    pts = [p["points"] for p in data["points_curve"]]
    kps = [p["kp"] for p in data["kp_curve"]]

    rows = "".join(
        f'<tr><td>{esc(l["ts"][5:16].replace("T"," "))}</td>'
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
<div class="hd">
  <div>
    <div class="camp">{_CAMP_TITLE}</div>
    <div class="name">{esc(data['name'])} <small>個人成績單</small></div>
  </div>
  <div class="meta">
    <div class="theme">主題 · {_THEME}</div>
    UID {esc(data['uid'])}<br>抽籤起始金 ${data['seed']}
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
</div>"""


def _wrap(title: str, body: str) -> str:
    return (f'<!doctype html><html lang="zh-Hant"><head><meta charset="utf-8">'
            f'<title>{html.escape(title)}</title><style>{_STYLE}</style></head>'
            f'<body>{body}</body></html>')


def render_html(data: dict) -> str:
    return _wrap(f"{data['name']} · 小市集成績單", _render_body(data))


def render_all(datas: list[dict]) -> str:
    """批次列印：每位學生一張 A4（page-break）。瀏覽器 Ctrl+P 直接印或存 PDF。"""
    if not datas:
        return _wrap("小市集成績單（批次）", '<p style="padding:20px">尚無學生資料</p>')
    body = "".join(_render_body(d) for d in datas)
    return _wrap(f"小市集成績單批次（{len(datas)} 人）", body)
