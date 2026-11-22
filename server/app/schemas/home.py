"""메인 화면 API(GET /home)의 응답 형식 (메인 07 · 08)."""

import uuid
from datetime import date

from pydantic import BaseModel, Field

from app.services.exam_schedule import ExamKind


class HomeClass(BaseModel):
    """수업 칸 하나 ("수업 중" 카드 · "오늘 수업" 한 줄)

    "지금" · "2시간 뒤" · "42분 남음" 같은 문구는 앱이 시각으로 계산한다.
    """

    subject_id: uuid.UUID
    name: str
    start: str = Field(examples=["10:30"])
    end: str = Field(examples=["12:00"])


class HomeWeek(BaseModel):
    """이번 주 막대 그래프. 정리가 끝난 판서만 센다"""

    # 이번 주 월요일
    start: date
    # 월 … 일 7칸
    days: list[int]
    total: int
    # "지난주보다 N장 더"
    last_week_total: int


class HomeExam(BaseModel):
    """진행 중이거나 다가오는 시험 (학사일정 기준, app/services/exam_schedule.py)"""

    kind: ExamKind
    starts_on: date
    ends_on: date
    # 시작까지 남은 날. 시험 중이면 0
    days_left: int
    in_progress: bool


class HomeOut(BaseModel):
    # 지금 수업 중인 칸. 없으면 null
    now_class: HomeClass | None
    # 오늘 요일의 수업 전부 (끝난 수업 포함), 시작 시각 순
    today: list[HomeClass]
    week: HomeWeek
    # 정리가 끝난 판서 전체 수. 0이면 07(처음) 화면
    total_captures: int
    # 학교가 없거나 학사일정에 없는 학교 · 학기, 기말까지 끝났으면 null
    exam: HomeExam | None
