# 小市集 App 設計規格（Flutter Android）v1.0

> 對應 SOT v1.0。沿用現有 PoC：`lib/main.dart` + `lib/screens/` + `lib/services/`（`nfc_service.dart` / `api_client.dart` / `settings.dart`），本規格在其上擴充。
>
> **目標**：關主拿一台 Android，感應卡 → 選交易 → 結算。所有金額邏輯在後端，App 只負責「讀 UID + 收集 user input + 呼叫對應 endpoint + 顯示結果」。

---

## 0. 技術前提

- Android only，`nfc_manager: ^3.5.0` 讀 NTAG213 UID（**卡片不寫入**）。
- HTTP via `http`，base url 存 `shared_preferences`（沿用 `Settings`）。
- App **不算錢、不存 state**；每次操作都是一次 round-trip 到後端，後端回新餘額。
- 離線容忍度低（需 Wi-Fi/熱點）；網路失敗一律顯示**錯誤紅 banner，不樂觀更新**。

---

## 1. 攤位模式（Stall Mode）— App 核心設定

關主進場第一件事：在 `SettingsScreen` 選「本攤位」。攤位決定**下拉選單預設值**與**可用交易集合**，避免關主選錯系統。

### 攤位 → 預設交易對照（`stall_id` 即交易 enum 的 group）

| stall_id | 攤位 | 預設交易 | Day |
|---|---|---|---|
| `day1_doll` | 賣娃娃 | `day1_sell_doll` | D1 |
| `day1_ring` | 套圈圈 | `day1_ring_toss` | D1 |
| `day1_dart` | 射飛鏢 | `day1_dart` | D1 |
| `day1_bingo` | 麻將賓果 | `day1_bingo` | D1 |
| `bank` | 銀行 | `bank`（lookup/deposit/withdraw） | D1–3 |
| `witness` | 聊天聽見證 | `witness` | D2–3 |
| `donation` | 舊鞋救命 | `donation` | D2–3 |
| `exchange` | 積分兌換 | `exchange` | D2–3 |
| `grocery` | 雜貨店 | `grocery`（純 debit，含感謝卡商品，不加 KP） | D2–3 |
| `mail` | 郵政 | `mail_kp`（**非 NFC**：名字搜尋寄件人 → 輸入卡數 → +200×n KP） | D2–3 |
| `meal` | 餐費 | `meal`（debit，關主/總控輸入金額或選預設150） | D1–3 |
| `casino_21` | 賭場21點 | `casino_21`（多步驟） | D2–3 |
| `casino_dice` | 賭場大小骰子 | `casino_dice`（多步驟） | D2–3 |
| `guild` | 公會台 | `guild_draw` | D2–3 |
| `game_*` | 9 款小遊戲關卡 | `guild_complete`（看 pending → 完成） | D2–3 |

> 攤位選定後，主畫面下拉選單**只列該攤位允許的交易**（少數攤如銀行有多 action）。「全部交易」模式保留給測試/總控（Settings 內隱藏開關）。

---

## 2. 交易類型 Enum（完整）

`lib/models/txn_type.dart`：

