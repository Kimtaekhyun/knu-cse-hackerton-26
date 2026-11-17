"""판서함 API 진입점."""

from fastapi import FastAPI

from app.api.v1 import api_router

app = FastAPI(title="판서함 API")
app.include_router(api_router)


@app.get("/health")
def health():
    """서버가 살아 있는지 확인"""
    return {"status": "ok"}
