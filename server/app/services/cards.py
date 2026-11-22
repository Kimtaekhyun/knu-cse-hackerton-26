"""카드 고치기 · 되돌리기 · 옮김 표시 · 삭제 규칙과 응답 만들기.

라우터(app/api/v1/cards.py)는 요청 확인만 하고 실제 처리는 여기서 한다.
카드는 판서 처리(워커)가 만든다.
처리 중이거나 실패한 판서의 카드는 다시 처리할 때 새로 만들어지므로 바꾸지 않는다.
"""

import uuid
from datetime import UTC, datetime

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from app.models import Capture, CaptureStatus, Card, User
from app.schemas.card import CardDetail, CardUpdate
from app.services.captures import card_out
from app.storage import local as storage

NOT_FOUND = "카드를 찾을 수 없어요."


def _mine(user: User):
    """내 판서의 카드만 (남의 카드는 없는 것으로 본다: 404)"""
    return (
        select(Card)
        .join(Capture, Card.capture_id == Capture.id)
        .where(Capture.user_id == user.id)
        .options(selectinload(Card.capture))
    )


def get_card(db: Session, user: User, card_id: uuid.UUID) -> Card:
    card = db.scalars(_mine(user).where(Card.id == card_id)).first()
    if card is None:
        raise HTTPException(404, NOT_FOUND)
    return card


def ensure_editable(card: Card) -> None:
    """정리가 끝난 판서의 카드만 바꾼다. 다시 처리하면 카드를 지우고 새로 만들기 때문"""
    if card.capture.status != CaptureStatus.done:
        raise HTTPException(409, "판서를 정리하는 중이라 카드를 바꿀 수 없어요.")


def update_card(card: Card, body: CardUpdate) -> None:
    """보낸 것만 바꾼다. 실제로 바뀐 게 있으면 고친 시각을 남긴다"""
    changed = False
    for field in body.model_fields_set:
        value = getattr(body, field)
        if value is not None and getattr(card, field) != value:
            setattr(card, field, value)
            changed = True
    if changed:
        card.edited_at = datetime.now(UTC)


def revert_card(card: Card) -> None:
    """내용을 처음 인식 결과로 되돌린다"""
    card.content = card.original_content
    card.edited_at = None


def set_moved(db: Session, user: User, card_ids: list[uuid.UUID], moved: bool) -> list[Card]:
    """여러 카드의 옮김 표시를 한 번에 바꾼다. 보낸 순서대로 돌려준다

    하나라도 내 카드가 아니거나 정리 중인 판서의 카드면 아무것도 바꾸지 않는다.
    이미 같은 상태인 카드는 그대로 둔다 (다시 보내도 결과가 같고, 처음 옮긴 시각이 남는다).
    """
    unique = list(dict.fromkeys(card_ids))
    cards = {card.id: card for card in db.scalars(_mine(user).where(Card.id.in_(unique)))}
    if len(cards) != len(unique):
        raise HTTPException(404, NOT_FOUND)
    for card in cards.values():
        ensure_editable(card)
    now = datetime.now(UTC)
    for card in cards.values():
        if card.is_moved != moved:
            card.is_moved = moved
            card.moved_at = now if moved else None
    return [cards[card_id] for card_id in unique]


def delete_card(db: Session, card: Card) -> None:
    """DB를 먼저 지우고(커밋) 스티커 파일을 지운다 (판서 삭제와 같은 순서).

    순서를 거꾸로 하면 커밋이 실패했을 때 "스티커 파일이 없는 카드"가 남는다.
    남은 카드 번호(order_no)는 그대로 둔다 (결과 화면의 번호가 갑자기 바뀌지 않게).
    """
    key = card.crop_image_key
    db.delete(card)
    db.commit()
    storage.delete(key)


def card_detail(card: Card) -> CardDetail:
    return CardDetail(**card_out(card).model_dump(), capture_id=card.capture_id)
