"""학사일정 찾기(app/services/academic_calendar.py). 웹 검색 · DB 없이 확인한다 (#173).

실제 Claude 웹 검색은 부르지 않는다 (search를 가짜로 바꿈).
저장은 tests/db/test_academic_calendar_db.py에서 확인한다.
"""

from datetime import date

import pytest

from app.models import SemesterTerm
from app.services import academic_calendar as service
from app.services.academic_calendar import FoundDates, check

SECOND = SemesterTerm.second
KEY = ("부산대학교", 2026, SECOND)


def found(start=date(2026, 9, 1), midterm=date(2026, 10, 19), final=date(2026, 12, 15)):
    return FoundDates(starts_on=start, midterm_start=midterm, final_start=final, source_url=None)


# ---------- 날짜 확인 ----------


def test_real_calendar_passes():
    # 부산대 2026년 2학기 (검색 결과 그대로): 중간 8주차 · 기말 16주차
    assert check(found(), 2026, SECOND)


@pytest.mark.parametrize("dates", [found(midterm=None), found(final=None)])
def test_missing_exam_date_fails(dates):
    # 비어 있는 채로 저장하면 다시 찾지 않으므로 저장하지 않는다 (하루 뒤 다시 찾음)
    assert not check(dates, 2026, SECOND)


@pytest.mark.parametrize(
    "dates",
    [
        found(start=None),  # 개강일은 꼭 있어야 함
        found(start=date(2025, 9, 1)),  # 다른 해
        found(start=date(2026, 3, 2)),  # 2학기인데 3월 개강
        found(midterm=date(2026, 9, 22)),  # 4주차 중간고사
        found(midterm=date(2026, 11, 10)),  # 11주차 중간고사
        found(final=date(2026, 11, 10)),  # 11주차 기말 (12주차보다 이름)
        found(final=date(2027, 1, 12)),  # 19주차 기말
    ],
)
def test_wrong_dates_fail(dates):
    assert not check(dates, 2026, SECOND)


def test_first_term_starts_in_spring():
    spring = found(start=date(2027, 3, 2), midterm=date(2027, 4, 20), final=date(2027, 6, 8))
    assert check(spring, 2027, SemesterTerm.first)
    assert not check(spring, 2027, SECOND)


# ---------- 찾기 · 다시 찾지 않기 ----------


@pytest.fixture(autouse=True)
def fresh_state(monkeypatch):
    """테스트마다 찾는 중 · 못 찾은 기록을 비우고, 뒤에서 도는 작업 대신 기록만 남긴다"""
    monkeypatch.setattr(service, "_running", set())
    monkeypatch.setattr(service, "_failed", {})
    submitted: list = []

    class FakeExecutor:
        def submit(self, fn, key):
            submitted.append(key)

    monkeypatch.setattr(service, "_executor", FakeExecutor())
    return submitted


@pytest.fixture
def saved(monkeypatch):
    rows: list = []
    monkeypatch.setattr(service, "save", lambda db, *args: rows.append(args))
    return rows


class FakeSession:
    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


def test_lookup_saves_checked_dates(monkeypatch, saved):
    monkeypatch.setattr(service, "search", lambda *key: found())
    assert service.lookup(KEY, session_factory=FakeSession)
    assert saved == [(*KEY, found())]
    assert KEY not in service._failed


@pytest.mark.parametrize("result", [None, found(start=None), found(final=date(2027, 1, 12))])
def test_lookup_without_good_dates_remembers_failure(monkeypatch, saved, result):
    monkeypatch.setattr(service, "search", lambda *key: result)
    assert not service.lookup(KEY, session_factory=FakeSession)
    assert saved == []
    assert KEY in service._failed


def test_lookup_error_remembers_failure(monkeypatch, saved):
    def broken(*key):
        raise service.claude.ClaudeError("ANTHROPIC_API_KEY가 설정되지 않았어요.")

    monkeypatch.setattr(service, "search", broken)
    assert not service.lookup(KEY, session_factory=FakeSession)
    assert KEY in service._failed


def test_request_lookup_runs_once_while_running(fresh_state):
    service.request_lookup(*KEY)
    service.request_lookup(*KEY)
    assert fresh_state == [KEY]


def test_recent_failure_is_not_searched_again(fresh_state, monkeypatch):
    service._failed[KEY] = service.time.time()
    service.request_lookup(*KEY)
    assert fresh_state == []
    # RETRY_AFTER가 지나면 다시 찾는다
    service._failed[KEY] = service.time.time() - service.RETRY_AFTER - 1
    service.request_lookup(*KEY)
    assert fresh_state == [KEY]


def test_seasonal_term_is_not_searched(fresh_state):
    service.request_lookup("부산대학교", 2026, SemesterTerm.summer)
    assert fresh_state == []
