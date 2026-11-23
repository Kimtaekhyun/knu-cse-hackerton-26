"""시간표 인식 API(POST /timetable/parse). AI는 부르지 않고 가짜 결과로 바꿔 끼운다."""

import uuid

import pytest
from fastapi.testclient import TestClient

from app.api.deps import get_current_user
from app.api.v1 import timetable as timetable_api
from app.core.config import get_settings
from app.main import app
from app.models import User
from app.schemas.timetable import Slot, Subject
from app.services import timetable_ocr
from app.services.claude import ClaudeError
from app.services.gemini import GeminiError

URL = "/api/v1/timetable/parse"
SECRET = "test-secret-at-least-32-bytes-long-0123456789"
client = TestClient(app)


def upload(data=b"fake-png", content_type="image/png", headers=None):
    return client.post(
        URL, files={"image": ("timetable.png", data, content_type)}, headers=headers or {}
    )


@pytest.fixture
def logged_in():
    """로그인 확인을 테스트 사용자로 바꿔 끼운다. DB에 사용자를 만들지 않아도 돈다"""
    app.dependency_overrides[get_current_user] = lambda: User(id=uuid.uuid4(), name="테스트")
    yield
    app.dependency_overrides.pop(get_current_user, None)


@pytest.fixture
def jwt_secret(monkeypatch):
    """토큰을 확인할 수 있게 테스트용 서명 키를 넣는다 (없으면 401이 아니라 503)"""
    monkeypatch.setenv("JWT_SECRET", SECRET)
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


@pytest.fixture
def ai_calls(monkeypatch):
    """AI(parse_timetable)를 몇 번 불렀는지 기록한다"""
    calls: list[str] = []

    def record(image, mime):
        calls.append(mime)
        return []

    monkeypatch.setattr(timetable_ocr, "parse_timetable", record)
    return calls


@pytest.fixture
def parsed(monkeypatch, logged_in):
    """로그인한 상태에서 parse_timetable 대신 정해 둔 결과를 돌려준다"""
    result = [Subject(name="자료구조", slots=[Slot(weekday=0, start="10:30", end="12:00")])]
    monkeypatch.setattr(timetable_ocr, "parse_timetable", lambda image, mime: result)


def test_parse_returns_subjects(parsed):
    response = upload()
    assert response.status_code == 200
    assert response.json() == {
        "subjects": [
            {"name": "자료구조", "slots": [{"weekday": 0, "start": "10:30", "end": "12:00"}]}
        ]
    }


def test_rejects_non_image(parsed):
    response = upload(content_type="text/plain")
    assert response.status_code == 415
    assert response.json()["detail"] == "이미지 파일(PNG, JPEG, WEBP)만 올릴 수 있어요."


def test_rejects_heic(parsed):
    # 앱은 JPEG로 바꿔 보내므로 HEIC는 앱 밖(/docs · curl)에서만 들어온다. 처리할 수 없으니 막는다
    response = upload(content_type="image/heic")
    assert response.status_code == 415


def test_rejects_empty_file(parsed):
    response = upload(data=b"")
    assert response.status_code == 400
    assert response.json()["detail"] == "빈 파일이에요."


def test_rejects_too_large(parsed, monkeypatch):
    monkeypatch.setattr(timetable_api, "MAX_BYTES", 10)
    response = upload(data=b"x" * 11)
    assert response.status_code == 413
    assert response.json()["detail"] == "이미지가 10MB를 넘어요."


def test_gemini_failure_is_502(monkeypatch, logged_in):
    def fail(image, mime):
        raise GeminiError("Gemini 사용 한도를 넘었어요(429).")

    monkeypatch.setattr(timetable_ocr, "parse_timetable", fail)
    response = upload()
    assert response.status_code == 502
    assert response.json()["detail"] == "Gemini 사용 한도를 넘었어요(429)."


def test_claude_failure_is_502(monkeypatch, logged_in):
    def fail(image, mime):
        raise ClaudeError("Claude 사용 한도를 넘었어요(429).")

    monkeypatch.setattr(timetable_ocr, "parse_timetable", fail)
    response = upload()
    assert response.status_code == 502
    assert response.json()["detail"] == "Claude 사용 한도를 넘었어요(429)."


# ---------- 로그인 확인 (#128): 서버 주소만 알아도 AI를 부를 수 있던 문제 ----------


def test_without_token_is_401_and_ai_is_not_called(ai_calls):
    response = upload()
    assert response.status_code == 401
    assert response.json()["detail"] == "로그인이 필요해요."
    assert ai_calls == []


@pytest.mark.parametrize("authorization", ["Bearer garbage", "Basic abc"])
def test_bad_token_is_401_and_ai_is_not_called(ai_calls, jwt_secret, authorization):
    response = upload(headers={"Authorization": authorization})
    assert response.status_code == 401
    assert ai_calls == []


def test_logged_in_user_calls_ai_once(ai_calls, logged_in):
    assert upload().status_code == 200
    assert ai_calls == ["image/png"]
