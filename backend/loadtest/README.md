# 壓力測試套件

目標：本地 uvicorn + 獨立測試 DB（`loadtest.db`），完全不碰正式 VM 資料。
模擬 100 人同時上線刷卡消費 / 公會 / 賭場 / 銀行轉帳，測流量上限、error handling、崩潰極限、寫鎖競態。

## 1. 準備

```bash
cd backend
python -m venv .venv_lt && source .venv_lt/bin/activate
pip install -r requirements.txt
python loadtest/seed.py
```

`seed.py` 會：
- 建 `backend/loadtest.db`（獨立檔，跟正式 `flyyoung.db` 完全分開）
- enroll 1 個 admin token + 5 個 staff token（模擬多攤位裝置）
- 灌 200 個假學生（`stu001`..`stu200`，每人 200,000 起始金，夠撐長時間測試）
- 開 D1、開市
- 產出 `loadtest/lib/data.json` 給所有 k6 腳本讀

## 2. 起 server（另開 terminal）

```bash
cd backend
DATABASE_URL=sqlite:///$(pwd)/loadtest.db uvicorn app:app --host 0.0.0.0 --port 8000
```

## 3. 跑測試（照順序）

```bash
k6 run loadtest/smoke.js              # 先確認腳本本身沒寫錯（1 VU 跑一輪全 endpoint）
k6 run loadtest/load_100.js           # 主測試：100 VU 穩定負載，混合真實流量比例
k6 run loadtest/stress.js             # 階梯拉高 RPS，找斷點
k6 run loadtest/spike.js              # 開市瞬間尖峰（0→150 VU）
k6 run loadtest/race_double_spend.js  # 同一 uid 50 個平行扣款，驗證無雙花
k6 run loadtest/error_handling.js     # 錯誤路徑斷言（會呼叫 admin/reset 收尾）

python loadtest/inject_expired_task.py  # 注入一個「9分鐘前抽的」公會任務（給下面 edge_cases.js 用）
k6 run loadtest/edge_cases.js         # 現場各種手忙腳亂情境（見下方清單）

k6 run loadtest/soak.js               # 100 VU 撐 20 分鐘（最慢，最後跑）
```

### edge_cases.js 涵蓋的情境

狂按重掃、兩關主搶同一學生的任務、賭場取消跟結算對撞、**同一局被兩個關主同時結算**、
**下注途中局被結算晚到的注單有沒有被擋**、銀行轉帳邊界輸入（自轉/不存在對象/金額0或負/漏欄位）、
網路重試造成重複轉帳、公會抽取池耗盡、見證點數去重、token 中途被撤銷、A⇄B 同時互轉（deadlock
檢查）、超長字串/SQL injection式字串/emoji 等怪輸入、公會任務逾時掃描扣罰款。

`BASE_URL` 預設 `http://127.0.0.1:8000`，要換可 `BASE_URL=http://... k6 run ...`。

## 4. 怎麼看結果

- **load_100.js / stress.js**：看 k6 summary 的 `http_req_duration` p(95)、`http_req_failed` rate。
  若 100 VU 時 p95 明顯 > 幾百 ms 或持續上升，通常是 SQLite 寫鎖排隊（`busy_timeout=5000ms`），
  代表單一 uvicorn process + SQLite 撐 100 人邊界已到，考慮：拆分寫多的 endpoint、
  或評估換 Postgres（`db.py` 已註明 schema 不變可直接換 `DATABASE_URL`）。
- **spike.js**：看有沒有大量非 200（尤其 5xx / 逾時），代表尖峰瞬間扛不住。
- **race_double_spend.js**：跑完 console 會印 `debit_success` counter（應該=1）跟最終餘額
  （應該=0，不可為負）。若成功筆數>1 或餘額變負 → 真的有雙花 bug。
- **error_handling.js**：k6 checks 全綠代表錯誤處理符合預期（業務錯誤回 200+ok:false，
  auth/驗證錯誤回 401/403/422，report 404）。

## 5. 清理

```bash
cd backend
rm -f loadtest.db loadtest.db-wal loadtest.db-shm
```

重跑測試前記得 `python loadtest/seed.py` 重新灌資料（`error_handling.js` 跑完會呼叫
`admin/reset` 把餘額歸零重置，不會刪學生/token，直接接著跑下一輪沒問題；
但如果中途腳本沒跑完就中斷，建議整個重 seed 保險）。
