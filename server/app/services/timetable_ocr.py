"""에브리타임 시간표 캡처 → 과목 후보.

1. 모델은 칸마다 과목명 · 요일 · 상자(box_2d)를, 왼쪽 시각 눈금마다 위치를 읽는다 (TimetableGrid)
   모델은 칸 위치를 시각으로 바로 바꾸는 데 약해서 (30분~1시간씩 틀림) 위치만 맡긴다
2. 코드가 칸의 색으로 상자 위아래를 맞추고, 눈금 위치로 시각을 계산한다 (grid_to_raw)
3. normalize()가 검사 · 합치기를 해서 과목 목록(Subject)으로 만든다
"""

import io
import json
import math
import mimetypes
import re
import sys
from pathlib import Path

import numpy as np
from google.genai import types
from PIL import Image, ImageOps
from pydantic import BaseModel, Field

from app.core.config import get_settings
from app.schemas.timetable import Slot, Subject
from app.services.gemini import ask_json

SNAP_MINUTES = 30  # 칸 위치로 시간을 읽어 몇 분씩 어긋나므로 30분 단위로 맞춘다
TIME_PATTERN = re.compile(r"^(\d{1,2}):(\d{2})$")


class RawBlock(BaseModel):
    """시각까지 계산한 칸 하나 (start · end는 24시간 HH:MM, 모르면 빈 글자)"""

    name: str
    weekday: int
    start: str
    end: str


class RawTimetable(BaseModel):
    blocks: list[RawBlock]
    untimed: list[str]


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


# ── 모델이 읽는 형식 ─────────────────────────────────────


class BlockBox(BaseModel):
    """시간표의 색칠된 칸 하나"""

    name: str = Field(description="칸 안의 과목명만. 교수명 · 강의실은 넣지 않는다")
    weekday: int = Field(description="칸이 놓인 열의 요일. 월=0, 화=1, … 토=5, 일=6")
    box_2d: list[int] = Field(
        description="색칠된 칸 전체를 꼭 맞게 감싸는 상자 [ymin, xmin, ymax, xmax]. "
        "이미지를 0~1000으로 본 좌표. 글씨만이 아니라 칸의 색이 끝나는 곳까지"
    )


class HourMark(BaseModel):
    """왼쪽 세로줄의 시각 눈금 숫자 하나"""

    hour: int = Field(description="눈금 숫자를 24시간으로 바꾼 값 (9→9, 12→12, 1→13, 6→18)")
    box_2d: list[int] = Field(description="눈금 숫자의 상자 [ymin, xmin, ymax, xmax], 0~1000 좌표")


class TimetableGrid(BaseModel):
    blocks: list[BlockBox] = Field(description="시간표의 칸들. 같은 과목이 여러 칸이면 칸마다 따로")
    hours: list[HourMark] = Field(description="왼쪽 시각 눈금 숫자들, 보이는 것 전부")
    untimed: list[str] = Field(
        description="시간 없이 따로 적힌 과목명 (온라인 · 사이버강의 등). 없으면 빈 목록"
    )


PROMPT = """
이 이미지는 에브리타임 앱의 시간표 화면 캡처야. 시간은 계산하지 말고 위치만 정확히 읽어 줘.

[규칙]
1. 색칠된 칸 하나가 blocks 하나야. 같은 과목이 여러 요일 · 여러 칸에 있으면 칸마다 따로 적어.
2. name에는 칸 안의 과목명만 적어. 교수명 · 강의실 · 건물 번호는 넣지 마.
   과목명이 칸에서 잘려 보이면 보이는 만큼만 적어.
3. weekday는 칸이 놓인 열의 요일이야. 맨 위 요일 줄을 보고 월=0, 화=1, 수=2, 목=3, 금=4, 토=5, 일=6.
4. box_2d는 색칠된 칸 전체를 감싸야 해. 글씨가 끝나도 칸의 색이 이어지면 색이 끝나는 곳까지.
5. hours에는 왼쪽 세로줄의 시각 숫자를 보이는 대로 전부 적고, 숫자마다 상자를 적어.
   hour는 24시간으로 바꿔 (오후 1시를 뜻하는 1은 13).
6. 시간표 아래처럼 시간 없이 따로 적힌 과목(온라인 · 사이버강의 등)은 untimed에 과목명만 넣어.
7. 읽을 수 없는 칸은 지어내지 말고 빼.
"""


# ── 위치 → 시각 ─────────────────────────────────────────


def hour_scale(hours: list[HourMark]) -> tuple[float, float] | None:
    """눈금 숫자 윗변(ymin)과 시각을 직선 y = a·시각 + b 로 맞춘다. 시각이 2개 미만이면 None.

    눈금 숫자는 그 시각 줄의 맨 위에 붙어 있어서 숫자 윗변을 줄의 시작으로 본다.
    """
    points = [(h.hour, h.box_2d[0]) for h in hours if len(h.box_2d) == 4]
    if len({x for x, _ in points}) < 2:
        return None
    mean_x = sum(x for x, _ in points) / len(points)
    mean_y = sum(y for _, y in points) / len(points)
    spread = sum((x - mean_x) ** 2 for x, _ in points)
    a = sum((x - mean_x) * (y - mean_y) for x, y in points) / spread
    if a <= 0:
        return None
    return a, mean_y - a * mean_x


def position_text(y: float, scale: tuple[float, float]) -> str:
    """0~1000 좌표의 세로 위치를 "HH:MM"으로 (반올림은 normalize가 한다). 하루 밖이면 빈 글자"""
    a, b = scale
    minutes = round((y - b) / a * 60)
    if not 0 <= minutes < 24 * 60:
        return ""
    return to_text(minutes)


