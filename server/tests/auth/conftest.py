"""로그인 테스트 도구.

- 로그인 설정(JWT_SECRET · KAKAO_APP_ID)을 테스트 값으로 바꾼다
- 카카오 API는 실제로 부르지 않고 FakeKakao가 정해 둔 응답을 돌려준다
"""

import httpx
import pytest
from fastapi.testclient import TestClient

from app.api.v1.auth import kakao_http
from app.core.config import get_settings
from app.db.session import get_db
from app.main import app

APP_ID = 1234567
SECRET = "test-secret-at-least-32-bytes-long-0123456789"


class FakeKakao:
    """카카오 API 가짜. 속성을 바꿔 상황을 만든다."""

    def __init__(self):
        self.kakao_id = 3001
        self.app_id = APP_ID
        self.status = 200  # 두 API가 모두 돌려줄 상태 코드
        self.timeout = False
        self.account = {
            "profile": {"nickname": "판서왕"},
            "email": "user@example.com",
            "is_email_valid": True,
            "is_email_verified": True,
        }
        self.tokens = []  # 받은 Authorization 헤더

    def handler(self, request: httpx.Request) -> httpx.Response:
        if self.timeout:
            raise httpx.ReadTimeout("시간 초과", request=request)
        self.tokens.append(request.headers.get("Authorization"))
        if self.status != 200:
            return httpx.Response(self.status, json={"code": -401, "msg": "error"})
        if request.url.path == "/v1/user/access_token_info":
            return httpx.Response(
                200, json={"id": self.kakao_id, "expires_in": 3600, "app_id": self.app_id}
            )
        if request.url.path == "/v2/user/me":
            return httpx.Response(200, json={"id": self.kakao_id, "kakao_account": self.account})
        return httpx.Response(404)

    def client(self) -> httpx.Client:
        return httpx.Client(transport=httpx.MockTransport(self.handler))


@pytest.fixture
def auth_settings(monkeypatch):
    monkeypatch.setenv("JWT_SECRET", SECRET)
    monkeypatch.setenv("KAKAO_APP_ID", str(APP_ID))
    monkeypatch.setenv("JWT_EXPIRE_DAYS", "30")
    get_settings.cache_clear()
    yield get_settings()
    get_settings.cache_clear()


@pytest.fixture
def kakao():
    return FakeKakao()


@pytest.fixture
def client(db, kakao, auth_settings):
    app.dependency_overrides[get_db] = lambda: db
    app.dependency_overrides[kakao_http] = kakao.client
    yield TestClient(app)
    app.dependency_overrides.clear()
