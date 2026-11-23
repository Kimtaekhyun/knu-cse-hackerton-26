"""POST /auth/email/signup · /auth/email/login (DB는 테스트 DB)."""

import uuid

import pytest
from sqlalchemy import func, select

from app.models import AuthProvider, User
from tests.db.factories import make_semester, make_subject, make_user

SIGNUP = "/api/v1/auth/email/signup"
LOGIN = "/api/v1/auth/email/login"
ME = "/api/v1/me"
WRONG = "이메일 또는 비밀번호가 맞지 않아요."


def signup(client, email="user@example.com", password="password123", name="판서왕"):
    return client.post(SIGNUP, json={"email": email, "password": password, "name": name})


def login(client, email="user@example.com", password="password123"):
    return client.post(LOGIN, json={"email": email, "password": password})


def count_users(db) -> int:
    return db.scalar(select(func.count()).select_from(User))


# 가입


def test_signup_creates_user_with_settings(client, db):
    response = signup(client)
    assert response.status_code == 201
    body = response.json()
    assert body["is_new_user"] is True
    assert body["token_type"] == "bearer"
    assert body["user"]["provider"] == "email"
    assert (body["user"]["name"], body["user"]["email"]) == ("판서왕", "user@example.com")

    user = db.get(User, uuid.UUID(body["user"]["id"]))
    assert (user.provider, user.provider_uid) == (AuthProvider.email, "user@example.com")
    assert user.settings is not None


def test_signup_token_works_for_me(client):
    body = signup(client).json()
    response = client.get(ME, headers={"Authorization": f"Bearer {body['access_token']}"})
    assert response.status_code == 200
    assert response.json() == body["user"]


def test_signup_normalizes_email(client):
    body = signup(client, email="  User@Example.COM ").json()
    assert body["user"]["email"] == "user@example.com"


def test_password_is_not_stored_as_plain_text(client, db):
    body = signup(client, password="password123").json()
    user = db.get(User, uuid.UUID(body["user"]["id"]))
    assert user.password_hash and "password123" not in user.password_hash


def test_signup_with_taken_email_is_409(client, db):
    signup(client)
    response = signup(client, email=" USER@example.com")
    assert response.status_code == 409
    assert response.json()["detail"] == {
        "code": "email_taken",
        "message": "이미 가입한 이메일이에요.",
    }
    assert count_users(db) == 1


def test_signup_with_kakao_account_email_is_409(client, db):
    # 카카오 이메일은 받은 그대로 저장돼 있어서 대소문자가 섞여 있을 수 있다
    make_user(db, provider=AuthProvider.kakao, provider_uid="3001", email="User@Example.com")
    response = signup(client, email="user@example.com")
    assert response.status_code == 409
    assert response.json()["detail"] == {
        "code": "kakao_account_exists",
        "message": "카카오로 가입한 이메일이에요. 카카오로 로그인해 주세요.",
    }
    assert count_users(db) == 1


@pytest.mark.parametrize(
    "fields",
    [
        {"email": "not-an-email"},
        {"email": "user@example"},
        {"email": "a b@example.com"},
        {"email": "a" * 250 + "@example.com"},
        {"password": "short12"},
        {"password": "p" * 65},
        {"name": "   "},
        {"name": "이름\n줄바꿈"},
        {"name": "가" * 51},
    ],
)
def test_signup_invalid_input_is_422(client, db, fields):
    values = {"email": "user@example.com", "password": "password123", "name": "판서왕"} | fields
    assert client.post(SIGNUP, json=values).status_code == 422
    assert count_users(db) == 0


def test_signup_without_server_config_is_503(client, monkeypatch, auth_settings):
    monkeypatch.setattr(auth_settings, "jwt_secret", "")
    assert signup(client).status_code == 503


# 로그인


def test_login_returns_same_user(client):
    created = signup(client).json()
    response = login(client)
    assert response.status_code == 200
    assert response.json()["user"]["id"] == created["user"]["id"]


def test_login_before_timetable_is_new_user(client, db):
    # 가입 후 창(앱)을 닫았다가 다시 로그인해도 시간표 등록으로 가야 한다 (#150)
    signup(client)
    assert login(client).json()["is_new_user"] is True
    assert login(client).json()["is_new_user"] is True


def test_login_with_semester_but_no_subjects_is_new_user(client, db):
    # "나중에 할게요" 뒤 판서를 찍으면 학기만 저절로 생긴다. 과목이 없으니 아직 시간표 전이다
    user_id = uuid.UUID(signup(client).json()["user"]["id"])
    make_semester(db, db.get(User, user_id))
    assert login(client).json()["is_new_user"] is True


def test_login_after_timetable_is_not_new_user(client, db):
    user_id = uuid.UUID(signup(client).json()["user"]["id"])
    make_subject(db, make_semester(db, db.get(User, user_id)))
    assert login(client).json()["is_new_user"] is False


def test_timetable_in_past_semester_counts(client, db):
    user_id = uuid.UUID(signup(client).json()["user"]["id"])
    user = db.get(User, user_id)
    make_subject(db, make_semester(db, user, year=2025, is_current=False))
    make_semester(db, user)  # 새 학기는 아직 비어 있다
    assert login(client).json()["is_new_user"] is False


def test_other_users_timetable_does_not_count(client, db):
    other = make_user(db)
    make_subject(db, make_semester(db, other))
    signup(client)
    assert login(client).json()["is_new_user"] is True


def test_login_email_is_case_insensitive(client):
    signup(client)
    assert login(client, email=" User@EXAMPLE.com").status_code == 200


def test_wrong_password_and_unknown_email_look_the_same(client):
    signup(client)
    wrong_password = login(client, password="password999")
    unknown_email = login(client, email="nobody@example.com")
    assert wrong_password.status_code == unknown_email.status_code == 401
    assert wrong_password.json()["detail"] == unknown_email.json()["detail"] == WRONG


def test_kakao_account_cannot_login_with_password(client, db):
    make_user(db, provider=AuthProvider.kakao, provider_uid="3001", email="user@example.com")
    response = login(client)
    assert response.status_code == 401
    assert response.json()["detail"] == WRONG
