"""찾은 학사일정 저장 · 사용 (app/services/academic_calendar.py, #173)."""

from datetime import UTC, date, datetime, timedelta

import pytest

from app.models import CalendarSearch, SemesterTerm
from app.services import academic_calendar as service
from app.services.academic_calendar import FoundDates
from tests.db.factories import make_semester, make_user

SECOND = SemesterTerm.second


def dates(midterm=date(2026, 10, 19)):
    return FoundDates(
        starts_on=date(2026, 9, 1),
        midterm_start=midterm,
        final_start=date(2026, 12, 15),
        source_url="https://example.ac.kr",
    )


def test_saved_calendar_is_used(db, monkeypatch):
    monkeypatch.setattr(service, "request_lookup", lambda *key: None)
    service.save(db, "부산대학교", 2026, SECOND, dates())
    user = make_user(db, school="부산대학교")
    make_semester(db, user)
    calendar = service.calendar_for(db, user)
    assert (calendar.midterm_start, calendar.final_start) == (
        date(2026, 10, 19),
        date(2026, 12, 15),
    )


def test_second_save_fills_only_missing_dates(db):
    service.save(db, "부산대학교", 2026, SECOND, dates(midterm=None))
    service.save(db, "부산대학교", 2026, SECOND, dates(midterm=date(2026, 10, 26)))
    calendar = service.saved_calendar(db, "부산대학교", 2026, SECOND)
    assert (calendar.midterm_start, calendar.final_start) == (
        date(2026, 10, 26),
        date(2026, 12, 15),
    )


def test_incomplete_saved_calendar_is_used_and_searched_again(db, monkeypatch):
    requested: list = []
    monkeypatch.setattr(service, "request_lookup", lambda db, *key: requested.append(key))
    service.save(db, "부산대학교", 2026, SECOND, dates(midterm=None))
    user = make_user(db, school="부산대학교")
    make_semester(db, user)
    calendar = service.calendar_for(db, user)
    assert (calendar.starts_on, calendar.midterm_start) == (date(2026, 9, 1), None)
    assert requested == [("부산대학교", 2026, SECOND)]


def test_complete_saved_calendar_is_not_searched(db, monkeypatch):
    requested: list = []
    monkeypatch.setattr(service, "request_lookup", lambda db, *key: requested.append(key))
    service.save(db, "부산대학교", 2026, SECOND, dates())
    user = make_user(db, school="부산대학교")
    make_semester(db, user)
    service.calendar_for(db, user)
    assert requested == []


def test_second_save_keeps_existing_dates(db):
    service.save(db, "부산대학교", 2026, SECOND, dates())
    service.save(db, "부산대학교", 2026, SECOND, dates(midterm=date(2026, 10, 26)))
    calendar = service.saved_calendar(db, "부산대학교", 2026, SECOND)
    assert calendar.midterm_start == date(2026, 10, 19)


def test_missing_calendar_is_estimated_and_requested(db, monkeypatch):
    requested: list = []
    monkeypatch.setattr(service, "request_lookup", lambda db, *key: requested.append(key))
    user = make_user(db, school="부산대학교")
    make_semester(db, user)
    calendar = service.calendar_for(db, user)
    assert calendar.starts_on == date(2026, 9, 1)
    assert calendar.midterm_start is None  # 8 · 15주차 규칙으로 채워짐
    assert requested == [("부산대학교", 2026, SECOND)]
    assert service.saved_calendar(db, "부산대학교", 2026, SECOND) is None  # 추정은 저장 안 함


def test_no_semester_means_no_calendar(db, monkeypatch):
    monkeypatch.setattr(service, "request_lookup", lambda *key: None)
    assert service.calendar_for(db, make_user(db, school="부산대학교")) is None


# ---------- 다시 찾지 않기 · 하루 한도 (검색 기록 calendar_searches) ----------

KEY = ("부산대학교", 2026, SECOND)


@pytest.fixture
def submitted(monkeypatch):
    """뒤에서 도는 실제 검색 대신 기록만 남긴다"""
    monkeypatch.setattr(service, "_running", set())
    started: list = []

    class FakeExecutor:
        def submit(self, fn, key):
            started.append(key)

    monkeypatch.setattr(service, "_executor", FakeExecutor())
    return started


def searched(db, key=KEY, hours_ago=0):
    school, year, term = key
    when = datetime.now(UTC) - timedelta(hours=hours_ago)
    db.add(CalendarSearch(school=school, year=year, term=term, searched_at=when))
    db.flush()


def test_first_request_starts_and_is_recorded(db, submitted):
    assert service.request_lookup(db, *KEY)
    assert submitted == [KEY]
    assert db.query(CalendarSearch).count() == 1


def test_running_search_is_not_started_again(db, submitted):
    service.request_lookup(db, *KEY)
    assert not service.request_lookup(db, *KEY)
    assert submitted == [KEY]


def test_searched_within_a_day_is_not_searched_again(db, submitted):
    searched(db, hours_ago=23)
    assert not service.request_lookup(db, *KEY)
    assert submitted == []


def test_searched_over_a_day_ago_is_searched_again(db, submitted):
    searched(db, hours_ago=25)
    assert service.request_lookup(db, *KEY)
    assert submitted == [KEY]


def test_daily_limit_across_schools(db, submitted, monkeypatch):
    monkeypatch.setattr(service, "DAILY_LIMIT", 2)
    searched(db, ("가대학교", 2026, SECOND))
    searched(db, ("나대학교", 2026, SECOND))
    searched(db, ("다대학교", 2026, SECOND), hours_ago=30)  # 하루 넘은 기록은 세지 않음
    assert not service.request_lookup(db, *KEY)
    assert submitted == []


def test_seasonal_term_is_not_searched(db, submitted):
    assert not service.request_lookup(db, "부산대학교", 2026, SemesterTerm.summer)
    assert submitted == []
