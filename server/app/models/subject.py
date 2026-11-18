"""과목 · 수업 시간."""

import uuid
from datetime import datetime, time

from sqlalchemy import CheckConstraint, ForeignKey, SmallInteger
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.models._common import created_at, uuid_pk
from app.models.semester import Semester


class Subject(Base):
    """강의실은 저장하지 않는다. 슬롯이 0개인 과목 = 사이버강의 등 (자동 분류 대상 아님)"""

    __tablename__ = "subjects"

    id: Mapped[uuid.UUID] = uuid_pk()
    semester_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("semesters.id", ondelete="CASCADE"))
    name: Mapped[str]
    created_at: Mapped[datetime] = created_at()

    semester: Mapped[Semester] = relationship(back_populates="subjects")
    slots: Mapped[list["SubjectSlot"]] = relationship(
        back_populates="subject", cascade="all, delete-orphan", passive_deletes=True
    )


class SubjectSlot(Base):
    """과목 하나에 여러 개 가능 (예: 데이터과학기초 화 · 목)"""

    __tablename__ = "subject_slots"
    __table_args__ = (
        CheckConstraint("weekday BETWEEN 0 AND 6", name="weekday_range"),
        CheckConstraint("start_time < end_time", name="time_order"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    subject_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("subjects.id", ondelete="CASCADE"))
    # 0=월 … 6=일 (토요일 수업 있음)
    weekday: Mapped[int] = mapped_column(SmallInteger)
    start_time: Mapped[time]
    end_time: Mapped[time]

    subject: Mapped[Subject] = relationship(back_populates="slots")
