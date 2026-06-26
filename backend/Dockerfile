FROM python:3.13-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
# Cloud Run 注入 PORT；預設 8000。SQLite 路徑用 /tmp（容器唯一可寫處，非持久）。
# 正式建議設 DATABASE_URL 指向 Cloud SQL Postgres，schema 不變。
ENV DATABASE_URL=sqlite:////tmp/flyyoung.db
CMD ["sh", "-c", "uvicorn app:app --host 0.0.0.0 --port ${PORT:-8000}"]
