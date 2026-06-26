"""營後報表 — docs/app/31 §7。只讀 transactions（單一真相），重算保證對帳。

曲線採後端內嵌 SVG（無外部依賴，弱網/批印安全）。
"""
import html
import json

from sqlalchemy import select

from models import Student, Transaction

# 入帳類 / 出帳類 action 分類（casino_bet/cancel 排除：只是凍結/退款，僅影響餘額曲線）
INCOME_ACTIONS = {"credit", "guild_complete", "interest"}
EXPENSE_ACTIONS = {"debit", "meal", "donate", "exchange_points", "guild_draw"}
KP_ACTIONS = {"donate", "credit_kp", "mail_kp", "response_card"}


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


# ── SVG 折線 ────────────────────────────────────────────────────────────
def _svg_line(points: list[int], color: str, w=520, h=120, pad=10) -> str:
    if not points:
        return f'<svg width="{w}" height="{h}"></svg>'
    lo, hi = min(points), max(points)
    span = (hi - lo) or 1
    n = len(points)
    dx = (w - 2 * pad) / max(n - 1, 1)
    pts = " ".join(
        f"{pad + i * dx:.1f},{h - pad - (v - lo) / span * (h - 2 * pad):.1f}"
        for i, v in enumerate(points)
    )
    return (f'<svg width="{w}" height="{h}" style="background:#fafafa;border:1px solid #ddd">'
            f'<polyline fill="none" stroke="{color}" stroke-width="2" points="{pts}"/>'
            f'<text x="{pad}" y="14" font-size="10" fill="#888">max {hi}</text>'
            f'<text x="{pad}" y="{h-2}" font-size="10" fill="#888">min {lo}</text></svg>')


def render_html(data: dict) -> str:
    esc = lambda x: html.escape(str(x))
    assets = [p["balance"] + p["deposit"] for p in data["balance_curve"]] or [0]
    deposits = [p["deposit"] for p in data["balance_curve"]] or [0]
    pts = [p["points"] for p in data["points_curve"]] or [0]
    kps = [p["kp"] for p in data["kp_curve"]] or [0]

    rows = "".join(
        f'<tr><td>{esc(l["ts"])}</td><td>{esc(l["day"])}</td><td>{esc(l["stall"])}</td>'
        f'<td>{esc(l["action"])}</td>'
        f'<td style="color:{"#137333" if l["amount"]>=0 else "#c5221f"};text-align:right">'
        f'{"+" if l["amount"]>=0 else ""}{l["amount"]}</td>'
        f'<td style="text-align:right">{l["balance_after"]}</td></tr>'
        for l in data["ledger"]
    )
    rp = data["rank_points"] or "-"
    rk = data["rank_kp"] or "-"
    return f"""<!doctype html><html lang="zh-Hant"><head><meta charset="utf-8">
<title>{esc(data['name'])} · 小市集成績單</title>
<style>
@page {{ size:A4; margin:14mm; }}
body {{ font-family:-apple-system,"PingFang TC","Microsoft JhengHei",sans-serif; color:#222; }}
h1 {{ font-size:22px; margin:0 0 2px; }} .sub {{ color:#888; font-size:12px; }}
.tracks {{ display:flex; gap:16px; margin:14px 0; }}
.track {{ flex:1; border:2px solid #1a4d2e; border-radius:8px; padding:12px; }}
.track.kp {{ border-color:#7a4ea0; }}
.big {{ font-size:30px; font-weight:700; }}
.kpis {{ display:flex; flex-wrap:wrap; gap:10px; margin:10px 0; }}
.kpi {{ background:#f2f2f2; border-radius:6px; padding:8px 12px; min-width:110px; }}
.kpi .l {{ font-size:11px; color:#777; }} .kpi .v {{ font-size:18px; font-weight:600; }}
.chart {{ margin:8px 0; }} .chart h3 {{ font-size:13px; margin:6px 0; color:#555; }}
table {{ border-collapse:collapse; width:100%; font-size:11px; margin-top:8px; }}
td,th {{ border-bottom:1px solid #eee; padding:3px 6px; }}
th {{ background:#1a4d2e; color:#fff; text-align:left; }}
.msg {{ margin-top:16px; padding:12px; background:#fff8e1; border-left:4px solid #f0b400; font-size:13px; }}
</style></head><body>
<h1>{esc(data['name'])}　小市集成績單</h1>
<div class="sub">UID {esc(data['uid'])}　·　抽籤起始金 ${data['seed']}</div>

<div class="tracks">
  <div class="track"><div class="l">積分榜（總資產）</div>
    <div class="big">{data['final_points']}</div><div class="sub">名次 #{rp}</div></div>
  <div class="track kp"><div class="l">管家獎（天國點數）</div>
    <div class="big">{data['kingdom_points']}</div><div class="sub">名次 #{rk}</div></div>
</div>

<div class="kpis">
  <div class="kpi"><div class="l">總進帳</div><div class="v">{data['total_income']}</div></div>
  <div class="kpi"><div class="l">總花費</div><div class="v">{data['total_expense']}</div></div>
  <div class="kpi"><div class="l">ROI</div><div class="v">{data['roi_pct']}%</div></div>
  <div class="kpi"><div class="l">已兌換積分</div><div class="v">{data['exchanged_points']}</div></div>
  <div class="kpi"><div class="l">現金折算積分</div><div class="v">{data['residual_cash_to_points']}</div></div>
  <div class="kpi"><div class="l">定存本利</div><div class="v">{data['deposit_final']}</div></div>
</div>

<div class="chart"><h3>總資產（現金＋定存）變化</h3>{_svg_line(assets, '#1a4d2e')}</div>
<div class="chart"><h3>定存軌</h3>{_svg_line(deposits, '#0a84ff')}</div>
<div class="chart"><h3>積分變化</h3>{_svg_line(pts, '#b8860b')}</div>
<div class="chart"><h3>天國點數變化</h3>{_svg_line(kps, '#7a4ea0')}</div>

<table><tr><th>時間</th><th>天</th><th>攤位</th><th>動作</th><th>金額</th><th>餘額</th></tr>
{rows}</table>

<div class="msg">「敬虔加上知足的心便是大利了」（提前 6:6）。<br>
地上的財寶會朽壞、帶不走（×0.1）；存在天上的（天國點數）卻存得住、帶得走。
你是忠心的好管家嗎？</div>
</body></html>"""
