"""학사일정 찾기 (#173).

사용자 학교 · 현재 학기 학사일정이 DB에 있으면 그대로 쓰고, 없으면
1. 뒤에서 Claude 웹 검색으로 그 학교 학사일정(개강일 · 중간 · 기말 시작일)을 찾아 저장하고
2. 그동안(또는 찾지 못하면) 추정 개강일로 만든 학사일정을 쓴다 (exam_schedule.estimated_calendar)

- Gemini 키는 구글 검색 할당량이 없어(429) Claude 웹 검색을 쓴다
- 찾은 날짜는 check()로 말이 되는지 확인하고, 비었거나 하나라도 어긋나면 버린다
- 같은 학교 · 학기는 찾는 중이면 다시 찾지 않고, 못 찾았으면 RETRY_AFTER초 동안 다시 찾지 않는다
- 저장한 학사일정은 같은 학교 사용자가 함께 쓴다 (school, year, term 유일)
"""

import logging
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import date

import anthropic
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.db.session import SessionLocal
from app.models import AcademicCalendar, Semester, SemesterTerm, User
from app.services import claude, exam_schedule

logger = logging.getLogger(__name__)

# 검색하는 학기 (계절학기는 시험 기간이 없어 찾지 않는다)
TERM_NAMES = {SemesterTerm.first: "1학기", SemesterTerm.second: "2학기"}
# 개강일이 들어가야 하는 달
START_MONTHS = {SemesterTerm.first: range(2, 5), SemesterTerm.second: range(8, 11)}
# 시험 시작일이 들어가야 하는 주차 (개강일이 든 주가 1주차)
MIDTERM_WEEKS = range(5, 11)
FINAL_WEEKS = range(12, 19)
# 못 찾은 학교 · 학기를 다시 찾기까지 기다리는 초 (학교가 학사일정을 늦게 올리는 경우)
RETRY_AFTER = 24 * 60 * 60
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
            return saved
        request_lookup(user.school, semester.year, semester.term)
    return exam_schedule.estimated_calendar(user.school or "", semester.year, semester.term)


# ---------- 찾은 날짜 확인 ----------


def week_of(start: date, day: date) -> int:
    """개강일이 든 주를 1주차로 셀 때 day가 몇 주차인지"""
    return (day - start).days // 7 + 1


def check(found: FoundDates, year: int, term: SemesterTerm) -> bool:
    """말이 되는 날짜인지. 세 날짜가 모두 있어야 한다.

    한 칸이라도 비면 저장하지 않는다. 저장한 학사일정은 다시 찾지 않아서, 비어 있는 채로 저장하면
    학교가 나중에 시험 일정을 올려도 반영되지 않는다. 대신 RETRY_AFTER초 뒤에 다시 찾는다.
    """
    start, midterm, final = found.starts_on, found.midterm_start, found.final_start
    if start is None or midterm is None or final is None:
        return False
    if start.year != year or start.month not in START_MONTHS.get(term, ()):
        return False
    return week_of(start, midterm) in MIDTERM_WEEKS and week_of(start, final) in FINAL_WEEKS


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
    """찾은 학사일정을 저장한다. 그 사이 다른 요청이 먼저 저장했으면 그대로 둔다"""
    db.execute(
        insert(AcademicCalendar)
        .values(
            school=school,
            year=year,
            term=term,
            starts_on=found.starts_on,
            midterm_start=found.midterm_start,
            final_start=found.final_start,
        )
        .on_conflict_do_nothing(index_elements=["school", "year", "term"])
    )
    db.commit()


# ---------- 뒤에서 찾기 ----------

_executor: ThreadPoolExecutor | None = None
_lock = threading.Lock()
_running: set[Key] = set()  # 지금 찾는 중
_failed: dict[Key, float] = {}  # 못 찾은 시각


def request_lookup(school: str, year: int, term: SemesterTerm) -> None:
    """학사일정을 뒤에서 찾게 한다. 이미 찾는 중이거나 최근에 못 찾았으면 아무것도 안 한다"""
    if term not in TERM_NAMES:
        return
    key = (school, year, term)
    global _executor
    with _lock:
        if key in _running or time.time() - _failed.get(key, float("-inf")) < RETRY_AFTER:
            return
        _running.add(key)
        if _executor is None:
            _executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="calendar")
    _executor.submit(lookup, key)


def lookup(key: Key, session_factory=SessionLocal) -> bool:
    """찾아서 확인하고 저장한다. 저장했으면 True. 못 찾으면 RETRY_AFTER초 동안 다시 찾지 않는다"""
    school, year, term = key
    try:
        found = search(school, year, term)
        if found is None or not check(found, year, term):
            logger.info("학사일정 못 찾음: %s %s %s → 추정 개강일 사용 (%s)", *key, found)
            ok = False
        else:
            with session_factory() as db:
                save(db, school, year, term, found)
            logger.info("학사일정 저장: %s %s %s %s", *key, found)
            ok = True
    except (claude.ClaudeError, anthropic.AnthropicError, ValueError) as error:
        logger.warning("학사일정 검색 실패: %s %s %s (%s)", *key, error)
        ok = False
    with _lock:
        _running.discard(key)
        if not ok:
            _failed[key] = time.time()
    return ok
