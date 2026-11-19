"""서버 설정. 저장소 최상위 .env 파일과 환경 변수에서 읽는다."""

from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

# server/app/core/config.py → 저장소 최상위
ROOT = Path(__file__).resolve().parents[3]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=ROOT / ".env", extra="ignore")

    gemini_api_key: str = ""
    # 판서 추출에 쓰는 기본 모델
    gemini_model: str = "gemini-3.5-flash-lite"
    # 시간표 추출 모델. 정확도가 더 중요해서 따로 바꿀 수 있게 둔다
    timetable_model: str = "gemini-3.5-flash-lite"
    # 로컬에서 uv로 실행할 때 기본값. docker compose 안에서는 DATABASE_URL로 db 컨테이너를 가리킨다
    database_url: str = "postgresql+psycopg://pansoham:pansoham@localhost:5432/pansoham"
    # 로그인 토큰(JWT) 서명 키. 비어 있으면 로그인 API가 503을 돌려준다
    jwt_secret: str = ""
    # 로그인 토큰 유효 기간(일). 리프레시 토큰이 없어서 길게 둔다
    jwt_expire_days: int = 30
    # 카카오 앱 ID (카카오 개발자 콘솔 > 앱 설정 > 앱 ID)
    # 다른 앱에서 받은 카카오 토큰을 거절할 때 쓴다
    kakao_app_id: int | None = None


@lru_cache
def get_settings() -> Settings:
    return Settings()
