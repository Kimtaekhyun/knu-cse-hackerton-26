"""학사일정 찾기(app/services/academic_calendar.py). 웹 검색 · DB 없이 확인한다 (#173).

실제 Claude 웹 검색은 부르지 않는다 (search를 가짜로 바꿈).
저장은 tests/db/test_academic_calendar_db.py에서 확인한다.
"""

from datetime import date

import pytest

from app.models import SemesterTerm
from app.services import academic_calendar as service
from app.services.academic_calendar import FoundDates, complete, usable

SECOND = SemesterTerm.second
KEY = ("부산대학교", 2026, SECOND)


def found(start=date(2026, 9, 1), midterm=date(2026, 10, 19), final=date(2026, 12, 15)):
    return FoundDates(starts_on=start, midterm_start=midterm, final_start=final, source_url=None)


# ---------- 날짜 확인 ----------


def test_real_calendar_is_used_as_is():
    # 부산대 2026년 2학기 (검색 결과 그대로): 중간 8주차 · 기말 16주차
    assert usable(found(), 2026, SECOND) == found()
    assert complete(found())


@pytest.mark.parametrize(
    "dates",
    [
        found(start=None),  # 개강일은 꼭 있어야 함
        found(start=date(2025, 9, 1)),  # 다른 해
        found(start=date(2026, 3, 2)),  # 2학기인데 3월 개강
    ],
)
def test_wrong_start_is_not_used(dates):
    assert usable(dates, 2026, SECOND) is None


def test_start_only_is_used_and_incomplete():
    # 시험 시작일이 없어도 실제 개강일로 8 · 15주차를 계산하도록 저장한다
    dates = usable(found(midterm=None, final=None), 2026, SECOND)
    assert dates == found(midterm=None, final=None)
    assert not complete(dates)


@pytest.mark.parametrize(
    ("dates", "expected"),
    [
        (found(midterm=date(2026, 9, 22)), found(midterm=None)),  # 4주차 중간고사
        (found(midterm=date(2026, 11, 10)), found(midterm=None)),  # 11주차 중간고사
        (found(final=date(2026, 11, 10)), found(final=None)),  # 11주차 기말
        (found(final=date(2027, 1, 12)), found(final=None)),  # 19주차 기말
    ],
)
def test_exam_date_out_of_range_is_cleared(dates, expected):
    assert usable(dates, 2026, SECOND) == expected


def test_first_term_starts_in_spring():
    spring = found(start=date(2027, 3, 2), midterm=date(2027, 4, 20), final=date(2027, 6, 8))
    assert usable(spring, 2027, SemesterTerm.first) == spring
    assert usable(spring, 2027, SECOND) is None


# ---------- 찾아서 저장하기 ----------
# 다시 찾지 않기 · 하루 한도는 검색 기록(DB)을 써서
# tests/db/test_academic_calendar_db.py에서 확인한다


@pytest.fixture(autouse=True)
def fresh_state(monkeypatch):
    """테스트마다 찾는 중 기록을 비운다"""
    monkeypatch.setattr(service, "_running", {KEY})


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
    assert KEY not in service._running


@pytest.mark.parametrize(
    ("result", "stored"),
    [
        (found(final=None), found(final=None)),
        (found(final=date(2027, 1, 12)), found(final=None)),  # 범위 밖 기말은 비움
    ],
)
def test_lookup_saves_start_only(monkeypatch, saved, result, stored):
    monkeypatch.setattr(service, "search", lambda *key: result)
    assert not service.lookup(KEY, session_factory=FakeSession)  # 아직 다 못 찾음
    assert saved == [(*KEY, stored)]


@pytest.mark.parametrize("result", [None, found(start=None), found(start=date(2026, 3, 2))])
def test_lookup_without_good_start_saves_nothing(monkeypatch, saved, result):
    monkeypatch.setattr(service, "search", lambda *key: result)
    assert not service.lookup(KEY, session_factory=FakeSession)
    assert saved == []
    assert KEY not in service._running


def test_lookup_error_is_not_raised(monkeypatch, saved):
    def broken(*key):
        raise service.claude.ClaudeError("ANTHROPIC_API_KEY가 설정되지 않았어요.")

    monkeypatch.setattr(service, "search", broken)
    assert not service.lookup(KEY, session_factory=FakeSession)
    assert KEY not in service._running
