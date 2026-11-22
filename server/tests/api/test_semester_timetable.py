"""고른 학기로 시간표 저장 · 기본 학기 API (#76).

PUT /semesters/timetable, GET /semesters/suggested
"""

from datetime import date

import pytest
from sqlalchemy import func, select

from app.models import Capture, Semester, SemesterTerm, Subject
from app.services import semesters as service
from tests.db.factories import make_capture, make_semester, make_subject, make_user

URL = "/api/v1/semesters/timetable"
CURRENT = "/api/v1/semesters/current"


def body(year=2026, term="second", subjects=None, **kw):
    if subjects is None:
        subjects = [
            {"name": "자료구조", "slots": [{"weekday": 0, "start": "10:30", "end": "12:00"}]},
            {"name": "운영체제", "slots": [{"weekday": 2, "start": "13:00", "end": "14:30"}]},
        ]
    return {"year": year, "term": term, "subjects": subjects, **kw}


def semester_count(db, user):
    return db.scalar(select(func.count()).select_from(Semester).where(Semester.user_id == user.id))


# ---------- 저장 ----------


def test_first_save_creates_semester_and_shows_on_main(client, auth, db, user):
    response = client.put(URL, json=body(), headers=auth)
    assert response.status_code == 200
    saved = response.json()
    assert saved["label"] == "2026년 2학기"
    assert saved["is_current"] is True
    assert [s["name"] for s in saved["subjects"]] == ["자료구조", "운영체제"]

    # 메인 화면이 부르는 현재 학기에 그대로 나온다
    current = client.get(CURRENT, headers=auth).json()
    assert current["id"] == saved["id"]
    assert current["subjects"] == saved["subjects"]
    assert semester_count(db, user) == 1


def test_same_request_twice_gives_same_result(client, auth, db, user):
    first = client.put(URL, json=body(), headers=auth)
    second = client.put(URL, json=body(), headers=auth)
    assert first.status_code == second.status_code == 200
    assert second.json()["id"] == first.json()["id"]
    assert second.json()["subjects"] == first.json()["subjects"]
    assert semester_count(db, user) == 1


def test_saving_into_existing_semester_keeps_same_name_subjects(client, auth, db, user):
    semester = make_semester(db, user, year=2026, term=SemesterTerm.second)
    kept = make_subject(db, semester, "자료구조")
    removed = make_subject(db, semester, "컴퓨터구조")
    kept_capture = make_capture(db, user, semester, kept)
    removed_capture = make_capture(db, user, semester, removed)

    response = client.put(URL, json=body(), headers=auth)
    assert response.status_code == 200
    assert response.json()["id"] == str(semester.id)
    names = {s["name"]: s["id"] for s in response.json()["subjects"]}
    assert names["자료구조"] == str(kept.id)  # 같은 이름은 그대로 (판서 유지)
    assert "컴퓨터구조" not in names
    db.expire_all()
    assert db.get(Capture, kept_capture.id).subject_id == kept.id
    assert db.get(Capture, removed_capture.id).subject_id is None  # 미분류함으로
    assert semester_count(db, user) == 1


def test_previous_current_semester_becomes_past(client, auth, db, user):
    old = make_semester(db, user, year=2026, term=SemesterTerm.first, is_current=True)

    response = client.put(URL, json=body(year=2026, term="second"), headers=auth)
    assert response.json()["is_current"] is True
    db.expire_all()
    assert db.get(Semester, old.id).is_current is False


def test_existing_semester_is_made_current(client, auth, db, user):
    past = make_semester(db, user, year=2026, term=SemesterTerm.second, is_current=False)
    make_semester(db, user, year=2027, term=SemesterTerm.first, is_current=True)

    response = client.put(URL, json=body(year=2026, term="second"), headers=auth)
    assert response.json()["id"] == str(past.id)
    assert response.json()["is_current"] is True
    assert client.get(CURRENT, headers=auth).json()["id"] == str(past.id)


def test_make_current_false_keeps_current_semester(client, auth, db, user):
    current = make_semester(db, user, year=2026, term=SemesterTerm.second, is_current=True)

    response = client.put(URL, json=body(year=2026, term="first", make_current=False), headers=auth)
    assert response.status_code == 200
    assert response.json()["label"] == "2026년 1학기"
    assert response.json()["is_current"] is False
    assert client.get(CURRENT, headers=auth).json()["id"] == str(current.id)


def test_subjects_in_same_request_with_same_name_are_merged(client, auth):
    subjects = [
        {"name": "자료구조", "slots": [{"weekday": 0, "start": "10:30", "end": "12:00"}]},
        {"name": "자료구조", "slots": [{"weekday": 2, "start": "10:30", "end": "12:00"}]},
    ]
    response = client.put(URL, json=body(subjects=subjects), headers=auth)
    (subject,) = response.json()["subjects"]
    assert [s["weekday"] for s in subject["slots"]] == [0, 2]


def test_other_users_semesters_are_untouched(client, auth, db):
    other_user = make_user(db)
    theirs = make_semester(db, other_user, year=2026, term=SemesterTerm.second, is_current=True)
    make_subject(db, theirs, "남의 과목")

    response = client.put(URL, json=body(), headers=auth)
    assert response.json()["id"] != str(theirs.id)
    db.expire_all()
    assert db.get(Semester, theirs.id).is_current is True
    names = db.scalars(select(Subject.name).where(Subject.semester_id == theirs.id)).all()
    assert names == ["남의 과목"]


@pytest.mark.parametrize(
    "bad",
    [
        body(term="spring"),
        body(year=1999),
        body(
            subjects=[
                {"name": "자료구조", "slots": [{"weekday": 0, "start": "12:00", "end": "11:00"}]}
            ]
        ),
        {"year": 2026, "term": "second"},  # subjects 없음
    ],
)
def test_invalid_request_is_422(client, auth, db, user, bad):
    assert client.put(URL, json=bad, headers=auth).status_code == 422
    assert semester_count(db, user) == 0


def test_without_token_is_401(client):
    assert client.put(URL, json=body()).status_code == 401
    assert client.get("/api/v1/semesters/suggested").status_code == 401


# ---------- 기본 학기 ----------


@pytest.mark.parametrize(
    ("day", "expected"),
    [
        (date(2027, 2, 28), {"year": 2026, "term": "winter", "label": "2026년 겨울학기"}),
        (date(2027, 3, 1), {"year": 2027, "term": "first", "label": "2027년 1학기"}),
        (date(2027, 7, 1), {"year": 2027, "term": "summer", "label": "2027년 여름학기"}),
        (date(2026, 11, 22), {"year": 2026, "term": "second", "label": "2026년 2학기"}),
    ],
)
def test_suggested_semester_follows_date(client, auth, monkeypatch, day, expected):
    monkeypatch.setattr(service, "today", lambda: day)
    response = client.get("/api/v1/semesters/suggested", headers=auth)
    assert response.status_code == 200
    assert response.json() == expected
