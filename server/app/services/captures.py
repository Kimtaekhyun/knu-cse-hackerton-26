"""판서(캡처) 저장 규칙과 응답 만들기.

라우터(app/api/v1/captures.py)는 요청 확인만 하고 실제 처리는 여기서 한다.

사진을 잃지 않기 위한 순서:
1. 원본을 디스크에 끝까지 쓴다 (storage.save)
2. DB에 판서 행을 커밋한다
3. 그다음에야 "받았다"(202)고 답한다
→ 앱이 202를 받은 사진은 서버가 꺼져도 남아 있다. 202를 못 받았으면 앱이 같은 id로 다시 보낸다.
"""

import uuid
from datetime import date, datetime

from fastapi import HTTPException
from sqlalchemy import exists, func, select
from sqlalchemy.orm import Session

from app.models import Capture, CaptureStatus, Card, Semester, SemesterTerm, User
from app.schemas.capture import CaptureDetail, CaptureOut, CardOut, Destination
from app.services import queries
from app.services.semesters import get_subject, set_current
from app.storage import local as storage

SEOUL = queries.SEOUL


# ---------- 저장소 키 (판서 하나의 파일은 한 폴더에 모아서 지울 때 폴더째 지운다) ----------


def capture_dir(capture_id: uuid.UUID) -> str:
    return f"captures/{capture_id}"


def original_key(capture_id: uuid.UUID, extension: str) -> str:
    return f"{capture_dir(capture_id)}/original.{extension}"


def rectified_key(capture_id: uuid.UUID) -> str:
    return f"{capture_dir(capture_id)}/rectified.jpg"


def card_crop_key(capture_id: uuid.UUID, card_id: uuid.UUID) -> str:
    return f"{capture_dir(capture_id)}/cards/{card_id}.png"


# ---------- 찾기 (남의 것은 없는 것으로 본다: 404) ----------


def get_capture(db: Session, user: User, capture_id: uuid.UUID) -> Capture:
    capture = db.scalars(
        select(Capture).where(Capture.id == capture_id, Capture.user_id == user.id)
    ).first()
    if capture is None:
        raise HTTPException(404, "판서를 찾을 수 없어요.")
    return capture


def find_resent(db: Session, user: User, capture_id: uuid.UUID) -> Capture | None:
    """앱이 같은 id로 다시 보낸 판서. 처음 요청은 저장됐는데 답만 못 받은 경우다

    다른 사용자가 이미 쓴 id면 409 (앱이 만든 UUID라 우연히 겹칠 일은 없다).
    """
    capture = db.get(Capture, capture_id)
    if capture is not None and capture.user_id != user.id:
        raise HTTPException(
            409, "이미 쓰인 판서 id예요."
        )  # 다른 사용지의 id면 남의 판서를 보게되는것.
    return capture


# ---------- 만들기 · 바꾸기 · 지우기 ----------


def to_seoul(moment: datetime) -> datetime:
    """시간대가 없으면 서울 시각으로 본다 (queries.current_slot과 같은 기준)"""
    return moment if moment.tzinfo else moment.replace(tzinfo=SEOUL)


def classify(
    db: Session, user: User, taken_at: datetime, subject_id: uuid.UUID | None
) -> tuple[uuid.UUID, uuid.UUID | None]:
    """(학기 id, 과목 id). 과목을 직접 고르지 않았으면 찍은 시각의 수업으로 자동 분류한다

    그 시각에 수업이 없으면 과목은 None (미분류함).
    """
    if subject_id is not None:
        subject = get_subject(db, user, subject_id)
        return subject.semester_id, subject.id
    semester_id = ensure_current_semester(db, user, datetime.now(SEOUL).date())
    slot = queries.current_slot(db, user.id, taken_at)
    return semester_id, slot.subject_id if slot else None


