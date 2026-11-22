"""카드 API의 요청 · 응답 형식."""

import unicodedata
import uuid
from typing import Annotated

from pydantic import AfterValidator, BaseModel, Field, StringConstraints

from app.models import CardType
from app.schemas.capture import CardOut

# 한 번에 옮김 표시할 수 있는 카드 수 ("N개 복사"). 판서 몇 장 분량이면 충분하다
MAX_MOVED_CARDS = 100

# 내용에 써도 되는 제어 문자 (줄바꿈 · 탭). 나머지(NUL 등)는 Postgres에 넣을 수 없거나 보이지 않는다
ALLOWED_CONTROLS = {"\n", "\r", "\t"}


def _clean_text(text: str) -> str:
    """한글을 NFC로 맞추고, 줄바꿈 · 탭 말고 제어 문자는 거절한다"""
    if any(unicodedata.category(ch) == "Cc" and ch not in ALLOWED_CONTROLS for ch in text):
        raise ValueError("쓸 수 없는 문자가 있어요.")
    return unicodedata.normalize("NFC", text)


def _single_line(text: str) -> str:
    if any(ch in ALLOWED_CONTROLS for ch in text):
        raise ValueError("제목은 한 줄로 써 주세요.")
    return text


CardTitle = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, max_length=100),
    AfterValidator(_clean_text),
    AfterValidator(_single_line),
]
CardContent = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, max_length=10000),
    AfterValidator(_clean_text),
]


class CardUpdate(BaseModel):
    """보낸 것만 바꾼다"""

    title: CardTitle | None = None
    content: CardContent | None = None
    card_type: CardType | None = None


class CardsMovedIn(BaseModel):
    """옮김 표시 · 취소. 굿노트로 끌어다 놓거나 복사한 카드, "N개 복사"한 카드들"""

    card_ids: list[uuid.UUID] = Field(min_length=1, max_length=MAX_MOVED_CARDS)
    moved: bool


class CardDetail(CardOut):
    """카드 하나. 어느 판서의 카드인지도 알려 준다 (결과 화면으로 돌아갈 때)"""

    capture_id: uuid.UUID
