"""chalkdrop API 진입점."""

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from sqlalchemy.exc import IntegrityError, OperationalError

from app.api.v1 import api_router
from app.services.pipeline import worker

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """켤 때 처리 중에 멈춘 판서를 다시 줄에 세우고, 끌 때 작업 줄을 닫는다.

    DB에 붙지 못해도 서버는 뜨게 둔다 (헬스 체크 · 다른 API는 쓸 수 있게).
    """
    try:
        count = worker.resume_unfinished()
        if count:
            logger.info("처리 중에 멈춘 판서 %d장을 다시 처리해요", count)
    except OperationalError:
        logger.exception("DB에 연결하지 못해 멈춘 판서를 다시 처리하지 못했어요")
    yield
    worker.shutdown()


app = FastAPI(title="chalkdrop API", lifespan=lifespan)
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
