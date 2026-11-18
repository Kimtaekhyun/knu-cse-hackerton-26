"""판서(촬영 한 장) · 카드(판서에서 찾아낸 덩어리)."""

import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import (
    DateTime,
    Enum,
    ForeignKey,
    Index,
    SmallInteger,
    UniqueConstraint,
    false,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.models._common import created_at, uuid_pk
from app.models.enums import CaptureStatus, CardType


class Capture(Base):
    """ "수업(날짜별 묶음)"은 테이블 없이 taken_at의 서울 날짜로 묶는다"""

    __tablename__ = "captures"

    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    # 촬영 시점의 현재 학기
    semester_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("semesters.id", ondelete="CASCADE"))
    # null = 미분류함. 과목을 지우면 미분류로 돌아간다
    subject_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("subjects.id", ondelete="SET NULL")
    )
    # 과목 분류 기준 (셔터를 누른 시각)
    taken_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    status: Mapped[CaptureStatus] = mapped_column(
        Enum(CaptureStatus, name="capture_status"), server_default=CaptureStatus.uploaded.value
    )
    # rectify / segment / interpret / unknown
    fail_reason: Mapped[str | None]
    original_key: Mapped[str]
    rectified_key: Mapped[str | None]
    created_at: Mapped[datetime] = created_at()

    cards: Mapped[list["Card"]] = relationship(
        back_populates="capture", cascade="all, delete-orphan", passive_deletes=True
    )


# 최신 판서부터 보여 주는 목록용 (사용자별 · 과목별)
Index("ix_captures_user_id_taken_at", Capture.user_id, Capture.taken_at.desc())
Index("ix_captures_subject_id_taken_at", Capture.subject_id, Capture.taken_at.desc())


class Card(Base):
    __tablename__ = "cards"
    __table_args__ = (UniqueConstraint("capture_id", "order_no"),)

    id: Mapped[uuid.UUID] = uuid_pk()
    capture_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("captures.id", ondelete="CASCADE"))
    # 결과 화면의 번호
    order_no: Mapped[int] = mapped_column(SmallInteger)
    title: Mapped[str]
    card_type: Mapped[CardType] = mapped_column(Enum(CardType, name="card_type"))
    # 평문 / LaTeX / 코드
    content: Mapped[str]
    # "원래대로 되돌리기"용
    original_content: Mapped[str]
    # 보정본 기준 0~1로 정규화한 {x, y, w, h}
    bbox: Mapped[dict[str, Any]] = mapped_column(JSONB)
    # 투명 PNG (손글씨 보기 · 드래그용). 복사 색은 앱이 입힌다
    crop_image_key: Mapped[str]
    # 드래그 드롭 성공 또는 복사 시 true, 수동으로 되돌릴 수 있음
    is_moved: Mapped[bool] = mapped_column(server_default=false())
    moved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    edited_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = created_at()

    capture: Mapped[Capture] = relationship(back_populates="cards")
