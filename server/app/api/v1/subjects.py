"""과목 API (조회 · 수정 · 삭제). 과목 추가는 학기 아래(POST /semesters/{id}/subjects)."""

import uuid

from fastapi import APIRouter

from app.api.deps import DbDep, UserDep, WriteUserDep
from app.schemas.semester import SubjectOut, SubjectUpdate
from app.services import semesters as service

router = APIRouter(prefix="/subjects", tags=["subjects"])


@router.get("/{subject_id}", response_model=SubjectOut)
def get_subject(subject_id: uuid.UUID, db: DbDep, user: UserDep):
    (out,) = service.subject_outs(db, [service.get_subject(db, user, subject_id)])
    return out


@router.patch("/{subject_id}", response_model=SubjectOut)
def update_subject(subject_id: uuid.UUID, body: SubjectUpdate, db: DbDep, user: WriteUserDep):
    """이름 · 시간 칸 수정. 보낸 것만 바꾼다"""
    subject = service.get_subject(db, user, subject_id)
    if body.name is not None and body.name != subject.name:
        service.ensure_unique_name(subject.semester, body.name, except_id=subject.id)
        subject.name = body.name
    if body.slots is not None:
        subject.slots = service.to_slot_rows(body.slots)
    db.commit()
    (out,) = service.subject_outs(db, [subject])
    return out


@router.delete("/{subject_id}", status_code=204)
def delete_subject(subject_id: uuid.UUID, db: DbDep, user: WriteUserDep):
    """과목 삭제. 그 과목 판서는 지우지 않고 미분류함으로 보낸다"""
    db.delete(service.get_subject(db, user, subject_id))
    db.commit()
