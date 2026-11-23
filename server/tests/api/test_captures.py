import io
import uuid
from datetime import UTC, date, datetime, timedelta

import pytest
from PIL import Image
from sqlalchemy import func, select

from app.core.config import get_settings
from app.models import Capture, CaptureStatus, Card, Semester, SemesterTerm
from app.services.captures import SEOUL, capture_dir, rectified_key
from app.services.semesters import term_of
from app.storage import local as storage
from tests.api.conftest import bearer
from tests.db.factories import (
    make_capture,
    make_card,
    make_semester,
    make_slot,
    make_subject,
    make_user,
)

URL = "/api/v1/captures"
# 수업 중인 시각 (서울 11:00). 요일은 이 날짜에서 계산해서 시간 칸을 만든다
IN_CLASS = datetime(2026, 11, 16, 11, 0, tzinfo=SEOUL)


@pytest.fixture(autouse=True)
def media_dir(tmp_path, monkeypatch, jwt_settings):
    """사진을 테스트마다 새 임시 폴더에 저장한다"""
    monkeypatch.setenv("MEDIA_DIR", str(tmp_path))
    get_settings.cache_clear()
    yield tmp_path
    get_settings.cache_clear()


@pytest.fixture
def semester(db, user):
    return make_semester(db, user)


@pytest.fixture
def subject(db, semester):
    """IN_CLASS 시각에 수업 중인 과목"""
    subject = make_subject(db, semester, name="자료구조")
    make_slot(db, subject, IN_CLASS.weekday(), "10:30", "12:00")
    return subject


def jpeg() -> bytes:
    buffer = io.BytesIO()
    Image.new("RGB", (8, 8), "white").save(buffer, "JPEG")
    return buffer.getvalue()


def upload(client, auth, data=None, image=None, content_type="image/jpeg"):
    image = jpeg() if image is None else image
    return client.post(
        URL, headers=auth, data=data or {}, files={"image": ("a.jpg", image, content_type)}
    )


def count_captures(db) -> int:
    return db.scalar(select(func.count()).select_from(Capture))


# ---------- 올리기 ----------


def test_upload_classifies_by_class_time(client, auth, db, subject):
    response = upload(client, auth, {"taken_at": IN_CLASS.isoformat()})
    assert response.status_code == 202
    body = response.json()
    assert body["subject_id"] == str(subject.id)
    assert body["semester_id"] == str(subject.semester_id)
    assert body["status"] == "uploaded"
    assert body["class_date"] == "2026-11-16"
    assert body["cards"] == [] and body["card_count"] == 0

    capture = db.get(Capture, uuid.UUID(body["id"]))
    assert storage.path(capture.original_key).read_bytes() == jpeg()


def test_upload_outside_class_goes_to_unsorted(client, auth, subject):
    evening = IN_CLASS.replace(hour=20)
    response = upload(client, auth, {"taken_at": evening.isoformat()})
    assert response.status_code == 202
    assert response.json()["subject_id"] is None


def test_naive_taken_at_is_seoul_time(client, auth, subject):
    """시간대 없는 11:00은 서울 11:00 → 수업 중"""
    response = upload(client, auth, {"taken_at": "2026-11-16T11:00:00"})
    assert response.json()["subject_id"] == str(subject.id)


def test_upload_to_chosen_subject(client, auth, db, semester, subject):
    other = make_subject(db, semester, name="운영체제")
    response = upload(client, auth, {"taken_at": IN_CLASS.isoformat(), "subject_id": str(other.id)})
    assert response.json()["subject_id"] == str(other.id)


def test_upload_without_taken_at_uses_now(client, auth, semester):
    before = datetime.now(UTC)
    response = upload(client, auth)
    taken_at = datetime.fromisoformat(response.json()["taken_at"])
    assert before - timedelta(seconds=1) <= taken_at <= datetime.now(UTC)


def test_upload_without_semester_creates_current_semester(client, auth, db, user):
    """시간표를 건너뛴 사용자: 오늘이 속한 학기를 만들고 판서는 미분류함에 넣는다"""
    response = upload(client, auth, {"taken_at": IN_CLASS.isoformat()})
    assert response.status_code == 202
    body = response.json()
    assert body["subject_id"] is None

    semester = db.get(Semester, uuid.UUID(body["semester_id"]))
    assert semester.user_id == user.id and semester.is_current
    assert (semester.year, semester.term) == term_of(datetime.now(SEOUL).date())

    # 다음 판서는 같은 학기를 쓴다 (학기를 또 만들지 않는다)
    again = upload(client, auth).json()
    assert again["semester_id"] == body["semester_id"]
    assert db.scalar(select(func.count()).select_from(Semester)) == 1


