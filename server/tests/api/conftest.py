"""API 테스트 도구. 앱의 DB 세션을 테스트 세션(끝나면 되돌림)으로 바꿔 끼운다."""

import pytest
from fastapi.testclient import TestClient

from app.core.config import get_settings
from app.core.security import create_access_token
from app.db.session import get_db
from app.main import app
from app.services import academic_calendar
from app.services.pipeline import worker
from tests.db.factories import make_user

SECRET = "test-secret-at-least-32-bytes-long-0123456789"


@pytest.fixture(autouse=True)
def jwt_settings(monkeypatch):
    """토큰을 만들고 확인할 수 있게 테스트용 서명 키를 넣는다"""
    monkeypatch.setenv("JWT_SECRET", SECRET)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


@pytest.fixture(autouse=True)
def enqueued(monkeypatch):
    """API 테스트에서는 판서를 실제로 처리하지 않고 처리 줄에 세운 기록만 남긴다

    진짜 워커는 테스트 DB가 아닌 개발 DB를 보고, AI도 부르기 때문이다.
    처리 자체는 tests/pipeline/에서 따로 확인한다.
    """
    calls: list[tuple] = []
    monkeypatch.setattr(
        worker,
        "enqueue",
        lambda capture_id, *, skip_rectify=False: calls.append((str(capture_id), skip_rectify)),
    )
    return calls


@pytest.fixture(autouse=True)
def calendar_lookups(monkeypatch):
    """API 테스트에서는 학사일정을 실제로 찾지 않고(웹 검색 · 요금) 찾으라고 한 기록만 남긴다 (#173)

    찾기 자체는 tests/test_academic_calendar.py에서 따로 확인한다.
    """
    calls: list[tuple] = []
    monkeypatch.setattr(academic_calendar, "request_lookup", lambda *key: calls.append(key))
    return calls


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
