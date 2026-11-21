"""판서(캡처) API의 요청 · 응답 형식."""

import uuid
from datetime import date, datetime
from typing import Any

from pydantic import BaseModel

from app.models import CaptureStatus, CardType


class CardOut(BaseModel):
    id: uuid.UUID
    # 결과 화면의 번호
    order_no: int
    title: str
    card_type: CardType
    content: str
    # 사용자가 내용을 고쳤는지 (원래대로 되돌리기 버튼을 보여 줄지)
    is_edited: bool
    # 보정본 기준 0~1로 정규화한 {x, y, w, h}
    bbox: dict[str, Any]
    is_moved: bool


class CaptureOut(BaseModel):
    """목록 · 상세 공통"""

    id: uuid.UUID
    semester_id: uuid.UUID
    # null = 미분류함
    subject_id: uuid.UUID | None
    taken_at: datetime
    # 서울 날짜. "수업(날짜별 묶음)"은 앱이 이 값으로 묶는다
    class_date: date
    status: CaptureStatus
    # rectify / segment / interpret / unknown
    fail_reason: str | None
    card_count: int
    # 아직 옮기지 않은 카드 수
    unmoved_count: int


class CaptureDetail(CaptureOut):
    # 처리가 끝난(done) 판서만 채워진다. order_no 순
    cards: list[CardOut]


class CaptureMove(BaseModel):
    """과목으로 옮기기. null을 보내면 미분류함으로 보낸다 (필드는 꼭 보내야 한다)"""

    subject_id: uuid.UUID | None
