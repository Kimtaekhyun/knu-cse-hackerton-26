"""학기 · 학교별 학사일정."""

import uuid
from datetime import date, datetime

from sqlalchemy import Enum, ForeignKey, Index, UniqueConstraint, false, text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.models._common import created_at, uuid_pk
from app.models.enums import SemesterTerm

semester_term = Enum(SemesterTerm, name="semester_term")


class Semester(Base):
    """ "2026년 2학기" 같은 표시용 이름은 응답에서 조합한다"""

    __tablename__ = "semesters"
    __table_args__ = (
        UniqueConstraint("user_id", "year", "term"),
        # 사용자당 현재 학기는 하나만
        Index(
            "uq_semesters_current_per_user",
            "user_id",
            unique=True,
            postgresql_where=text("is_current"),
        ),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    year: Mapped[int]
    term: Mapped[SemesterTerm] = mapped_column(semester_term)
    is_current: Mapped[bool] = mapped_column(server_default=false())
    # 업로드한 에타 캡처
    timetable_image_key: Mapped[str | None]
    created_at: Mapped[datetime] = created_at()

    subjects: Mapped[list["Subject"]] = relationship(  # noqa: F821
        back_populates="semester", cascade="all, delete-orphan", passive_deletes=True
    )


class AcademicCalendar(Base):
    """학교 단위 학사일정. users.school과 (school, year, term)으로 조인한다 (FK 없음)

    시험 기간은 시작일부터 1주일. 시작일이 비어 있으면 개강일 기준 중간 8주차 · 기말 15주차.
    """

    __tablename__ = "academic_calendars"
    __table_args__ = (UniqueConstraint("school", "year", "term"),)

    id: Mapped[uuid.UUID] = uuid_pk()
    school: Mapped[str]
    year: Mapped[int]
    term: Mapped[SemesterTerm] = mapped_column(semester_term)
    # 개강일
    starts_on: Mapped[date]
    midterm_start: Mapped[date | None]
    final_start: Mapped[date | None]
