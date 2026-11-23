"""판서(캡처) API: 올리기 · 목록 · 상세 · 과목으로 옮기기 · 삭제 · 사진 · 다시 처리 · 저장 위치.

처리(판서 펴기 → 글씨 찾기 → 정리)는 서버가 뒤에서 한다 (app/services/pipeline/worker.py).
앱은 올린 뒤 GET /captures/{id}를 주기적으로 불러 status가 done · failed가 될 때까지 기다린다.
"""

import uuid
from datetime import datetime
from typing import Annotated, Literal

from fastapi import APIRouter, File, Form, HTTPException, Query, Response, UploadFile
from fastapi.responses import FileResponse

from app.api.deps import DbDep, UserDep, WriteUserDep
from app.schemas.capture import CaptureDetail, CaptureMove, CaptureOut, CaptureRetry, Destination
from app.services import captures as service
from app.services import image_limits
from app.services.pipeline import worker
from app.storage import local as storage

router = APIRouter(prefix="/captures", tags=["captures"])

# HEIC는 받지 않는다. 서버(Pillow · OpenCV)가 열 수 없고, 앱은 올리기 전에 JPEG로 바꿔 보낸다
EXTENSIONS = {"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp"}
MAX_BYTES = 10 * 1024 * 1024


def read_image(image: UploadFile) -> tuple[bytes, str]:
    """(이미지, 확장자). 형식 · 용량 · 해상도가 맞지 않으면 4xx

    저장하기 전에 검사하므로 거절한 사진은 파일도 DB 행도 남지 않는다.
    """
    extension = EXTENSIONS.get(image.content_type or "")
    if extension is None:
        raise HTTPException(415, "이미지 파일(JPEG, PNG, WEBP)만 올릴 수 있어요.")
    data = image.file.read(MAX_BYTES + 1)
    if not data:
        raise HTTPException(400, "빈 파일이에요.")
    if len(data) > MAX_BYTES:
        raise HTTPException(413, "이미지가 10MB를 넘어요.")
    # 용량이 작아도 해상도가 크면 처리할 때 서버 메모리가 바닥난다 (#130). 헤더만 읽어 확인한다
    try:
        image_limits.check_pixels(data)
    except image_limits.TooManyPixels as error:
        raise HTTPException(413, "사진 해상도가 너무 커요.") from error
    except image_limits.UnreadableImage as error:
        raise HTTPException(400, "사진을 읽지 못했어요.") from error
    return data, extension


# 202: 요청은 받았고, 처리는 아직이란 뜻.
# (AI 처리는 10초 이상 걸릴수있고, 요청 하나로 끝까지 기다리는 앱의 요청이 시간초과로 끊김)
@router.post("", response_model=CaptureDetail, status_code=202)
def upload(
    response: Response,
    db: DbDep,
    user: WriteUserDep,
    image: Annotated[UploadFile, File()],
    capture_id: Annotated[
        uuid.UUID | None,
        Form(alias="id", description="앱이 만든 판서 id. 답을 못 받아 다시 보낼 때 같은 값을 쓴다"),
    ] = None,
    taken_at: Annotated[
        datetime | None,
        Form(description="셔터를 누른 시각 (앨범은 찍은 시각). 없으면 지금. 시간대가 없으면 서울"),
    ] = None,
    subject_id: Annotated[
        uuid.UUID | None,
        Form(description="저장할 과목. 없으면 찍은 시각의 수업으로 자동 분류한다"),
    ] = None,
):
    """판서 사진을 받아 저장하고 처리 줄에 세운다. 처음은 202, 이미 받은 id를 다시 보내면 200.

    사용자 잠금(WriteUserDep) 안에서 확인하므로 같은 id가 동시에 와도 하나만 저장된다.
    처리 줄에는 DB 커밋이 끝난 뒤에 세운다 (워커가 아직 없는 판서를 찾지 않게).
    """
    if capture_id is not None and (resent := service.find_resent(db, user, capture_id)):
        response.status_code = 200
        return service.capture_detail(db, resent)
    data, extension = read_image(image)
    capture = service.create_capture(
        db,
        user,
        capture_id=capture_id or uuid.uuid4(),
        image=data,
        extension=extension,
        taken_at=taken_at or datetime.now(service.SEOUL),
        subject_id=subject_id,
    )
    worker.enqueue(capture.id)
    return service.capture_detail(db, capture)


