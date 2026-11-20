import io
from types import SimpleNamespace

import anthropic
import httpx
import pytest
from PIL import Image
from pydantic import BaseModel

from app.services import claude
from app.services.claude import ClaudeError, ask_image_json, prepare_image


class Dummy(BaseModel):
    value: int


def reply(parsed=None, stop_reason="end_turn"):
    usage = SimpleNamespace(input_tokens=10, output_tokens=5)
    return SimpleNamespace(
        parsed_output=parsed, stop_reason=stop_reason, model="claude-x", usage=usage
    )


def status_error(cls, code):
    request = httpx.Request("POST", "https://api.anthropic.com/v1/messages")
    response = httpx.Response(code, request=request)
    return cls("x", response=response, body=None)


@pytest.fixture
def fake(monkeypatch):
    """get_client() 대신 정해 둔 답(또는 오류)을 돌려주는 가짜 연결. 받은 인자는 calls에 남는다"""
    state = {"answer": reply(Dummy(value=1)), "calls": []}

    def parse(**kwargs):
        state["calls"].append(kwargs)
        if isinstance(state["answer"], Exception):
            raise state["answer"]
        return state["answer"]

    client = SimpleNamespace(beta=SimpleNamespace(messages=SimpleNamespace(parse=parse)))
    monkeypatch.setattr(claude, "get_client", lambda: client)
    return state


def png_bytes(size=(10, 10)):
    out = io.BytesIO()
    Image.new("RGB", size, (200, 90, 80)).save(out, format="PNG")
    return out.getvalue()


def test_returns_parsed_result_and_info(fake):
    result, info = ask_image_json(b"img", "image/png", "읽어 줘", Dummy, model="claude-x")
    assert result == Dummy(value=1)
    assert info["model"] == "claude-x"
    assert (info["input_tokens"], info["output_tokens"]) == (10, 5)


def test_sends_image_prompt_schema_and_fallback(fake):
    ask_image_json(b"img", "image/png", "읽어 줘", Dummy, model="claude-x")
    call = fake["calls"][0]
    image, text = call["messages"][0]["content"]
    assert image["source"] == {"type": "base64", "media_type": "image/png", "data": "aW1n"}
    assert text == {"type": "text", "text": "읽어 줘"}
    assert call["model"] == "claude-x"
    assert call["output_format"] is Dummy
    assert call["fallbacks"] == "default"
    assert call["betas"] == [claude.FALLBACK_BETA]


@pytest.mark.parametrize(
    ("stop_reason", "message"),
    [("refusal", "안전 거절"), ("max_tokens", "끊겼어요")],
)
def test_bad_stop_reason_raises(fake, stop_reason, message):
    fake["answer"] = reply(Dummy(value=1), stop_reason=stop_reason)
    with pytest.raises(ClaudeError, match=message):
        ask_image_json(b"img", "image/png", "p", Dummy, model="m")


def test_empty_answer_raises(fake):
    fake["answer"] = reply(None)
    with pytest.raises(ClaudeError, match="빈 답"):
        ask_image_json(b"img", "image/png", "p", Dummy, model="m")


@pytest.mark.parametrize(
    ("error", "message"),
    [
        (status_error(anthropic.AuthenticationError, 401), "ANTHROPIC_API_KEY"),
        (status_error(anthropic.RateLimitError, 429), "429"),
        (status_error(anthropic.InternalServerError, 500), "500"),
        (
            anthropic.APIConnectionError(request=httpx.Request("POST", "https://x")),
            "연결하지 못했어요",
        ),
        (ValueError("bad json"), "읽지 못했어요"),
    ],
)
def test_api_errors_become_claude_error(fake, error, message):
    fake["answer"] = error
    with pytest.raises(ClaudeError, match=message):
        ask_image_json(b"img", "image/png", "p", Dummy, model="m")


def test_missing_key_raises(monkeypatch):
    monkeypatch.setattr(claude, "_client", None)
    monkeypatch.setattr(claude, "get_settings", lambda: SimpleNamespace(anthropic_api_key=""))
    with pytest.raises(ClaudeError, match="ANTHROPIC_API_KEY"):
        claude.get_client()


def test_prepare_image_keeps_supported_small_image():
    data = png_bytes()
    assert prepare_image(data, "image/png") == (data, "image/png")


def test_prepare_image_converts_unsupported_type_to_jpeg():
    data, mime = prepare_image(png_bytes(), "image/heic")
    assert mime == "image/jpeg"
    assert Image.open(io.BytesIO(data)).format == "JPEG"


def test_prepare_image_shrinks_large_image(monkeypatch):
    monkeypatch.setattr(claude, "MAX_IMAGE_BYTES", 10)
    data, mime = prepare_image(png_bytes((3000, 1000)), "image/png")
    assert mime == "image/jpeg"
    assert max(Image.open(io.BytesIO(data)).size) == claude.MAX_SIDE


def test_prepare_image_rejects_unreadable():
    with pytest.raises(ClaudeError, match="읽을 수 없어요"):
        prepare_image(b"not-an-image", "image/heic")


def test_haiku_is_sent_without_fallback(fake):
    ask_image_json(b"img", "image/png", "p", Dummy, model="claude-haiku-5-5")
    call = fake["calls"][0]
    assert "fallbacks" not in call
    assert "betas" not in call
