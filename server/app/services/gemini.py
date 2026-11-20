"""Gemini 공통 호출 모듈.

이미지와 프롬프트를 보내고 정해진 형식(pydantic 스키마)의 JSON 답을 받는다.
판서 파이프라인(pipeline/note_pipeline.py)에서 쓰던 방식을 그대로 옮겼다.
- 요청 한 번은 REQUEST_TIMEOUT초까지만 기다린다
- 일시 오류는 RETRY_WAITS 간격으로 다시 시도한다
- 키 하나의 분당 한도를 넘지 않도록 이 모듈을 쓰는 모든 기능이 같은 카운터를 쓴다
"""

import logging
import threading
import time
from collections import deque
from collections.abc import Callable
from typing import TypeVar

import httpx
from google import genai
from google.genai import errors, types
from pydantic import BaseModel

from app.core.config import get_settings
from app.services.llm import LLMError

logger = logging.getLogger(__name__)

T = TypeVar("T", bound=BaseModel)

RPM_LIMIT = 12  # 무료 등급 한도는 분당 15회. 여유를 두고 12회까지만 보낸다 (다시 시도 포함)
RETRY_WAITS = (3, 6, 12)  # 다시 시도하기 전에 쉬는 초. 최대 3번 다시 시도
RETRY_CODES = {408, 500, 502, 503, 504}  # 일시 오류(시간 초과·서버 오류)만 다시 시도한다
# 요청 한 번을 기다리는 최대 초. 라이브러리의 시간 제한은 연결·받기 단계마다 따로 걸려서
# 요청 전체를 막지 못한다 (실제로 312초 걸린 적 있음). 그래서 전체 시간을 직접 잰다.
REQUEST_TIMEOUT = 30

_calls = deque()  # 최근 60초 동안 보낸 요청 시각
_calls_lock = threading.Lock()  # 여러 요청이 동시에 들어와도 한도를 지키도록
_client = None


class GeminiError(LLMError):
    """Gemini에 요청했지만 끝내 답을 받지 못함. 메시지는 사용자에게 그대로 보여 준다."""


def get_client():
    """Gemini 연결을 한 번만 만들어 다시 쓴다."""
    global _client
    if _client is None:
        key = get_settings().gemini_api_key
        if not key:
            raise GeminiError(
                "GEMINI_API_KEY가 설정되지 않았어요. 저장소 최상위 .env에 넣어 주세요."
            )
        # 단계별 시간 제한도 REQUEST_TIMEOUT으로 맞춘다. generate()가 시간 초과로 버린 요청이
        # 뒤에서 오래 살아 있으면 다시 시도할 때마다 요청이 겹쳐 쌓이고 분당 한도도 잡아먹는다.
        _client = genai.Client(
            api_key=key, http_options=types.HttpOptions(timeout=REQUEST_TIMEOUT * 1000)
        )
    return _client


def generate(contents, config, model):
    """Gemini 요청을 한 번 보내고 REQUEST_TIMEOUT초까지만 기다린다. 넘으면 TimeoutError.

    요청은 별도 스레드에서 보내고, 시간이 넘으면 기다리지 않고 버린다 (뒤에서 끝나도 결과는 안 씀).
    """
    client = get_client()
    box = {}

    def work():
        try:
            box["response"] = client.models.generate_content(
                model=model, contents=contents, config=config
            )
        except Exception as error:  # 오류는 부른 쪽에서 다시 던진다
            box["error"] = error

    worker = threading.Thread(target=work, daemon=True)
    worker.start()
    worker.join(REQUEST_TIMEOUT)
    if worker.is_alive():
        raise TimeoutError(f"{REQUEST_TIMEOUT}초 안에 답이 없음")
    if "error" in box:
        raise box["error"]
    return box["response"]


