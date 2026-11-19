"""API 테스트 도구. 앱의 DB 세션을 테스트 세션(끝나면 되돌림)으로 바꿔 끼운다."""

import pytest
from fastapi.testclient import TestClient

from app.db.session import get_db
from app.main import app
from tests.db.factories import make_user


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
    """요청 헤더. 로그인이 생기기 전까지 X-User-Id로 사용자를 고른다"""
    return {"X-User-Id": str(user.id)}
