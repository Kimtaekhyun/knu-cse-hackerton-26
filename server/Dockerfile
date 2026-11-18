# 판서함 API 서버 이미지
FROM python:3.11-slim

COPY --from=ghcr.io/astral-sh/uv:0.13.8 /uv /uvx /bin/

WORKDIR /app
# 가상환경을 /app 밖에 둔다. 개발 중에는 ./server를 /app에 연결하므로 그 안에 두면 가려진다
ENV UV_PROJECT_ENVIRONMENT=/opt/venv \
    UV_LINK_MODE=copy \
    PYTHONUNBUFFERED=1

COPY pyproject.toml uv.lock .python-version ./
RUN uv sync --frozen

COPY . .

EXPOSE 8000
# 시작할 때 테이블 · 시드를 최신으로 맞춘 뒤 서버 실행 (코드를 고치면 --reload로 자동 재시작)
CMD ["sh", "-c", "uv run --no-sync alembic upgrade head && uv run --no-sync uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload"]
