# 小市集 Backend 設計規格（FastAPI 正式版）v1.0

> 取代 PoC in-memory dict，改 **SQLite（SQLAlchemy）持久化** + WAL，單機部署足以撐約 18 攤同時 polling。
> 所有寫入走 DB transaction，行級鎖定 + 樂觀檢查防作弊。
> 主入口沿用 `POST /api/scan`（單一學生交易）；賭場、公會多步驟與管理、報表另開 endpoint。
> 所有數字以《小市集 單一真相源 SOT v1.0》為唯一來源。

---

## 0. 部署與技術選型

| 項目 | 選型 |
|---|---|
| Web 框架 | FastAPI + Uvicorn（沿用） |
| ORM / DB | SQLAlchemy 2.0 + SQLite（`flyyoung.db`，`PRAGMA journal_mode=WAL`） |
| 適用規模 | 正式人數 < 100，SQLite 足夠；要多 worker 改 Postgres，schema 不變 |
| 交易原子性 | 金流寫入用 `with Session.begin():` 單一 transaction |
| 行級鎖 | 對 `students` 該列 `SELECT ... FOR UPDATE`（Postgres）或 SQLite 序列化寫鎖 |
| 全域狀態 | 單一 `game_state` 列控制 `current_day` 與 `market_open` |

### 0.1 專案結構

```
backend/
  app.py            # FastAPI app + routers
  db.py             # engine/session
  models.py         # SQLAlchemy ORM
  schemas.py        # Pydantic request/response
  services/
    txn.py          # 金流核心（atomic）
    guild.py        # 公會抽/完成
    casino.py       # 賭場 round
    bank.py         # 定存/利息/市場關閉
    report.py       # 報表 HTML 生成
  templates/report.html
  seed_import.py    # 營前建表匯入
```

---

## 1. 共用 response 形狀

所有單學生交易回傳 `StudentState`，App 直接刷新卡片。

```python
class StudentState(BaseModel):
    uid: str
    student_name: str
    balance: int            # 現金
    points: int             # 積分
    kingdom_points: int     # 天國點數 KP
    deposit_balance: int    # 定存本利現值
    stall: str
    action: str
    message: str
    ok: bool = True
```

**錯誤策略**：業務錯誤（餘額不足／市場關閉／重複完成等）→ HTTP 200 + `ok=false` + `message`，方便 App 顯示；4xx/5xx 僅用於系統錯誤。

---

## 2. `POST /api/scan` — 單學生交易主入口

### 2.1 Request

```python
class ScanReq(BaseModel):
    uid: str
    stall_id: str
    action: str           # 見下方 enum
    amount: int = 0
    # 選用
    cost: int = 0         # game_settle 用
    reward: int = 0       # game_settle 用
    tier: int | None = None     # exchange_points 檔位 (100/250/400/800)
    cards: int = 0        # mail_kp 郵政核銷卡數（寄件人）
    sender_name: str | None = None  # mail_kp 用：寄件人名字（非 NFC 流程，亦可改帶 uid）
    staff_uid: str | None = None  # witness / 防作弊
```

### 2.2 action 列舉與處理

