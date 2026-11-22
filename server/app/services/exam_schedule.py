"""학사일정 → 시험 기간 · 남은 날 계산 (#21). 시험 기간 규칙은 여기 한 곳에만 둔다.

- 시험 기간은 시작일부터 7일 (종료일 = 시작일 + 6일)
- 시작일이 비어 있으면 개강일 기준 중간 8주차 · 기말 15주차 시작일
"""

from datetime import date, timedelta
from typing import Literal, NamedTuple

from app.models import AcademicCalendar

ExamKind = Literal["midterm", "final"]

EXAM_DAYS = 7
MIDTERM_WEEK = 8
FINAL_WEEK = 15


class Exam(NamedTuple):
    kind: ExamKind
    starts_on: date
    ends_on: date
    # 시작까지 남은 날. 시험 중이면 0
    days_left: int
    in_progress: bool


def week_start(calendar: AcademicCalendar, week: int) -> date:
    """개강일이 1주차 첫날일 때 week주차 첫날"""
    return calendar.starts_on + timedelta(weeks=week - 1)


def exam_periods(calendar: AcademicCalendar) -> list[tuple[ExamKind, date, date]]:
    """(종류, 시작일, 종료일) 중간 · 기말 순"""
    midterm = calendar.midterm_start or week_start(calendar, MIDTERM_WEEK)
    final = calendar.final_start or week_start(calendar, FINAL_WEEK)
    last_day = timedelta(days=EXAM_DAYS - 1)
    return [("midterm", midterm, midterm + last_day), ("final", final, final + last_day)]


def next_exam(calendar: AcademicCalendar | None, today: date) -> Exam | None:
    """진행 중인 시험, 없으면 다가오는 시험. 기말까지 끝났거나 학사일정이 없으면 None"""
    if calendar is None:
        return None
    for kind, starts_on, ends_on in exam_periods(calendar):
        if today <= ends_on:
            in_progress = starts_on <= today
            days_left = 0 if in_progress else (starts_on - today).days
            return Exam(kind, starts_on, ends_on, days_left, in_progress)
    return None
