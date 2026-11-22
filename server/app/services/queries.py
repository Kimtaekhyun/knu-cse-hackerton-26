"""화면별 집계 질의 (#21 "화면별 집계" 표).

API가 이 함수들을 그대로 불러 쓴다. 날짜 · 요일은 모두 서울 시각 기준이다.
"""

import uuid
from datetime import date, datetime, timedelta
from typing import NamedTuple
from zoneinfo import ZoneInfo

from sqlalchemy import Date, cast, exists, func, select
from sqlalchemy.orm import Session, contains_eager

from app.models import (
    AcademicCalendar,
    Capture,
    CaptureStatus,
    Card,
    Semester,
    Subject,
    SubjectSlot,
    User,
)

SEOUL = ZoneInfo("Asia/Seoul")


class AccountStats(NamedTuple):
    """내 계정 통계: 찍은 판서 / 정리된 카드 / 옮긴 카드"""

    captures: int
    cards: int
    moved_cards: int


def subject_capture_count(db: Session, subject_id: uuid.UUID) -> int:
    """과목 폴더의 "12장". 처리가 끝난 판서만 센다"""
    return db.scalar(
        select(func.count())
        .select_from(Capture)
        .where(Capture.subject_id == subject_id, Capture.status == CaptureStatus.done)
    )


def unsorted_capture_count(db: Session, user_id: uuid.UUID) -> int:
    """미분류함의 "3장". 처리 상태와 관계없이 과목이 없는 판서를 전부 센다"""
    return db.scalar(
        select(func.count())
        .select_from(Capture)
        .where(Capture.user_id == user_id, Capture.subject_id.is_(None))
    )


def unmoved_captures(db: Session, user_id: uuid.UUID) -> list[Capture]:
    """아직 옮기지 않은 카드가 하나라도 남은 판서. 최신 판서부터"""
    has_unmoved = exists().where(Card.capture_id == Capture.id, Card.is_moved.is_(False))
    return list(
        db.scalars(
            select(Capture)
            .where(Capture.user_id == user_id, has_unmoved)
            .order_by(Capture.taken_at.desc())
        )
    )


def account_stats(db: Session, user_id: uuid.UUID) -> AccountStats:
    captures = db.scalar(
        select(func.count()).select_from(Capture).where(Capture.user_id == user_id)
    )
    cards, moved = db.execute(
        select(func.count(Card.id), func.count(Card.id).filter(Card.is_moved))
        .join(Capture, Card.capture_id == Capture.id)
        .where(Capture.user_id == user_id)
    ).one()
    return AccountStats(captures, cards, moved)


def current_slot(db: Session, user_id: uuid.UUID, now: datetime) -> SubjectSlot | None:
    """지금 수업 중인 시간 칸 (현재 학기 과목만). 시작 시각은 포함, 끝 시각은 포함하지 않는다

    now에 시간대가 없으면 서울 시각으로 본다.
    """
    local = now.astimezone(SEOUL) if now.tzinfo else now.replace(tzinfo=SEOUL)
    clock = local.time().replace(tzinfo=None)
    return db.scalars(
        select(SubjectSlot)
        .join(Subject, SubjectSlot.subject_id == Subject.id)
        .join(Semester, Subject.semester_id == Semester.id)
        .where(
            Semester.user_id == user_id,
            Semester.is_current,
            SubjectSlot.weekday == local.weekday(),
            SubjectSlot.start_time <= clock,
            SubjectSlot.end_time > clock,
        )
        .order_by(SubjectSlot.start_time)
    ).first()


def today_slots(db: Session, user_id: uuid.UUID, weekday: int) -> list[SubjectSlot]:
    """그 요일의 수업 칸 전부 (현재 학기 과목만), 시작 시각 순. 끝난 수업도 들어간다

    과목 이름을 바로 쓸 수 있게 subject를 함께 불러온다.
    """
    return list(
        db.scalars(
            select(SubjectSlot)
            .join(Subject, SubjectSlot.subject_id == Subject.id)
            .join(Semester, Subject.semester_id == Semester.id)
            .where(Semester.user_id == user_id, Semester.is_current, SubjectSlot.weekday == weekday)
            .options(contains_eager(SubjectSlot.subject))
            .order_by(SubjectSlot.start_time, SubjectSlot.end_time, Subject.name)
        )
    )


def done_capture_count(db: Session, user_id: uuid.UUID) -> int:
    """정리가 끝난 판서 수 (메인 07 처음 · 08 판서가 쌓인 뒤 구분)"""
    return db.scalar(
        select(func.count())
        .select_from(Capture)
        .where(Capture.user_id == user_id, Capture.status == CaptureStatus.done)
    )


def weekly_capture_counts(db: Session, user_id: uuid.UUID, week_start: date) -> dict[date, int]:
    """week_start부터 7일 동안 날짜별로 정리가 끝난 판서 수. 판서가 없는 날도 0으로 넣는다

    과목 폴더 장수(subject_capture_count)와 같이 처리 중 · 실패한 판서는 세지 않는다.
    """
    week_end = week_start + timedelta(days=6)
    seoul_day = cast(func.timezone("Asia/Seoul", Capture.taken_at), Date)
    rows = db.execute(
        select(seoul_day, func.count())
        .where(
            Capture.user_id == user_id,
            Capture.status == CaptureStatus.done,
            seoul_day.between(week_start, week_end),
        )
        .group_by(seoul_day)
    ).all()
    counts = {week_start + timedelta(days=i): 0 for i in range(7)}
    counts.update({day: count for day, count in rows})
    return counts


def current_calendar(db: Session, user_id: uuid.UUID) -> AcademicCalendar | None:
    """현재 학기의 학사일정. 사용자 학교 · 현재 학기의 (year, term)으로 찾는다

    시험까지 남은 기간 계산은 exam_schedule에서 한다.
    """
    return db.scalars(
        select(AcademicCalendar)
        .join(User, AcademicCalendar.school == User.school)
        .join(
            Semester,
            (Semester.user_id == User.id)
            & (Semester.year == AcademicCalendar.year)
            & (Semester.term == AcademicCalendar.term),
        )
        .where(User.id == user_id, Semester.is_current)
    ).first()
