"""API 테스트 도구. 앱의 DB 세션을 테스트 세션(끝나면 되돌림)으로 바꿔 끼운다."""

import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.core.security import create_access_token
from app.db.session import get_db
from app.main import app
from tests.db.factories import make_user

SECRET = "test-secret-at-least-32-bytes-long-0123456789"


@pytest.fixture(autouse=True)
def jwt_settings(monkeypatch):
    """토큰을 만들고 확인할 수 있게 테스트용 서명 키를 넣는다"""
    monkeypatch.setenv("JWT_SECRET", SECRET)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def bearer(user_id) -> dict[str, str]:
    """그 사용자로 로그인한 요청 헤더"""
    return {"Authorization": f"Bearer {create_access_token(user_id)}"}


@pytest.fixture
def client(db):
    app.dependency_overrides[get_db] = lambda: db
    yield TestClient(app)
    app.dependency_overrides.clear()


@pytest.fixture
def user(db):
    return make_user(db, school="경북대학교")


@pytest.fixture
def auth(user):
    """user로 로그인한 요청 헤더"""
    return bearer(user.id)
