"""POST /auth/kakao · GET /me (카카오 API는 가짜, DB는 테스트 DB)."""

import uuid
from datetime import UTC, datetime, timedelta

from sqlalchemy import func, select

from app.core.security import create_access_token
from app.models import AuthProvider, User
from tests.db.factories import make_user

LOGIN = "/api/v1/auth/kakao"
ME = "/api/v1/me"


def login(client, token="kakao-token"):
    return client.post(LOGIN, json={"access_token": token})


def bearer(token):
    return {"Authorization": f"Bearer {token}"}


def test_first_login_creates_user_with_settings(client, db):
    response = login(client)
    assert response.status_code == 200
    body = response.json()
    assert body["is_new_user"] is True
    assert body["token_type"] == "bearer"
    assert body["user"]["name"] == "판서왕"
    assert body["user"]["email"] == "user@example.com"
    assert body["user"]["provider"] == "kakao"

    user = db.get(User, uuid.UUID(body["user"]["id"]))
    assert (user.provider, user.provider_uid) == (AuthProvider.kakao, "3001")
    assert user.settings is not None


def test_login_response_includes_settings(client):
    # 앱이 로그인 직후 알림 스위치를 그릴 수 있게 로그인 응답의 user에도 알림 설정이 들어간다
    settings = login(client).json()["user"]["settings"]
    assert settings == {"notify_unmoved": True, "notify_exam": True}


def test_second_login_reuses_user(client, db):
    first = login(client).json()
    second = login(client).json()
    assert second["is_new_user"] is False
    assert second["user"]["id"] == first["user"]["id"]
    count = db.scalar(select(func.count()).select_from(User).where(User.provider_uid == "3001"))
    assert count == 1


def test_login_does_not_overwrite_edited_name(client, db, kakao):
    user_id = uuid.UUID(login(client).json()["user"]["id"])
    db.get(User, user_id).name = "앱에서 고친 이름"
    db.flush()
    kakao.account["profile"]["nickname"] = "바뀐 카카오 닉네임"
    assert login(client).json()["user"]["name"] == "앱에서 고친 이름"


def make_email_user(db, email="user@example.com"):
    return make_user(db, provider=AuthProvider.email, provider_uid=email, email=email)


def count_users(db) -> int:
    return db.scalar(select(func.count()).select_from(User))


def test_first_login_with_email_account_email_is_409(client, db, kakao):
    # 카카오 이메일은 대소문자가 섞여 있을 수 있다. 이메일 계정은 소문자로 저장된다
    make_email_user(db)
    kakao.account["email"] = "User@Example.COM"
    response = login(client)
    assert response.status_code == 409
    assert response.json()["detail"] == {
        "code": "email_account_exists",
        "message": "이 이메일로 가입한 계정이 있어요.",
        # 앱이 이메일 로그인 화면의 이메일 칸을 미리 채운다 (카카오가 확인한 본인 이메일)
        "email": "user@example.com",
    }
    assert count_users(db) == 1


def test_allow_duplicate_email_creates_separate_kakao_user(client, db):
    other = make_email_user(db)
    response = client.post(LOGIN, json={"access_token": "t", "allow_duplicate_email": True})
    body = response.json()
    assert body["is_new_user"] is True
    assert body["user"]["id"] != str(other.id)
    assert body["user"]["provider"] == "kakao"


def test_existing_kakao_user_is_not_asked_about_email_account(client, db):
    first = login(client).json()
    make_email_user(db)
    second = login(client)
    assert second.status_code == 200
    assert second.json()["user"]["id"] == first["user"]["id"]


def test_kakao_user_with_same_email_does_not_block_kakao_login(client, db, kakao):
    # 막는 건 이메일 계정과 겹칠 때뿐이다
    make_user(db, provider=AuthProvider.kakao, provider_uid="9999", email="user@example.com")
    assert login(client).status_code == 200


def test_no_consent_still_signs_up(client, kakao):
    kakao.account = {}
    body = login(client).json()
    assert (body["user"]["name"], body["user"]["email"]) == ("사용자", None)


def test_token_from_other_app_is_401(client, kakao, db):
    kakao.app_id = 9999999
    response = login(client)
    assert response.status_code == 401
    assert db.scalar(select(func.count()).select_from(User)) == 0


def test_rejected_kakao_token_is_401(client, kakao):
    kakao.status = 401
    assert login(client).status_code == 401


def test_kakao_down_is_502(client, kakao):
    kakao.status = 503
    assert login(client).status_code == 502
    kakao.status, kakao.timeout = 200, True
    assert login(client).status_code == 502


def test_empty_kakao_token_is_422(client):
    assert login(client, token="").status_code == 422


def test_missing_server_config_is_503(client, monkeypatch, auth_settings):
    monkeypatch.setattr(auth_settings, "kakao_app_id", None)
    assert login(client).status_code == 503


def test_me_with_login_token(client):
    body = login(client).json()
    response = client.get(ME, headers=bearer(body["access_token"]))
    assert response.status_code == 200
    assert response.json() == body["user"]


def test_me_without_token_is_401(client):
    response = client.get(ME)
    assert response.status_code == 401
    assert response.json()["detail"] == "로그인이 필요해요."
    assert response.headers["WWW-Authenticate"] == "Bearer"


def test_me_with_bad_tokens_is_401(client):
    token = login(client).json()["access_token"]
    assert client.get(ME, headers=bearer(token[:-2] + "xx")).status_code == 401
    assert client.get(ME, headers={"Authorization": f"Basic {token}"}).status_code == 401
    assert client.get(ME, headers=bearer("garbage")).status_code == 401


def test_me_with_expired_token_is_401(client, db):
    user = make_user(db)
    expired = create_access_token(user.id, now=datetime.now(UTC) - timedelta(days=31))
    assert client.get(ME, headers=bearer(expired)).status_code == 401


def test_me_for_deleted_user_is_401(client, db):
    user = make_user(db)
    token = create_access_token(user.id)
    db.delete(user)
    db.flush()
    assert client.get(ME, headers=bearer(token)).status_code == 401
