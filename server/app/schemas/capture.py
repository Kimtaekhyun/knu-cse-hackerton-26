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


class CaptureRetry(BaseModel):
    """처리에 실패한 판서 다시 처리하기"""

    # 화면을 못 찾아도 사진 그대로 쓴다 (오류 화면 11의 "그대로 쓰기")
    skip_rectify: bool = False


class Destination(BaseModel):
    """지금 찍으면 어디에 저장되는지 (촬영 화면의 "○○ 폴더에 저장")

    과목이 없으면 미분류함이다. 학기가 아직 없으면 semester_id도 null이고,
    실제로 올릴 때 서버가 현재 학기를 만든다.
    """

    semester_id: uuid.UUID | None
    subject_id: uuid.UUID | None
    subject_name: str | None