```dart
enum TxnType {
  // ── 查詢（所有攤共用）
  lookup,            // action=lookup，無 input

  // ── Day1 技能攤
  day1SellDoll,      // 賣娃娃   action=debit       input: 售價
  day1RingToss,      // 套圈圈   debit 20 + credit  input: 中圈數→賠 n×10
  day1Dart,          // 射飛鏢   debit 20 + credit  input: 命中數→賠 n×5
  day1Bingo,         // 麻將賓果 debit 20 + credit  input: 中/未中 → 300/0（6×6選16，任一連線單獎）

  // ── 銀行
  bankDeposit,       // 定存     action=deposit     input: 金額
  bankWithdraw,      // 提領本利 action=withdraw    input: 金額（或全部）

  // ── 天國 / 兌換
  witness,           // 分享見證 action=credit_kp       +1000 固定，無 input（防刷靠後端）
  donation,          // 舊鞋救命 action=donate          input: 奉獻金額（cash→KP 1:1）
  exchange,          // 積分     action=exchange_points input: 兌換檔位
  grocery,           // 雜貨店   action=debit           input: 售價（含感謝卡商品；**不加任何 KP**）
  mailKp,            // 郵政     action=mail_kp         **非 NFC**：input 寄件人名字搜尋 + 卡數 → +200×n KP（加給寄件人）
  meal,              // 餐費     action=meal(debit)     input: 餐費金額（預設150，範圍100–250）

  // ── 賭場（多步驟，見 §4）
  casino21,          // action=casino round         multi-step
  casinoDice,        // action=casino round         multi-step

  // ── 公會
  guildDraw,         // 公會抽     action=guild_draw      扣300，回傳隨機派發遊戲
  guildComplete,     // 小遊戲完成 action=guild_complete  固定獎勵，看 pending 名單
}
```

> 9 款小遊戲攤皆使用 `guildComplete`，差別只在 `stall_id`（後端用 stall_id 對應該攤是哪款遊戲、能完成哪些 pending）。

---

## 3. 主流程與螢幕拆解

### 3.1 螢幕清單

| Screen | 檔案 | 職責 |
|---|---|---|
| `ScanScreen`（改造現有） | `screens/scan_screen.dart` | 主畫面：感應卡 → 顯示學生卡片 → 下拉選交易 → 執行 |
| `SettingsScreen`（沿用+擴充） | `screens/settings_screen.dart` | backend url + **本攤位選擇** + 全交易測試開關 |
| `StudentCard`（元件） | `widgets/student_card.dart` | 顯示 中文名/餘額/積分/天國點數/定存本利 |
| `AmountInputSheet`（元件） | `widgets/amount_input_sheet.dart` | 通用金額/數量輸入 bottom sheet |
| `ExchangePicker`（元件） | `widgets/exchange_picker.dart` | 積分兌換檔位（500/1000/2500/4000/7500）選擇 |
| `CasinoTableScreen` | `screens/casino_table_screen.dart` | 賭場多步驟：湊桌→壓注→結算（見 §4） |
| `GuildPendingScreen` | `screens/guild_pending_screen.dart` | 小遊戲攤：列 pending 名單 → 點完成 |

### 3.2 主流程（單步交易）

```
ScanScreen
 ┌─────────────────────────────────────────────┐
 │ [本攤位: 舊鞋救命 ▼]            (來自 Settings)│
 │                                              │
 │   ┌────────────────────────┐                 │
 │   │   感應 NTAG 卡片區       │  ← NfcManager.startSession
 │   └────────────────────────┘                 │
 │                                              │
 │  讀到 UID → 自動 call /api/scan lookup        │
 │                                              │
 │  ┌── StudentCard ──────────────────────┐     │
 │  │ 王小明                               │     │
 │  │ 現金 $480   積分 300   天國點數 100   │     │
 │  │ 定存本利 $144                        │     │
 │  └─────────────────────────────────────┘     │
 │                                              │
 │  交易類型 [舊鞋救命 ▼]   (該攤允許清單)        │
 │  [  執行  ]                                   │
 └─────────────────────────────────────────────┘
        │ 需 input?
        ├─ 是 → 跳對應 input UI（sheet / picker）→ 帶值呼叫 endpoint
        └─ 否 → 直接呼叫 endpoint
        │
        ▼
   顯示結果 banner（綠=成功含新餘額 / 紅=失敗訊息）
   2 秒後回到「等待感應」狀態（清空當前學生）
```

**狀態 enum**：`idle(等待感應) → reading → loaded(顯示學生) → submitting → result → idle`。

### 3.3 各交易 UI 行為與後端呼叫對應

