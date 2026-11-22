"""API v1 라우터를 한곳에 모은다."""

from fastapi import APIRouter

from app.api.v1 import auth, captures, me, semesters, subjects, timetable

api_router = APIRouter(prefix="/api/v1")
api_router.include_router(captures.router)
api_router.include_router(timetable.router)
api_router.include_router(semesters.router)
api_router.include_router(subjects.router)
api_router.include_router(auth.router)
api_router.include_router(me.router)
