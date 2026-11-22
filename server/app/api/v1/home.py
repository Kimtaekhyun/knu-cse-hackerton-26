"""메인 화면 API: 수업 중 · 오늘 수업 · 이번 주 판서 · 시험까지 남은 기간 (메인 07 · 08)."""

from datetime import datetime

from fastapi import APIRouter

from app.api.deps import DbDep, UserDep
from app.schemas.home import HomeOut
from app.services import home as service
from app.services.queries import SEOUL

router = APIRouter(prefix="/home", tags=["home"])


@router.get("", response_model=HomeOut)
def get_home(db: DbDep, user: UserDep, at: datetime | None = None):
    """메인 화면 값 한 번에. at을 주면 그 시각 기준 (테스트 · 시연용, 없으면 지금)

    "아직 옮기지 않은 판서"는 GET /captures?unmoved=true를 쓴다.
    """
    return service.home(db, user, at or datetime.now(SEOUL))