| TxnType | 需 input | input UI | 呼叫（見 backend 規格） |
|---|---|---|---|
| `lookup` | 否 | — | `POST /api/scan {action:lookup}` |
| `day1SellDoll` | 是 | `AmountInputSheet`（售價，建議鍵 20/50/100） | `{action:debit, amount}` |
| `day1RingToss` | 是 | 數字輸入「中圈數 0–10」 | `game_settle` cost20 reward n×10 |
| `day1Dart` | 是 | 數字「命中數 0–10」 | `game_settle` cost20 reward n×5 |
| `day1Bingo` | 是 | 二選一 chip：中／未中（6×6 選16，任一連線） | `game_settle` cost20 reward {0, 300} |
| `bankDeposit` | 是 | 金額 sheet | `{action:deposit, amount}` |
| `bankWithdraw` | 是 | 金額 sheet（含「全部」鍵） | `{action:withdraw, amount}` |
| `witness` | 否 | — | `{action:credit_kp, amount:100}`（後端帶 staff_uid 去重） |
| `donation` | 是 | 金額 sheet（下限 50；快捷 100/500/1000） | `{action:donate, amount}` |
| `exchange` | 是 | `ExchangePicker` 500/1000/2500/4000/7500 可多次 | `{action:exchange_points, amount:tier}` |
| `grocery` | 是 | 售價 sheet（含感謝卡商品） | `{action:debit, amount}`（**純扣款，不再帶 cards、不加任何 KP**） |
| `mailKp` | 是 | **非 NFC**：名字搜尋框 → 候選清單（同名顯示小組消歧）選定學生 → 「卡數 1–3」 | `{action:mail_kp, sender_name 或 uid, cards:n}`（後端 name→uid 反查，kingdom_points += 200×n，受 `card_count≤3`） |
| `meal` | 是 | 金額 sheet（預設鍵 150，範圍 100–250） | `{action:meal, amount}`（debit，計入 total_expense） |
| `guildDraw` | 否（系統固定扣300） | 結果對話框顯示「派發：投籃高手」 | `POST /api/scan {action:guild_draw}` |
| `guildComplete` | 否 | `GuildPendingScreen` 點名單 | `POST /api/guild/complete {student_uid, stall_id, staff_uid}` |
| `casino21` / `casinoDice` | 是（多步） | `CasinoTableScreen` | 見 §4 |

> **合成交易（原子）建議**：D1 三攤「先收 20 再賠 n」若用兩次呼叫，網路中斷會導致只收不賠。後端應提供原子 `game_settle`（一次 request 內 cost+reward），App 只送一次。Ring / Dart / Bingo 皆走此路。

### 3.4 重要 input 規格

- **`AmountInputSheet`**：大數字鍵盤 + 快捷鍵（攤位相關預設值）+ 即時驗證（>0、≤桌限/≤餘額由後端最終裁定，App 只做基本擋）。
- **staff_uid**：App 啟動時於 Settings 綁定「本機關主 UID」（同工自己的卡或手動輸入字串），所有 `witness` / `guild_complete` 帶上，供後端去重與防作弊。
- **郵政 `mail_kp`（唯一非 NFC by-name 流程）**：紙本感謝卡無 UID，**不感應卡**。郵政同工在 app 輸入卡上**寄件人名字**→ 呼叫 by-name lookup（見 backend），回**候選清單**（同名以小組/座號消歧）→ 選定正確學生 → 輸入卡數 1–3 → `mail_kp` 加 +200×n KP 給寄件人。選錯人會加錯 KP，務必核對；沒寫名字的卡無法登記。

---

## 4. 賭場多步驟 UI 流程（CasinoTableScreen）

賭場特性：**先感應多位學生湊一桌 → 各自壓注 → 一次擲骰/比牌 → 系統批次結算**。用「一個 round」貫穿。

### 4.1 狀態機

