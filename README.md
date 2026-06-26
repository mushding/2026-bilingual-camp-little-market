# 2026 雙語營 小市集 — App + Backend

「忠心好管家」三天經濟大地遊戲。NTAG 感應卡＝身分＋錢包，攤主 App 刷卡交易，
後端做雙軌結算（地上積分 / 天國點數 KP）。

企劃與技術設計見 [`docs/`](docs/)，所有數字以 **SOT v1.0** 為唯一真相源。

## 結構

```
lib/            Flutter 攤主端 App（Android + iOS）
  models/       StudentState、TxnType
  data/         攤位設定（stall → 允許交易）
  services/     nfc / api_client / settings
  screens/      scan / settings / casino / guild / mail / admin
  widgets/      student_card / amount_input / exchange_picker
backend/        FastAPI + SQLAlchemy(SQLite/WAL)
  app.py        所有 endpoint
  models.py     ORM schema（docs/app/32）
  services/     txn / guild / casino / bank / report
  seed_import.py 營前建表 CLI
  tests/        經濟邏輯自我檢查
docs/           企劃 + App/Backend 設計
```

## 快速開始

**Backend**
```bash
cd backend && python -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
python tests/test_economy.py        # 驗核心金流
uvicorn app:app --host 0.0.0.0 --port 8000
```

**App**
```bash
flutter pub get
flutter run                          # 接實機（NFC 需實體裝置）
```
App 設定填 Backend URL + 選本攤位 + 綁關主 UID。

## 部署

Backend 跑在 GCE VM（systemd + uvicorn），CICD 用 GitHub Actions：push 到 main 動到
`backend/` → SSH（IAP）進 VM → git pull → 重啟服務。
完整步驟與要提供的設定見 [`DEPLOY.md`](DEPLOY.md)。
