"""카드 API: 수정 · 되돌리기 · 옮김 표시 · 삭제 · 스티커 이미지 (#88)."""

import uuid

import pytest

from app.core.config import get_settings
from app.models import CaptureStatus, Card
from app.storage import local as storage
from tests.api.conftest import bearer
from tests.db.factories import make_capture, make_card, make_semester, make_user

URL = "/api/v1/cards"
PNG = b"\x89PNG\r\n\x1a\nfake"


@pytest.fixture(autouse=True)
def media_dir(tmp_path, monkeypatch, jwt_settings):
    """스티커를 테스트마다 새 임시 폴더에 저장한다"""
    monkeypatch.setenv("MEDIA_DIR", str(tmp_path))
    get_settings.cache_clear()
    yield tmp_path
    get_settings.cache_clear()


@pytest.fixture
def capture(db, user):
    return make_capture(db, user, make_semester(db, user))


@pytest.fixture
def card(db, capture):
    return make_card(db, capture, 1, content="x^2 + 1", original_content="x^2 + 1")


# ---------- 조회 ----------


def test_get_card(client, auth, card, capture):
    response = client.get(f"{URL}/{card.id}", headers=auth)
    assert response.status_code == 200
    body = response.json()
    assert body["id"] == str(card.id)
    assert body["capture_id"] == str(capture.id)
    assert body["content"] == "x^2 + 1"
    assert body["is_edited"] is False
    assert body["is_moved"] is False


def test_other_users_card_is_404(client, db):
    other = make_user(db)
    theirs = make_card(db, make_capture(db, other, make_semester(db, other)), 1)
    me = make_user(db)
    headers = bearer(me.id)
    assert client.get(f"{URL}/{theirs.id}", headers=headers).status_code == 404
    assert (
        client.patch(f"{URL}/{theirs.id}", json={"title": "x"}, headers=headers).status_code == 404
    )
    assert client.delete(f"{URL}/{theirs.id}", headers=headers).status_code == 404
    assert client.get(f"{URL}/{theirs.id}/image", headers=headers).status_code == 404


def test_unknown_card_is_404(client, auth):
    assert client.get(f"{URL}/{uuid.uuid4()}", headers=auth).status_code == 404


def test_without_token_is_401(client, card):
    assert client.get(f"{URL}/{card.id}").status_code == 401
    assert (
        client.put(f"{URL}/moved", json={"card_ids": [str(card.id)], "moved": True}).status_code
        == 401
    )


# ---------- 수정 · 되돌리기 ----------


def test_update_only_sent_fields(client, auth, card, db):
    response = client.patch(f"{URL}/{card.id}", json={"content": "  x^2 + 2  "}, headers=auth)
    assert response.status_code == 200
    body = response.json()
    assert body["content"] == "x^2 + 2"  # 앞뒤 공백 제거
    assert body["title"] == card.title  # 안 보낸 건 그대로
    assert body["is_edited"] is True
    db.refresh(card)
    assert card.original_content == "x^2 + 1"  # 처음 인식 결과는 남는다
    assert card.edited_at is not None


def test_update_title_and_type(client, auth, card):
    response = client.patch(
        f"{URL}/{card.id}", json={"title": "이차식", "card_type": "math"}, headers=auth
    )
    assert response.json()["title"] == "이차식"
    assert response.json()["card_type"] == "math"
    assert response.json()["is_edited"] is False  # 내용은 그대로


def test_update_keeps_newlines_in_content(client, auth, card):
    response = client.patch(f"{URL}/{card.id}", json={"content": "1줄\n2줄"}, headers=auth)
    assert response.json()["content"] == "1줄\n2줄"


@pytest.mark.parametrize(
    "bad",
    [
        {"title": ""},
        {"title": "   "},
        {"title": "가" * 101},
        {"title": "두\n줄"},
        {"content": ""},
        {"content": "가" * 10001},
        {"content": "NUL\x00"},
        {"card_type": "table"},
    ],
)
def test_invalid_update_is_422(client, auth, card, bad):
    assert client.patch(f"{URL}/{card.id}", json=bad, headers=auth).status_code == 422


def test_revert(client, auth, card, db):
    client.patch(f"{URL}/{card.id}", json={"content": "고친 내용"}, headers=auth)
    response = client.post(f"{URL}/{card.id}/revert", headers=auth)
    assert response.status_code == 200
    assert response.json()["content"] == "x^2 + 1"
    assert response.json()["is_edited"] is False
    db.refresh(card)
    assert card.edited_at is None


