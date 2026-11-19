"""임시 사용자 정하기 (로그인 전까지)."""

import uuid

from sqlalchemy import func, select

from app.api.deps import DEV_USER_UID
from app.models import User

URL = "/api/v1/semesters"


def test_without_header_uses_dev_user(client, db):
    first = client.post(URL, json={"year": 2026, "term": "second"})
    assert first.status_code == 201

    # 두 번째 요청도 같은 개발용 사용자 → 같은 학기가 보인다
    assert [s["id"] for s in client.get(URL).json()] == [first.json()["id"]]
    count = db.scalar(
        select(func.count()).select_from(User).where(User.provider_uid == DEV_USER_UID)
    )
    assert count == 1


def test_dev_user_has_school_and_settings(client, db):
    client.get(URL)
    user = db.scalars(select(User).where(User.provider_uid == DEV_USER_UID)).one()
    assert user.school == "경북대학교"
    assert user.settings is not None


def test_unknown_user_is_401(client):
    response = client.get(URL, headers={"X-User-Id": str(uuid.uuid4())})
    assert response.status_code == 401
    assert response.json()["detail"] == "로그인이 필요해요."


def test_malformed_user_id_is_422(client):
    assert client.get(URL, headers={"X-User-Id": "not-a-uuid"}).status_code == 422
