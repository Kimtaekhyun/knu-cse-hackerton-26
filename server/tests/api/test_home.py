"""메인 화면 API: GET /home (#95).

날짜 기준: 2026-11-23은 월요일, 2026-11-24는 화요일(weekday 1).
"""

from datetime import date, datetime
from zoneinfo import ZoneInfo

import pytest

from app.models import CaptureStatus, SemesterTerm
from app.services import home as service
from tests.api.conftest import bearer
from tests.db.factories import make_capture, make_semester, make_slot, make_subject, make_user

URL = "/api/v1/home"
SEOUL = ZoneInfo("Asia/Seoul")


def kst(text: str) -> datetime:
    return datetime.fromisoformat(text).replace(tzinfo=SEOUL)


def get_home(client, auth, at: str | None = None, **params):
    if at is not None:
        params["at"] = at
    response = client.get(URL, params=params, headers=auth)
    assert response.status_code == 200, response.text
    return response.json()


@pytest.fixture
def timetable(db, user):
    """화요일 수업 3개 + 수요일 수업 1개"""
    semester = make_semester(db, user)
    data = make_subject(db, semester, "자료구조")
    arch = make_subject(db, semester, "컴퓨터구조")
    math = make_subject(db, semester, "이산수학")
    make_slot(db, arch, 1, "13:00", "14:30")
    make_slot(db, data, 1, "10:30", "12:00")
    make_slot(db, math, 1, "15:00", "16:30")
    make_slot(db, data, 2, "10:30", "12:00")
    return semester, {"자료구조": data, "컴퓨터구조": arch, "이산수학": math}


# ---------- 수업 중 · 오늘 수업 ----------


def test_today_classes_in_start_order(client, auth, timetable):
    body = get_home(client, auth, "2026-11-24T09:00:00+09:00")
    assert [(c["name"], c["start"], c["end"]) for c in body["today"]] == [
        ("자료구조", "10:30", "12:00"),
        ("컴퓨터구조", "13:00", "14:30"),
        ("이산수학", "15:00", "16:30"),
    ]
    assert body["now_class"] is None  # 아직 수업 전


def test_now_class_during_class(client, auth, timetable):
    _, subjects = timetable
    now = get_home(client, auth, "2026-11-24T10:40:00+09:00")["now_class"]
    assert now == {
        "subject_id": str(subjects["자료구조"].id),
        "name": "자료구조",
        "start": "10:30",
        "end": "12:00",
    }


@pytest.mark.parametrize(
    ("at", "expected"),
    [
        ("2026-11-24T10:30:00+09:00", "자료구조"),  # 시작 시각은 수업 중
        ("2026-11-24T12:00:00+09:00", None),  # 끝 시각은 수업 아님
        ("2026-11-24T13:00:00+09:00", "컴퓨터구조"),
        ("2026-11-24T17:00:00+09:00", None),
    ],
)
def test_now_class_boundaries(client, auth, timetable, at, expected):
    now = get_home(client, auth, at)["now_class"]
    assert (now and now["name"]) == expected


def test_finished_classes_stay_in_today(client, auth, timetable):
    body = get_home(client, auth, "2026-11-24T20:00:00+09:00")
    assert len(body["today"]) == 3
    assert body["now_class"] is None


def test_utc_time_uses_seoul_weekday(client, auth, timetable):
    # 화 10:40 KST = 화 01:40 UTC. 월 23:00 UTC는 화 08:00 KST
    assert get_home(client, auth, "2026-11-24T01:40:00Z")["now_class"]["name"] == "자료구조"
    assert len(get_home(client, auth, "2026-11-23T23:00:00Z")["today"]) == 3


def test_time_without_zone_is_seoul(client, auth, timetable):
    assert get_home(client, auth, "2026-11-24T10:40:00")["now_class"]["name"] == "자료구조"


def test_other_weekday_shows_that_day_only(client, auth, timetable):
    body = get_home(client, auth, "2026-11-25T11:00:00+09:00")  # 수요일
    assert [c["name"] for c in body["today"]] == ["자료구조"]
    assert body["now_class"]["name"] == "자료구조"


def test_no_class_day_is_empty(client, auth, timetable):
    body = get_home(client, auth, "2026-11-29T11:00:00+09:00")  # 일요일
    assert body["today"] == []
    assert body["now_class"] is None


