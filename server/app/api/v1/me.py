"""내 계정 API: 내 정보 조회 · 이름 · 학교 수정 (내 계정 화면 23)."""

from fastapi import APIRouter

from app.api.deps import DbDep, UserDep, WriteUserDep
from app.schemas.auth import UserOut
from app.schemas.me import ProfileUpdate
from app.services import users as service

router = APIRouter(prefix="/me", tags=["me"])


@router.get("", response_model=UserOut)
def get_me(user: UserDep):
    """내 정보. 앱이 자동 로그인할 때 저장된 토큰이 아직 유효한지 확인하는 데도 쓴다."""
    return user


@router.patch("", response_model=UserOut)
def update_me(body: ProfileUpdate, db: DbDep, user: WriteUserDep):
    """이름 · 학교 수정. 보낸 것만 바꾼다"""
    return service.update_profile(db, user, body)
