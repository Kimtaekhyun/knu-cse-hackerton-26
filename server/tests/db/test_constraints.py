"""스키마 제약 · 삭제 규칙이 DB에서 실제로 동작하는지.

삭제는 DB의 ON DELETE 규칙으로 일어나야 하므로 ORM cascade가 아니라 SQL delete로 지운다.
"""

import pytest
from sqlalchemy import delete, func, select
from sqlalchemy.exc import IntegrityError

from app.models import Capture, Card, Semester, Subject, SubjectSlot, User, UserSettings
from tests.db.factories import (
    make_capture,
    make_card,
    make_semester,
    make_slot,
    make_subject,
    make_user,
)


def count(db, model, **where) -> int:
    query = select(func.count()).select_from(model)
    for column, value in where.items():
        query = query.where(getattr(model, column) == value)
    return db.scalar(query)


def test_only_one_current_semester(db):
    user = make_user(db)
    make_semester(db, user, year=2026, is_current=True)
    with pytest.raises(IntegrityError):
        make_semester(db, user, year=2025, is_current=True)


def test_duplicate_semester_rejected(db):
    user = make_user(db)
    make_semester(db, user, is_current=False)
    with pytest.raises(IntegrityError):
        make_semester(db, user, is_current=False)


def test_delete_capture_deletes_cards(db):
    user = make_user(db)
    capture = make_capture(db, user, make_semester(db, user))
    make_card(db, capture, 1)
    make_card(db, capture, 2)
    db.execute(delete(Capture).where(Capture.id == capture.id))
    assert count(db, Card, capture_id=capture.id) == 0


def test_delete_subject_moves_captures_to_unsorted(db):
    user = make_user(db)
    semester = make_semester(db, user)
    subject = make_subject(db, semester)
    capture = make_capture(db, user, semester, subject)
    db.execute(delete(Subject).where(Subject.id == subject.id))
    db.expire_all()
    assert db.get(Capture, capture.id).subject_id is None


def test_delete_user_removes_everything(db):
    user = make_user(db)
    db.add(UserSettings(user_id=user.id))
    semester = make_semester(db, user)
    subject = make_subject(db, semester)
    make_slot(db, subject, 1, "13:30", "15:00")
    capture = make_capture(db, user, semester, subject)
    make_card(db, capture, 1)
    db.flush()
    # 지운 뒤에는 객체를 다시 읽을 수 없으므로 id를 먼저 꺼내 둔다
    user_id, semester_id, subject_id, capture_id = user.id, semester.id, subject.id, capture.id

    db.execute(delete(User).where(User.id == user_id))
    db.expire_all()
    assert count(db, UserSettings, user_id=user_id) == 0
    assert count(db, Semester, user_id=user_id) == 0
    assert count(db, Subject, semester_id=semester_id) == 0
    assert count(db, SubjectSlot, subject_id=subject_id) == 0
    assert count(db, Capture, user_id=user_id) == 0
    assert count(db, Card, capture_id=capture_id) == 0


def test_slot_weekday_checked(db):
    subject = make_subject(db, make_semester(db, make_user(db)))
    with pytest.raises(IntegrityError):
        make_slot(db, subject, 7, "09:00", "10:00")


def test_slot_time_order_checked(db):
    subject = make_subject(db, make_semester(db, make_user(db)))
    with pytest.raises(IntegrityError):
        make_slot(db, subject, 1, "12:00", "11:00")


def test_new_user_settings_defaults(db):
    user = make_user(db)
    db.add(UserSettings(user_id=user.id))
    db.flush()
    db.expire_all()
    settings = db.get(UserSettings, user.id)
    assert settings.notify_unmoved is True
    assert settings.notify_exam is True


# ── ORM으로 지울 때 (API는 보통 db.delete(obj)를 쓴다) ──


def test_orm_delete_user_removes_everything(db):
    user = make_user(db)
    db.add(UserSettings(user_id=user.id))
    semester = make_semester(db, user)
    subject = make_subject(db, semester)
    make_slot(db, subject, 1, "13:30", "15:00")
    capture = make_capture(db, user, semester, subject)
    make_card(db, capture, 1)
    db.flush()
    db.refresh(user)  # settings 관계를 불러온 상태에서 지운다
    user_id, capture_id = user.id, capture.id

    db.delete(user)
    db.flush()
    db.expire_all()
    assert count(db, UserSettings, user_id=user_id) == 0
    assert count(db, Capture, user_id=user_id) == 0
    assert count(db, Card, capture_id=capture_id) == 0


def test_orm_delete_capture_deletes_cards(db):
    user = make_user(db)
    capture = make_capture(db, user, make_semester(db, user))
    make_card(db, capture, 1)
    capture_id = capture.id
    db.refresh(capture)

    db.delete(capture)
    db.flush()
    assert count(db, Card, capture_id=capture_id) == 0


def test_orm_delete_subject_keeps_captures_unsorted(db):
    user = make_user(db)
    semester = make_semester(db, user)
    subject = make_subject(db, semester)
    make_slot(db, subject, 1, "13:30", "15:00")
    capture = make_capture(db, user, semester, subject)
    subject_id = subject.id
    db.refresh(subject)

    db.delete(subject)
    db.flush()
    db.expire_all()
    assert count(db, SubjectSlot, subject_id=subject_id) == 0
    assert db.get(Capture, capture.id).subject_id is None


def test_orm_delete_semester_removes_subjects(db):
    user = make_user(db)
    semester = make_semester(db, user)
    make_subject(db, semester)
    semester_id = semester.id
    db.refresh(semester)

    db.delete(semester)
    db.flush()
    assert count(db, Subject, semester_id=semester_id) == 0


def test_duplicate_subject_name_rejected(db):
    semester = make_semester(db, make_user(db))
    make_subject(db, semester, name="자료구조")
    with pytest.raises(IntegrityError):
        make_subject(db, semester, name="자료구조")


def test_same_subject_name_allowed_in_other_semester(db):
    user = make_user(db)
    make_subject(db, make_semester(db, user, year=2026), name="자료구조")
    make_subject(db, make_semester(db, user, year=2025, is_current=False), name="자료구조")
