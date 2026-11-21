from types import SimpleNamespace

import pytest
from pydantic import BaseModel

from app.services import claude, gemini, llm


class Dummy(BaseModel):
    value: int


def use(monkeypatch, provider):
    settings = SimpleNamespace(
        llm_provider=provider,
        timetable_model="gemini-x",
        claude_timetable_model="claude-x",
        gemini_model="gemini-note",
        claude_note_model="claude-note",
    )
    monkeypatch.setattr(llm, "get_settings", lambda: settings)


@pytest.mark.parametrize(("provider", "model"), [("gemini", "gemini-x"), ("claude", "claude-x")])
def test_model_for_follows_provider(monkeypatch, provider, model):
    use(monkeypatch, provider)
    assert llm.model_for("timetable") == model


@pytest.mark.parametrize(
    ("provider", "model"), [("gemini", "gemini-note"), ("claude", "claude-note")]
)
def test_note_model_follows_provider(monkeypatch, provider, model):
    use(monkeypatch, provider)
    assert llm.model_for("note") == model


def test_gemini_parse_goes_to_gemini_only(monkeypatch):
    """LaTeX 보정 같은 Gemini 전용 읽기 함수는 Gemini에만 넘긴다"""
    use(monkeypatch, "gemini")
    seen = {}

    def fake(contents, schema, *, model, parse=None):
        seen["parse"] = parse
        return Dummy(value=1), {}

    monkeypatch.setattr(gemini, "ask_json", fake)

    def reader(text):
        return Dummy(value=3)

    llm.ask_image_json(b"img", "image/png", "p", Dummy, task="note", gemini_parse=reader)
    assert seen["parse"] is reader


def test_sends_to_gemini_by_setting(monkeypatch):
    use(monkeypatch, "gemini")
    seen = {}

    def fake(contents, schema, *, model, **kwargs):
        seen.update(count=len(contents), prompt=contents[1], schema=schema, model=model)
        return Dummy(value=1), {}

    monkeypatch.setattr(gemini, "ask_json", fake)
    result, _ = llm.ask_image_json(b"img", "image/png", "읽어 줘", Dummy, task="timetable")
    assert result == Dummy(value=1)
    assert seen == {"count": 2, "prompt": "읽어 줘", "schema": Dummy, "model": "gemini-x"}


def test_sends_to_claude_by_setting(monkeypatch):
    use(monkeypatch, "claude")
    seen = {}

    def fake(image, mime_type, prompt, schema, *, model):
        seen.update(image=image, mime=mime_type, prompt=prompt, schema=schema, model=model)
        return Dummy(value=2), {}

    monkeypatch.setattr(claude, "ask_image_json", fake)
    result, _ = llm.ask_image_json(b"img", "image/png", "읽어 줘", Dummy, task="timetable")
    assert result == Dummy(value=2)
    assert seen == {
        "image": b"img",
        "mime": "image/png",
        "prompt": "읽어 줘",
        "schema": Dummy,
        "model": "claude-x",
    }


def test_both_errors_are_llm_errors():
    assert issubclass(gemini.GeminiError, llm.LLMError)
    assert issubclass(claude.ClaudeError, llm.LLMError)