def test_upload_reuses_same_term_semester_when_none_is_current(client, auth, db, user):
    """오늘 학기가 있는데 현재 학기 지정만 풀려 있으면 그 학기를 다시 현재로 쓴다"""
    year, term = term_of(datetime.now(SEOUL).date())
    existing = make_semester(db, user, year=year, term=term, is_current=False)
    response = upload(client, auth)
    assert response.json()["semester_id"] == str(existing.id)
    db.refresh(existing)
    assert existing.is_current


@pytest.mark.parametrize(
    ("day", "expected"),
    [
        (date(2027, 1, 15), (2026, SemesterTerm.winter)),
        (date(2027, 2, 28), (2026, SemesterTerm.winter)),
        (date(2027, 3, 1), (2027, SemesterTerm.first)),
        (date(2027, 6, 30), (2027, SemesterTerm.first)),
        (date(2027, 7, 1), (2027, SemesterTerm.summer)),
        (date(2027, 8, 31), (2027, SemesterTerm.summer)),
        (date(2026, 9, 1), (2026, SemesterTerm.second)),
        (date(2026, 12, 31), (2026, SemesterTerm.second)),
    ],
)
def test_term_of(day, expected):
    assert term_of(day) == expected


def test_upload_to_others_subject_is_404(client, auth, db, semester):
    stranger = make_user(db)
    their_subject = make_subject(db, make_semester(db, stranger))
    response = upload(client, auth, {"subject_id": str(their_subject.id)})
    assert response.status_code == 404


def test_resend_same_id_returns_existing(client, auth, db, semester):
    """답을 못 받아 다시 보낸 경우: 새로 만들지 않고 처음 것을 돌려준다"""
    capture_id = str(uuid.uuid4())
    first = upload(client, auth, {"id": capture_id})
    second = upload(client, auth, {"id": capture_id})
    assert first.status_code == 202
    assert second.status_code == 200
    assert second.json()["id"] == first.json()["id"] == capture_id
    assert count_captures(db) == 1


def test_id_used_by_another_user_is_409(client, db, semester):
    stranger = make_user(db)
    theirs = make_capture(db, stranger, make_semester(db, stranger))
    me = semester.user_id
    response = upload(client, bearer(me), {"id": str(theirs.id)})
    assert response.status_code == 409


@pytest.mark.parametrize(
    ("image", "content_type", "status"),
    [
        (b"", "image/jpeg", 400),
        (b"%PDF", "application/pdf", 415),
        (b"heic", "image/heic", 415),
    ],
)
def test_bad_image_is_rejected(client, auth, db, semester, image, content_type, status):
    response = upload(client, auth, image=image, content_type=content_type)
    assert response.status_code == status
    assert count_captures(db) == 0


def test_too_large_image_is_413(client, auth, semester, monkeypatch):
    monkeypatch.setattr("app.api.v1.captures.MAX_BYTES", 10)
    response = upload(client, auth)
    assert response.status_code == 413


def sized_jpeg(width: int, height: int) -> bytes:
    buffer = io.BytesIO()
    Image.new("RGB", (width, height), "white").save(buffer, "JPEG")
    return buffer.getvalue()


def test_too_many_pixels_is_413_and_nothing_is_kept(
    client, auth, db, semester, media_dir, enqueued, monkeypatch
):
    # 용량은 작아도 해상도가 크면 처리할 때 서버 메모리가 바닥난다 (#130).
    # 한도를 줄여 작은 사진으로 확인한다
    monkeypatch.setattr("app.services.image_limits.MAX_PIXELS", 100)
    response = upload(client, auth, image=sized_jpeg(11, 10))
    assert response.status_code == 413
    assert response.json()["detail"] == "사진 해상도가 너무 커요."
    assert count_captures(db) == 0
    assert [p for p in media_dir.rglob("*") if p.is_file()] == []
    assert enqueued == []


def test_pixels_at_limit_are_accepted(client, auth, semester, monkeypatch):
    monkeypatch.setattr("app.services.image_limits.MAX_PIXELS", 100)
    assert upload(client, auth, image=sized_jpeg(10, 10)).status_code == 202


def test_unreadable_image_is_400(client, auth, db, semester):
    response = upload(client, auth, image=b"not-an-image")
    assert response.status_code == 400
    assert response.json()["detail"] == "사진을 읽지 못했어요."
    assert count_captures(db) == 0


def test_upload_requires_login(client, semester):
    assert upload(client, {}).status_code == 401


