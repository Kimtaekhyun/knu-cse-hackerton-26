"""판서 처리 워커. AI는 가짜로 바꾸고, OpenCV는 합성한 프로젝터 사진으로 실제로 돌린다."""

import uuid
from contextlib import nullcontext

import cv2
import numpy as np
import pytest
from sqlalchemy import select

from app.core.config import get_settings
from app.models import Capture, CaptureStatus, Card, CardType
from app.services.captures import capture_dir
from app.services.llm import LLMError
from app.services.pipeline import worker
from app.services.pipeline.regions import NoteRegion
from app.storage import local as storage
from tests.db.factories import make_capture, make_card, make_semester, make_user


@pytest.fixture(autouse=True)
def media_dir(tmp_path, monkeypatch):
    monkeypatch.setenv("MEDIA_DIR", str(tmp_path))
    get_settings.cache_clear()
    yield tmp_path
    get_settings.cache_clear()


@pytest.fixture
def owner(db):
    user = make_user(db)
    return user, make_semester(db, user)


def screen_photo() -> bytes:
    """어두운 교실에 밝은 프로젝터 화면이 있고, 화면 가운데에 검은 펜 필기가 있는 사진"""
    img = np.full((900, 1200, 3), 40, np.uint8)
    cv2.rectangle(img, (150, 150), (1050, 700), (235, 235, 235), -1)
    for i, y in enumerate((360, 420, 480)):
        cv2.line(img, (450, y), (700 + i * 20, y), (20, 20, 20), 6)
    return cv2.imencode(".jpg", img)[1].tobytes()


def plain_photo() -> bytes:
    """화면이 없는 사진. 밝은 물체가 세로로 길어서(문 등) 화면 비율이 아니다"""
    img = np.full((900, 1200, 3), 40, np.uint8)
    cv2.rectangle(img, (500, 100), (750, 800), (235, 235, 235), -1)
    return cv2.imencode(".jpg", img)[1].tobytes()


def region(**kw) -> NoteRegion:
    values = {
        "box_2d": [300, 300, 700, 700],
        "title": "점화식",
        "kind": "text",
        "card_type": "math",
        "lines": ["$T(n) = 2T(n/2) + n$", "$= O(n \\log n)$"],
    }
    return NoteRegion(**(values | kw))


def uploaded(db, owner, photo: bytes, **kw) -> Capture:
    user, semester = owner
    capture = make_capture(db, user, semester, status=CaptureStatus.uploaded, original_key="", **kw)
    capture.original_key = f"{capture_dir(capture.id)}/original.jpg"
    storage.save(capture.original_key, photo)
    db.flush()
    return capture


def run(db, capture_id, **kw):
    worker.process_capture(capture_id, session_factory=lambda: nullcontext(db), **kw)
    db.expire_all()
    return db.get(Capture, capture_id)


@pytest.fixture
def ai(monkeypatch):
    """가짜 AI. answer에 덩어리 목록이나 예외를 넣는다. 받은 사진(JPEG)은 seen에 남는다"""
    state = {"answer": [region()], "seen": []}

    def fake(image_jpeg):
        state["seen"].append(image_jpeg)
        if isinstance(state["answer"], Exception):
            raise state["answer"]
        return state["answer"], {"seconds": 0.0}

    monkeypatch.setattr(worker, "ask_regions", fake)
    return state


def cards_of(db, capture) -> list[Card]:
    return list(
        db.scalars(select(Card).where(Card.capture_id == capture.id).order_by(Card.order_no))
    )


# ---------- 성공 ----------


def test_processes_photo_into_cards(db, owner, ai):
    capture = run(db, uploaded(db, owner, screen_photo()).id)

    assert (capture.status, capture.fail_reason) == (CaptureStatus.done, None)
    assert storage.exists(capture.rectified_key)
    assert len(ai["seen"]) == 1  # AI에는 보정본을 한 번만 보낸다

    (card,) = cards_of(db, capture)
    assert (card.order_no, card.title, card.card_type) == (1, "점화식", CardType.math)
    assert card.content == card.original_content == "$T(n) = 2T(n/2) + n$\n$= O(n \\log n)$"
    assert not card.is_moved
    assert all(0 <= card.bbox[k] <= 1 for k in "xywh") and card.bbox["w"] > 0
    crop = cv2.imdecode(
        np.frombuffer(storage.path(card.crop_image_key).read_bytes(), np.uint8),
        cv2.IMREAD_UNCHANGED,
    )
    assert crop.shape[2] == 4  # 투명 배경 PNG (BGRA)
    assert crop[..., 3].max() == 255  # 필기 부분은 보인다


def test_rectified_photo_is_straightened_and_shrunk(db, owner, ai):
    capture = run(db, uploaded(db, owner, screen_photo()).id)
    rectified = cv2.imdecode(
        np.frombuffer(storage.path(capture.rectified_key).read_bytes(), np.uint8),
        cv2.IMREAD_COLOR,
    )
    # 화면(900 × 550)에 사방 12% 여백을 둔 크기. 원본(1200 × 900)과 다르다
    assert abs(rectified.shape[1] - 900 * 1.24) < 30
    assert abs(rectified.shape[0] - 550 * 1.24) < 30


