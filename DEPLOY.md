# 部署：Backend 上 GCE VM（你已建好的執行個體）

你的後端跑在 **Compute Engine VM**（截圖那台）：

| 項目 | 值 |
|---|---|
| VM 名稱 | `bilingual-camp-little-market-backend-2026` |
| Zone | `asia-east1-c`（Region `asia-east1`），機型 e2-small |
| OS | Debian 13 (trixie), x86_64 |
| **Project ID** | **`rust-online-judge`** |
| **VM 外部 IP** | **`104.199.226.128`** → App Backend URL 填 `http://104.199.226.128:8080` |
| **Port** | **8080**（防火牆規則 `bilingual-camp` 已開 tcp:8080 給 0.0.0.0/0，免再設） |

> 「repo」名詞釐清：
> - **GitHub repo** = `mushding/2026-bilingual-camp-little-market`（程式碼放哪）。
> - DEPLOY 裡的 `REPO=flyyoung` 是 Cloud Run 用的，**VM 部署用不到，忽略**。

CICD 用 **GitHub Actions**：push 到 `main` 動到 `backend/` → 自動 SSH 進這台 VM →
`git pull` → 重裝相依 → 重啟 systemd 服務。
SSH 走 `gcloud compute ssh --tunnel-through-iap`：**VM 不需公開 IP、不必開 22 port**。
Workflow 檔：`.github/workflows/deploy-backend.yml`。

---

## 0. Project（已查到）

```bash
gcloud config set project rust-online-judge
gcloud compute instances list   # bilingual-camp-little-market-backend-2026 RUNNING, IP 104.199.226.128
```
下面所有 `<PROJECT_ID>` = `rust-online-judge`。

---

## 1. VM 上一次性設定（在 VM 內跑）

先 SSH 進去（console 按「SSH」鈕，或本機）：
```bash
gcloud compute ssh bilingual-camp-little-market-backend-2026 \
  --zone asia-east1-c --project rust-online-judge --tunnel-through-iap
```

VM 內執行：
```bash
sudo apt update && sudo apt install -y python3-venv git

# 拉 code（HTTPS public repo，免金鑰）
git clone https://github.com/mushding/2026-bilingual-camp-little-market.git
cd 2026-bilingual-camp-little-market/backend

python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
python tests/test_economy.py        # 應 ALL 9 PASS

# （可選）營前建表
# python seed_import.py students.csv
```

建 systemd 服務（開機自啟 + 自動重啟）：
```bash
sudo tee /etc/systemd/system/flyyoung-backend.service >/dev/null <<EOF
[Unit]
Description=Flyyoung 小市集 backend
After=network.target

[Service]
User=$USER
WorkingDirectory=/home/$USER/2026-bilingual-camp-little-market/backend
Environment=DATABASE_URL=sqlite:////home/$USER/flyyoung.db
ExecStart=/home/$USER/2026-bilingual-camp-little-market/backend/.venv/bin/uvicorn app:app --host 0.0.0.0 --port 8080
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now flyyoung-backend
sudo systemctl status flyyoung-backend --no-pager   # 確認 running
```

> DB 用 SQLite 存在 `/home/$USER/flyyoung.db`（VM 磁碟持久，重啟不掉，
> 跟 Cloud Run 不同 — VM 適合 SQLite）。<100 人三天綽綽有餘。

防火牆：**port 8080 已開**（規則 `bilingual-camp`，tcp:8080 給 0.0.0.0/0），免再設。
App 設定的 Backend URL 填 `http://104.199.226.128:8080`。

確認服務通：
```bash
curl http://104.199.226.128:8080/health    # 應回 {"ok":true}
```

> ⚠️ 純 http + 開放 0.0.0.0。營會用沒差；要更安全可只開營會場地 IP，或前面架 nginx + Let's Encrypt 上 https。

---

## 2. 設定 CICD（GitHub Actions 自動部署）

### 2a. 一次性 GCP 設定（本機跑，需 `gcloud auth login`）