# ---------- 목록 ----------


def test_list_newest_first_with_filters(client, auth, db, user, semester, subject):
    old = make_capture(db, user, semester, subject, taken_at=IN_CLASS - timedelta(days=7))
    unsorted = make_capture(db, user, semester, None, taken_at=IN_CLASS - timedelta(days=1))
    new = make_capture(db, user, semester, subject, taken_at=IN_CLASS)
    make_card(db, old, 1, is_moved=True)
    make_card(db, new, 1, is_moved=True)
    make_card(db, new, 2)
    make_capture(db, make_user(db), make_semester(db, make_user(db)))  # 남의 판서

    def ids(**params):
        response = client.get(URL, headers=auth, params=params)
        assert response.status_code == 200
        return [item["id"] for item in response.json()]

    assert ids() == [str(new.id), str(unsorted.id), str(old.id)]
    assert ids(subject_id=subject.id) == [str(new.id), str(old.id)]
    assert ids(unsorted=True) == [str(unsorted.id)]
    assert ids(unmoved=True) == [str(new.id)]
    assert ids(before=IN_CLASS.isoformat()) == [str(unsorted.id), str(old.id)]
    assert ids(limit=1) == [str(new.id)]

    first = client.get(URL, headers=auth).json()[0]
    assert (first["card_count"], first["unmoved_count"]) == (2, 1)


def test_list_subject_and_unsorted_together_is_400(client, auth, subject):
    response = client.get(URL, headers=auth, params={"subject_id": subject.id, "unsorted": True})
    assert response.status_code == 400


# ---------- 상세 ----------


def test_detail_has_cards_in_order(client, auth, db, user, semester):
    capture = make_capture(db, user, semester)
    make_card(db, capture, 2, content="고침", original_content="원래")
    make_card(db, capture, 1)
    response = client.get(f"{URL}/{capture.id}", headers=auth)
    assert response.status_code == 200
    cards = response.json()["cards"]
    assert [c["order_no"] for c in cards] == [1, 2]
    assert [c["is_edited"] for c in cards] == [False, True]


def test_others_capture_is_404(client, auth, db):
    stranger = make_user(db)
    theirs = make_capture(db, stranger, make_semester(db, stranger))
    assert client.get(f"{URL}/{theirs.id}", headers=auth).status_code == 404
    assert (
        client.patch(f"{URL}/{theirs.id}", headers=auth, json={"subject_id": None}).status_code
        == 404
    )
    assert client.delete(f"{URL}/{theirs.id}", headers=auth).status_code == 404


# ---------- 과목으로 옮기기 ----------


def test_move_to_subject_and_back_to_unsorted(client, auth, db, user, semester, subject):
    capture = make_capture(db, user, semester, None)
    url = f"{URL}/{capture.id}"

    response = client.patch(url, headers=auth, json={"subject_id": str(subject.id)})
    assert response.status_code == 200
    assert response.json()["subject_id"] == str(subject.id)

    response = client.patch(url, headers=auth, json={"subject_id": None})
    assert response.json()["subject_id"] is None


def test_move_to_other_semester_subject_moves_semester(client, auth, db, user, semester):
    capture = make_capture(db, user, semester, None)
    last_term = make_semester(db, user, year=2026, term=SemesterTerm.first, is_current=False)
    last_subject = make_subject(db, last_term, name="이산수학")
    response = client.patch(
        f"{URL}/{capture.id}", headers=auth, json={"subject_id": str(last_subject.id)}
    )
    assert response.json()["semester_id"] == str(last_term.id)


def test_move_requires_subject_id_field(client, auth, db, user, semester):
    capture = make_capture(db, user, semester)
    assert client.patch(f"{URL}/{capture.id}", headers=auth, json={}).status_code == 422


# ---------- 삭제 ----------


def test_delete_removes_cards_and_files(client, auth, db, semester):
    capture_id = upload(client, auth).json()["id"]
    capture = db.get(Capture, uuid.UUID(capture_id))
    make_card(db, capture, 1)
    folder = storage.path(capture_dir(capture.id))
    assert folder.is_dir()

    response = client.delete(f"{URL}/{capture_id}", headers=auth)
    assert response.status_code == 204
    db.expire_all()
    assert db.get(Capture, capture.id) is None
    assert db.scalar(select(func.count()).select_from(Card)) == 0
    assert not folder.exists()


# ---------- 사진 ----------