| action | 邏輯 | 防護 |
|---|---|---|
| `lookup` | 回 StudentState | 學生不存在 → ok=false |
| `debit` | balance -= amount（雜貨店含感謝卡商品，**純扣款、不加任何 KP**） | amount>0、balance≥amount、market_open |
| `meal` | balance -= amount（餐費，預設150、範圍100–250）。計入 `total_expense` | amount>0、balance≥amount、market_open |
| `mail_kp` | 郵政核銷：依 `uid`（或 `sender_name` 反查）對**寄件人** kingdom_points += 20×cards；`card_count += cards`（**封頂 3 張＝60 KP**，超出不加並在 message 標註） | cards≥1；name 反查需唯一命中（同名→回候選清單由 App 選定 uid）；不需 market_open（核銷可在關市後整理） |
| `credit` | balance += amount | amount>0 |
| `game_settle` | balance -= cost；若 reward>0 則 balance += reward（單交易原子）。**transaction.meta 必存 `{cost, reward}`**，供報表分別計入 expense（cost）與 income（reward） | cost≤balance；D1 攤專用 |
| `deposit` | balance -= amount；deposit_balance += amount | amount≤balance、market_open |
| `withdraw` | deposit_balance -= amount；balance += amount（amount=-1 代表全部） | amount≤deposit_balance、market_open |
| `credit_kp` | kingdom_points += amount（見證固定 100） | **去重** `witness_log` unique(student_uid, staff_uid)；已給 → ok=false |
| `donate` | balance -= amount；kingdom_points += amount；D3 且 amount≥100 且本生未領 bonus → 額外 +50 KP | amount≥10、balance≥amount、market_open |
| `exchange_points` | balance -= tier；points += TIER_MAP[tier] | tier∈{100,250,400,800}、balance≥tier、market_open |
| `guild_draw` | balance -= 30，隨機派任務（見 §3） | balance≥30、market_open、覆蓋舊 pending |

**積分兌換對照表**

```python
TIER_MAP = {100:100, 250:300, 400:500, 800:1000}
```

### 2.3 感謝卡 KP（郵政核銷，加給寄件人）

> **設計變更**：雜貨店**不再即時加 KP**。買感謝卡＝純 `debit`（花現金買商品）。感謝卡 KP 改由**郵政同工**後台核銷，依卡上**寄件人名字**加給寄件人。

- 學生在雜貨店買卡（debit）→ 寫感謝話＋**自己名字（寄件人）**→ 投郵筒。
- 郵政同工整理分發卡片時，逐張用 app `mail_kp` 登記：輸入**寄件人名字**→ by-name 反查 → 選定 uid → 卡數 n → `kingdom_points += 20×n`（給寄件人），`card_count += n`，封頂 **3 張＝60 KP**，超出不加並在 message 標註。
- 卡上**沒寫名字 → 無法 by-name 反查 → 不登記、不加 KP**。
- 寫一筆 `action=mail_kp` 的 transaction，`kp_after` 反映 +20×n。

**by-name 反查 endpoint（非 NFC，紙本卡無 UID）**

```
GET /api/students/search?name=王小明
→ [{uid, name, group, seat_no}]   # 同名回多筆候選，App 顯示小組/座號消歧後選定 uid
```

- 反查資料源＝營前建表的 `students`（name→uid）。同名以小組/座號欄位消歧。
- App 選定正確 uid 後再送 `POST /api/scan {action:mail_kp, uid, cards:n}`；亦容許直接帶 `sender_name`，但唯一命中才接受，多筆命中回 ok=false 要求改帶 uid。

### 2.4 回應卡（D3 一次性）

回應／決志卡 +200 KP 走獨立 `POST /api/admin/response_card {uid}`（牧養用，主持統一操作），每生限一次。

### 2.5 金流核心骨架（services/txn.py）

```python
def apply(session, uid, fn) -> StudentState:
    s = session.get(Student, uid, with_for_update=True)
    if s is None: return err("查無此卡")
    if not market_open(session) and fn.needs_market:
        return err("市場已關閉，僅能查詢")
    new = fn(s)                      # 改 s.balance/points/kp
    if new.rejected: return new      # 餘額不足等，不寫 ledger
    session.add(Transaction(
        uid=uid, stall_id=..., action=..., amount=...,
        balance_after=s.balance, points_after=s.points,
        kp_after=s.kingdom_points, deposit_after=s.deposit_balance,
        day=current_day(session), meta=json, created_at=now()))
    return ok(s)
# 整段在 with session.begin(): 內，commit 才生效（原子）
```

防併發：`with_for_update` 鎖該學生列，賭場、公會同卡操作序列化，杜絕雙扣／雙領。

---

## 3. 公會 endpoints（services/guild.py）

### 3.1 抽任務

```
POST /api/scan {action:guild_draw, uid, stall_id:'guild', staff_uid}
```

原子流程：

