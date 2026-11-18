"""#21 "화면별 집계" 질의가 모델로 동작하는지."""

from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

from app.models import CaptureStatus
from app.services import queries
from tests.db.factories import (
    make_capture,
    make_card,
    make_semester,
    make_slot,
    make_subject,
    make_user,
)

SEOUL = ZoneInfo("Asia/Seoul")


def kst(text: str) -> datetime:
    return datetime.fromisoformat(text).replace(tzinfo=SEOUL)


def test_subject_count_only_done(db):
    user = make_user(db)
    semester = make_semester(db, user)
    subject = make_subject(db, semester)
    for status in [CaptureStatus.done, CaptureStatus.done, CaptureStatus.failed]:
        make_capture(db, user, semester, subject, status=status)
    make_capture(db, user, semester, subject, status=CaptureStatus.segmenting)
    assert queries.subject_capture_count(db, subject.id) == 2


def test_unsorted_counts_all_statuses(db):
    user = make_user(db)
    semester = make_semester(db, user)
    make_capture(db, user, semester, status=CaptureStatus.done)
    make_capture(db, user, semester, status=CaptureStatus.uploaded)
    make_capture(db, user, semester, make_subject(db, semester))
    assert queries.unsorted_capture_count(db, user.id) == 2


def test_unmoved_captures(db):
    user = make_user(db)
    semester = make_semester(db, user)
    all_moved = make_capture(db, user, semester)
    make_card(db, all_moved, 1, is_moved=True)
    make_card(db, all_moved, 2, is_moved=True)
    one_left = make_capture(db, user, semester)
    make_card(db, one_left, 1, is_moved=True)
    make_card(db, one_left, 2, is_moved=False)
    make_capture(db, user, semester)  # 카드 없음
    assert [c.id for c in queries.unmoved_captures(db, user.id)] == [one_left.id]


def test_unmoved_captures_newest_first(db):
    user = make_user(db)
    semester = make_semester(db, user)
    older = make_capture(db, user, semester, taken_at=kst("2026-11-16T10:00"))
    newer = make_capture(db, user, semester, taken_at=kst("2026-11-17T10:00"))
    make_card(db, older, 1)
    make_card(db, newer, 1)
    assert [c.id for c in queries.unmoved_captures(db, user.id)] == [newer.id, older.id]


def test_account_stats(db):
    user = make_user(db)
    semester = make_semester(db, user)
    first = make_capture(db, user, semester)
    second = make_capture(db, user, semester)
    make_card(db, first, 1, is_moved=True)
    make_card(db, first, 2)
    make_card(db, second, 1)
    assert queries.account_stats(db, user.id) == (2, 3, 1)


def test_current_slot_boundaries(db):
    user = make_user(db)
    subject = make_subject(db, make_semester(db, user))
    tuesday = make_slot(db, subject, 1, "13:30", "15:00")
    saturday = make_slot(db, subject, 5, "09:00", "12:00")
    # 2026-11-17은 화요일, 2026-11-21은 토요일
    assert queries.current_slot(db, user.id, kst("2026-11-17T13:30")).id == tuesday.id
    assert queries.current_slot(db, user.id, kst("2026-11-17T15:00")) is None
    assert queries.current_slot(db, user.id, kst("2026-11-21T10:00")).id == saturday.id


def test_current_slot_accepts_utc_time(db):
    user = make_user(db)
    subject = make_subject(db, make_semester(db, user))
    slot = make_slot(db, subject, 1, "13:30", "15:00")
    # 화 13:30 KST = 화 04:30 UTC
    utc = kst("2026-11-17T13:30").astimezone(ZoneInfo("UTC"))
    assert queries.current_slot(db, user.id, utc).id == slot.id


def test_current_slot_ignores_past_semester(db):
    user = make_user(db)
    past = make_semester(db, user, year=2025, is_current=False)
    make_slot(db, make_subject(db, past), 1, "13:30", "15:00")
    assert queries.current_slot(db, user.id, kst("2026-11-17T14:00")) is None


def test_weekly_counts_use_seoul_date(db):
    user = make_user(db)
    semester = make_semester(db, user)
    # 한국 시각 11/18 00:30 (UTC로는 11/17 15:30)
    make_capture(db, user, semester, taken_at=datetime.fromisoformat("2026-11-17T15:30+00:00"))
    counts = queries.weekly_capture_counts(db, user.id, date(2026, 11, 16))
    expected = {date(2026, 11, 16) + timedelta(days=i): 0 for i in range(7)}
    expected[date(2026, 11, 18)] = 1
    assert counts == expected


def test_current_calendar_joins_school(db):
    user = make_user(db, school="경북대학교")
    make_semester(db, user)  # 2026 2학기, 현재 학기
    calendar = queries.current_calendar(db, user.id)
    assert calendar is not None
    assert calendar.starts_on == date(2026, 9, 1)


def test_current_calendar_none_without_school(db):
    user = make_user(db)
    make_semester(db, user)
    assert queries.current_calendar(db, user.id) is None
