"""DB 테스트용 데이터 만들기 도우미. 만들 때마다 flush해서 id가 바로 채워진다."""

from datetime import UTC, datetime, time
from uuid import uuid4

from app.models import (
    AuthProvider,
    Capture,
    CaptureStatus,
    Card,
    CardType,
    Semester,
    SemesterTerm,
    Subject,
    SubjectSlot,
    User,
)


def _save(db, row):
    db.add(row)
    db.flush()
    return row


def make_user(db, **kw) -> User:
    values = {"provider": AuthProvider.email, "provider_uid": f"{uuid4()}@test", "name": "테스트"}
    return _save(db, User(**(values | kw)))


def make_semester(db, user, **kw) -> Semester:
    values = {"year": 2026, "term": SemesterTerm.second, "is_current": True}
    return _save(db, Semester(user_id=user.id, **(values | kw)))


def make_subject(db, semester, name="자료구조") -> Subject:
    return _save(db, Subject(semester_id=semester.id, name=name))


def make_slot(db, subject, weekday: int, start: str, end: str) -> SubjectSlot:
    return _save(
        db,
        SubjectSlot(
            subject_id=subject.id,
            weekday=weekday,
            start_time=time.fromisoformat(start),
            end_time=time.fromisoformat(end),
        ),
    )


def make_capture(db, user, semester, subject=None, **kw) -> Capture:
    values = {
        "status": CaptureStatus.done,
        "taken_at": datetime(2026, 11, 18, 3, 0, tzinfo=UTC),
        "original_key": f"captures/{uuid4()}.jpg",
    }
    return _save(
        db,
        Capture(
            user_id=user.id,
            semester_id=semester.id,
            subject_id=subject.id if subject else None,
            **(values | kw),
        ),
    )


def make_card(db, capture, order_no: int, **kw) -> Card:
    values = {
        "title": f"카드 {order_no}",
        "card_type": CardType.text,
        "content": "내용",
        "original_content": "내용",
        "bbox": {"x": 0.1, "y": 0.1, "w": 0.2, "h": 0.2},
        "crop_image_key": f"cards/{uuid4()}.png",
        "is_moved": False,
    }
    return _save(db, Card(capture_id=capture.id, order_no=order_no, **(values | kw)))
