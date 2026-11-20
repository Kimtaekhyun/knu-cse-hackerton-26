"""AI 모델 호출 창구.

기능 코드(시간표 인식 등)는 이 모듈만 부르고, 실제로 어느 AI에 보낼지는
LLM_PROVIDER 설정(gemini · claude)이 정한다. 그래서 두 모델을 같은 사진으로 비교하거나
기본 모델을 바꿀 때 기능 코드는 고치지 않아도 된다.
"""

from typing import Literal, TypeVar

from pydantic import BaseModel

from app.core.config import get_settings

T = TypeVar("T", bound=BaseModel)
Task = Literal["timetable"]


class LLMError(RuntimeError):
    """AI에 요청했지만 끝내 답을 받지 못함. 메시지는 사용자에게 그대로 보여 준다."""


def model_for(task: Task) -> str:
    """지금 고른 AI에서 task에 쓸 모델 이름"""
    settings = get_settings()
    if settings.llm_provider == "claude":
        return {"timetable": settings.claude_timetable_model}[task]
    return {"timetable": settings.timetable_model}[task]


def ask_image_json(
    image: bytes, mime_type: str, prompt: str, schema: type[T], *, task: Task
) -> tuple[T, dict]:
    """이미지 한 장과 프롬프트를 보내 schema 형식의 답을 받는다. 끝내 실패하면 LLMError.

    돌려주는 값: (결과, 정보). 정보의 내용은 AI마다 다르다 (로그 · 비교용).
    각 모듈은 쓸 때만 불러온다 (gemini.py가 LLMError를 가져가므로 위에서 부르면 순환 참조가 된다).
    """
    model = model_for(task)
    if get_settings().llm_provider == "claude":
        from app.services import claude

        return claude.ask_image_json(image, mime_type, prompt, schema, model=model)

    from google.genai import types

    from app.services import gemini

    contents = [types.Part.from_bytes(data=image, mime_type=mime_type), prompt]
    return gemini.ask_json(contents, schema, model=model)
