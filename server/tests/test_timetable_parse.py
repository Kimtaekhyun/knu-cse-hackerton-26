from types import SimpleNamespace

import pytest
from app.schemas.timetable import Slot, Subject
from app.services import timetable_ocr
from app.services.gemini import GeminiError
from app.services.timetable_ocr import RawBlock, RawTimetable, parse_timetable


@pytest.fixture
def settings(monkeypatch):
    monkeypatch.setattr(
        timetable_ocr, "get_settings", lambda: SimpleNamespace(timetable_model="test-model")
    )


def test_parse_timetable_uses_timetable_model(monkeypatch, settings):
    seen = {}

    def fake_ask_json(contents, schema, *, model, **kwargs):
        seen["model"] = model
        seen["contents"] = len(contents)
        raw = RawTimetable(
            blocks=[RawBlock(name="자료구조", weekday=0, start="10:30", end="12:00")], untimed=[]
        )
        return raw, {}

    monkeypatch.setattr(timetable_ocr, "ask_json", fake_ask_json)
    result = parse_timetable(b"png-bytes", "image/png")
    assert seen == {"model": "test-model", "contents": 2}
    assert result == [Subject(name="자료구조", slots=[Slot(weekday=0, start="10:30", end="12:00")])]


def test_parse_timetable_passes_gemini_error(monkeypatch, settings):
    def fake_ask_json(*args, **kwargs):
        raise GeminiError("x")

    monkeypatch.setattr(timetable_ocr, "ask_json", fake_ask_json)
    with pytest.raises(GeminiError):
        parse_timetable(b"png-bytes", "image/png")