def term_of(day: date) -> tuple[int, SemesterTerm]:
    """날짜가 속한 (학년도, 학기). 1 · 2월은 지난해 겨울학기다

    3~6월 1학기 · 7~8월 여름학기 · 9~12월 2학기 · 다음 해 1~2월 겨울학기.
    """
    if day.month <= 2:
        return day.year - 1, SemesterTerm.winter
    if day.month <= 6:
        return day.year, SemesterTerm.first
    if day.month <= 8:
        return day.year, SemesterTerm.summer
    return day.year, SemesterTerm.second


def ensure_current_semester(db: Session, user: User, today: date) -> uuid.UUID:
    """현재 학기 id. 없으면 오늘이 속한 학기를 현재 학기로 만든다

    시간표 등록을 "나중에 할게요"로 건너뛴 사용자는 학기가 하나도 없다.
    판서는 학기가 꼭 있어야 저장되므로, 그대로 두면 찍은 사진을 거절하게 된다.
    같은 학기가 이미 있으면(현재 학기만 해제된 경우) 새로 만들지 않고 그 학기를 현재로 지정한다.
    시간표가 없으니 이렇게 저장한 판서는 미분류함으로 간다.
    """
    current = db.scalar(select(Semester.id).where(Semester.user_id == user.id, Semester.is_current))
    if current is not None:
        return current
    year, term = term_of(today)
    semester = db.scalars(
        select(Semester).where(
            Semester.user_id == user.id, Semester.year == year, Semester.term == term
        )
    ).first()
    if semester is None:
        semester = Semester(user_id=user.id, year=year, term=term, is_current=False)
        db.add(semester)
        db.flush()
    set_current(db, user, semester)
    return semester.id


def create_capture(
    db: Session,
    user: User,
    *,
    capture_id: uuid.UUID,
    image: bytes,
    extension: str,
    taken_at: datetime,
    subject_id: uuid.UUID | None,
) -> Capture:
    taken_at = to_seoul(taken_at)
    semester_id, subject_id = classify(db, user, taken_at, subject_id)
    capture = Capture(
        id=capture_id,
        user_id=user.id,
        semester_id=semester_id,
        subject_id=subject_id,
        taken_at=taken_at,
        status=CaptureStatus.uploaded,
        original_key=original_key(capture_id, extension),
    )
    storage.save(capture.original_key, image)  # 1. 파일저장
    db.add(capture)  # 2. db add
    try:
        # 3. db 커밋 시도
        # (만약 파일저장보다 db커밋을 먼저했을 떄,
        #  db커밋 후 서버 꺼지면 "파일이 없는 판서 행"이 남음 )
        db.commit()
    except BaseException:
        # DB에 못 남긴 사진은 아무도 찾을 수 없으니 지움. 앱은 202를 못 받았으니 다시 보냄
        db.rollback()
        storage.delete_tree(capture_dir(capture_id))
        raise
    return capture


def destination(db: Session, user: User, at: datetime) -> Destination:
    """지금(at) 찍으면 어디에 저장되는지. 업로드의 자동 분류(classify)와 같은 규칙이다

    조회만 하므로 학기가 없어도 만들지 않는다 (그때는 전부 null = 미분류함).
    """
    semester_id = db.scalar(
        select(Semester.id).where(Semester.user_id == user.id, Semester.is_current)
    )
    if semester_id is None:
        return Destination(semester_id=None, subject_id=None, subject_name=None)
    slot = queries.current_slot(db, user.id, to_seoul(at))
    if slot is None:
        return Destination(semester_id=semester_id, subject_id=None, subject_name=None)
    return Destination(
        semester_id=semester_id, subject_id=slot.subject_id, subject_name=slot.subject.name
    )


def reset_for_retry(db: Session, capture: Capture) -> None:
    """실패한 판서를 처음 상태로 되돌린다. 처리 중이거나 끝난 판서는 409"""
    if capture.status != CaptureStatus.failed:
        raise HTTPException(409, "처리에 실패한 판서만 다시 처리할 수 있어요.")
    capture.status = CaptureStatus.uploaded
    capture.fail_reason = None
    db.commit()


