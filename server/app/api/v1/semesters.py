"""학기 API (+ 학기 안에 과목 추가 · 시간표 저장)."""

import uuid

from fastapi import APIRouter
from sqlalchemy import select

from app.api.deps import DbDep, UserDep, WriteUserDep
from app.models import Semester, Subject
from app.schemas.semester import (
    SemesterCreate,
    SemesterDetail,
    SemesterOut,
    SubjectIn,
    SubjectOut,
    SuggestedSemester,
    TermTimetableSave,
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
def create_semester(body: SemesterCreate, db: DbDep, user: WriteUserDep):
    semester = service.create_semester(db, user, body.year, body.term, body.make_current)
    db.commit()
    return service.semester_detail(db, service.get_semester(db, user, semester.id))


# 아래 세 경로(/suggested · /timetable · /current)는 /{semester_id}보다 먼저 둬야 id로 읽히지 않는다
@router.get("/suggested", response_model=SuggestedSemester)
def suggested(user: UserDep):
    """오늘 날짜 기준 기본 학기. 앱 학기 선택 휠의 처음 값으로 쓴다

    3~6월 1학기 · 7~8월 여름학기 · 9~12월 2학기 · 1~2월 지난해 겨울학기 (판서 자동 분류와 같은 규칙)
    """
    year, term = service.term_of(service.today())
    return SuggestedSemester(year=year, term=term, label=service.label(year, term))


@router.put("/timetable", response_model=SemesterDetail)
def save_term_timetable(body: TermTimetableSave, db: DbDep, user: WriteUserDep):
    """고른 학기로 "이대로 저장" (가입 후 첫 등록 · 새 학기 추가). 학기가 없으면 만든다

    학기 만들기 · 현재 학기 지정 · 과목 저장을 한 번에 해서, 중간에 실패해도 빈 학기가 남지 않고
    같은 요청을 다시 보내도 학기가 두 개 생기지 않는다. 과목 저장 규칙은 학기 id로 저장할 때와 같다.
    """
    semester = service.save_timetable_for_term(
        db, user, body.year, body.term, body.subjects, body.make_current
    )
    db.commit()
    return service.semester_detail(db, service.get_semester(db, user, semester.id))


@router.get("/current", response_model=SemesterDetail)
def get_current(db: DbDep, user: UserDep):
    """현재 학기와 과목 · 시간표. 없으면 404 (앱은 시간표 등록 화면으로)"""
    return service.semester_detail(db, service.get_current_semester(db, user))


@router.get("/{semester_id}", response_model=SemesterDetail)
def get_semester(semester_id: uuid.UUID, db: DbDep, user: UserDep):
    return service.semester_detail(db, service.get_semester(db, user, semester_id))


@router.put("/{semester_id}/current", response_model=SemesterOut)
def set_current(semester_id: uuid.UUID, db: DbDep, user: WriteUserDep):
    """이 학기를 현재 학기로. 기존 현재 학기는 지난 학기가 된다"""
    semester = service.get_semester(db, user, semester_id)
    service.set_current(db, user, semester)
    db.commit()
    (out,) = service.semester_outs(db, [semester])
    return out


@router.delete("/{semester_id}", status_code=204)
def delete_semester(semester_id: uuid.UUID, db: DbDep, user: WriteUserDep):
    """학기 삭제. 그 학기 과목 · 판서 · 카드와 판서 사진 · 카드 이미지 파일도 같이 지워진다"""
    service.delete_semester(db, service.get_semester(db, user, semester_id))


@router.put("/{semester_id}/timetable", response_model=SemesterDetail)
def save_timetable(semester_id: uuid.UUID, body: TimetableSave, db: DbDep, user: WriteUserDep):
    """시간표 확인 화면의 "이대로 저장". 보낸 목록이 그 학기 과목 전체가 된다

    이름이 같은 과목은 유지(판서도 유지)하고, 빠진 과목은 지운다(판서는 미분류함으로).
    """
    semester = service.get_semester(db, user, semester_id)
    service.save_timetable(db, semester, body.subjects)
    db.commit()
    return service.semester_detail(db, service.get_semester(db, user, semester_id))


@router.post("/{semester_id}/subjects", response_model=SubjectOut, status_code=201)
def create_subject(semester_id: uuid.UUID, body: SubjectIn, db: DbDep, user: WriteUserDep):
    semester = service.get_semester(db, user, semester_id)
    service.ensure_unique_name(semester, body.name)
    subject = Subject(name=body.name, slots=service.to_slot_rows(body.slots))
    semester.subjects.append(subject)
    db.commit()
    (out,) = service.subject_outs(db, [subject])
    return out
