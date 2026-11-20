import io
from types import SimpleNamespace

import numpy as np
import pytest
from PIL import Image

from app.schemas.timetable import Slot, Subject
from app.services import llm
from app.services.gemini import GeminiError
from app.services.timetable_ocr import BlockBox, HourMark, TimetableGrid, parse_timetable


def grid(box):
    """9~12시 눈금이 100 간격으로 놓인 시간표에 칸 하나"""
    hours = [
        HourMark(hour=h, box_2d=[100 * (h - 8), 0, 100 * (h - 8) + 20, 50]) for h in range(9, 13)
    ]
    return TimetableGrid(
        blocks=[BlockBox(name="자료구조", weekday=0, box_2d=box)], hours=hours, untimed=[]
    )


@pytest.fixture
def settings(monkeypatch):
    monkeypatch.setattr(
        llm,
        "get_settings",
        lambda: SimpleNamespace(llm_provider="gemini", timetable_model="test-model"),
    )


def test_parse_timetable_asks_with_timetable_task(monkeypatch, settings):
    seen = {}

    def fake_ask(image, mime_type, prompt, schema, *, task):
        seen.update(image=image, mime=mime_type, schema=schema, task=task)
        return grid([250, 100, 400, 900]), {}

    monkeypatch.setattr(llm, "ask_image_json", fake_ask)
    result = parse_timetable(b"png-bytes", "image/png")
    assert seen == {
        "image": b"png-bytes",
        "mime": "image/png",
        "schema": TimetableGrid,
        "task": "timetable",
    }
    assert result == [Subject(name="자료구조", slots=[Slot(weekday=0, start="10:30", end="12:00")])]


def test_parse_timetable_passes_gemini_error(monkeypatch, settings):
    def fake_ask_json(*args, **kwargs):
        raise GeminiError("x")

    monkeypatch.setattr(llm, "ask_image_json", fake_ask_json)
    with pytest.raises(GeminiError):
        parse_timetable(b"png-bytes", "image/png")


def test_parse_timetable_fixes_end_with_image_colors(monkeypatch, settings):
    # 칸은 10:00~12:00 (200~400)인데 모델이 글씨 부분(200~260)만 감쌈
    pixels = np.zeros((1000, 100, 3), dtype=np.uint8)
    pixels[200:400, 10:90] = (200, 90, 80)
    png = io.BytesIO()
    Image.fromarray(pixels).save(png, format="PNG")

    monkeypatch.setattr(llm, "ask_image_json", lambda *a, **k: (grid([200, 100, 260, 900]), {}))
    result = parse_timetable(png.getvalue(), "image/png")
    assert result == [Subject(name="자료구조", slots=[Slot(weekday=0, start="10:00", end="12:00")])]
