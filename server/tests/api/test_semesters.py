from sqlalchemy import select

from app.models import Capture, Semester, SemesterTerm, Subject
from app.services.timetable_ocr import RawBlock, RawTimetable, normalize
from tests.db.factories import make_capture, make_semester, make_slot, make_subject, make_user

URL = "/api/v1/semesters"


def create(client, auth, year=2026, term="second", **kw):
    return client.post(URL, json={"year": year, "term": term, **kw}, headers=auth)


# ---------- 목록 · 만들기 ----------


def test_list_is_empty_at_first(client, auth):
    response = client.get(URL, headers=auth)
    assert response.status_code == 200
    assert response.json() == []


def test_create_semester(client, auth):
    response = create(client, auth)
    assert response.status_code == 201
    body = response.json()
    assert body["label"] == "2026년 2학기"
    assert body["is_current"] is True
    assert body["subjects"] == []


def test_new_current_semester_replaces_old_one(client, auth):
    old = create(client, auth, term="first").json()
    new = create(client, auth, term="second").json()

    semesters = {s["id"]: s for s in client.get(URL, headers=auth).json()}
    assert semesters[old["id"]]["is_current"] is False
    assert semesters[new["id"]]["is_current"] is True


def test_create_without_making_current(client, auth):
    current = create(client, auth, term="second").json()
    past = create(client, auth, term="first", make_current=False).json()

    assert past["is_current"] is False
    assert client.get(f"{URL}/current", headers=auth).json()["id"] == current["id"]


def test_duplicate_semester_is_409(client, auth):
    create(client, auth)
    response = create(client, auth)
    assert response.status_code == 409
    assert response.json()["detail"] == "2026년 2학기는 이미 있어요."


def test_invalid_term_is_422(client, auth):
    assert create(client, auth, term="third").status_code == 422


def test_list_is_newest_first_with_counts(client, auth, db, user):
    past = make_semester(db, user, year=2026, term=SemesterTerm.first, is_current=False)
    current = make_semester(db, user, year=2026, term=SemesterTerm.second)
    subject = make_subject(db, current)
    make_subject(db, current, name="운영체제")
    make_capture(db, user, current, subject)
    make_capture(db, user, current)  # 미분류도 학기 판서 수에 들어간다

    body = client.get(URL, headers=auth).json()
    assert [s["id"] for s in body] == [str(current.id), str(past.id)]
    assert body[0]["subject_count"] == 2
    assert body[0]["capture_count"] == 2
    assert body[1]["subject_count"] == 0


# ---------- 현재 학기 ----------


def test_no_current_semester_is_404(client, auth):
    response = client.get(f"{URL}/current", headers=auth)
    assert response.status_code == 404
    assert response.json()["detail"] == "현재 학기가 없어요."


def test_current_semester_has_subjects_in_class_order(client, auth, db, user):
    semester = make_semester(db, user)
    cyber = make_subject(db, semester, name="사이버강의")
    os_ = make_subject(db, semester, name="운영체제")
    make_slot(db, os_, 2, "09:00", "10:30")
    ds = make_subject(db, semester, name="자료구조")
    make_slot(db, ds, 3, "10:30", "12:00")
    make_slot(db, ds, 0, "10:30", "12:00")
    make_capture(db, user, semester, ds)

    body = client.get(f"{URL}/current", headers=auth).json()
    assert [s["name"] for s in body["subjects"]] == ["자료구조", "운영체제", "사이버강의"]
    first = body["subjects"][0]
    assert first["slots"] == [
        {"weekday": 0, "start": "10:30", "end": "12:00"},
        {"weekday": 3, "start": "10:30", "end": "12:00"},
    ]
    assert first["capture_count"] == 1
    assert body["subjects"][2]["id"] == str(cyber.id)


def test_set_current(client, auth):
    first = create(client, auth, term="first").json()
    create(client, auth, term="second")

    response = client.put(f"{URL}/{first['id']}/current", headers=auth)
    assert response.status_code == 200
    assert response.json()["is_current"] is True
    assert client.get(f"{URL}/current", headers=auth).json()["id"] == first["id"]
    assert sum(s["is_current"] for s in client.get(URL, headers=auth).json()) == 1


def test_set_current_twice_is_fine(client, auth):
    semester = create(client, auth).json()
    for _ in range(2):
        assert client.put(f"{URL}/{semester['id']}/current", headers=auth).status_code == 200


# ---------- 남의 학기 · 삭제 ----------


def test_other_users_semester_is_404(client, auth, db):
    other = make_user(db)
    semester = make_semester(db, other)

    assert client.get(f"{URL}/{semester.id}", headers=auth).status_code == 404
    assert client.delete(f"{URL}/{semester.id}", headers=auth).status_code == 404
    assert client.put(f"{URL}/{semester.id}/current", headers=auth).status_code == 404
    assert client.get(URL, headers=auth).json() == []


