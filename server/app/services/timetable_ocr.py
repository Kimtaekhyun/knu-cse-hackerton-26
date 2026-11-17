"""에브리타임 시간표 캡처 → 과목 후보.

모델은 시간표의 칸을 하나씩(RawBlock) 읽고, normalize()가 검사 · 합치기를 해서
과목 목록(Subject)으로 만든다.
"""

import json
import mimetypes
import re
import sys
from pathlib import Path

from google.genai import types
from pydantic import BaseModel, Field

from app.core.config import get_settings
from app.schemas.timetable import Slot, Subject
from app.services.gemini import ask_json

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


PROMPT = """
이 이미지는 에브리타임 앱의 시간표 화면 캡처야. 시간표에 있는 수업을 빠짐없이 읽어 줘.

[규칙]
1. 색칠된 칸 하나가 blocks 하나야. 같은 과목이 여러 요일 · 여러 칸에 있으면 칸마다 따로 적어.
2. name에는 칸 안의 과목명만 적어. 교수명 · 강의실 · 건물 번호는 넣지 마.
   과목명이 칸에서 잘려 보이면 보이는 만큼만 적어.
3. weekday는 칸이 놓인 열의 요일이야. 맨 위 요일 줄을 보고 월=0, 화=1, 수=2, 목=3, 금=4, 토=5, 일=6.
4. start와 end는 칸의 위 · 아래 가장자리를 왼쪽 시각 눈금에 맞춰 읽은 24시간 HH:MM이야.
   눈금의 숫자는 그 줄이 시작하는 시각이야 (예: 9는 09:00, 1은 13:00).
   칸 안에 시각이 적혀 있으면 그 시각을 써.
5. 시간표 아래처럼 시간 없이 따로 적힌 과목(온라인 · 사이버강의 등)은 untimed에 과목명만 넣어.
6. 읽을 수 없는 칸은 지어내지 말고 빼.
"""


def parse_timetable(image: bytes, mime_type: str) -> list[Subject]:
    """시간표 캡처에서 과목 후보를 뽑는다. Gemini가 끝내 실패하면 GeminiError."""
    contents = [types.Part.from_bytes(data=image, mime_type=mime_type), PROMPT]
    raw, _ = ask_json(contents, RawTimetable, model=get_settings().timetable_model)
    return normalize(raw)


if __name__ == "__main__":
    # 확인용: uv run python -m app.services.timetable_ocr <캡처 경로>
    path = Path(sys.argv[1])
    mime = mimetypes.guess_type(path.name)[0] or "image/png"
    subjects = parse_timetable(path.read_bytes(), mime)
    print(get_settings().timetable_model)
    print(json.dumps([s.model_dump() for s in subjects], ensure_ascii=False, indent=2))
