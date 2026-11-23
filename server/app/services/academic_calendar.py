"""학사일정 찾기 (#173).

사용자 학교 · 현재 학기 학사일정이 DB에 있으면 그대로 쓰고, 없으면
1. 뒤에서 Claude 웹 검색으로 그 학교 학사일정(개강일 · 중간 · 기말 시작일)을 찾아 저장하고
2. 그동안(또는 찾지 못하면) 추정 개강일로 만든 학사일정을 쓴다 (exam_schedule.estimated_calendar)

- Gemini 키는 구글 검색 할당량이 없어(429) Claude 웹 검색을 쓴다
- 찾은 날짜는 usable()로 확인한다. 개강일이 맞으면 저장하고,
  범위를 벗어난 시험 시작일은 그 칸만 비운다. 빈 칸은 실제 개강일 기준 8 · 15주차로 채워진다
- 시험 시작일이 빈 학사일정은 RETRY_AFTER초마다 다시 찾아 빈 칸만 채운다
  (학교가 시험 일정을 늦게 올리는 경우)
- 같은 학교 · 학기는 찾는 중이거나 마지막 검색 뒤 RETRY_AFTER초가 안 지났으면 다시 찾지 않는다
- 모든 학교를 합쳐 RETRY_AFTER초 동안 DAILY_LIMIT번까지만 찾는다 (넘으면 추정 개강일)
- 검색 기록은 calendar_searches 테이블에 남겨서 서버를 다시 켜도 유지된다
- 저장한 학사일정은 같은 학교 사용자가 함께 쓴다 (school, year, term 유일)
"""

import logging
import threading
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, date, datetime, timedelta

import anthropic
from pydantic import BaseModel
from sqlalchemy import exists, func, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.db.session import SessionLocal
from app.models import AcademicCalendar, CalendarSearch, Semester, SemesterTerm, User
from app.services import claude, exam_schedule

logger = logging.getLogger(__name__)

# 검색하는 학기 (계절학기는 시험 기간이 없어 찾지 않는다)
TERM_NAMES = {SemesterTerm.first: "1학기", SemesterTerm.second: "2학기"}
# 개강일이 들어가야 하는 달
START_MONTHS = {SemesterTerm.first: range(2, 5), SemesterTerm.second: range(8, 11)}
# 시험 시작일이 들어가야 하는 주차 (개강일이 든 주가 1주차)
MIDTERM_WEEKS = range(5, 11)
FINAL_WEEKS = range(12, 19)
# 못 찾았거나 시험 시작일이 빈 학교 · 학기를 다시 찾기까지 기다리는 초
RETRY_AFTER = 24 * 60 * 60
# 모든 학교를 합쳐 RETRY_AFTER초 동안 할 수 있는 검색 수
# (학교 이름을 바꿔 가며 저장해도 요금이 한도를 넘지 않게)
DAILY_LIMIT = 30
# 요청 한 번에 웹 검색을 몇 번까지 하게 할지 (검색 1번에 요금이 붙는다)
MAX_SEARCHES = 3
# 생각 깊이. 날짜 몇 개를 뽑는 일이라 낮게 둔다
EFFORT = "low"

Key = tuple[str, int, SemesterTerm]


class FoundDates(BaseModel):
    """Claude가 찾은 날짜. 학교 공식 학사일정에서 확인하지 못한 칸은 null"""

    starts_on: date | None
    midterm_start: date | None
    final_start: date | None
    source_url: str | None


# ---------- 현재 학기 학사일정 ----------


def current_semester(db: Session, user: User) -> Semester | None:
    return db.scalars(
        select(Semester).where(Semester.user_id == user.id, Semester.is_current)
    ).first()


def saved_calendar(db: Session, school: str, year: int, term: SemesterTerm):
    return db.scalars(
        select(AcademicCalendar).where(
            AcademicCalendar.school == school,
            AcademicCalendar.year == year,
            AcademicCalendar.term == term,
        )
    ).first()


def calendar_for(db: Session, user: User) -> AcademicCalendar | None:
    """사용자 현재 학기 학사일정. 저장된 게 없으면 뒤에서 찾게 하고 추정 학사일정을 돌려준다.

    현재 학기가 없거나 계절학기면 None (시험 없음).
    """
    semester = current_semester(db, user)
    if semester is None:
        return None
    if user.school:
        saved = saved_calendar(db, user.school, semester.year, semester.term)
        if saved is not None:
            if not complete(saved):  # 시험 시작일이 비었으면 다시 찾아 채운다 (하루 한 번까지)
                request_lookup(db, user.school, semester.year, semester.term)
            return saved
        request_lookup(db, user.school, semester.year, semester.term)
    return exam_schedule.estimated_calendar(user.school or "", semester.year, semester.term)


# ---------- 찾은 날짜 확인 ----------


def week_of(start: date, day: date) -> int:
    """개강일이 든 주를 1주차로 셀 때 day가 몇 주차인지"""
    return (day - start).days // 7 + 1


def usable(found: FoundDates, year: int, term: SemesterTerm) -> FoundDates | None:
    """저장해도 되는 날짜. 개강일이 없거나 그 학기 달이 아니면 None.

    시험 시작일이 주차 범위(중간 5~10주차 · 기말 12~18주차)를 벗어나면 그 칸만 비운다.
    """
    start = found.starts_on
    if start is None or start.year != year or start.month not in START_MONTHS.get(term, ()):
        return None

    def within(day: date | None, weeks: range) -> date | None:
        return day if day is not None and week_of(start, day) in weeks else None

    return found.model_copy(
        update={
            "midterm_start": within(found.midterm_start, MIDTERM_WEEKS),
            "final_start": within(found.final_start, FINAL_WEEKS),
        }
    )