def test_past_semester_classes_are_not_shown(client, db, auth, user):
    past = make_semester(db, user, year=2026, is_current=False, term=SemesterTerm.first)
    make_slot(db, make_subject(db, past, "지난 과목"), 1, "10:00", "12:00")
    body = get_home(client, auth, "2026-11-24T11:00:00+09:00")
    assert body["today"] == []
    assert body["now_class"] is None


def test_without_semester(client, auth):
    body = get_home(client, auth, "2026-11-24T11:00:00+09:00")
    assert body["now_class"] is None
    assert body["today"] == []
    assert body["exam"] is None
    assert body["total_captures"] == 0
    assert body["week"]["days"] == [0] * 7


# ---------- 이번 주 ----------


def test_week_counts_done_captures_by_seoul_day(client, db, auth, user, timetable):
    semester, _ = timetable
    for taken in ["2026-11-23T10:00", "2026-11-23T15:00", "2026-11-24T09:00"]:
        make_capture(db, user, semester, taken_at=kst(taken))
    # 일 23:30 KST (이번 주 마지막 날)
    make_capture(db, user, semester, taken_at=kst("2026-11-29T23:30"))
    # 다음 주 월 00:30 KST = 일 15:30 UTC → 이번 주에 들어가지 않음
    make_capture(db, user, semester, taken_at=datetime.fromisoformat("2026-11-29T15:30+00:00"))
    # 처리 중 · 실패는 세지 않음
    make_capture(db, user, semester, taken_at=kst("2026-11-24T10:00"), status=CaptureStatus.failed)
    make_capture(
        db, user, semester, taken_at=kst("2026-11-24T10:00"), status=CaptureStatus.segmenting
    )

    week = get_home(client, auth, "2026-11-25T12:00:00+09:00")["week"]
    assert week["start"] == "2026-11-23"
    assert week["days"] == [2, 1, 0, 0, 0, 0, 1]
    assert week["total"] == 4


def test_last_week_total(client, db, auth, user, timetable):
    semester, _ = timetable
    for taken in ["2026-11-16T10:00", "2026-11-22T23:59", "2026-11-23T00:00"]:
        make_capture(db, user, semester, taken_at=kst(taken))
    make_capture(db, user, semester, taken_at=kst("2026-11-15T10:00"))  # 지지난주
    week = get_home(client, auth, "2026-11-24T12:00:00+09:00")["week"]
    assert week["total"] == 1
    assert week["last_week_total"] == 2


def test_monday_and_sunday_are_same_week(client, auth):
    monday = get_home(client, auth, "2026-11-23T00:00:00+09:00")["week"]["start"]
    sunday = get_home(client, auth, "2026-11-29T23:59:00+09:00")["week"]["start"]
    assert monday == sunday == "2026-11-23"


def test_total_captures_counts_done_only(client, db, auth, user, timetable):
    semester, _ = timetable
    make_capture(db, user, semester, taken_at=kst("2025-03-01T10:00"))  # 오래전 판서도 셈
    make_capture(db, user, semester)
    make_capture(db, user, semester, status=CaptureStatus.uploaded)
    assert get_home(client, auth, "2026-11-24T12:00:00+09:00")["total_captures"] == 2


# ---------- 시험 ----------


def test_exam_from_school_calendar(client, auth, timetable):
    # 경북대 2026년 2학기 시드: 기말 12/14 시작
    exam = get_home(client, auth, "2026-11-22T12:00:00+09:00")["exam"]
    assert exam == {
        "kind": "final",
        "starts_on": "2026-12-14",
        "ends_on": "2026-12-20",
        "days_left": 22,
        "in_progress": False,
    }


def test_exam_in_progress(client, auth, timetable):
    exam = get_home(client, auth, "2026-12-15T12:00:00+09:00")["exam"]
    assert (exam["kind"], exam["days_left"], exam["in_progress"]) == ("final", 0, True)


def test_no_exam_after_final(client, auth, timetable):
    assert get_home(client, auth, "2026-12-21T00:00:00+09:00")["exam"] is None


def test_seeded_calendar_is_not_searched(client, auth, timetable, calendar_lookups):
    get_home(client, auth, "2026-11-22T12:00:00+09:00")
    assert calendar_lookups == []


