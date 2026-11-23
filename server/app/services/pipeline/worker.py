"""판서 처리 워커: 올라온 판서를 뒤에서 한 장씩 처리해 카드를 만든다.

단계마다 status를 커밋하므로 앱은 GET /captures/{id}로 지금 단계를 볼 수 있다 (처리 중 화면 10-1~3).
  uploaded → rectifying(화면 펴기) → segmenting(AI가 덩어리 찾기)
  → interpreting(상자 다듬기 · 카드 저장) → done
  실패하면 failed + fail_reason(too_large / rectify / segment / interpret / unknown)
  too_large: 사진 해상도가 상한(image_limits.MAX_PIXELS)을 넘어 열지 않음

- 작업 스레드는 PIPELINE_WORKERS개(기본 1). 1이면 올린 순서대로 처리된다.
- 서버가 처리 중에 꺼지면 다시 켤 때 resume_unfinished()가 멈춘 판서를 다시 줄에 세운다.
  카드는 마지막에 한 번에 커밋하므로 반쯤 만든 카드가 남지 않는다.
- 처리 중에 판서가 지워지면 만들던 파일을 지우고 그만둔다.
"""

import logging
import threading
import uuid
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from contextlib import AbstractContextManager

import numpy as np
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.db.session import SessionLocal
from app.models import Capture, CaptureStatus, Card
from app.services import image_limits
from app.services.captures import capture_dir, card_crop_key, rectified_key
from app.services.llm import LLMError
from app.services.pipeline import vision
from app.services.pipeline.regions import NoteRegion, ask_regions, card_type_of
from app.storage import local as storage

logger = logging.getLogger(__name__)

# 촬영 화면에 펜 종류를 고르는 곳이 아직 없어서 검은 펜(프로젝터)으로 고정한다
PEN = "black"
# 아직 처리가 끝나지 않은 상태. 서버를 다시 켜면 이 판서들을 다시 처리한다
UNFINISHED = (
    CaptureStatus.uploaded,
    CaptureStatus.rectifying,
    CaptureStatus.segmenting,
    CaptureStatus.interpreting,
)
# 이보다 작은 상자(픽셀)는 AI가 잘못 짚은 것으로 보고 버린다
MIN_BOX = 10

SessionFactory = Callable[[], AbstractContextManager[Session]]


class StageFailed(Exception):
    """처리 단계 하나가 실패함. reason이 그대로 fail_reason이 된다"""

    def __init__(self, reason: str):
        super().__init__(reason)
        self.reason = reason


# ---------- 판서 한 장 처리 ----------


def process_capture(
    capture_id: uuid.UUID,
    *,
    skip_rectify: bool = False,
    session_factory: SessionFactory = SessionLocal,
) -> None:
    """판서 한 장을 끝까지 처리한다. 실패는 DB에 남기고 예외를 밖으로 내지 않는다.

    skip_rectify: 화면을 못 찾아도 실패하지 않고 사진 그대로 쓴다 (오류 화면의 "그대로 쓰기")
    """
    with session_factory() as db:
        capture = db.get(Capture, capture_id)
        if capture is None or capture.status not in UNFINISHED:
            return  # 지워졌거나 이미 끝난 판서 (같은 판서가 두 번 줄에 선 경우)
        try:
            image = rectify(db, capture, skip_rectify)
            jpeg = vision.encode_jpeg(image)
            storage.save(rectified_key(capture_id), jpeg)
            capture.rectified_key = rectified_key(capture_id)

            set_status(db, capture, CaptureStatus.segmenting)  # 각 단계별로 지정해서 status update
            try:
                regions, info = ask_regions(jpeg)
            except LLMError as error:
                logger.warning("판서 %s 덩어리 찾기 실패: %s", capture_id, error)
                raise StageFailed("segment") from error
            logger.info("판서 %s 덩어리 %d개 (%s)", capture_id, len(regions), info)

            set_status(db, capture, CaptureStatus.interpreting)
            try:
                cards = build_cards(capture_id, image, regions)
            except Exception as error:
                logger.exception("판서 %s 카드 만들기 실패", capture_id)
                raise StageFailed("interpret") from error
            finish(db, capture_id, cards)
        except StageFailed as failed:
            mark_failed(db, capture_id, failed.reason)
        except Exception:
            logger.exception("판서 %s 처리 중 알 수 없는 오류", capture_id)
            mark_failed(db, capture_id, "unknown")


#  워커가 단계마다 set_status()로 커밋하므로 다른 요청(GET)에서도 지금 단계가 보임
def set_status(db: Session, capture: Capture, status: CaptureStatus) -> None:
    capture.status = status
    db.commit()


def rectify(db: Session, capture: Capture, skip_rectify: bool) -> np.ndarray:
    """원본을 읽어 화면을 찾아 펴고 줄인 사진을 돌려준다. 화면을 못 찾으면 StageFailed("rectify")"""
    set_status(db, capture, CaptureStatus.rectifying)
    data = storage.path(capture.original_key).read_bytes()
    # 거대한 사진을 열면 메모리가 바닥나 서버가 죽고,
    # 다시 켤 때 같은 판서를 또 열어 또 죽는다 (#130). 업로드에서도 막지만,
    # 이미 저장된 원본 · "다시 처리"에 대비해 열기 전에 한 번 더 확인한다
    try:
        image_limits.check_pixels(data)
    except image_limits.TooManyPixels as error:
        raise StageFailed("too_large") from error
    original = vision.decode(data)
    corners = vision.find_screen(original) if PEN != "board" else None
    if corners is None and not skip_rectify:
        raise StageFailed("rectify")
    straight = original if corners is None else vision.straighten(original, corners)
    return vision.shrink(straight)


