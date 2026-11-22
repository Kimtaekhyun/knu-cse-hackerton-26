"""카드 API: 수정 · 되돌리기 · 옮김 표시 · 삭제 · 스티커 이미지.

카드는 판서 상세(GET /captures/{id})의 cards로도 받는다.
여기서는 카드 하나를 바꾸거나 스티커를 받는다.
"""

import uuid

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse

from app.api.deps import DbDep, UserDep, WriteUserDep
from app.schemas.card import CardDetail, CardsMovedIn, CardUpdate
from app.services import cards as service
from app.storage import local as storage

router = APIRouter(prefix="/cards", tags=["cards"])


# /{card_id}보다 먼저 둬야 "moved"가 id로 읽히지 않는다
@router.put("/moved", response_model=list[CardDetail])
def set_moved(body: CardsMovedIn, db: DbDep, user: WriteUserDep):
    """옮김 표시 · 취소 (굿노트로 끌어다 놓기 · 복사 · "N개 복사", 수동 되돌리기)

    여러 장을 한 번에 바꾼다. 하나라도 내 카드가 아니면 아무것도 바꾸지 않고 404.
    "아직 옮기지 않은 판서"(GET /captures?unmoved=true)는 옮기지 않은 카드가 남은 판서다.
    """
    cards = service.set_moved(db, user, body.card_ids, body.moved)
    db.commit()
    return [service.card_detail(card) for card in cards]


@router.get("/{card_id}", response_model=CardDetail)
def get_card(card_id: uuid.UUID, db: DbDep, user: UserDep):
    return service.card_detail(service.get_card(db, user, card_id))


@router.patch("/{card_id}", response_model=CardDetail)
def update_card(card_id: uuid.UUID, body: CardUpdate, db: DbDep, user: WriteUserDep):
    """제목 · 내용 · 종류 중 보낸 것만 고친다. 처음 인식 결과는 남아서 되돌릴 수 있다"""
    card = service.get_card(db, user, card_id)
    service.ensure_editable(card)
    service.update_card(card, body)
    db.commit()
    return service.card_detail(card)


@router.post("/{card_id}/revert", response_model=CardDetail)
def revert_card(card_id: uuid.UUID, db: DbDep, user: WriteUserDep):
    """원래대로 되돌리기: 내용을 처음 인식 결과로"""
    card = service.get_card(db, user, card_id)
    service.ensure_editable(card)
    service.revert_card(card)
    db.commit()
    return service.card_detail(card)


@router.delete("/{card_id}", status_code=204)
def delete_card(card_id: uuid.UUID, db: DbDep, user: WriteUserDep):
    """카드와 스티커 PNG를 지운다. 판서 · 다른 카드는 그대로"""
    card = service.get_card(db, user, card_id)
    service.ensure_editable(card)
    service.delete_card(db, card)


@router.get("/{card_id}/image", response_class=FileResponse)
def get_image(card_id: uuid.UUID, db: DbDep, user: UserDep):
    """카드 스티커: 손글씨만 남긴 투명 PNG (손글씨 보기 · 드래그용, 복사 색은 앱이 입힌다)"""
    card = service.get_card(db, user, card_id)
    if not storage.exists(card.crop_image_key):
        raise HTTPException(404, "스티커 이미지가 없어요.")
    return FileResponse(storage.path(card.crop_image_key), media_type="image/png")