def move_capture(db: Session, user: User, capture: Capture, subject_id: uuid.UUID | None) -> None:
    """과목으로 옮기기. 다른 학기 과목으로 옮기면 판서의 학기도 따라간다"""
    if subject_id is None:
        capture.subject_id = None
    else:
        subject = get_subject(db, user, subject_id)
        capture.subject_id = subject.id
        capture.semester_id = subject.semester_id
    db.commit()


def delete_capture(db: Session, capture: Capture) -> None:
    """DB를 먼저 지우고(카드는 ON DELETE CASCADE) 파일을 지운다.

    순서를 거꾸로 하면 커밋이 실패했을 때 "사진 파일이 없는 판서"가 남는다.
    """
    folder = capture_dir(capture.id)
    db.delete(capture)
    db.commit()
    storage.delete_tree(folder)


# ---------- 목록 ----------


def list_captures(
    db: Session,
    user: User,
    *,
    subject_id: uuid.UUID | None,
    unsorted: bool,
    unmoved: bool,
    before: datetime | None,
    limit: int,
) -> list[Capture]:
    """최신 판서부터. 조건은
    함께 쓸 수 있다 (예: 미분류 + 옮기지 않은 카드가 남은 판서)

    - subject_id: 과목 폴더
    - unsorted: 미분류함 (처리 상태와 관계없이 과목이 없는 판서)
    - unmoved: 아직 옮기지 않은 카드가 하나라도 남은 판서
    - before: 이 시각보다 먼저 찍은 판서 (다음 쪽 불러오기: 받은 목록의 마지막 taken_at)
    """
    if subject_id is not None and unsorted:
        raise HTTPException(400, "subject_id와 unsorted는 함께 쓸 수 없어요.")
    query = select(Capture).where(Capture.user_id == user.id)
    if subject_id is not None:
        query = query.where(Capture.subject_id == subject_id)
    if unsorted:
        query = query.where(Capture.subject_id.is_(None))
    if unmoved:
        query = query.where(exists().where(Card.capture_id == Capture.id, Card.is_moved.is_(False)))
    if before is not None:
        query = query.where(Capture.taken_at < to_seoul(before))
    # 같은 시각에 찍은 판서끼리도 순서가 매번 같게 id로 한 번 더 정렬한다
    query = query.order_by(Capture.taken_at.desc(), Capture.id).limit(limit)
    return list(db.scalars(query))


# ---------- 응답 ----------


def _card_counts(db: Session, capture_ids: list[uuid.UUID]) -> dict[uuid.UUID, tuple[int, int]]:
    """판서별 (카드 수, 옮기지 않은 카드 수)"""
    rows = db.execute(
        select(Card.capture_id, func.count(), func.count().filter(Card.is_moved.is_(False)))
        .where(Card.capture_id.in_(capture_ids))
        .group_by(Card.capture_id)
    ).all()
    return {capture_id: (total, unmoved) for capture_id, total, unmoved in rows}


def capture_outs(db: Session, captures: list[Capture]) -> list[CaptureOut]:
    counts = _card_counts(db, [c.id for c in captures])
    return [
        CaptureOut(
            id=c.id,
            semester_id=c.semester_id,
            subject_id=c.subject_id,
            taken_at=c.taken_at,
            class_date=c.taken_at.astimezone(SEOUL).date(),
            status=c.status,
            fail_reason=c.fail_reason,
            card_count=counts.get(c.id, (0, 0))[0],
            unmoved_count=counts.get(c.id, (0, 0))[1],
        )
        for c in captures
    ]


def card_out(card: Card) -> CardOut:
    return CardOut(
        id=card.id,
        order_no=card.order_no,
        title=card.title,
        card_type=card.card_type,
        content=card.content,
        is_edited=card.content != card.original_content,
        bbox=card.bbox,
        is_moved=card.is_moved,
    )


def capture_detail(db: Session, capture: Capture) -> CaptureDetail:
    (base,) = capture_outs(db, [capture])
    cards = sorted(capture.cards, key=lambda card: card.order_no)
    return CaptureDetail(**base.model_dump(), cards=[card_out(card) for card in cards])
