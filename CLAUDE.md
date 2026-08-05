# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

3-day bilingual camp economy game ("忠心好管家" / 小市集). NFC NTAG cards = student identity + wallet. Stall-owner (攤主) Flutter app scans cards to run transactions; FastAPI backend does dual-ledger settlement: 地上積分 (earthly points, spendable in-camp) and 天國點數 KP (kingdom points, the "real" score). All numeric rules (starting balances, interest rates, fees, payouts) are defined in `docs/01-經濟與平衡模型.md` — treat it as authoritative; don't hardcode or invent economy numbers without checking it first. `docs/CHANGELOG.md` is the only place balance-value history is recorded — other docs describe current values only.

## Commands

**Backend** (from `backend/`):
```bash
python -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
uvicorn app:app --host 0.0.0.0 --port 8000       # run locally
python -m pytest tests/ -q                        # all tests, pytest-style
python tests/test_economy.py                       # same suite, plain-assert script mode (in-memory sqlite)
python -m pytest tests/test_economy.py::test_bank_transfer -q   # single test
python seed_import.py students.csv                 # pre-camp: bulk-create Student rows from CSV
```
No `pytest.ini`/`conftest.py`/`pyproject.toml` — both `pytest tests/` (from `backend/`) and `pytest backend/tests` (from repo root) work and are both used in practice; DEPLOY and CI always run `python tests/test_economy.py` from inside `backend/` as the deploy gate.

**App** (from repo root):
```bash
flutter pub get
flutter run                    # NFC requires a physical device, not a simulator
flutter analyze                # lint (flutter_lints via analysis_options.yaml)
```
No Flutter test suite exists (`test/` dir is effectively empty scaffold). Backend URL is hardcoded in `lib/services/settings.dart` (no in-app setter) — change and rebuild to point at a different backend.

## Architecture

**Backend (`backend/`)** — single-file FastAPI app, no routers:
- `app.py` — all ~37 endpoints declared directly on one `FastAPI()`, grouped by comment header (auth/scan/bank/topic1/guild/casino/admin/roster/report). A global middleware enforces Bearer auth on everything except `/health`, `/admin`, `/ledger`, `/api/auth/enroll`; paths under `/api/admin/` and `/api/report` require `admin` scope. Endpoint handlers mostly parse params and delegate to `services/`.
- `services/{txn,bank,casino,guild,roster,topic1,report}.py` — business logic. `txn.py` holds the core atomic money-flow primitives that every other service calls into.
- `db.py` — two separate sessionmakers (`ReadSessionLocal` / `SessionLocal`) against one SQLite file in WAL mode. Write sessions force `BEGIN IMMEDIATE` to serialize writes and prevent lost-update double-spend/double-payout bugs — don't bypass this when adding a new mutating endpoint. `DATABASE_URL` can swap in Postgres without schema changes.
- `models.py` — ORM: `Student`, `Transaction`, `GuildTask`, `CasinoRound`, `CasinoBet`, `WitnessLog`, `DeviceToken`, `GameState` (singleton, id=1). `Student.card_uid` (nullable+unique) doubles as "roster entry bound to a physical card" — a past migration (`migrate_unify_roster.py`) merged a separate roster table into `Student`. No Alembic; schema changes so far have been one-off scripts.
- `services/report.py` recomputes everything from the `transactions` table only (single source of truth for reporting) and renders charts as inline SVG, no external chart lib.

**App (`lib/`)** — no router package; `MaterialApp.home` is `ScanScreen` directly, and every other screen is pushed imperatively (`Navigator.push`) from `scan_screen.dart`, which is the de facto hub. Screens: `scan_screen.dart` (main NFC-scan-then-transact flow), `admin_screen.dart` (irreversible ops: set day, settle interest, market close, reset — all confirmation-gated), `bank_transfer_screen.dart` (scan A → amount → scan B → confirm), `casino_table_screen.dart` (multi-phase round lifecycle for two table types), `guild_pending_screen.dart` (staff pending-list is default view; student self-scan status check is secondary), `mail_screen.dart` (only non-NFC flow — search by name), `qr_scan_screen.dart`/`roster_bind_screen.dart` (QR fallback when NFC unavailable, same UID payload as NFC), `topic1_screen.dart` (Day1: credits whole groups at once, not per-card).

`services/api_client.dart` attaches `Authorization: Bearer <token>` from `Settings.instance.apiToken` (obtained via one-time enrollment code against `/api/auth/enroll`, persisted in `flutter_secure_storage`). 401/403 map to localized error messages; all requests have a 5s timeout.

## Docs map

- `docs/01-經濟與平衡模型.md` — authoritative balance/economy numbers (SOT).
- `docs/app/32-資料模型與交易類型.md` — data model / transaction type reference for `models.py`.
- `docs/app/33-架構與部署.md` — architecture + deploy overview with diagrams.
- `docs/CHANGELOG.md` — only place balance-value changes over time are recorded.
- `DEPLOY.md` — full deploy runbook (GCE VM, Cloudflare Tunnel, GitHub Actions via Workload Identity Federation + IAP SSH; deploy gate runs `python tests/test_economy.py` before restarting the systemd service).
