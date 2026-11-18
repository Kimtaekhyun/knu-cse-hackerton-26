"""DB 테스트 도구.

- 테스트 DB(pansoham_test)를 만들고, 테스트를 시작할 때 마이그레이션을 처음부터 다시 적용한다
- 테스트마다 트랜잭션 안에서 실행하고 끝나면 되돌린다 (테스트끼리 데이터가 섞이지 않게)
- DB에 붙을 수 없으면 DB 테스트는 건너뛴다. REQUIRE_DB=1 이면 실패로 처리한다 (CI용)
"""

import argparse
import os
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, text
from sqlalchemy.engine import make_url
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session

from app.core.config import get_settings

SERVER = Path(__file__).resolve().parents[1]
TEST_DATABASE = "pansoham_test"


def ensure_database(url) -> None:
    """테스트 DB가 없으면 만든다. DB 서버에 붙을 수 없으면 OperationalError."""
    admin = create_engine(url.set(database="postgres"), isolation_level="AUTOCOMMIT")
    try:
        with admin.connect() as connection:
            found = connection.scalar(
                text("SELECT 1 FROM pg_database WHERE datname = :name"), {"name": url.database}
            )
            if not found:
                connection.execute(text(f'CREATE DATABASE "{url.database}"'))
    finally:
        admin.dispose()


def migrate(url: str) -> None:
    """마이그레이션을 처음부터 다시 적용한다 (downgrade → upgrade 둘 다 확인하는 셈)."""
    config = Config(str(SERVER / "alembic.ini"), cmd_opts=argparse.Namespace(x=[f"url={url}"]))
    config.set_main_option("script_location", str(SERVER / "alembic"))
    command.downgrade(config, "base")
    command.upgrade(config, "head")


@pytest.fixture(scope="session")
def db_engine():
    url = make_url(get_settings().database_url).set(database=TEST_DATABASE)
    try:
        ensure_database(url)
    except OperationalError as error:
        if os.environ.get("REQUIRE_DB") == "1":
            raise
        pytest.skip(f"DB에 연결할 수 없어 DB 테스트를 건너뜀 ({type(error).__name__})")
    migrate(url.render_as_string(hide_password=False))
    engine = create_engine(url)
    yield engine
    engine.dispose()


@pytest.fixture
def db(db_engine):
    """테스트 하나 동안 쓰는 세션. 끝나면 모든 변경을 되돌린다."""
    with db_engine.connect() as connection:
        transaction = connection.begin()
        session = Session(bind=connection, join_transaction_mode="create_savepoint")
        try:
            yield session
        finally:
            session.close()
            transaction.rollback()
