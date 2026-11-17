import numpy as np
import pytest
from app.services.timetable_ocr import (
    BlockBox,
    HourMark,
    TimetableGrid,
    grid_to_raw,
    hour_scale,
    refine_rows,
)

RED = (200, 90, 80)
BLUE = (100, 130, 200)
WHITE = (255, 255, 255)


def canvas(height=1000, width=100):
    """검은 바탕 이미지 (H x W x 3)"""
    return np.zeros((height, width, 3), dtype=np.uint8)


def paint(img, y0, y1, x0, x1, color):
    img[y0:y1, x0:x1] = color
    return img


def mark(hour, ymin):
    return HourMark(hour=hour, box_2d=[ymin, 0, ymin + 20, 50])


# ── 눈금 → 시각 ───────────────────────────────────────


def test_hour_scale_fits_labels():
    a, b = hour_scale([mark(9, 36), mark(10, 111), mark(13, 336)])
    assert a == pytest.approx(75)
    assert b == pytest.approx(-639)


def test_hour_scale_needs_two_distinct_hours():
    assert hour_scale([mark(9, 36)]) is None
    assert hour_scale([]) is None


def test_grid_to_raw_converts_positions():
    grid = TimetableGrid(
        blocks=[BlockBox(name="자료구조", weekday=1, box_2d=[250, 10, 400, 90])],
        hours=[mark(9, 100), mark(10, 200), mark(11, 300), mark(12, 400)],
        untimed=["사이버강의"],
    )
    raw = grid_to_raw(grid, image=None)
    block = raw.blocks[0]
    assert (block.name, block.weekday, block.start, block.end) == ("자료구조", 1, "10:30", "12:00")
    assert raw.untimed == ["사이버강의"]


def test_grid_without_hours_gives_unreadable_times():
    grid = TimetableGrid(
        blocks=[BlockBox(name="자료구조", weekday=1, box_2d=[250, 10, 400, 90])],
        hours=[],
        untimed=[],
    )
    block = grid_to_raw(grid, image=None).blocks[0]
    assert (block.start, block.end) == ("", "")


# ── 색으로 칸 위아래 맞추기 (이미지 높이 1000 → 0~1000 좌표와 픽셀이 같음) ──


def test_refine_extends_box_cut_at_text():
    img = paint(canvas(), 200, 600, 10, 90, RED)
    paint(img, 210, 230, 15, 45, WHITE)  # 과목명 글씨
    assert refine_rows(img, [200, 100, 300, 900]) == pytest.approx((200, 600), abs=2)


def test_refine_shrinks_box_too_tall():
    img = paint(canvas(), 200, 600, 10, 90, RED)
    assert refine_rows(img, [150, 100, 700, 900]) == pytest.approx((200, 600), abs=2)


def test_refine_stops_at_adjacent_block():
    img = paint(canvas(), 200, 400, 10, 90, RED)
    paint(img, 402, 600, 10, 90, BLUE)
    assert refine_rows(img, [200, 100, 300, 900]) == pytest.approx((200, 400), abs=2)


def test_refine_passes_through_wide_title_text():
    img = paint(canvas(), 200, 600, 10, 90, RED)
    paint(img, 205, 235, 12, 85, WHITE)  # 칸 너비 거의 전부를 덮는 굵은 제목
    assert refine_rows(img, [240, 100, 600, 900]) == pytest.approx((200, 600), abs=2)


def test_refine_keeps_box_when_no_block_color():
    img = canvas()
    assert refine_rows(img, [200, 100, 300, 900]) == (200, 300)


def test_grid_to_raw_uses_image_to_fix_end():
    img = paint(canvas(), 200, 400, 10, 90, RED)
    grid = TimetableGrid(
        blocks=[BlockBox(name="자료구조", weekday=0, box_2d=[200, 100, 260, 900])],
        hours=[mark(9, 100), mark(10, 200), mark(11, 300), mark(12, 400)],
        untimed=[],
    )
    block = grid_to_raw(grid, image=img).blocks[0]
    assert (block.start, block.end) == ("10:00", "12:00")