1. balance ≥ 30？否 → ok=false。
2. balance -= 30（手續費）。
3. 將該生現有 `status=pending` 任務改 `superseded`。
4. 從 9 款池 **uniform random** 抽 1。
5. 寫 `guild_tasks(uid, game_key, difficulty, reward, status=pending)`。
6. message 例：`派發任務：投籃高手（中・獎勵90）`，回 StudentState + `assigned_game`。

**抽取池（9 款，均勻隨機）**

| 難度 | 固定獎勵 | 款數 | 遊戲 |
|---|---|---|---|
| 低 | 60 | 3 | 顏色分類、終極密碼、搬家人工 |
| 中 | 90 | 5 | 投籃高手、丟紙飛機、拍氣球、比手畫腳、記憶翻牌 |
| 高 | 130 | 1 | 七巧板 |

> 期望獎勵 84.44、每抽淨值 +54.44；重抽期望 −5.56（SOT §1.4），自帶剎車，無須額外限制。

### 3.2 小遊戲攤看 pending

```
GET /api/guild/pending?stall_id=game_basketball
→ [{student_uid, student_name, game_key, drawn_at}]
```

只列該攤對應 `game_key` 的 pending（後端 `stall_id → game_key` 常數對照），讓關主只看到「該來我這關」的學生。

### 3.3 標記完成

```
POST /api/guild/complete {student_uid, stall_id, staff_uid}
```

原子流程：

1. 找該生 `status=pending` 且 `game_key == STALL_GAME[stall_id]` 的任務；無 → ok=false「無待完成任務」。
2. 任務 status=completed, completed_by=staff_uid, completed_at=now。
3. balance += reward（固定，依 difficulty）。
4. 寫 transaction（action=guild_complete）。回 StudentState。

**防作弊**：獎勵 server 端固定（不收 amount）；`stall_id` 必須對得上 `game_key`（學生不能拿低任務去高關領）；重複完成被 status 擋。

---

## 4. 賭場 endpoints（services/casino.py）

```
POST /api/casino/open   {table:'21'|'dice', stall_id} → {round_id, status:'open'}
POST /api/casino/bet    {round_id, uid, bet_type, amount}
        # 21:  bet_type 固定 'play'；amount 10–100
        # dice: bet_type ∈ 'big'|'small'|'seven'；amount 10–100
        → {ok, student_name, balance, table_bets:[...]}
        # 下注即原子凍結：balance -= amount，寫 casino_bet(status=placed)
POST /api/casino/cancel {round_id, uid}                # 退注退款（改注用）
POST /api/casino/settle {round_id, dice:[d1,d2]}            # dice 桌
                   或   {round_id, results:[{uid, win:bool}]} # 21 桌
        → {round_id, status:'settled', results:[{uid,name,bet,delta,balance}]}
GET  /api/casino/round/{id}                            # 續桌
```

### 4.1 結算規則

**21 點（比大小，平手歸莊，賠 1 倍）**

| 結果 | 處理 | 淨值 |
|---|---|---|
| win | balance += amount×2（退本金 + 彩金） | +amount |
| lose / push（平手歸莊） | 已扣 amount 不退 | −amount |

> 房屋優勢 5.88%（SOT §3.1）。

**大小骰子（2 顆骰，sum = d1+d2，賠率如下）**

| 注別 | 命中條件 | 命中賠付 | 未命中 |
|---|---|---|---|
| small | sum ∈ 2–6 | balance += amount×2 | −amount |
| big | sum ∈ 8–12 | balance += amount×2 | −amount |
| seven | sum == 7 | balance += amount×5 | −amount |

> 7 對 big/small 皆輸（big/small 不含 7）。三注房屋優勢一致 16.67%（SOT §3.2）。

**結算實作**：下注時已扣 amount。命中者 `balance += amount×2`（small/big）或 `amount×5`（seven）；未命中不動。每注寫一筆 transaction，整桌一筆 `casino_round`，全部在單一 transaction。

**桌限驗證**（bet 時）：10 ≤ amount ≤ 100、amount ≤ balance、市場開、同一 round 同一 uid 僅一注（除非先 cancel）。

---