```bash
export PROJECT_ID=rust-online-judge
export GH_REPO=mushding/2026-bilingual-camp-little-market
export ZONE=asia-east1-c
export VM=bilingual-camp-little-market-backend-2026

# 開 API
gcloud services enable iamcredentials.googleapis.com iap.googleapis.com \
  compute.googleapis.com --project "$PROJECT_ID"

# 部署用 service account
gcloud iam service-accounts create gh-deployer \
  --display-name "GitHub Actions deployer" --project "$PROJECT_ID"
export SA_EMAIL="gh-deployer@${PROJECT_ID}.iam.gserviceaccount.com"

# 權限：透過 IAP SSH 進 VM
for ROLE in roles/compute.instanceAdmin.v1 roles/iap.tunnelResourceAccessor \
            roles/iam.serviceAccountUser; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" --role="$ROLE"
done

# WIF pool + provider（綁 GitHub repo）
gcloud iam workload-identity-pools create github-pool \
  --location=global --project "$PROJECT_ID"
export POOL_ID=$(gcloud iam workload-identity-pools describe github-pool \
  --location=global --project "$PROJECT_ID" --format="value(name)")
gcloud iam workload-identity-pools providers create-oidc github-provider \
  --location=global --workload-identity-pool=github-pool \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --attribute-condition="assertion.repository=='${GH_REPO}'" \
  --project "$PROJECT_ID"
gcloud iam service-accounts add-iam-policy-binding "$SA_EMAIL" \
  --role=roles/iam.workloadIdentityUser \
  --member="principalSet://iam.googleapis.com/${POOL_ID}/attribute.repository/${GH_REPO}" \
  --project "$PROJECT_ID"

# 印出要填進 GitHub 的值
echo "GCP_WIF_PROVIDER = $(gcloud iam workload-identity-pools providers describe github-provider \
  --location=global --workload-identity-pool=github-pool --project "$PROJECT_ID" --format='value(name)')"
echo "GCP_SA_EMAIL     = $SA_EMAIL"
```

### 2b. 填進 GitHub repo（Settings → Secrets and variables → Actions）

**Secrets：**
| 名稱 | 值 |
|---|---|
| `GCP_WIF_PROVIDER` | 上面 echo 的 provider 路徑 |
| `GCP_SA_EMAIL` | `gh-deployer@<project>.iam.gserviceaccount.com` |

**Variables：**
| 名稱 | 值 |
|---|---|
| `GCP_PROJECT_ID` | `rust-online-judge` |
| `GCP_ZONE` | `asia-east1-c` |
| `GCP_VM_NAME` | `bilingual-camp-little-market-backend-2026` |

設好後：push 到 main 動到 `backend/` → 自動部署；或 Actions 頁手動 `Run workflow`。

> CICD 帳號的 SSH 第一次會在 VM 自動建 user；workflow 內 `git pull` 用的是
> VM 上 §1 你 clone 的那份 repo，所以**§1 的 clone 路徑要在該 SSH user 的 home**。
> 若 CICD user 與你手動 clone 的 user 不同，最簡單做法：把 clone 放共用路徑，
> 或讓 workflow 的 `--command` 指到正確絕對路徑（改 `cd ~/...` 為 `cd /home/<user>/...`）。

---

## 3. 本機跑 backend（開發 / 現場備援）

```bash
cd backend
python -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
uvicorn app:app --host 0.0.0.0 --port 8000   # App 填 http://<本機LAN IP>:8000
```

---

## 你總共要提供的東西（清單）

1. ~~Project ID~~ → 已查到 `rust-online-judge`，VM IP `104.199.226.128`。
2. 在 VM 跑 **§1**（clone + venv + systemd）。App Backend URL 填 `http://104.199.226.128:8080`。
3. 跑 **§2a** → 拿 `GCP_WIF_PROVIDER` / `GCP_SA_EMAIL`。
4. 在 GitHub 填 **§2b** 的 2 Secrets + 3 Variables。

做完 2–4，之後改 backend push 就自動上線。
（不想設 CICD 也行：手動 SSH 進 VM `cd backend && git pull && sudo systemctl restart flyyoung-backend`。）