# ── 색으로 칸 위아래 맞추기 ─────────────────────────────────

COLOR_TOLERANCE = 40  # 칸 색과 같은 색으로 볼 채널별 차이 (JPEG 잡음 감안)
ROW_FRACTION = 0.3  # 한 줄에서 칸 색이 이 비율 이상이면 칸에 속한 줄 (글씨가 덮는 부분 감안)
GAP_RATIO = 0.04  # 칸 색이 끊겨도 이 높이(이미지 대비)까지는 이어 본다 (굵은 제목 글씨 줄)


def _mode_color(pixels: np.ndarray) -> np.ndarray:
    """가장 흔한 색 (16단계로 묶어 센 뒤 그 묶음의 평균)"""
    quant = pixels // 16
    colors, counts = np.unique(quant, axis=0, return_counts=True)
    top = colors[counts.argmax()]
    return pixels[(quant == top).all(axis=1)].mean(axis=0)


def _grow(match: np.ndarray, seed: int, step: int, gap: int) -> int:
    """seed에서 step 방향으로 칸에 속한 줄을 따라가 마지막 줄을 돌려준다. gap줄 넘게 끊기면 멈춤"""
    last, misses, row = seed, 0, seed
    while 0 <= row + step < len(match):
        row += step
        if match[row]:
            last, misses = row, 0
        else:
            misses += 1
            if misses > gap:
                break
    return last


def refine_rows(image: np.ndarray, box: list[int]) -> tuple[int, int]:
    """칸의 색이 이어지는 곳까지 상자 위아래를 맞춘다. 돌려주는 값은 0~1000 좌표 (ymin, ymax).

    모델이 긴 칸에서 글씨 부분만 감싸 끝 시각이 일찍 끝나는 문제를 막는다.
    칸 색을 찾지 못하면(상자 안이 배경색) 원래 상자를 그대로 쓴다.
    """
    ymin, xmin, ymax, xmax = box
    height, width = image.shape[:2]
    y0 = min(max(int(ymin * height / 1000), 0), height - 1)
    y1 = min(max(math.ceil(ymax * height / 1000), y0 + 1), height)
    x0, x1 = int(xmin * width / 1000), int(xmax * width / 1000)
    inset = (x1 - x0) // 10  # 칸 가장자리 테두리 · 그림자는 빼고 본다
    x0, x1 = max(x0 + inset, 0), min(x1 - inset, width)
    if x1 - x0 < 2:
        return ymin, ymax

    pixels = image.astype(np.int16)
    color = _mode_color(pixels[y0:y1, x0:x1].reshape(-1, 3))
    background = _mode_color(pixels[::4, ::4].reshape(-1, 3))
    if np.abs(color - background).max() <= COLOR_TOLERANCE:
        return ymin, ymax

    same = np.abs(pixels[:, x0:x1] - color).max(axis=2) <= COLOR_TOLERANCE
    fraction = same.mean(axis=1)
    seed = y0 + int(fraction[y0:y1].argmax())
    match = fraction >= ROW_FRACTION
    if not match[seed]:
        return ymin, ymax
    gap = max(2, int(height * GAP_RATIO))
    top, bottom = _grow(match, seed, -1, gap), _grow(match, seed, 1, gap)
    return round(top * 1000 / height), round((bottom + 1) * 1000 / height)


def grid_to_raw(grid: TimetableGrid, image: np.ndarray | None) -> RawTimetable:
    """모델이 읽은 위치를 시각으로 바꾼다. image가 있으면 칸 색으로 위아래를 먼저 맞춘다"""
    scale = hour_scale(grid.hours)
    blocks = []
    for block in grid.blocks:
        start = end = ""
        if scale is not None and len(block.box_2d) == 4:
            top, bottom = block.box_2d[0], block.box_2d[2]
            if image is not None:
                top, bottom = refine_rows(image, block.box_2d)
            start, end = position_text(top, scale), position_text(bottom, scale)
        blocks.append(RawBlock(name=block.name, weekday=block.weekday, start=start, end=end))
    return RawTimetable(blocks=blocks, untimed=grid.untimed)


def decode_image(data: bytes) -> np.ndarray | None:
    """이미지를 RGB 배열로. 열 수 없는 형식(HEIC 등)이면 None (색 보정 없이 진행)"""
    try:
        with Image.open(io.BytesIO(data)) as opened:
            return np.asarray(ImageOps.exif_transpose(opened).convert("RGB"))
    except Exception:
        return None


def parse_timetable(image: bytes, mime_type: str) -> list[Subject]:
    """시간표 캡처에서 과목 후보를 뽑는다. Gemini가 끝내 실패하면 GeminiError."""
    contents = [types.Part.from_bytes(data=image, mime_type=mime_type), PROMPT]
    grid, _ = ask_json(contents, TimetableGrid, model=get_settings().timetable_model)
    return normalize(grid_to_raw(grid, decode_image(image)))


if __name__ == "__main__":
    # 확인용: uv run python -m app.services.timetable_ocr <캡처 경로>
    path = Path(sys.argv[1])
    mime = mimetypes.guess_type(path.name)[0] or "image/png"
    subjects = parse_timetable(path.read_bytes(), mime)
    print(get_settings().timetable_model)
    print(json.dumps([s.model_dump() for s in subjects], ensure_ascii=False, indent=2))