## 5. 銀行利息與市場關閉（services/bank.py，管理操作）

```
POST /api/admin/settle_interest   {day}   # 每場小市集結束按一次
POST /api/admin/market_close             # D3 10:25 突襲
POST /api/admin/set_day {day:'D1'|'D2'|'D3'}
GET  /api/admin/state                    # current_day, market_open, settlement_count
```

### 5.1 結息（複利 20%/天，最多 3 次）

- 防呆：`settlement_count` < 3 才執行，且同一 day 不重複（記 `settled_days`）。
- 對所有 `deposit_balance > 0` 學生：`interest = floor(deposit_balance * 0.2)`；`deposit_balance += interest`；寫 transaction(action=interest)。
- **複利**，每場對「當前定存餘額」+20%，無條件捨去整數。範例：100 → 120 → 144 → 172（最大造幣率 +72.8%，SOT §7.3）。

### 5.2 市場關閉（未兌換現金 ×0.1，封堵套利）

- `market_open = False`。
- 對每位學生：`taxable = balance + deposit_balance`；`points += floor(taxable * 0.1)`；`balance=0; deposit_balance=0`；寫 transaction(action=market_close, meta={taxable})。
- 此後 scan 除 `lookup` 外一律 ok=false「市場已關閉」。
- 最終積分 = points（已含兌換積分 + 折算），與 SOT §7.1 公式一致：

```
總積分 = 已兌換積分 + (現金 + 定存本利) × 0.1
```

---

## 6. 營前建表（seed_import.py）

CSV/Excel 匯入欄位：`name, uid, seed_amount`（seed ∈ {500,400,300} 抽籤分配）。

```
POST /api/admin/import   (multipart csv)        # 或 CLI: python seed_import.py students.csv
  每列 → upsert Student(uid, name, balance=seed, seed_amount=seed,
                        points=0, kingdom_points=0, deposit_balance=0)
  回 {imported, skipped, errors:[...]}
```

CSV 範例：

```
name,uid,seed_amount
王小明,04A1B2C3,500
李小華,04D4E5F6,400
```

- uid 取自實體刷卡。建表前可用「綁卡」流程：感應 → 輸入姓名 → 選抽籤金額 → POST。
- 提供 `POST /api/admin/bind {uid,name,seed_amount}`。
- 重複 uid → skip 並回報。

---

## 7. 營後報表（services/report.py + templates/report.html）

```
GET /api/report/{uid}            # 回完整 HTML（A4 可列印，內嵌資料）
GET /api/report/{uid}/data       # 回 JSON datasource（給前端/除錯）
GET /api/report/all              # 批次：產所有人 HTML（zip 或逐頁）
```

### 7.1 Datasource（JSON）

由 `transactions` 依 uid 撈全明細 + 衍生統計：

```jsonc
{
  "uid":"04A1B2C3", "name":"王小明", "seed":500,
  "final_points": 642,            // 市場關閉後 points
  "kingdom_points": 320,
  "rank_points": 3, "rank_kp": 5, // 兩軌名次
  "total_income": 980,            // 所有 credit 類加總
  "total_expense": 640,           // 所有 debit 類加總
  "roi_pct": 28.4,
  "exchanged_points": 600,        // 兌換鎖定積分
  "residual_cash_to_points": 42,  // 折算
  "deposit_final": 0,
  "balance_curve": [
    {"ts":"D1 17:32","balance":480,"deposit":0},
    {"ts":"D1 17:40","balance":510,"deposit":100}
  ],
  // 曲線畫「總資產」= balance_after + deposit_after，避免把「搬進定存」誤畫成虧損；
  // 或同圖加第二條定存軌（deposit_after）。每點取 transactions.balance_after 與 deposit_after。
  "points_curve": [], "kp_curve": [],
  "ledger": [
    {"ts":"...", "stall":"舊鞋救命","action":"donate","amount":-100,
     "balance_after":380,"note":"奉獻→KP+100"}
  ]
}
```

**統計衍生規則**

