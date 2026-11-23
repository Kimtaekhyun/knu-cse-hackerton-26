"""학기 · 과목 저장 규칙과 응답 만들기.

라우터(app/api/v1/semesters.py, subjects.py)는 요청 확인만 하고 실제 처리는 여기서 한다.
"""

import uuid
from collections.abc import Iterable
from datetime import date, datetime, time

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
from app.services.queries import SEOUL

TERM_LABELS = {
    SemesterTerm.first: "1학기",
    SemesterTerm.summer: "여름학기",
    SemesterTerm.second: "2학기",
    SemesterTerm.winter: "겨울학기",
}


def label(year: int, term: SemesterTerm) -> str:
    """화면에 보여 줄 학기 이름 (예: "2026년 2학기")"""
    return f"{year}년 {TERM_LABELS[term]}"


# ---------- 날짜로 학기 정하기 ----------


def today() -> date:
    """오늘(서울 날짜). 테스트에서 날짜를 정할 때 바꿔 끼운다"""
    return datetime.now(SEOUL).date()


def term_of(day: date) -> tuple[int, SemesterTerm]:
    """날짜가 속한 (학년도, 학기). 1 · 2월은 지난해 겨울학기다

    3~6월 1학기 · 7~8월 여름학기 · 9~12월 2학기 · 다음 해 1~2월 겨울학기.
    앱 학기 선택 휠의 처음 값(GET /semesters/suggested)과 판서 자동 분류가 같은 규칙을 쓴다.
    """
    if day.month <= 2:
        return day.year - 1, SemesterTerm.winter
    if day.month <= 6:
        return day.year, SemesterTerm.first
    if day.month <= 8:
        return day.year, SemesterTerm.summer
    return day.year, SemesterTerm.second


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


def semester_exists(db: Session, user: User, year: int, term: SemesterTerm) -> bool:
    return (
        db.scalar(
            select(Semester.id).where(
                Semester.user_id == user.id, Semester.year == year, Semester.term == term
            )
        )
        is not None
    )


def create_semester(
    db: Session, user: User, year: int, term: SemesterTerm, make_current: bool
) -> Semester:
    if semester_exists(db, user, year, term):
        # 학기 이름이 모두 모음(…학기)으로 끝나서 조사는 "는"
        raise HTTPException(409, f"{label(year, term)}는 이미 있어요.")
    semester = Semester(user_id=user.id, year=year, term=term, is_current=False)
    db.add(semester)
    db.flush()
    if make_current:
        set_current(db, user, semester)
    return semester


def _find_or_create(db: Session, user: User, year: int, term: SemesterTerm) -> Semester:
    """(year, term) 학기. 없으면 만든다 (현재 학기 지정은 부르는 쪽에서)"""
    semester = db.scalars(
        select(Semester)
        .where(Semester.user_id == user.id, Semester.year == year, Semester.term == term)
        .options(selectinload(Semester.subjects).selectinload(Subject.slots))
    ).first()
    if semester is None:
        semester = Semester(user_id=user.id, year=year, term=term, is_current=False, subjects=[])
        db.add(semester)
        db.flush()
    return semester


def ensure_current_semester(db: Session, user: User, day: date) -> uuid.UUID:
    """현재 학기 id. 없으면 day가 속한 학기를 현재 학기로 만든다

    시간표 등록을 "나중에 할게요"로 건너뛴 사용자는 학기가 하나도 없다.
    판서는 학기가 꼭 있어야 저장되므로, 그대로 두면 찍은 사진을 거절하게 된다.
    같은 학기가 이미 있으면(현재 학기만 해제된 경우) 새로 만들지 않고 그 학기를 현재로 지정한다.
    시간표가 없으니 이렇게 저장한 판서는 미분류함으로 간다.
    """
    current = db.scalar(select(Semester.id).where(Semester.user_id == user.id, Semester.is_current))
    if current is not None:
        return current
    semester = _find_or_create(db, user, *term_of(day))
    set_current(db, user, semester)
    return semester.id


def save_timetable_for_term(
    db: Session,
    user: User,
    year: int,
    term: SemesterTerm,
    subjects: list[SubjectIn],
    make_current: bool,
) -> Semester:
    """고른 학기에 시간표를 저장한다. 학기가 없으면 만든다 (가입 후 첫 등록 · 새 학기 추가)

    학기 만들기 · 현재 학기 지정 · 과목 저장이 같은 트랜잭션이라,
    중간에 실패하면 아무것도 남지 않는다.
    같은 요청을 다시 보내도 결과가 같다 (학기가 두 개 생기지 않고 409도 나지 않는다).
    """
    semester = _find_or_create(db, user, year, term)
    if make_current:
        set_current(db, user, semester)
    save_timetable(db, semester, subjects)
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
    - 같은 학기 같은 이름 과목은 DB 제약으로 하나뿐이다 (예전 중복은 마이그레이션 0003이 정리)
    """
    merged: dict[str, list[Slot]] = {}
    for item in subjects:
        merged.setdefault(item.name, []).extend(item.slots)

    kept: dict[str, Subject] = {subject.name: subject for subject in semester.subjects}

    for name, slots in merged.items():
        subject = kept.pop(name, None)
        if subject is None:
            subject = Subject(name=name)
            semester.subjects.append(subject)
        subject.slots = to_slot_rows(slots)
    for removed in kept.values():
        semester.subjects.remove(removed)
    db.flush()


def delete_semester(db: Session, semester: Semester) -> None:
    """학기 삭제. 과목 · 판서 · 카드 행은 DB의 ON DELETE CASCADE로 같이 지워진다.

    판서 파일(원본 · 보정본 · 카드 조각)은 DB가 지워 주지 않으므로, 지우기 전에 판서 id를 모아 두고
    커밋한 뒤 판서마다 폴더째 지운다. 판서 삭제(captures.delete_capture)와 같은 순서
    (DB 먼저, 파일 나중)라 커밋이 실패해도 "사진 파일이 없는 판서"가 남지 않는다.

    처리 중인 판서가 있어도 괜찮다: 워커는 판서 행이 없어지면 finish · mark_failed에서
    그사이 만든 파일까지 폴더째 지우고 끝낸다.
    """
    # captures가 이 모듈을 불러 쓰므로(순환 import) 여기서 불러온다
    from app.services.captures import capture_dir
    from app.storage import local as storage

    capture_ids = db.scalars(select(Capture.id).where(Capture.semester_id == semester.id)).all()
    db.delete(semester)
    db.commit()
    for capture_id in capture_ids:
        storage.delete_tree(capture_dir(capture_id))


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
            label=label(s.year, s.term),
            is_current=s.is_current,
            subject_count=subject_counts.get(s.id, 0),
            capture_count=capture_counts.get(s.id, 0),
        )
        for s in semesters
    ]


def semester_detail(db: Session, semester: Semester) -> SemesterDetail:
    (base,) = semester_outs(db, [semester])
    return SemesterDetail(**base.model_dump(), subjects=subject_outs(db, semester.subjects))