```
[OPEN_TABLE]  關主按「開新局」→ POST /api/casino/open {table, stall_id}
              ← round_id, status=open
      │
      ▼
[COLLECT]     反覆：感應學生卡 → 立刻顯示姓名/餘額 → 輸入壓注
   ┌── 21點：  壓注金額（50–500）
   └── 大小骰： 壓注內容(大/小/7) + 金額(50–500)
              每加一人 → POST /api/casino/bet {round_id, uid, bet_type, amount}
              （後端當下凍結/檢查餘額，回 ok 或 餘額不足）
              桌面列出已入座清單（姓名・注別・金額），最多 6 人
      │ 關主按「封盤」
      ▼
[RESOLVE]
   ┌── 大小骰： 輸入兩顆骰點數 [d1][d2] → 系統自動判每注輸贏
   └── 21點：   逐人 win/lose 切換（關主比牌後手動標）；平手預設莊家通吃
              POST /api/casino/settle {round_id, dice:[d1,d2]}
                                   或 {round_id, results:[{uid,win:bool}]}
      │
      ▼
[RESULT]      顯示每人結果（+/- 金額、新餘額）→「結束本局」回 OPEN_TABLE
```

### 4.2 畫面要點

- **COLLECT 階段**：桌面是一個可滾動 list，每 row `姓名 | 注別 | $金額 | 狀態(已凍結)`。重複感應同一人 → 提示「已在桌上」可改注（先 cancel 再 bet）。
- **大小骰 RESOLVE**：兩個 1–6 stepper，送出後後端算 sum 判 big(8–12) / small(2–6) / seven(7=6/36)，賠率 **big/small 1:1、seven 4:1**。
- **21點 RESOLVE**：每 row 一個「贏/輸」toggle（關主依抽牌比大小手動定，**平手歸莊＝輸**），賠 **1:1**。
- **RESULT banner**：綠/紅逐行；整局結算後後端寫一筆 `casino_round` + 多筆 `transactions`，原子提交。
- **斷線保護**：round 在後端有狀態；App 重進可 `GET /api/casino/round/{id}` 續桌。

---

## 5. 與 Backend 呼叫對應總表

| App 動作 | Endpoint | 主要欄位 |
|---|---|---|
| 感應查詢 | `POST /api/scan` | `action=lookup` |
| 一般扣/入帳 | `POST /api/scan` | `debit` / `credit` |
| D1 遊戲結算 | `POST /api/scan` | `action=game_settle, cost, reward` |
| 定存/提領 | `POST /api/scan` | `deposit` / `withdraw` |
| 見證 KP | `POST /api/scan` | `credit_kp`, `staff_uid` |
| 奉獻 | `POST /api/scan` | `donate` |
| 積分兌換 | `POST /api/scan` | `exchange_points`, tier |
| 雜貨店 | `POST /api/scan` | `debit`（純扣款，不帶 cards、不加 KP） |
| 郵政（依名字查學生） | `GET /api/students/search?name=` | 回候選清單（同名消歧） |
| 郵政（感謝卡核銷） | `POST /api/scan` | `action=mail_kp, uid（或 sender_name）, cards` |
| 餐費 | `POST /api/scan` | `action=meal, amount` |
| 公會抽 | `POST /api/scan` | `guild_draw` |
| 公會完成 | `POST /api/guild/complete` | `student_uid, stall_id, staff_uid` |
| 公會 pending 名單 | `GET /api/guild/pending?stall_id=` | — |
| 賭場開局/下注/結算 | `POST /api/casino/{open,bet,settle}` | 見 §4 |

> App 端 `ApiClient` 擴充：保留現有 `scan()`，新增 `guildComplete()`、`guildPending()`、`casinoOpen/Bet/Settle()`、`casinoRound()`、`studentSearch()`（郵政 by-name）。所有方法 **5s timeout、非 200 throw、UI 顯示 `message`**。

---

## 6. 防呆 / UX 守則