def build_cards(capture_id: uuid.UUID, image: np.ndarray, regions: list[NoteRegion]) -> list[Card]:
    """AI가 준 덩어리마다 상자를 필기에 맞게 다듬고 손글씨 조각(투명 PNG)을 저장한다"""
    h, w = image.shape[:2]
    mask = vision.ink_mask(image, PEN)
    clean = vision.remove_long_lines(mask)
    cards: list[Card] = []
    for region in regions:
        if len(region.box_2d) != 4:
            continue
        rough = vision.to_pixels(region.box_2d, w, h)
        if rough[2] - rough[0] < MIN_BOX or rough[3] - rough[1] < MIN_BOX:
            continue
        box = vision.refine_box(clean, rough)
        card_id = uuid.uuid4()
        key = card_crop_key(capture_id, card_id)
        storage.save(key, vision.encode_png(vision.card_ink(image, mask, box)))
        content = "\n".join(region.lines)
        cards.append(
            Card(
                id=card_id,
                capture_id=capture_id,
                order_no=len(cards) + 1,
                title=region.title,
                card_type=card_type_of(region),
                content=content,
                original_content=content,
                bbox=vision.normalized(box, w, h),
                crop_image_key=key,
                is_moved=False,
            )
        )
    return cards


def finish(db: Session, capture_id: uuid.UUID, cards: list[Card]) -> None:
    """카드를 한 번에 저장하고 done으로 바꾼다.

    판서 행을 잠근 뒤 다시 읽어서, 그사이 지워졌으면 만든 파일을 지우고 그만둔다.
    서버가 interpreting 중에 꺼졌다가 다시 처리하는 경우를 위해 예전 카드는 지우고 넣는다.
    """
    capture = db.get(Capture, capture_id, with_for_update=True, populate_existing=True)
    if capture is None:
        db.rollback()
        storage.delete_tree(capture_dir(capture_id))
        return
    db.execute(delete(Card).where(Card.capture_id == capture_id))
    db.add_all(cards)
    capture.status = CaptureStatus.done
    capture.fail_reason = None
    db.commit()


def mark_failed(db: Session, capture_id: uuid.UUID, reason: str) -> None:
    """실패를 남긴다. 원본은 지우지 않는다 (다시 처리할 수 있게). 판서가 지워졌으면 파일만 정리"""
    db.rollback()
    capture = db.get(Capture, capture_id, populate_existing=True)
    if capture is None:
        storage.delete_tree(capture_dir(capture_id))
        return
    capture.status = CaptureStatus.failed
    capture.fail_reason = reason
    db.commit()


# ---------- 작업 줄 ----------

"""
    ThreadPoolExecutor(max_workers=1)는 작업 스레드 1개와 작업 대기 줄(큐)로 이루어짐. 
    - enqueue로 큐에 넣기만 하고 바로 리턴되어 원래 위치로 옴. 
"""
_executor: ThreadPoolExecutor | None = None
_executor_lock = threading.Lock()


def _get_executor() -> ThreadPoolExecutor:
    global _executor
    with _executor_lock:
        if _executor is None:
            workers = max(1, get_settings().pipeline_workers)
            _executor = ThreadPoolExecutor(max_workers=workers, thread_name_prefix="pipeline")
        return _executor


def enqueue(capture_id: uuid.UUID, *, skip_rectify: bool = False) -> None:
    """판서를 처리 줄 맨 뒤에 세운다. 바로 돌아오고 처리는 작업 스레드가 한다"""
    _get_executor().submit(_run, capture_id, skip_rectify)


def _run(capture_id: uuid.UUID, skip_rectify: bool) -> None:
    try:
        process_capture(capture_id, skip_rectify=skip_rectify)
    except Exception:  # 작업 스레드에서 난 예외는 아무도 받지 않으므로 여기서 남긴다
        logger.exception("판서 %s 처리 작업이 죽었어요", capture_id)


def resume_unfinished(session_factory: SessionFactory = SessionLocal) -> int:
    """서버가 켜질 때 처리 중에 멈춘 판서를 올린 순서대로 다시 줄에 세운다. 세운 수를 돌려준다"""
    with session_factory() as db:
        ids = list(
            db.scalars(
                select(Capture.id)
                .where(Capture.status.in_(UNFINISHED))
                .order_by(Capture.created_at, Capture.id)
            )
        )
    for capture_id in ids:
        enqueue(capture_id)
    return len(ids)


def shutdown() -> None:
    """서버를 끌 때. 기다리는 작업은 버린다 (다음에 켤 때 resume_unfinished가 다시 세운다)"""
    global _executor
    with _executor_lock:
        if _executor is not None:
            _executor.shutdown(wait=False, cancel_futures=True)
            _executor = None