def complete(calendar: AcademicCalendar | FoundDates) -> bool:
    """시험 시작일까지 모두 있는지 (없으면 나중에 다시 찾는다)"""
    return calendar.midterm_start is not None and calendar.final_start is not None


# ---------- Claude 웹 검색 ----------


def search(school: str, year: int, term: SemesterTerm) -> FoundDates | None:
    """Claude 웹 검색으로 학사일정 날짜를 찾는다. 답을 받지 못하면 None (오류는 그대로 던진다)"""
    prompt = (
        f"{school} {year}학년도 {TERM_NAMES[term]} 학사일정에서 개강일, 중간고사 시작일, "
        "기말고사 시작일을 웹 검색으로 찾아 줘. 날짜는 YYYY-MM-DD. "
        "학교 공식 학사일정에서 확인하지 못한 칸은 null로 두고, 추측하지 마."
    )
    response = claude.get_client().beta.messages.parse(
        model=get_settings().calendar_model,
        max_tokens=claude.MAX_TOKENS,
        messages=[{"role": "user", "content": prompt}],
        tools=[{"type": "web_search_20260209", "name": "web_search", "max_uses": MAX_SEARCHES}],
        output_format=FoundDates,
        output_config={"effort": EFFORT},
        **claude.FALLBACK_OPTIONS,
    )
    if response.stop_reason != "end_turn":  # 거절 · 끊김 · 검색 도중 멈춤
        logger.warning("학사일정 검색 답 없음: %s %s (%s)", school, year, response.stop_reason)
        return None
    found = response.parsed_output
    return found if isinstance(found, FoundDates) else None


def save(db: Session, school: str, year: int, term: SemesterTerm, found: FoundDates) -> None:
    """찾은 학사일정을 저장한다. 이미 있으면 비어 있던 시험 시작일만 채운다 (있는 날짜는 그대로)"""
    statement = insert(AcademicCalendar).values(
        school=school,
        year=year,
        term=term,
        starts_on=found.starts_on,
        midterm_start=found.midterm_start,
        final_start=found.final_start,
    )
    table = AcademicCalendar.__table__.c
    db.execute(
        statement.on_conflict_do_update(
            index_elements=["school", "year", "term"],
            set_={
                "midterm_start": func.coalesce(
                    table.midterm_start, statement.excluded.midterm_start
                ),
                "final_start": func.coalesce(table.final_start, statement.excluded.final_start),
            },
        )
    )
    db.commit()


# ---------- 뒤에서 찾기 ----------

_executor: ThreadPoolExecutor | None = None
_lock = threading.Lock()
_running: set[Key] = set()  # 지금 찾는 중 (이 서버 안에서)


def request_lookup(db: Session, school: str, year: int, term: SemesterTerm) -> bool:
    """학사일정을 뒤에서 찾게 한다. 찾기 시작했으면 True.

    찾지 않는 경우: 계절학기 · 찾는 중 · 같은 학교 · 학기를 RETRY_AFTER초 안에 찾은 적 있음 ·
    모든 학교를 합친 검색 수가 DAILY_LIMIT에 닿음
    """
    if term not in TERM_NAMES:
        return False
    key = (school, year, term)
    since = datetime.now(UTC) - timedelta(seconds=RETRY_AFTER)
    global _executor
    with _lock:
        if key in _running:
            return False
        recent = db.scalar(
            select(
                exists().where(
                    CalendarSearch.school == school,
                    CalendarSearch.year == year,
                    CalendarSearch.term == term,
                    CalendarSearch.searched_at > since,
                )
            )
        )
        if recent:
            return False
        searches = db.scalar(
            select(func.count())
            .select_from(CalendarSearch)
            .where(CalendarSearch.searched_at > since)
        )
        if searches >= DAILY_LIMIT:
            logger.warning("학사일정 검색 하루 한도(%d번) 도달: %s %s %s 건너뜀", DAILY_LIMIT, *key)
            return False
        db.add(CalendarSearch(school=school, year=year, term=term))
        db.commit()
        _running.add(key)
        if _executor is None:
            _executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="calendar")
    _executor.submit(lookup, key)
    return True


def lookup(key: Key, session_factory=SessionLocal) -> bool:
    """찾아서 확인하고 저장한다. 세 날짜를 모두 저장했으면 True.

    개강일만 찾았으면 저장은 하되 False. 시험 시작일이 빈 학사일정은 RETRY_AFTER초 뒤
    누군가 메인을 열 때 다시 찾아 채운다 (request_lookup이 검색 기록으로 간격을 지킨다).
    """
    school, year, term = key
    ok = False
    try:
        found = search(school, year, term)
        dates = usable(found, year, term) if found is not None else None
        if dates is None:
            logger.info("학사일정 못 찾음: %s %s %s → 추정 개강일 사용 (%s)", *key, found)
        else:
            with session_factory() as db:
                save(db, school, year, term, dates)
            logger.info("학사일정 저장: %s %s %s %s", *key, dates)
            ok = complete(dates)
    except (claude.ClaudeError, anthropic.AnthropicError, ValueError) as error:
        logger.warning("학사일정 검색 실패: %s %s %s (%s)", *key, error)
    finally:
        with _lock:
            _running.discard(key)
    return ok