1. **選錯攤位風險**：主畫面頂部恆顯示「本攤位：XXX」紅底，選錯一眼看出。
2. **金額類交易送出前彈確認**（姓名 + 動作 + 金額），避免手滑。
3. **市場關閉後（D3 10:25）**：後端回 `market_closed` 錯誤，App 顯示「市場已關閉」並鎖定除 lookup 外所有交易。
4. **餘額不足、重複完成、桌限超限**：一律後端裁定，App 顯示後端 `message`，不自行判斷成功。

---

## 7. Admin / 總控介面（現場管理操作）

> 換日、結息、市場關閉、D3 回應卡屬**全域 / 管理操作**，不走一般攤位關主。由**總控同工**（一人，單一裝置）負責，避免多人誤觸。對應 backend §5 / §2.4 的 `/api/admin/*` endpoints。

| 管理動作 | endpoint | 操作者 | 觸發時點 |
|---|---|---|---|
| 換日 `set_day` | `POST /api/admin/set_day {day}` | 總控同工 | 每場小市集開始前切到 D1 / D2 / D3 |
| 每場結息 `settle_interest` | `POST /api/admin/settle_interest {day}` | 總控同工 | **D1（18:10）/ D2（14:00）/ D3（市場關閉時）各場結束各按一次**，全營最多 3 次 |
| 市場關閉 `market_close` | `POST /api/admin/market_close` | 總控同工 | **D3 約 10:25 突襲**，主持喊停同時執行（一鍵凍結，未兌換現金＋定存本利 ×0.1） |
| 全重置 `reset` | `POST /api/admin/reset` | 總控同工 | 測試用：學員回起始金、清空帳本/任務/賭局/見證、天數回 D1、市場重開 |
| 查全域狀態 | `GET /api/admin/state` | 總控同工 | 隨時確認 `current_day` / `market_open` / `settlement_count` |

> 舊版「D3 回應卡 `response_card` +200 KP」已取消（Day3 不加開強化天國攤）。

**形式（二擇一）**

- **隱藏 admin screen**：Settings 內「總控模式」隱藏開關打開後，顯示 `AdminScreen`，列出上述按鈕（含二次確認），現場一鍵操作。
- **curl / Postman runbook**：不另做 UI，總控同工照預備好的指令清單逐條打（換日、結息、市場關閉、回應卡）。低成本，但需熟手。

> 操作守則：`settle_interest` 每場**只按一次**（後端以 `settled_days` 防重複）；`market_close` **不可預告、只按一次**（突襲設計）；兩者皆為不可逆，按前口頭複誦確認。

---

## 附錄：交易字串 / action 對照

`Day1賣娃娃`、`Day1套圈圈`、`Day1射飛鏢`、`Day1麻將賓果`、`銀行`(lookup/deposit/withdraw)、`分享見證`(credit_kp +1000)、`舊鞋救命`(debit + credit_kp)、`積分`(debit + credit_points)、`雜貨店`(**純 debit，不加 KP**)、`郵政`(mail_kp，名字搜尋寄件人 +200×n KP)、`餐費`(meal debit，約150)、`賭場21點`、`賭場大小骰子`、`公會`(抽取 −300)、`顏色分類`、`終極密碼`、`搬家人工`、`投籃高手`、`丟紙飛機`、`拍氣球`、`比手畫腳`、`記憶翻牌`、`七巧板`（後 9 款：lookup / complete 固定獎勵）。

> 後端沿用現有 `POST /api/scan {uid,stall_id,action,amount}`；新增 action：`deposit`、`withdraw`、`credit_kp`、`credit_points`、`meal`（餐費 debit）、`mail_kp`（郵政感謝卡核銷，by-name，+200×n KP）、`complete`（公會固定獎勵）。郵政另需 `GET /api/students/search?name=`（by-name 反查）。所有 state 入後端 DB、原子交易、UID-lookup、**卡片不寫入**。
