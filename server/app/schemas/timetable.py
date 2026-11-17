"""시간표 인식 API의 응답 형식. DB 스키마 초안(#21)의 subjects · subject_slots 구조를 따른다."""

from pydantic import BaseModel, Field


class Slot(BaseModel):
    """수업 시간 한 칸"""

    weekday: int = Field(ge=0, le=6, description="0=월 … 6=일")
    start: str = Field(description="시작 시각 HH:MM (24시간)")
    end: str = Field(description="끝 시각 HH:MM (24시간)")


class Subject(BaseModel):
    """과목 하나. 시간이 없는 과목(사이버강의 등)은 slots가 비어 있다"""

    name: str
    slots: list[Slot]


class TimetableParseResult(BaseModel):
    subjects: list[Subject]