def test_skips_tiny_and_broken_boxes(db, owner, ai):
    ai["answer"] = [
        region(box_2d=[300, 300, 302, 700]),  # 너무 얇음
        region(box_2d=[1, 2, 3]),  # 좌표가 3개
        region(title="두 번째", card_type="이상한값"),
    ]
    capture = run(db, uploaded(db, owner, screen_photo()).id)
    (card,) = cards_of(db, capture)
    assert (card.order_no, card.title, card.card_type) == (1, "두 번째", CardType.text)


def test_no_regions_is_done_without_cards(db, owner, ai):
    ai["answer"] = []
    capture = run(db, uploaded(db, owner, screen_photo()).id)
    assert capture.status == CaptureStatus.done
    assert cards_of(db, capture) == []


def test_resumed_capture_replaces_old_cards(db, owner, ai):
    """interpreting 중에 꺼졌다 다시 처리해도 카드가 두 벌 생기지 않는다"""
    capture = uploaded(db, owner, screen_photo())
    capture.status = CaptureStatus.interpreting
    make_card(db, capture, 1, title="예전 카드")
    capture = run(db, capture.id)
    assert [c.title for c in cards_of(db, capture)] == ["점화식"]


# ---------- 실패 ----------


def test_screen_not_found_fails_rectify_without_calling_ai(db, owner, ai):
    capture = run(db, uploaded(db, owner, plain_photo()).id)
    assert (capture.status, capture.fail_reason) == (CaptureStatus.failed, "rectify")
    assert ai["seen"] == []
    assert storage.exists(capture.original_key)  # 원본은 남긴다


def test_skip_rectify_uses_photo_as_is(db, owner, ai):
    """오류 화면의 "그대로 쓰기": 화면을 못 찾아도 사진 그대로 처리한다"""
    capture = run(db, uploaded(db, owner, plain_photo()).id, skip_rectify=True)
    assert capture.status == CaptureStatus.done
    assert len(ai["seen"]) == 1


def test_ai_failure_fails_segment(db, owner, ai):
    ai["answer"] = LLMError("한도 초과")
    capture = run(db, uploaded(db, owner, screen_photo()).id)
    assert (capture.status, capture.fail_reason) == (CaptureStatus.failed, "segment")
    assert storage.exists(capture.rectified_key)  # 다시 처리할 때 덮어쓴다


def test_unreadable_photo_fails_unknown(db, owner, ai):
    capture = run(db, uploaded(db, owner, b"not an image").id)
    assert (capture.status, capture.fail_reason) == (CaptureStatus.failed, "unknown")


def test_card_building_error_fails_interpret(db, owner, ai, monkeypatch):
    def broken(*args):
        raise RuntimeError("버그")

    monkeypatch.setattr(worker, "build_cards", broken)
    capture = run(db, uploaded(db, owner, screen_photo()).id)
    assert (capture.status, capture.fail_reason) == (CaptureStatus.failed, "interpret")


# ---------- 건너뛰기 ----------


@pytest.mark.parametrize("status", [CaptureStatus.done, CaptureStatus.failed])
def test_finished_capture_is_not_processed_again(db, owner, ai, status):
    capture = uploaded(db, owner, screen_photo())
    capture.status = status
    db.flush()
    assert run(db, capture.id).status == status
    assert ai["seen"] == []


def test_missing_capture_is_ignored(db, ai):
    worker.process_capture(uuid.uuid4(), session_factory=lambda: nullcontext(db))
    assert ai["seen"] == []


def test_capture_deleted_while_processing_cleans_files(db, owner, monkeypatch):
    """AI를 기다리는 사이 사용자가 판서를 지우면 만들던 파일까지 지운다"""
    capture = uploaded(db, owner, screen_photo())
    capture_id = capture.id

    def delete_then_answer(image_jpeg):
        db.delete(db.get(Capture, capture_id))
        db.commit()
        return [region()], {}

    monkeypatch.setattr(worker, "ask_regions", delete_then_answer)
    worker.process_capture(capture_id, session_factory=lambda: nullcontext(db))
    assert db.get(Capture, capture_id) is None
    assert not storage.path(capture_dir(capture_id)).exists()


# ---------- 다시 켤 때 ----------


def test_resume_unfinished_enqueues_in_upload_order(db, owner, monkeypatch):
    statuses = [
        CaptureStatus.uploaded,
        CaptureStatus.done,
        CaptureStatus.segmenting,
        CaptureStatus.failed,
        CaptureStatus.interpreting,
    ]
    captures = [uploaded(db, owner, b"x") for _ in statuses]
    for capture, status in zip(captures, statuses, strict=True):
        capture.status = status
    db.flush()
    queued = []
    monkeypatch.setattr(worker, "enqueue", lambda capture_id, **kw: queued.append(capture_id))

    count = worker.resume_unfinished(session_factory=lambda: nullcontext(db))
    unfinished = [captures[0], captures[2], captures[4]]
    expected = sorted(unfinished, key=lambda c: (c.created_at, c.id))
    assert count == 3
    assert queued == [c.id for c in expected]