| 欄位 | 計算 |
|---|---|
| `total_income` | Σ amount of credit / **game_settle `meta.reward`** / guild_complete / interest / **賭場淨彩金（payout − 原始 bet 本金，不含退回本金）**。賭場以淨輸贏入帳，避免把整筆 payout（含退回本金）計入而灌大毛額 |
| `total_expense` | Σ |amount| of debit / **meal（餐費）** / **game_settle `meta.cost`（固定 20）** / donate / exchange / casino lose / 公會手續費 30（deposit 不計） |
| `roi_pct`（建議直觀版） | `(total_income − total_expense) / seed × 100`，另列「最終總積分」「總 KP」獨立呈現 |
| `kingdom_points`（總 KP） | Σ KP 類交易：`donate` / `credit_kp`（聽見證）/ **`mail_kp`（郵政感謝卡核銷）** / `response_card`。買感謝卡的 `debit` 不加 KP（已改郵政核銷） |

### 7.2 HTML + 圖表產法（建議）

正式採 **後端內嵌 SVG**（report.py 直接吐 `<svg><polyline points=...>`），HTML 純靜態、無外部依賴，適合大量批印與弱網，避免 CDN/JS 在現場出包。列印走瀏覽器 `Ctrl+P` → A4。

> 替代：Jinja2 注入 `<script>const DATA=...</script>` + Chart.js（CDN 或內嵌）畫曲線。現場穩定度較低，不建議正式採用。

**report.html 區塊**

1. 抬頭：姓名 + UID + 抽籤起始金。
2. 兩軌成績：最終總積分（名次）｜總天國點數（名次）。
3. KPI 卡：總 income / 總花費 / ROI / 已兌換積分 / 剩餘現金折算 / 定存本利。
4. 三張曲線圖（SVG）：總資產時間軸（balance_after + deposit_after，或加第二條定存軌；不可只畫現金，否則搬進定存會誤顯為虧損）、積分變化、天國點數變化。
5. 總帳本表格（進帳綠／出帳紅）。
6. 信息結語區（手動文案）。

### 7.3 防作弊 / 一致性

- 報表只讀 `transactions`（單一真相），不另存衍生值，重算保證對帳。
- 名次由 `GET /api/report/all` 一次性算 `final_points`、`kingdom_points` 排序後寫回快取（market_close 後凍結）。

---

## 8. 原子性與防作弊總則

1. 每筆金流 = 一個 DB transaction，`with_for_update` 鎖學生列，先檢查後扣款，commit 前任何失敗全 rollback。
2. 餘額不足／定存不足／桌限／市場關閉 → 業務拒絕（ok=false），不寫 ledger。
3. 重複完成（公會）、重複見證（KP）由 unique 約束 + status 機制擋。
4. 賭場下注即時凍結資金（先扣），結算只發彩金，杜絕「下注後沒錢」。
5. 固定獎勵（公會／見證）server 端寫死，App 不可傳金額覆蓋。
6. UID-lookup：卡片不寫入，換手機／重感應無影響，state 全在 DB。

---

## 附：新增 / 沿用 action 對照

| action | 來源 | 說明 |
|---|---|---|
| `lookup` `debit` `credit` | 沿用 | 查詢／扣款／入帳 |
| `meal` | 新增 | 餐費扣款（debit 類，預設150、計入 total_expense） |
| `game_settle` | 沿用 | D1 技能攤單交易結算 |
| `deposit` `withdraw` | 新增 | 銀行定存／提領 |
| `credit_kp` | 新增 | 聽見證 +100（雜貨店不再經此加 KP） |
| `mail_kp` | 新增 | 郵政感謝卡核銷，by-name 反查寄件人，+20×n KP（封頂 3 張＝60 KP） |
| `exchange_points`（積分） | 新增 | 依 TIER_MAP 兌換 |
| `donate` | 新增 | 奉獻 1:1 轉 KP，D3 bonus +50 |
| `guild_draw` / `guild_complete` | 新增 | 公會抽取 −30 / 固定獎勵入帳 |
| `interest` `market_close` | 新增 | 管理：結息／市場關閉 |