# ---------- 옮김 표시 ----------


def moved(client, auth, cards, value=True):
    return client.put(
        f"{URL}/moved", json={"card_ids": [str(c.id) for c in cards], "moved": value}, headers=auth
    )


def test_mark_several_cards_moved(client, auth, db, capture, card):
    second = make_card(db, capture, 2)
    response = moved(client, auth, [second, card])
    assert response.status_code == 200
    assert [c["id"] for c in response.json()] == [str(second.id), str(card.id)]  # 보낸 순서
    assert all(c["is_moved"] for c in response.json())
    db.refresh(card)
    assert card.moved_at is not None


def test_mark_moved_twice_keeps_first_time(client, auth, db, card):
    moved(client, auth, [card])
    db.refresh(card)
    first = card.moved_at
    assert moved(client, auth, [card, card]).status_code == 200  # 중복 id도 한 번만
    db.refresh(card)
    assert card.moved_at == first


def test_unmark_moved(client, auth, db, card):
    moved(client, auth, [card])
    response = moved(client, auth, [card], value=False)
    assert response.json()[0]["is_moved"] is False
    db.refresh(card)
    assert card.moved_at is None


def test_mixed_with_other_users_card_changes_nothing(client, auth, db, card):
    other = make_user(db)
    theirs = make_card(db, make_capture(db, other, make_semester(db, other)), 1)
    assert moved(client, auth, [card, theirs]).status_code == 404
    db.refresh(card)
    assert card.is_moved is False


@pytest.mark.parametrize("count", [0, 101])
def test_moved_card_count_limits(client, auth, count):
    ids = [str(uuid.uuid4()) for _ in range(count)]
    response = client.put(f"{URL}/moved", json={"card_ids": ids, "moved": True}, headers=auth)
    assert response.status_code == 422


def test_unmoved_capture_list_follows_moved_marks(client, auth, db, capture, card):
    second = make_card(db, capture, 2)
    unmoved_url = "/api/v1/captures?unmoved=true"
    assert [c["id"] for c in client.get(unmoved_url, headers=auth).json()] == [str(capture.id)]

    moved(client, auth, [card])
    (listed,) = client.get(unmoved_url, headers=auth).json()
    assert listed["unmoved_count"] == 1

    moved(client, auth, [second])
    assert client.get(unmoved_url, headers=auth).json() == []  # 다 옮기면 빠진다


# ---------- 삭제 ----------


def test_delete_card_and_sticker(client, auth, db, capture, card):
    storage.save(card.crop_image_key, PNG)
    other = make_card(db, capture, 2)

    assert client.delete(f"{URL}/{card.id}", headers=auth).status_code == 204
    assert db.get(Card, card.id) is None
    assert not storage.exists(card.crop_image_key)
    detail = client.get(f"/api/v1/captures/{capture.id}", headers=auth).json()
    assert [c["id"] for c in detail["cards"]] == [str(other.id)]
    assert detail["cards"][0]["order_no"] == 2  # 남은 번호는 그대로


def test_delete_without_sticker_file(client, auth, card):
    assert client.delete(f"{URL}/{card.id}", headers=auth).status_code == 204


# ---------- 처리 중인 판서 ----------


@pytest.mark.parametrize("status", [CaptureStatus.segmenting, CaptureStatus.failed])
def test_cards_of_unfinished_capture_cannot_change(client, auth, db, user, status):
    capture = make_capture(db, user, make_semester(db, user), status=status)
    card = make_card(db, capture, 1)
    assert client.patch(f"{URL}/{card.id}", json={"title": "x"}, headers=auth).status_code == 409
    assert client.post(f"{URL}/{card.id}/revert", headers=auth).status_code == 409
    assert moved(client, auth, [card]).status_code == 409
    assert client.delete(f"{URL}/{card.id}", headers=auth).status_code == 409
    assert client.get(f"{URL}/{card.id}", headers=auth).status_code == 200  # 조회는 된다


# ---------- 스티커 이미지 ----------


def test_sticker_image(client, auth, card):
    storage.save(card.crop_image_key, PNG)
    response = client.get(f"{URL}/{card.id}/image", headers=auth)
    assert response.status_code == 200
    assert response.headers["content-type"] == "image/png"
    assert response.content == PNG


def test_sticker_image_missing_is_404(client, auth, card):
    assert client.get(f"{URL}/{card.id}/image", headers=auth).status_code == 404
