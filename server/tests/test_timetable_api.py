import pytest
from fastapi.testclient import TestClient

from app.api.v1 import timetable as timetable_api
from app.main import app
from app.schemas.timetable import Slot, Subject
from app.services import timetable_ocr
from app.services.gemini import GeminiError

URL = "/api/v1/timetable/parse"
client = TestClient(app)


def upload(data=b"fake-png", content_type="image/png"):
    return client.post(URL, files={"image": ("timetable.png", data, content_type)})


@pytest.fixture
def parsed(monkeypatch):
    """parse_timetable 대신 정해 둔 결과를 돌려준다"""
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
    assert response.json()["detail"] == "이미지 파일(PNG, JPEG, WEBP, HEIC)만 올릴 수 있어요."


def test_rejects_empty_file(parsed):
    response = upload(data=b"")
    assert response.status_code == 400
    assert response.json()["detail"] == "빈 파일이에요."


def test_rejects_too_large(parsed, monkeypatch):
    monkeypatch.setattr(timetable_api, "MAX_BYTES", 10)
    response = upload(data=b"x" * 11)
    assert response.status_code == 413
    assert response.json()["detail"] == "이미지가 10MB를 넘어요."


def test_gemini_failure_is_502(monkeypatch):
    def fail(image, mime):
        raise GeminiError("Gemini 사용 한도를 넘었어요(429).")

    monkeypatch.setattr(timetable_ocr, "parse_timetable", fail)
    response = upload()
    assert response.status_code == 502
    assert response.json()["detail"] == "Gemini 사용 한도를 넘었어요(429)."