def test_delete_semester_removes_subjects_and_captures(client, auth, db, user):
    semester = make_semester(db, user)
    subject = make_subject(db, semester)
    make_capture(db, user, semester, subject)
    db.commit()

    assert client.delete(f"{URL}/{semester.id}", headers=auth).status_code == 204
    assert db.scalar(select(Semester).where(Semester.id == semester.id)) is None
    assert db.scalars(select(Subject).where(Subject.semester_id == semester.id)).all() == []
    assert db.scalars(select(Capture).where(Capture.semester_id == semester.id)).all() == []


# ---------- 시간표 저장 ----------


def test_save_timetable(client, auth, db, user):
    semester = make_semester(db, user)
    kept = make_subject(db, semester, name="자료구조")
    make_slot(db, kept, 0, "10:30", "12:00")
    removed = make_subject(db, semester, name="이산수학")
    capture_of_kept = make_capture(db, user, semester, kept)
    capture_of_removed = make_capture(db, user, semester, removed)
    db.commit()

    response = client.put(
        f"{URL}/{semester.id}/timetable",
        headers=auth,
        json={
            "subjects": [
                {"name": "자료구조", "slots": [{"weekday": 1, "start": "13:00", "end": "14:30"}]},
                {"name": " 운영체제 ", "slots": [{"weekday": 4, "start": "10:30", "end": "12:00"}]},
                # 인식 결과가 같은 과목을 둘로 나눈 경우 → 합친다
                {"name": "운영체제", "slots": [{"weekday": 2, "start": "10:30", "end": "12:00"}]},
                {"name": "사이버강의", "slots": []},
            ]
        },
    )
    assert response.status_code == 200
    subjects = {s["name"]: s for s in response.json()["subjects"]}
    assert set(subjects) == {"자료구조", "운영체제", "사이버강의"}

    # 이름이 같은 과목은 그대로(id · 판서 유지), 시간 칸만 바뀐다
    assert subjects["자료구조"]["id"] == str(kept.id)
    assert subjects["자료구조"]["slots"] == [{"weekday": 1, "start": "13:00", "end": "14:30"}]
    assert subjects["자료구조"]["capture_count"] == 1
    assert [s["weekday"] for s in subjects["운영체제"]["slots"]] == [2, 4]

    # 빠진 과목의 판서는 미분류함으로
    db.expire_all()
    assert db.get(Capture, capture_of_kept.id).subject_id == kept.id
    assert db.get(Capture, capture_of_removed.id).subject_id is None


def test_timetable_result_can_be_saved_as_is(client, auth):
    """시간표 인식 응답의 subjects를 그대로 저장 요청에 넣을 수 있다"""
    semester = create(client, auth).json()
    parsed = {
        "subjects": [
            {"name": "자료구조", "slots": [{"weekday": 0, "start": "10:30", "end": "12:00"}]}
        ]
    }

    response = client.put(f"{URL}/{semester['id']}/timetable", headers=auth, json=parsed)
    assert response.status_code == 200
    assert response.json()["subject_count"] == 1


def test_late_timetable_result_can_be_saved_as_is(client, auth):
    """밤늦게 끝나는 수업도 인식 결과(normalize)를 그대로 저장할 수 있다 (24:00 → 23:59, #72)"""
    raw = RawTimetable(
        blocks=[RawBlock(name="야간 실습", weekday=2, start="22:30", end="23:50")], untimed=[]
    )
    parsed = {"subjects": [s.model_dump() for s in normalize(raw)]}
    semester = create(client, auth).json()

    response = client.put(f"{URL}/{semester['id']}/timetable", headers=auth, json=parsed)
    assert response.status_code == 200
    (subject,) = response.json()["subjects"]
    assert subject["slots"] == [{"weekday": 2, "start": "22:30", "end": "23:59"}]


def test_save_empty_timetable_removes_all_subjects(client, auth, db, user):
    semester = make_semester(db, user)
    make_subject(db, semester)
    db.commit()

    response = client.put(f"{URL}/{semester.id}/timetable", headers=auth, json={"subjects": []})
    assert response.json()["subjects"] == []


def test_too_many_subjects_is_422(client, auth):
    semester = create(client, auth).json()
    body = {"subjects": [{"name": f"과목{i}"} for i in range(51)]}
    response = client.put(f"{URL}/{semester['id']}/timetable", headers=auth, json=body)
    assert response.status_code == 422


def test_unique_violation_is_409_not_500(client, auth, monkeypatch):
    """API의 중복 확인을 피해 간 경우에도 DB 제약 위반은 409로 돌려준다"""
    from app.services import semesters as service

    create(client, auth)
    monkeypatch.setattr(service, "semester_exists", lambda *args: False)
    response = create(client, auth)
    assert response.status_code == 409
    assert response.json()["detail"] == "이미 같은 항목이 있어요."
