"""찾은 학사일정 저장 · 사용 (app/services/academic_calendar.py, #173)."""

from datetime import date

from app.models import SemesterTerm
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
    monkeypatch.setattr(service, "request_lookup", lambda *key: requested.append(key))
    service.save(db, "부산대학교", 2026, SECOND, dates(midterm=None))
    user = make_user(db, school="부산대학교")
    make_semester(db, user)
    calendar = service.calendar_for(db, user)
    assert (calendar.starts_on, calendar.midterm_start) == (date(2026, 9, 1), None)
    assert requested == [("부산대학교", 2026, SECOND)]


def test_complete_saved_calendar_is_not_searched(db, monkeypatch):
    requested: list = []
    monkeypatch.setattr(service, "request_lookup", lambda *key: requested.append(key))
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
    monkeypatch.setattr(service, "request_lookup", lambda *key: requested.append(key))
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
