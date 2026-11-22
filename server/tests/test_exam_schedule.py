"""시험 기간 규칙(app/services/exam_schedule.py). DB 없이 학사일정 객체만으로 확인한다."""

from datetime import date

import pytest

from app.models import AcademicCalendar, SemesterTerm
from app.services.exam_schedule import Exam, exam_periods, next_exam


def calendar(midterm=None, final=None) -> AcademicCalendar:
    # 2026-09-01(화) 개강
    return AcademicCalendar(
        school="경북대학교",
        year=2026,
        term=SemesterTerm.second,
        starts_on=date(2026, 9, 1),
        midterm_start=midterm,
        final_start=final,
    )


def test_given_start_dates_are_used_with_seven_days():
    periods = exam_periods(calendar(date(2026, 10, 21), date(2026, 12, 14)))
    assert periods == [
        ("midterm", date(2026, 10, 21), date(2026, 10, 27)),
        ("final", date(2026, 12, 14), date(2026, 12, 20)),
    ]


def test_missing_start_dates_use_week_8_and_15():
    # 1주차 첫날 9/1 → 8주차 첫날 10/20, 15주차 첫날 12/8
    periods = exam_periods(calendar())
    assert periods == [
        ("midterm", date(2026, 10, 20), date(2026, 10, 26)),
        ("final", date(2026, 12, 8), date(2026, 12, 14)),
    ]


@pytest.mark.parametrize(
    ("today", "expected"),
    [
        # 개강 전 · 중간 전: 중간고사
        (date(2026, 8, 20), Exam("midterm", date(2026, 10, 21), date(2026, 10, 27), 62, False)),
        (date(2026, 10, 20), Exam("midterm", date(2026, 10, 21), date(2026, 10, 27), 1, False)),
        # 시험 첫날 · 마지막 날은 진행 중
        (date(2026, 10, 21), Exam("midterm", date(2026, 10, 21), date(2026, 10, 27), 0, True)),
        (date(2026, 10, 27), Exam("midterm", date(2026, 10, 21), date(2026, 10, 27), 0, True)),
        # 중간이 끝난 다음 날부터 기말
        (date(2026, 10, 28), Exam("final", date(2026, 12, 14), date(2026, 12, 20), 47, False)),
        (date(2026, 11, 22), Exam("final", date(2026, 12, 14), date(2026, 12, 20), 22, False)),
        (date(2026, 12, 20), Exam("final", date(2026, 12, 14), date(2026, 12, 20), 0, True)),
        # 기말까지 끝나면 없음
        (date(2026, 12, 21), None),
    ],
)
def test_next_exam(today, expected):
    assert next_exam(calendar(date(2026, 10, 21), date(2026, 12, 14)), today) == expected


def test_no_calendar_means_no_exam():
    assert next_exam(None, date(2026, 11, 22)) is None
