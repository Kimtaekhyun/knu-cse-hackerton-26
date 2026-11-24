"""서버 설정. 저장소 최상위 .env 파일과 환경 변수에서 읽는다."""

from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict

# server/app/core/config.py → 저장소 최상위
ROOT = Path(__file__).resolve().parents[3]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=ROOT / ".env", extra="ignore")

    # 시간표 · 판서 인식에 쓸 AI. claude(기본) 또는 gemini (services/llm.py가 이 값으로 고른다)
    llm_provider: Literal["gemini", "claude"] = "claude"
    # 실제 키는 .env의 ANTHROPIC_API_KEY에서 읽는다. ""는 .env에 없을 때 쓰는 값이다
    anthropic_api_key: str = ""
    # Claude로 시간표를 읽을 때 쓰는 모델
    claude_timetable_model: str = "claude-haiku-5-5"
    # Claude로 판서를 읽을 때 쓰는 모델
    claude_note_model: str = "claude-haiku-5-5"
    # 학사일정을 웹 검색으로 찾을 때 쓰는 모델 (#173). 학교 · 학기마다 한 번만 찾는다
    calendar_model: str = "claude-opus-5-5"
    # LLM_PROVIDER=gemini일 때만 쓴다
    gemini_api_key: str = ""
    # Gemini로 판서를 읽을 때 쓰는 모델
    gemini_model: str = "gemini-3.5-flash-lite"
    # Gemini로 시간표를 읽을 때 쓰는 모델. 정확도가 더 중요해서 따로 바꿀 수 있게 둔다
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
    # 업로드한 판서 사진 · 카드 조각을 저장하는 폴더 (app/storage/local.py)
    # 로컬에서 uv로 실행할 때 기본값. docker compose 안에서는 MEDIA_DIR로 media 볼륨을 가리킨다
    media_dir: Path = ROOT / "server" / "media"
    # 판서를 동시에 몇 장까지 처리할지. 1이면 올린 순서대로 한 장씩 (AI 분당 한도 · 화면 순서)
    pipeline_workers: int = 1


@lru_cache
def get_settings() -> Settings:
    return Settings()
