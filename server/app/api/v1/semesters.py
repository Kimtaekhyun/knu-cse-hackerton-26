"""학기 API (+ 학기 안에 과목 추가 · 시간표 저장)."""

import uuid

from fastapi import APIRouter
from sqlalchemy import select

from app.api.deps import DbDep, UserDep
from app.models import Semester, Subject
from app.schemas.semester import (
    SemesterCreate,
    SemesterDetail,
    SemesterOut,
    SubjectIn,
    SubjectOut,
    TimetableSave,
)
from app.services import semesters as service

router = APIRouter(prefix="/semesters", tags=["semesters"])


@router.get("", response_model=list[SemesterOut])
def list_semesters(db: DbDep, user: UserDep):
    """전체 학기. 최근 학기부터"""
    rows = db.scalars(
        select(Semester)
        .where(Semester.user_id == user.id)
        .order_by(Semester.year.desc(), Semester.term.desc())
    ).all()
    return service.semester_outs(db, list(rows))


@router.post("", response_model=SemesterDetail, status_code=201)
def create_semester(body: SemesterCreate, db: DbDep, user: UserDep):
    semester = service.create_semester(db, user, body.year, body.term, body.make_current)
    db.commit()
    return service.semester_detail(db, service.get_semester(db, user, semester.id))


# /{semester_id}보다 먼저 둬야 "current"가 id로 읽히지 않는다
@router.get("/current", response_model=SemesterDetail)
def get_current(db: DbDep, user: UserDep):
    """현재 학기와 과목 · 시간표. 없으면 404 (앱은 시간표 등록 화면으로)"""
    return service.semester_detail(db, service.get_current_semester(db, user))


@router.get("/{semester_id}", response_model=SemesterDetail)
def get_semester(semester_id: uuid.UUID, db: DbDep, user: UserDep):
    return service.semester_detail(db, service.get_semester(db, user, semester_id))


@router.put("/{semester_id}/current", response_model=SemesterOut)
def set_current(semester_id: uuid.UUID, db: DbDep, user: UserDep):
    """이 학기를 현재 학기로. 기존 현재 학기는 지난 학기가 된다"""
    semester = service.get_semester(db, user, semester_id)
    service.set_current(db, user, semester)
    db.commit()
    (out,) = service.semester_outs(db, [semester])
    return out


@router.delete("/{semester_id}", status_code=204)
def delete_semester(semester_id: uuid.UUID, db: DbDep, user: UserDep):
    """학기 삭제. 그 학기 과목 · 판서 · 카드도 같이 지워진다"""
    db.delete(service.get_semester(db, user, semester_id))
    db.commit()


@router.put("/{semester_id}/timetable", response_model=SemesterDetail)
def save_timetable(semester_id: uuid.UUID, body: TimetableSave, db: DbDep, user: UserDep):
    """시간표 확인 화면의 "이대로 저장". 보낸 목록이 그 학기 과목 전체가 된다

    이름이 같은 과목은 유지(판서도 유지)하고, 빠진 과목은 지운다(판서는 미분류함으로).
    """
    semester = service.get_semester(db, user, semester_id)
    service.save_timetable(db, semester, body.subjects)
    db.commit()
    return service.semester_detail(db, service.get_semester(db, user, semester_id))


@router.post("/{semester_id}/subjects", response_model=SubjectOut, status_code=201)
def create_subject(semester_id: uuid.UUID, body: SubjectIn, db: DbDep, user: UserDep):
    semester = service.get_semester(db, user, semester_id)
    service.ensure_unique_name(semester, body.name)
    subject = Subject(name=body.name, slots=service.to_slot_rows(body.slots))
    semester.subjects.append(subject)
    db.commit()
    (out,) = service.subject_outs(db, [subject])
    return out
