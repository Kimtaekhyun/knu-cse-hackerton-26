"""학기 · 과목 저장 규칙과 응답 만들기.

라우터(app/api/v1/semesters.py, subjects.py)는 요청 확인만 하고 실제 처리는 여기서 한다.
"""

import uuid
from collections.abc import Iterable
from datetime import time

from fastapi import HTTPException
from sqlalchemy import func, select, update
from sqlalchemy.orm import Session, selectinload

from app.models import (
    Capture,
    CaptureStatus,
    Semester,
    SemesterTerm,
    Subject,
    SubjectSlot,
    User,
)
from app.schemas.semester import (
    SemesterDetail,
    SemesterOut,
    Slot,
    SubjectIn,
    SubjectOut,
)

TERM_LABELS = {
    SemesterTerm.first: "1학기",
    SemesterTerm.summer: "여름학기",
    SemesterTerm.second: "2학기",
    SemesterTerm.winter: "겨울학기",
}


# ---------- 찾기 (남의 것은 없는 것으로 본다: 404) ----------


def get_semester(db: Session, user: User, semester_id: uuid.UUID) -> Semester:
    semester = db.scalars(
        select(Semester)
        .where(Semester.id == semester_id, Semester.user_id == user.id)
        .options(selectinload(Semester.subjects).selectinload(Subject.slots))
    ).first()
    if semester is None:
        raise HTTPException(404, "학기를 찾을 수 없어요.")
    return semester


def get_current_semester(db: Session, user: User) -> Semester:
    semester = db.scalars(
        select(Semester)
        .where(Semester.user_id == user.id, Semester.is_current)
        .options(selectinload(Semester.subjects).selectinload(Subject.slots))
    ).first()
    if semester is None:
        raise HTTPException(404, "현재 학기가 없어요.")
    return semester


def get_subject(db: Session, user: User, subject_id: uuid.UUID) -> Subject:
    subject = db.scalars(
        select(Subject)
        .join(Semester, Subject.semester_id == Semester.id)
        .where(Subject.id == subject_id, Semester.user_id == user.id)
        .options(selectinload(Subject.slots))
    ).first()
    if subject is None:
        raise HTTPException(404, "과목을 찾을 수 없어요.")
    return subject


# ---------- 바꾸기 ----------


def set_current(db: Session, user: User, semester: Semester) -> None:
    """현재 학기를 바꾼다.

    "사용자당 현재 학기 하나" 부분 인덱스는 행마다 바로 검사하므로
    기존 현재 학기를 먼저 해제(UPDATE 실행)한 다음 새 학기를 지정해야 한다.
    """
    db.execute(
        update(Semester)
        .where(Semester.user_id == user.id, Semester.is_current, Semester.id != semester.id)
        .values(is_current=False)
    )
    semester.is_current = True
    db.flush()


def create_semester(
    db: Session, user: User, year: int, term: SemesterTerm, make_current: bool
) -> Semester:
    exists = db.scalar(
        select(Semester.id).where(
            Semester.user_id == user.id, Semester.year == year, Semester.term == term
        )
    )
    if exists:
        raise HTTPException(409, f"{year}년 {TERM_LABELS[term]}은 이미 있어요.")
    semester = Semester(user_id=user.id, year=year, term=term, is_current=False)
    db.add(semester)
    db.flush()
    if make_current:
        set_current(db, user, semester)
    return semester


def ensure_unique_name(semester: Semester, name: str, except_id: uuid.UUID | None = None) -> None:
    if any(s.name == name and s.id != except_id for s in semester.subjects):
        raise HTTPException(409, f"'{name}' 과목이 이미 있어요.")


def to_slot_rows(slots: Iterable[Slot]) -> list[SubjectSlot]:
    """같은 칸이 두 번 오면 하나만 남긴다"""
    unique = {(s.weekday, s.start, s.end) for s in slots}
    return [
        SubjectSlot(weekday=w, start_time=time.fromisoformat(a), end_time=time.fromisoformat(b))
        for w, a, b in sorted(unique)
    ]


def save_timetable(db: Session, semester: Semester, subjects: list[SubjectIn]) -> None:
    """시간표 저장. 목록이 그 학기 과목 전체가 된다.

    - 이름이 같은 과목은 그대로 두고 시간 칸만 바꾼다 (그 과목 판서가 유지되도록)
    - 목록에 없는 과목은 지운다. 그 과목 판서는 미분류함으로 간다 (DB의 SET NULL)
    - 목록 안에서 이름이 겹치면 시간 칸을 합친다 (인식 결과가 과목을 둘로 나눈 경우)
    """
    merged: dict[str, list[Slot]] = {}
    for item in subjects:
        merged.setdefault(item.name, []).extend(item.slots)

    existing = {s.name: s for s in semester.subjects}
    for name, slots in merged.items():
        subject = existing.pop(name, None)
        if subject is None:
            subject = Subject(name=name)
            semester.subjects.append(subject)
        subject.slots = to_slot_rows(slots)
    for removed in existing.values():
        semester.subjects.remove(removed)
    db.flush()


# ---------- 응답 ----------


def _subject_counts(db: Session, semester_ids: list[uuid.UUID]) -> dict[uuid.UUID, int]:
    rows = db.execute(
        select(Subject.semester_id, func.count())
        .where(Subject.semester_id.in_(semester_ids))
        .group_by(Subject.semester_id)
    ).all()
    return dict(rows)


def _capture_counts(db: Session, column, ids: list[uuid.UUID]) -> dict[uuid.UUID, int]:
    """처리가 끝난 판서 수 (queries.subject_capture_count와 같은 기준)"""
    rows = db.execute(
        select(column, func.count())
        .where(column.in_(ids), Capture.status == CaptureStatus.done)
        .group_by(column)
    ).all()
    return dict(rows)


def _slot_key(slot: SubjectSlot):
    return (slot.weekday, slot.start_time)


def subject_outs(db: Session, subjects: list[Subject]) -> list[SubjectOut]:
    """수업이 이른 과목부터, 시간이 없는 과목(사이버강의 등)은 맨 뒤"""
    counts = _capture_counts(db, Capture.subject_id, [s.id for s in subjects])

    def order(subject: Subject):
        first = min(map(_slot_key, subject.slots), default=None)
        return (first is None, first or (0, time()), subject.name)

    return [
        SubjectOut(
            id=s.id,
            semester_id=s.semester_id,
            name=s.name,
            slots=[
                Slot(
                    weekday=slot.weekday,
                    start=slot.start_time.strftime("%H:%M"),
                    end=slot.end_time.strftime("%H:%M"),
                )
                for slot in sorted(s.slots, key=_slot_key)
            ],
            capture_count=counts.get(s.id, 0),
        )
        for s in sorted(subjects, key=order)
    ]


def semester_outs(db: Session, semesters: list[Semester]) -> list[SemesterOut]:
    ids = [s.id for s in semesters]
    subject_counts = _subject_counts(db, ids)
    capture_counts = _capture_counts(db, Capture.semester_id, ids)
    return [
        SemesterOut(
            id=s.id,
            year=s.year,
            term=s.term,
            label=f"{s.year}년 {TERM_LABELS[s.term]}",
            is_current=s.is_current,
            subject_count=subject_counts.get(s.id, 0),
            capture_count=capture_counts.get(s.id, 0),
        )
        for s in semesters
    ]


def semester_detail(db: Session, semester: Semester) -> SemesterDetail:
    (base,) = semester_outs(db, [semester])
    return SemesterDetail(**base.model_dump(), subjects=subject_outs(db, semester.subjects))
