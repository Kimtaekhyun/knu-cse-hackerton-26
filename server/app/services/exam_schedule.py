"""학사일정 → 시험 기간 · 남은 날 계산 (#21). 시험 기간 규칙은 여기 한 곳에만 둔다.

- 시험 기간은 시작일부터 7일 (종료일 = 시작일 + 6일)
- 시작일이 비어 있으면 개강일 기준 중간 8주차 · 기말 15주차 시작일
- 학사일정이 아예 없으면 개강일을 추정한다 (1학기 3월 2일 · 2학기 9월 1일, 주말이면 다음 월요일).
  계절학기(여름 · 겨울)는 시험 기간을 잡지 않는다 (#173)
"""

from datetime import date, timedelta
from typing import Literal, NamedTuple

from app.models import AcademicCalendar, SemesterTerm

ExamKind = Literal["midterm", "final"]

EXAM_DAYS = 7
MIDTERM_WEEK = 8
FINAL_WEEK = 15
# 학사일정이 없을 때 추정하는 개강일 (월, 일)
ESTIMATED_START = {SemesterTerm.first: (3, 2), SemesterTerm.second: (9, 1)}


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


def estimated_start(year: int, term: SemesterTerm) -> date | None:
    """학사일정이 없을 때 쓰는 개강일. 주말이면 다음 월요일. 계절학기는 None"""
    if term not in ESTIMATED_START:
        return None
    month, day = ESTIMATED_START[term]
    start = date(year, month, day)
    return start + timedelta(days=(7 - start.weekday()) % 7 if start.weekday() >= 5 else 0)


def estimated_calendar(school: str, year: int, term: SemesterTerm) -> AcademicCalendar | None:
    """추정 개강일로 만든 학사일정 (DB에 저장하지 않음).

    시험 시작일은 비워 두어 8 · 15주차 규칙으로 채워진다.
    """
    start = estimated_start(year, term)
    if start is None:
        return None
    return AcademicCalendar(school=school, year=year, term=term, starts_on=start)


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
