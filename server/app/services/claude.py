"""Claude 공통 호출 모듈.

gemini.py의 ask_json처럼 이미지와 프롬프트를 보내고 pydantic 스키마 형식의 JSON 답을 받는다.
- 답 형식은 structured outputs(output_format)로 강제해서, 깨진 JSON을 다시 요청할 일이 없다
- 일시 오류(429 · 5xx · 연결 끊김)는 SDK가 알아서 다시 시도한다 (MAX_RETRIES)
- 안전 거절이 나면 서버가 다른 모델로 한 번 더 시도한다 (server-side fallback, Haiku는 지원 안 함)
"""

import base64
import io
import time

import anthropic
from PIL import Image, ImageOps
from pydantic import BaseModel

from app.core.config import get_settings
from app.services.llm import LLMError, T

# Claude가 읽는 이미지 형식. 나머지는 JPEG로 바꿔 보낸다
SUPPORTED_TYPES = {"image/png", "image/jpeg", "image/gif", "image/webp"}
MAX_IMAGE_BYTES = 5 * 1024 * 1024  # API의 이미지 한 장 한도
MAX_SIDE = 2000  # 크기를 줄여야 할 때 긴 변 길이. 좌표는 0~1000 비율이라 줄여도 결과가 같다
# 요청 한 번을 기다리는 최대 초. Claude는 답하기 전에 생각하는 시간이 있어 Gemini(30초)보다 길다
REQUEST_TIMEOUT = 120
MAX_RETRIES = 3
MAX_TOKENS = 16000
# 생각을 얼마나 깊게 할지 (low · medium · high · xhigh · max). 정확도와 시간 · 비용을 맞바꾼다
EFFORT = "medium"
FALLBACK_BETA = "server-side-fallback-2026-07-01"
FALLBACK_OPTIONS = {"betas": [FALLBACK_BETA], "fallbacks": "default"}

_client = None


class ClaudeError(LLMError):
    """Claude에 요청했지만 끝내 답을 받지 못함. 메시지는 사용자에게 그대로 보여 준다."""


def get_client() -> anthropic.Anthropic:
    """Claude 연결을 한 번만 만들어 다시 쓴다."""
    global _client
    if _client is None:
        key = get_settings().anthropic_api_key
        if not key:
            raise ClaudeError(
                "ANTHROPIC_API_KEY가 설정되지 않았어요. 저장소 최상위 .env에 넣어 주세요."
            )
        _client = anthropic.Anthropic(api_key=key, timeout=REQUEST_TIMEOUT, max_retries=MAX_RETRIES)
    return _client


def prepare_image(image: bytes, mime_type: str) -> tuple[bytes, str]:
    """Claude가 받는 형식 · 크기로 맞춘다. 이미 맞으면 그대로 돌려준다."""
    if mime_type in SUPPORTED_TYPES and len(image) <= MAX_IMAGE_BYTES:
        return image, mime_type
    try:
        with Image.open(io.BytesIO(image)) as opened:
            picture = ImageOps.exif_transpose(opened).convert("RGB")
    except Exception as error:
        raise ClaudeError("이 이미지 형식은 읽을 수 없어요. PNG나 JPEG로 올려 주세요.") from error
    picture.thumbnail((MAX_SIDE, MAX_SIDE))
    out = io.BytesIO()
    picture.save(out, format="JPEG", quality=90)
    return out.getvalue(), "image/jpeg"


def ask_image_json(
    image: bytes, mime_type: str, prompt: str, schema: type[T], *, model: str
) -> tuple[T, dict]:
    """Claude에 이미지와 프롬프트를 보내고 schema 형식의 답을 받는다.

    돌려주는 값: (결과, 정보). 정보는 seconds(응답 시간), model(실제로 답한 모델),
    input_tokens · output_tokens(요금 계산용)
    끝내 실패하면 ClaudeError를 던진다.
    """
    data, media_type = prepare_image(image, mime_type)
    content = [
        {
            "type": "image",
            "source": {
                "type": "base64",
                "media_type": media_type,
                "data": base64.standard_b64encode(data).decode("ascii"),
            },
        },
        {"type": "text", "text": prompt},
    ]
    # Haiku는 서버 측 fallback이 없다 (보내면 거절이 그대로이거나 400). 다른 모델에만 붙인다
    fallback = {} if model.startswith("claude-haiku") else FALLBACK_OPTIONS
    start = time.time()
    try:
        response = get_client().beta.messages.parse(
            model=model,
            max_tokens=MAX_TOKENS,
            messages=[{"role": "user", "content": content}],
            output_format=schema,
            output_config={"effort": EFFORT},
            **fallback,
        )
    except anthropic.AuthenticationError as error:
        raise ClaudeError("ANTHROPIC_API_KEY가 올바르지 않아요.") from error
    except anthropic.RateLimitError as error:
        message = "Claude 사용 한도를 넘었어요(429). 잠시 뒤 다시 시도해 주세요."
        raise ClaudeError(message) from error
    except anthropic.APIStatusError as error:
        raise ClaudeError(f"Claude 요청 실패({error.status_code}): {error.message}") from error
    except anthropic.APIConnectionError as error:  # 시간 초과(APITimeoutError)도 여기에 들어온다
        message = "Claude에 연결하지 못했어요. 잠시 뒤 다시 시도해 주세요."
        raise ClaudeError(message) from error
    except ValueError as error:  # 답이 스키마와 안 맞을 때 (pydantic 검사 오류)
        raise ClaudeError("Claude의 답을 읽지 못했어요.") from error

    if response.stop_reason == "refusal":
        raise ClaudeError("Claude가 이 이미지를 처리하지 않았어요(안전 거절).")
    if response.stop_reason == "max_tokens":
        raise ClaudeError("Claude의 답이 너무 길어서 끊겼어요.")
    result = response.parsed_output
    if not isinstance(result, BaseModel):
        raise ClaudeError("Claude가 빈 답을 보냈어요.")
    info = {
        "seconds": time.time() - start,
        "model": response.model,
        "input_tokens": response.usage.input_tokens,
        "output_tokens": response.usage.output_tokens,
    }
    return result, info