@router.get("/destination", response_model=Destination)
def get_destination(db: DbDep, user: UserDep, at: datetime | None = None):
    """지금(at, 없으면 현재 시각) 찍으면 어느 과목에 저장되는지. 촬영 화면의 "○○ 폴더에 저장"

    과목이 null이면 미분류함. 틀렸으면 앱이 과목을 골라 업로드에 subject_id로 보낸다.
    /{capture_id}보다 먼저 선언해야 "destination"이 판서 id로 읽히지 않는다.
    """
    return service.destination(db, user, at or datetime.now(service.SEOUL))


@router.get("", response_model=list[CaptureOut])
def list_captures(
    db: DbDep,
    user: UserDep,
    subject_id: uuid.UUID | None = None,
    unsorted: bool = False,
    unmoved: bool = False,
    before: datetime | None = None,
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
):
    """최신 판서부터. 과목 폴더(subject_id) · 미분류함(unsorted) · 옮기지 않은 판서(unmoved)"""
    captures = service.list_captures(
        db,
        user,
        subject_id=subject_id,
        unsorted=unsorted,
        unmoved=unmoved,
        before=before,
        limit=limit,
    )
    return service.capture_outs(db, captures)


@router.get("/{capture_id}", response_model=CaptureDetail)
def get_capture(capture_id: uuid.UUID, db: DbDep, user: UserDep):
    """처리 상태 · 결과. 처리 중 화면은 이걸 1초쯤마다 불러 status를 확인한다"""
    return service.capture_detail(db, service.get_capture(db, user, capture_id))


@router.patch("/{capture_id}", response_model=CaptureDetail)
def move_capture(capture_id: uuid.UUID, body: CaptureMove, db: DbDep, user: WriteUserDep):
    """과목으로 옮기기 (미분류함 → 과목, 과목 → 과목, 과목 → 미분류함)"""
    capture = service.get_capture(db, user, capture_id)
    service.move_capture(db, user, capture, body.subject_id)
    return service.capture_detail(db, capture)


@router.post("/{capture_id}/retry", response_model=CaptureDetail, status_code=202)
def retry_capture(
    capture_id: uuid.UUID, db: DbDep, user: WriteUserDep, body: CaptureRetry | None = None
):
    """처리에 실패한 판서를 다시 처리한다. skip_rectify면 화면을 못 찾아도 사진 그대로 쓴다"""
    capture = service.get_capture(db, user, capture_id)
    service.reset_for_retry(db, capture)
    worker.enqueue(capture.id, skip_rectify=body is not None and body.skip_rectify)
    return service.capture_detail(db, capture)


@router.delete("/{capture_id}", status_code=204)
def delete_capture(capture_id: uuid.UUID, db: DbDep, user: WriteUserDep):
    """판서 삭제. 카드와 사진 파일도 함께 지운다"""
    service.delete_capture(db, service.get_capture(db, user, capture_id))


@router.get("/{capture_id}/image", response_class=FileResponse)
def get_image(
    capture_id: uuid.UUID,
    db: DbDep,
    user: UserDep,
    kind: Literal["original", "rectified"] = "original",
):
    """찍은 사진(original) 또는 반듯하게 편 사진(rectified, 처리 후에만 있음)"""
    capture = service.get_capture(db, user, capture_id)
    key = capture.original_key if kind == "original" else capture.rectified_key
    if key is None or not storage.exists(key):
        raise HTTPException(404, "사진이 아직 없어요.")
    return FileResponse(storage.path(key))