def test_get_original_and_rectified_image(client, auth, db, semester):
    capture_id = upload(client, auth).json()["id"]
    url = f"{URL}/{capture_id}/image"

    response = client.get(url, headers=auth)
    assert response.status_code == 200
    assert response.headers["content-type"] == "image/jpeg"
    assert response.content == jpeg()

    # 처리 전에는 보정본이 없다
    assert client.get(url, headers=auth, params={"kind": "rectified"}).status_code == 404

    capture = db.get(Capture, uuid.UUID(capture_id))
    capture.rectified_key = rectified_key(capture.id)
    capture.status = CaptureStatus.done
    storage.save(capture.rectified_key, b"rectified")
    db.flush()
    response = client.get(url, headers=auth, params={"kind": "rectified"})
    assert response.content == b"rectified"


# ---------- 저장소 ----------


def test_storage_rejects_keys_outside_media_dir():
    with pytest.raises(ValueError):
        storage.path("../secret")
    with pytest.raises(ValueError):
        storage.path("")


# ---------- 처리 줄 ----------


def test_upload_enqueues_once_even_when_resent(client, auth, semester, enqueued):
    """처음 받은 사진만 처리 줄에 선다. 다시 보낸 사진은 이미 줄에 있다"""
    capture_id = str(uuid.uuid4())
    upload(client, auth, {"id": capture_id})
    upload(client, auth, {"id": capture_id})
    assert enqueued == [(capture_id, False)]


def test_rejected_upload_is_not_enqueued(client, auth, semester, enqueued):
    upload(client, auth, image=b"", content_type="image/jpeg")
    assert enqueued == []


# ---------- 다시 처리 ----------


def test_retry_failed_capture(client, auth, db, user, semester, enqueued):
    capture = make_capture(db, user, semester, status=CaptureStatus.failed, fail_reason="rectify")
    response = client.post(f"{URL}/{capture.id}/retry", headers=auth, json={"skip_rectify": True})
    assert response.status_code == 202
    body = response.json()
    assert (body["status"], body["fail_reason"]) == ("uploaded", None)
    assert enqueued == [(str(capture.id), True)]


def test_retry_without_body_does_not_skip_rectify(client, auth, db, user, semester, enqueued):
    capture = make_capture(db, user, semester, status=CaptureStatus.failed, fail_reason="segment")
    assert client.post(f"{URL}/{capture.id}/retry", headers=auth).status_code == 202
    assert enqueued == [(str(capture.id), False)]


@pytest.mark.parametrize("status", [CaptureStatus.done, CaptureStatus.segmenting])
def test_retry_only_failed_capture(client, auth, db, user, semester, enqueued, status):
    capture = make_capture(db, user, semester, status=status)
    response = client.post(f"{URL}/{capture.id}/retry", headers=auth)
    assert response.status_code == 409
    assert enqueued == []


def test_retry_others_capture_is_404(client, auth, db):
    stranger = make_user(db)
    theirs = make_capture(db, stranger, make_semester(db, stranger), status=CaptureStatus.failed)
    assert client.post(f"{URL}/{theirs.id}/retry", headers=auth).status_code == 404


# ---------- 저장 위치 미리보기 ----------


def destination(client, auth, at):
    response = client.get(f"{URL}/destination", headers=auth, params={"at": at.isoformat()})
    assert response.status_code == 200
    return response.json()


def test_destination_during_class(client, auth, subject):
    assert destination(client, auth, IN_CLASS) == {
        "semester_id": str(subject.semester_id),
        "subject_id": str(subject.id),
        "subject_name": "자료구조",
    }


def test_destination_outside_class_is_unsorted(client, auth, semester, subject):
    body = destination(client, auth, IN_CLASS.replace(hour=20))
    assert body == {"semester_id": str(semester.id), "subject_id": None, "subject_name": None}


def test_destination_without_semester_does_not_create_one(client, auth, db):
    body = destination(client, auth, IN_CLASS)
    assert body == {"semester_id": None, "subject_id": None, "subject_name": None}
    assert db.scalar(select(func.count()).select_from(Semester)) == 0


def test_destination_matches_upload(client, auth, subject):
    """미리 보여 준 곳과 실제로 저장되는 곳이 같다"""
    for at in (IN_CLASS, IN_CLASS.replace(hour=20)):
        preview = destination(client, auth, at)
        saved = upload(client, auth, {"taken_at": at.isoformat()}).json()
        assert saved["subject_id"] == preview["subject_id"]
        assert saved["semester_id"] == preview["semester_id"]


def test_destination_without_at_uses_now(client, auth, semester):
    response = client.get(f"{URL}/destination", headers=auth)
    assert response.status_code == 200
    assert response.json()["semester_id"] == str(semester.id)
