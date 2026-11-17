"""API v1 라우터를 한곳에 모은다."""

from fastapi import APIRouter

from app.api.v1 import timetable

api_router = APIRouter(prefix="/api/v1")
api_router.include_router(timetable.router)
