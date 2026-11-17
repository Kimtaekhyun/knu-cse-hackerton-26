"""에브리타임 시간표 캡처 → 과목 후보.

모델은 시간표의 칸을 하나씩(RawBlock) 읽고, normalize()가 검사 · 합치기를 해서
과목 목록(Subject)으로 만든다.
"""

import re

from pydantic import BaseModel, Field

from app.schemas.timetable import Slot, Subject

SNAP_MINUTES = 30  # 칸 위치로 시간을 읽어 몇 분씩 어긋나므로 30분 단위로 맞춘다
TIME_PATTERN = re.compile(r"^(\d{1,2}):(\d{2})$")


class RawBlock(BaseModel):
    """시간표의 색칠된 칸 하나"""

    name: str = Field(description="칸 안의 과목명만. 교수명 · 강의실은 넣지 않는다")
    weekday: int = Field(description="칸이 놓인 열의 요일. 월=0, 화=1, … 토=5, 일=6")
    start: str = Field(description="칸 위 가장자리의 시각. 24시간 HH:MM")
    end: str = Field(description="칸 아래 가장자리의 시각. 24시간 HH:MM")


class RawTimetable(BaseModel):
    blocks: list[RawBlock] = Field(description="시간표의 칸들. 같은 과목이 여러 칸이면 칸마다 따로")
    untimed: list[str] = Field(
        description="시간 없이 따로 적힌 과목명 (온라인 · 사이버강의 등). 없으면 빈 목록"
    )


def clean_name(name: str) -> str:
    """앞뒤 공백을 지우고 연속 공백은 하나로"""
    return " ".join(name.split())


def to_minutes(text: str) -> int | None:
    """'H:MM' 또는 'HH:MM'을 30분 단위로 반올림한 분으로. 읽을 수 없으면 None. 15분은 올린다"""
    match = TIME_PATTERN.match(text.strip())
    if not match:
        return None
    hour, minute = int(match.group(1)), int(match.group(2))
    if hour > 23 or minute > 59:
        return None
    total = hour * 60 + minute
    return (total + SNAP_MINUTES // 2) // SNAP_MINUTES * SNAP_MINUTES


def to_text(minutes: int) -> str:
    return f"{minutes // 60:02d}:{minutes % 60:02d}"


def merge_slots(slots: list[tuple[int, int, int]]) -> list[Slot]:
    """같은 요일에서 맞닿거나 겹치는 칸을 하나로 합치고 (요일, 시작) 순으로 정렬"""
    merged: list[list[int]] = []
    for weekday, start, end in sorted(slots):
        last = merged[-1] if merged else None
        if last and last[0] == weekday and start <= last[2]:
            last[2] = max(last[2], end)
        else:
            merged.append([weekday, start, end])
    return [Slot(weekday=w, start=to_text(s), end=to_text(e)) for w, s, e in merged]


def normalize(raw: RawTimetable) -> list[Subject]:
    """모델이 읽은 칸들을 과목 목록으로 정리한다.

    읽을 수 없는 시각, 0~6 밖의 요일, 시작 ≥ 끝인 칸은 그 칸만 버리고 과목은 남긴다
    (06 화면에서 직접 고칠 수 있게). 시간 있는 과목은 첫 수업 순, 시간 없는 과목은 그 뒤에 둔다.
    """
    grouped: dict[str, list[tuple[int, int, int]]] = {}
    for block in raw.blocks:
        name = clean_name(block.name)
        if not name:
            continue
        slots = grouped.setdefault(name, [])
        start, end = to_minutes(block.start), to_minutes(block.end)
        if start is None or end is None or not 0 <= block.weekday <= 6 or start >= end:
            continue
        slots.append((block.weekday, start, end))

    for name in map(clean_name, raw.untimed):
        if name:
            grouped.setdefault(name, [])

    subjects = [Subject(name=name, slots=merge_slots(slots)) for name, slots in grouped.items()]
    timed = sorted(
        (s for s in subjects if s.slots), key=lambda s: (s.slots[0].weekday, s.slots[0].start)
    )
    untimed = [s for s in subjects if not s.slots]
    return timed + untimed