# 학사일정이 없으면 추정 개강일(2026-09-01 화) 기준 8 · 15주차: 중간 10/20, 기말 12/8 (#173)
ESTIMATED_FINAL = {
    "kind": "final",
    "starts_on": "2026-12-08",
    "ends_on": "2026-12-14",
    "days_left": 16,
    "in_progress": False,
}


def test_estimated_exam_without_school(client, db, calendar_lookups):
    user = make_user(db)  # 학교 없음
    make_semester(db, user)
    exam = get_home(client, bearer(user.id), "2026-11-22T12:00:00+09:00")["exam"]
    assert exam == ESTIMATED_FINAL
    assert calendar_lookups == []  # 학교를 모르면 찾지 않음


def test_school_without_calendar_is_searched_and_estimated(client, db, calendar_lookups):
    user = make_user(db, school="없는대학교")
    make_semester(db, user)
    exam = get_home(client, bearer(user.id), "2026-11-22T12:00:00+09:00")["exam"]
    assert exam == ESTIMATED_FINAL
    assert calendar_lookups == [("없는대학교", 2026, SemesterTerm.second)]


def test_semester_without_calendar_is_searched_and_estimated(
    client, db, auth, user, calendar_lookups
):
    make_semester(db, user, year=2027, term=SemesterTerm.first)  # 시드에 없는 학기
    exam = get_home(client, auth, "2027-04-01T12:00:00+09:00")["exam"]
    # 2027-03-02(화) 개강 → 8주차 첫날 4/20
    assert (exam["kind"], exam["starts_on"], exam["days_left"]) == ("midterm", "2027-04-20", 19)
    assert calendar_lookups == [("경북대학교", 2027, SemesterTerm.first)]


def test_start_only_calendar_uses_found_start(client, db, calendar_lookups):
    # 검색으로 개강일(8/31 월)만 찾아 저장된 경우: 추정 9/1이 아니라 8/31 기준 15주차 → 기말 12/7
    from app.services.academic_calendar import FoundDates, save

    save(
        db,
        "부산대학교",
        2026,
        SemesterTerm.second,
        FoundDates(
            starts_on=date(2026, 8, 31), midterm_start=None, final_start=None, source_url=None
        ),
    )
    user = make_user(db, school="부산대학교")
    make_semester(db, user)
    exam = get_home(client, bearer(user.id), "2026-11-22T12:00:00+09:00")["exam"]
    assert (exam["kind"], exam["starts_on"], exam["ends_on"]) == (
        "final",
        "2026-12-07",
        "2026-12-13",
    )
    # 시험 시작일이 비어 있으니 다시 찾게 한다
    assert calendar_lookups == [("부산대학교", 2026, SemesterTerm.second)]


def test_no_exam_in_summer_term(client, db, auth, user, calendar_lookups):
    make_semester(db, user, year=2027, term=SemesterTerm.summer)
    assert get_home(client, auth, "2027-07-10T12:00:00+09:00")["exam"] is None


# ---------- 다른 사용자 · 인증 · 기본 시각 ----------


def test_other_users_data_is_excluded(client, db, auth, timetable):
    other = make_user(db, school="경북대학교")
    theirs = make_semester(db, other)
    make_slot(db, make_subject(db, theirs, "남의 과목"), 1, "10:00", "12:00")
    make_capture(db, other, theirs, taken_at=kst("2026-11-24T09:00"))

    body = get_home(client, auth, "2026-11-24T11:00:00+09:00")
    assert "남의 과목" not in [c["name"] for c in body["today"]]
    assert body["now_class"]["name"] == "자료구조"
    assert body["week"]["total"] == 0
    assert body["total_captures"] == 0


def test_without_token_is_401(client):
    assert client.get(URL).status_code == 401


def test_bad_at_is_422(client, auth):
    assert client.get(URL, params={"at": "어제"}, headers=auth).status_code == 422


def test_now_is_used_without_at(client, auth, monkeypatch):
    seen = []
    real = service.home

    def spy(db, user, at):
        seen.append(at)
        return real(db, user, at)

    monkeypatch.setattr(service, "home", spy)
    get_home(client, auth)
    (at,) = seen
    assert at.tzinfo is not None
    assert abs((datetime.now(SEOUL) - at).total_seconds()) < 60
