"""메인 화면(07 · 08) 값 모으기.

라우터(app/api/v1/home.py)는 기준 시각만 정하고 계산은 여기서 한다.
집계 질의는 queries, 시험 기간 규칙은 exam_schedule, 학사일정 찾기는 academic_calendar에 있다.
"""

from datetime import datetime, timedelta

from sqlalchemy.orm import Session

from app.models import SubjectSlot, User
from app.schemas.home import HomeClass, HomeExam, HomeOut, HomeWeek
from app.services import academic_calendar, exam_schedule, queries
from app.services.queries import SEOUL


def to_seoul(moment: datetime) -> datetime:
    """서울 시각으로 바꾼다. 시간대가 없으면 서울 시각으로 본다"""
    return moment.astimezone(SEOUL) if moment.tzinfo else moment.replace(tzinfo=SEOUL)


def _class(slot: SubjectSlot) -> HomeClass:
    return HomeClass(
        subject_id=slot.subject_id,
        name=slot.subject.name,
        start=slot.start_time.strftime("%H:%M"),
        end=slot.end_time.strftime("%H:%M"),
    )


def home(db: Session, user: User, at: datetime) -> HomeOut:
    now = to_seoul(at)
    today = now.date()

    slots = queries.today_slots(db, user.id, today.weekday())
    # "수업 중"은 판서 자동 분류와 같은 규칙(queries.current_slot)으로 고른다
    current = queries.current_slot(db, user.id, now)
    now_class = next((_class(s) for s in slots if current and s.id == current.id), None)

    monday = today - timedelta(days=today.weekday())
    this_week = queries.weekly_capture_counts(db, user.id, monday)
    last_week = queries.weekly_capture_counts(db, user.id, monday - timedelta(days=7))
    days = [this_week[monday + timedelta(days=i)] for i in range(7)]

    # 학사일정이 없으면 뒤에서 찾게 하고 추정 개강일로 계산한다 (#173)
    exam = exam_schedule.next_exam(academic_calendar.calendar_for(db, user), today)

    return HomeOut(
        now_class=now_class,
        today=[_class(s) for s in slots],
        week=HomeWeek(
            start=monday,
            days=days,
            total=sum(days),
            last_week_total=sum(last_week.values()),
        ),
        total_captures=queries.done_capture_count(db, user.id),
        exam=HomeExam(**exam._asdict()) if exam else None,
    )
