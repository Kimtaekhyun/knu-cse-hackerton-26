"""학기 · 과목 API의 요청 · 응답 형식.

수업 시간 칸은 시간표 인식 응답(app/schemas/timetable.py)과 같은 모양({weekday, start, end})이라
인식 결과를 그대로 저장 요청에 넣을 수 있다.
"""

import uuid
from typing import Annotated

from pydantic import BaseModel, Field, StringConstraints, model_validator

from app.models import SemesterTerm

HHMM = r"^([01]\d|2[0-3]):[0-5]\d$"

SubjectName = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=100)]


class Slot(BaseModel):
    """수업 시간 한 칸"""

    weekday: int = Field(ge=0, le=6, description="0=월 … 6=일")
    start: str = Field(pattern=HHMM, description="시작 시각 HH:MM (24시간)")
    end: str = Field(pattern=HHMM, description="끝 시각 HH:MM (24시간)")

    @model_validator(mode="after")
    def start_before_end(self):
        # 두 자리로 맞춘 HH:MM이라 문자열 비교가 곧 시각 비교
        if self.start >= self.end:
            raise ValueError("시작 시각이 끝 시각보다 앞이어야 해요.")
        return self


class SubjectIn(BaseModel):
    name: SubjectName
    slots: list[Slot] = []


class SubjectUpdate(BaseModel):
    """보낸 것만 바꾼다. slots를 보내면 시간 칸 전체를 바꾼다"""

    name: SubjectName | None = None
    slots: list[Slot] | None = None


class SubjectOut(BaseModel):
    id: uuid.UUID
    semester_id: uuid.UUID
    name: str
    slots: list[Slot]
    # 과목 폴더의 "12장" (처리가 끝난 판서)
    capture_count: int


class SemesterCreate(BaseModel):
    year: int = Field(ge=2000, le=2100)
    term: SemesterTerm
    # 만들면서 현재 학기로 지정할지. 기존 현재 학기는 지난 학기가 된다
    make_current: bool = True


class SemesterOut(BaseModel):
    id: uuid.UUID
    year: int
    term: SemesterTerm
    # "2026년 2학기"
    label: str
    is_current: bool
    subject_count: int
    # 처리가 끝난 판서 수
    capture_count: int


class SemesterDetail(SemesterOut):
    subjects: list[SubjectOut]


class TimetableSave(BaseModel):
    """시간표 확인 화면의 "이대로 저장". 이 목록이 그 학기 과목 전체가 된다"""

    subjects: list[SubjectIn]
