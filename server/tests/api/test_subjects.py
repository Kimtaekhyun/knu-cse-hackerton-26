import pytest
from sqlalchemy import select

from app.models import Capture, SubjectSlot
from tests.db.factories import make_capture, make_semester, make_slot, make_subject, make_user

SLOT = {"weekday": 0, "start": "10:30", "end": "12:00"}


@pytest.fixture
def semester(db, user):
    return make_semester(db, user)


def subjects_url(semester):
    return f"/api/v1/semesters/{semester.id}/subjects"


def subject_url(subject):
    return f"/api/v1/subjects/{subject.id}"


# ---------- 추가 ----------


def test_create_subject(client, auth, semester):
    response = client.post(
        subjects_url(semester), headers=auth, json={"name": "자료구조", "slots": [SLOT, SLOT]}
    )
    assert response.status_code == 201
    body = response.json()
    assert body["name"] == "자료구조"
    assert body["semester_id"] == str(semester.id)
    assert body["slots"] == [SLOT]  # 같은 칸은 하나만
    assert body["capture_count"] == 0


def test_create_subject_without_slots(client, auth, semester):
    response = client.post(subjects_url(semester), headers=auth, json={"name": "사이버강의"})
    assert response.status_code == 201
    assert response.json()["slots"] == []


def test_duplicate_subject_name_is_409(client, auth, db, semester):
    make_subject(db, semester, name="자료구조")
    response = client.post(subjects_url(semester), headers=auth, json={"name": "자료구조"})
    assert response.status_code == 409
    assert response.json()["detail"] == "'자료구조' 과목이 이미 있어요."


@pytest.mark.parametrize(
    "body",
    [
        {"name": ""},
        {"name": "   "},
        {"name": "자료구조", "slots": [{"weekday": 7, "start": "10:30", "end": "12:00"}]},
        {"name": "자료구조", "slots": [{"weekday": 0, "start": "12:00", "end": "10:30"}]},
        {"name": "자료구조", "slots": [{"weekday": 0, "start": "10:30", "end": "10:30"}]},
        {"name": "자료구조", "slots": [{"weekday": 0, "start": "9:00", "end": "10:30"}]},
        {"name": "자료구조", "slots": [{"weekday": 0, "start": "24:00", "end": "25:00"}]},
        {"name": "자료\u0000구조"},  # NUL은 Postgres에 넣을 수 없음
        {"name": "자료\n구조"},
        {"name": "자료구조", "slots": [SLOT] * 21},
    ],
)
def test_invalid_subject_is_422(client, auth, semester, body):
    assert client.post(subjects_url(semester), headers=auth, json=body).status_code == 422


def test_cannot_add_subject_to_other_users_semester(client, auth, db):
    other_semester = make_semester(db, make_user(db))
    response = client.post(subjects_url(other_semester), headers=auth, json={"name": "자료구조"})
    assert response.status_code == 404


# ---------- 조회 · 수정 ----------


def test_get_subject(client, auth, db, user, semester):
    subject = make_subject(db, semester)
    make_slot(db, subject, 0, "10:30", "12:00")
    make_capture(db, user, semester, subject)

    body = client.get(subject_url(subject), headers=auth).json()
    assert body["slots"] == [SLOT]
    assert body["capture_count"] == 1


def test_rename_subject(client, auth, db, semester):
    subject = make_subject(db, semester, name="자료구조")
    make_slot(db, subject, 0, "10:30", "12:00")

    response = client.patch(subject_url(subject), headers=auth, json={"name": "자료구조론"})
    assert response.status_code == 200
    assert response.json()["name"] == "자료구조론"
    assert response.json()["slots"] == [SLOT]  # 보내지 않은 시간 칸은 그대로


def test_replace_slots(client, auth, db, semester):
    subject = make_subject(db, semester)
    make_slot(db, subject, 0, "10:30", "12:00")
    new_slots = [{"weekday": 1, "start": "09:00", "end": "10:30"}]

    response = client.patch(subject_url(subject), headers=auth, json={"slots": new_slots})
    assert response.json()["slots"] == new_slots
    rows = db.scalars(select(SubjectSlot).where(SubjectSlot.subject_id == subject.id)).all()
    assert len(rows) == 1


def test_rename_to_existing_name_is_409(client, auth, db, semester):
    make_subject(db, semester, name="운영체제")
    subject = make_subject(db, semester, name="자료구조")
    response = client.patch(subject_url(subject), headers=auth, json={"name": "운영체제"})
    assert response.status_code == 409


def test_rename_to_same_name_is_fine(client, auth, db, semester):
    subject = make_subject(db, semester, name="자료구조")
    response = client.patch(subject_url(subject), headers=auth, json={"name": "자료구조"})
    assert response.status_code == 200


def test_other_users_subject_is_404(client, auth, db):
    other_subject = make_subject(db, make_semester(db, make_user(db)))
    assert client.get(subject_url(other_subject), headers=auth).status_code == 404
    assert client.patch(subject_url(other_subject), headers=auth, json={}).status_code == 404
    assert client.delete(subject_url(other_subject), headers=auth).status_code == 404


# ---------- 삭제 ----------


def test_delete_subject_sends_captures_to_unsorted(client, auth, db, user, semester):
    subject = make_subject(db, semester)
    capture = make_capture(db, user, semester, subject)
    db.commit()

    assert client.delete(subject_url(subject), headers=auth).status_code == 204
    assert client.get(subject_url(subject), headers=auth).status_code == 404
    db.expire_all()
    assert db.get(Capture, capture.id).subject_id is None


def test_name_is_normalized_to_nfc(client, auth, db, semester):
    """iOS 입력(NFD)과 서버 인식 결과(NFC)가 달라도 같은 과목으로 본다"""
    import unicodedata

    nfc = "자료구조"
    nfd = unicodedata.normalize("NFD", nfc)
    assert nfc != nfd

    created = client.post(subjects_url(semester), headers=auth, json={"name": nfd})
    assert created.status_code == 201
    assert created.json()["name"] == nfc
    again = client.post(subjects_url(semester), headers=auth, json={"name": nfc})
    assert again.status_code == 409


def test_too_many_slots_in_update_is_422(client, auth, db, semester):
    subject = make_subject(db, semester)
    response = client.patch(subject_url(subject), headers=auth, json={"slots": [SLOT] * 21})
    assert response.status_code == 422