def wait_for_slot():
    """최근 60초 동안 보낸 요청이 RPM_LIMIT개면 자리가 날 때까지 기다린다. 기다린 초를 돌려준다."""
    waited = 0.0
    while True:
        with _calls_lock:
            now = time.time()
            while _calls and now - _calls[0] > 60:
                _calls.popleft()
            if len(_calls) < RPM_LIMIT:
                _calls.append(now)
                return waited
            pause = 60 - (now - _calls[0]) + 0.1
        logger.info("분당 %d회 도달 → %.0f초 대기", RPM_LIMIT, pause)
        time.sleep(pause)
        waited += pause


def empty_reason(response):
    """빈 답이 온 이유를 짧게 (차단 이유나 생성이 끝난 이유)."""
    feedback = getattr(response, "prompt_feedback", None)
    if feedback and feedback.block_reason:
        return f"차단: {feedback.block_reason}"
    if response.candidates:
        return f"끝난 이유: {response.candidates[0].finish_reason}"
    return "답 후보 없음"


def ask_json(
    contents: list,
    schema: type[T],
    *,
    model: str,
    parse: Callable[[str], T] | None = None,
    temperature: float = 0.1,
) -> tuple[T, dict]:
    """Gemini에 묻고 schema 형식의 답을 받는다.

    parse가 없으면 schema.model_validate_json으로 답을 읽는다.
    돌려주는 값: (결과, 정보). 정보는 seconds(성공한 요청의 응답 시간),
    retries(다시 시도한 횟수), waited(한도·다시 시도로 기다린 초)
    다시 시도: 일시 오류(408·500·502·503·504), 연결 끊김, REQUEST_TIMEOUT초 넘게 답이 없음,
    답이 끊기거나 깨짐
    바로 멈춤: 사용 한도 초과(429), 빈 답(안전 차단 등),
    키·모델 이름 문제처럼 다시 해도 안 되는 오류
    끝내 실패하면 GeminiError를 던진다.
    """
    read = parse or schema.model_validate_json
    config = types.GenerateContentConfig(
        response_mime_type="application/json", response_schema=schema, temperature=temperature
    )
    waited = 0.0
    reason = ""
    for attempt in range(len(RETRY_WAITS) + 1):
        waited += wait_for_slot()
        start = time.time()
        try:
            response = generate(contents, config, model)
            if not response.text:  # 안전 차단 등으로 빈 답이면 다시 해도 같으므로 바로 멈춘다
                raise GeminiError(f"Gemini가 빈 답을 보냈어요({empty_reason(response)}).")
            result = read(response.text)
            info = {"seconds": time.time() - start, "retries": attempt, "waited": waited}
            return result, info
        except errors.APIError as error:
            if error.code == 429:
                message = "Gemini 사용 한도를 넘었어요(429). 잠시 뒤 다시 시도해 주세요."
                raise GeminiError(message) from error
            if error.code not in RETRY_CODES:
                raise GeminiError(f"Gemini 요청 실패({error.code}): {error.message}") from error
            reason = f"서버 오류 {error.code}"
        except httpx.TransportError:
            reason = "연결 끊김"
        except TimeoutError:  # OSError의 한 종류라 OSError보다 먼저 잡는다
            reason = f"{REQUEST_TIMEOUT}초 안에 답이 없음"
        except OSError:  # httpx 밖에서 나는 연결 오류 (연결 재설정, SSL 오류 등)
            reason = "연결 끊김"
        except ValueError:  # JSON 오류와 형식 검사(pydantic) 오류가 모두 ValueError
            reason = "답이 끊기거나 깨짐"
        if attempt == len(RETRY_WAITS):
            break
        pause = RETRY_WAITS[attempt]
        logger.warning(
            "Gemini 실패: %s → %d초 뒤 다시 시도 (%d/%d)",
            reason,
            pause,
            attempt + 1,
            len(RETRY_WAITS),
        )
        time.sleep(pause)
        waited += pause
    raise GeminiError(
        f"Gemini에 {len(RETRY_WAITS) + 1}번 요청했지만 실패했어요({reason}). "
        "잠시 뒤 다시 시도해 주세요."
    )
