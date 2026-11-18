"""DB 연결과 세션."""

from collections.abc import Iterator

from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import get_settings

engine = create_engine(get_settings().database_url, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, expire_on_commit=False)


def get_db() -> Iterator[Session]:
    """FastAPI 의존성. 요청 하나에 세션 하나를 쓰고 끝나면 닫는다."""
    with SessionLocal() as session:
        yield session
