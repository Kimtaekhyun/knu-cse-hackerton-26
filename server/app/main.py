"""판서함 API 진입점."""

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from sqlalchemy.exc import IntegrityError

from app.api.v1 import api_router

app = FastAPI(title="판서함 API")
app.include_router(api_router)

UNIQUE_VIOLATION = "23505"


@app.exception_handler(IntegrityError)
def integrity_error(request: Request, error: IntegrityError):
    """중복 제약 위반은 409로 돌려준다 (API의 중복 확인을 피해 간 경우의 마지막 방어선).

    외래 키 · CHECK 위반 등 다른 위반은 코드 버그이므로 그대로 500으로 둔다.
    """
    if getattr(error.orig, "sqlstate", None) == UNIQUE_VIOLATION:
        return JSONResponse({"detail": "이미 같은 항목이 있어요."}, status_code=409)
    raise error


@app.get("/health")
def health():
    """서버가 살아 있는지 확인"""
    return {"status": "ok"}
