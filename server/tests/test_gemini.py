from types import SimpleNamespace

import pytest
from google.genai import errors
from pydantic import BaseModel

from app.services import gemini
from app.services.gemini import GeminiError, ask_json


class Dummy(BaseModel):
    value: int


def reply(text):
    return SimpleNamespace(text=text, prompt_feedback=None, candidates=[])


def api_error(code):
    return errors.APIError(code, {"error": {"code": code, "message": "x", "status": "X"}})


@pytest.fixture
def fake(monkeypatch):
    """gemini.generate 대신 미리 정한 답을 차례로 돌려준다. 호출 횟수는 calls에 남는다."""
    state = {"answers": [], "calls": 0}

    def generate(contents, config, model):
        state["calls"] += 1
        answer = state["answers"].pop(0) if len(state["answers"]) > 1 else state["answers"][0]
        if isinstance(answer, BaseException):
            raise answer
        return answer

    monkeypatch.setattr(gemini, "generate", generate)
    monkeypatch.setattr(gemini.time, "sleep", lambda s: None)
    monkeypatch.setattr(gemini, "RETRY_WAITS", (0, 0, 0))
    gemini._calls.clear()
    return state


def test_returns_parsed_result(fake):
    fake["answers"] = [reply('{"value": 1}')]
    result, info = ask_json(["x"], Dummy, model="m")
    assert result.value == 1
    assert info["retries"] == 0


def test_retries_on_503_then_succeeds(fake):
    fake["answers"] = [api_error(503), reply('{"value": 2}')]
    result, info = ask_json(["x"], Dummy, model="m")
    assert result.value == 2
    assert info["retries"] == 1
    assert fake["calls"] == 2


def test_429_stops_immediately(fake):
    fake["answers"] = [api_error(429)]
    with pytest.raises(GeminiError):
        ask_json(["x"], Dummy, model="m")
    assert fake["calls"] == 1


def test_empty_text_stops_immediately(fake):
    fake["answers"] = [reply("")]
    with pytest.raises(GeminiError):
        ask_json(["x"], Dummy, model="m")
    assert fake["calls"] == 1


def test_broken_json_retried_then_fails(fake):
    fake["answers"] = [reply('{"value":')]
    with pytest.raises(GeminiError):
        ask_json(["x"], Dummy, model="m")
    assert fake["calls"] == 4


def test_timeout_retried(fake):
    fake["answers"] = [TimeoutError(), reply('{"value": 3}')]
    _, info = ask_json(["x"], Dummy, model="m")
    assert info["retries"] == 1


def test_custom_parse_used(fake):
    fake["answers"] = [reply("x")]
    result, _ = ask_json(["x"], Dummy, model="m", parse=lambda text: Dummy(value=7))
    assert result.value == 7


def test_waits_when_rate_limit_full(monkeypatch):
    slept = []
    monkeypatch.setattr(gemini.time, "sleep", slept.append)
    now = gemini.time.time()
    gemini._calls.clear()
    gemini._calls.extend([now] * gemini.RPM_LIMIT)
    # 한 번 쉬고 나면 자리가 난 것처럼 기록을 비운다
    monkeypatch.setattr(gemini.time, "sleep", lambda s: (slept.append(s), gemini._calls.clear()))
    gemini.wait_for_slot()
    assert len(slept) == 1
    assert slept[0] > 0
