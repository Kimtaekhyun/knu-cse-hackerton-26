"""학기 · 과목 API가 로그인 토큰으로 사용자를 정하는지."""

import uuid

import pytest

from app.models import User
from tests.api.conftest import bearer
from tests.db.factories import make_user

URL = "/api/v1/semesters"


def test_token_user_sees_own_semesters(client, auth):
    created = client.post(URL, json={"year": 2026, "term": "second"}, headers=auth)
    assert created.status_code == 201
    assert [s["id"] for s in client.get(URL, headers=auth).json()] == [created.json()["id"]]


def test_other_user_cannot_see_semesters(client, db, auth):
    client.post(URL, json={"year": 2026, "term": "second"}, headers=auth)
    other = make_user(db)
    assert client.get(URL, headers=bearer(other.id)).json() == []


@pytest.mark.parametrize("method", ["get", "post"])
def test_without_token_is_401(client, method):
    response = getattr(client, method)(URL)
    assert response.status_code == 401
    assert response.json()["detail"] == "로그인이 필요해요."


def test_user_id_header_is_ignored(client, user):
    # 로그인 전에 쓰던 X-User-Id 헤더로는 더 이상 사용자를 고를 수 없다
    assert client.get(URL, headers={"X-User-Id": str(user.id)}).status_code == 401


def test_bad_token_is_401(client):
    assert client.get(URL, headers={"Authorization": "Bearer garbage"}).status_code == 401


def test_token_for_deleted_user_is_401(client, db):
    gone = make_user(db)
    headers = bearer(gone.id)
    db.delete(db.get(User, gone.id))
    db.flush()
    assert client.get(URL, headers=headers).status_code == 401


def test_token_for_unknown_user_is_401(client):
    assert client.get(URL, headers=bearer(uuid.uuid4())).status_code == 401
