"""마이그레이션으로 들어가는 기본 데이터."""

from datetime import date

from sqlalchemy import select

from app.models import AcademicCalendar, SemesterTerm


def test_knu_2026_second_seeded(db):
    rows = db.scalars(
        select(AcademicCalendar).where(
            AcademicCalendar.school == "경북대학교",
            AcademicCalendar.year == 2026,
            AcademicCalendar.term == SemesterTerm.second,
        )
    ).all()
    assert len(rows) == 1
    assert rows[0].starts_on == date(2026, 9, 1)
    assert rows[0].midterm_start == date(2026, 10, 21)
    assert rows[0].final_start == date(2026, 12, 14)
