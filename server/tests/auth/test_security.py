"""로그인 토큰(JWT) 발급 · 확인. DB 없이 돈다."""

import uuid
from datetime import UTC, datetime, timedelta

import jwt
import pytest

from app.core.config import get_settings
from app.core.security import (
    AuthNotConfigured,
    InvalidToken,
    create_access_token,
    read_access_token,
)


def test_round_trip(auth_settings):
    user_id = uuid.uuid4()
    assert read_access_token(create_access_token(user_id)) == user_id


def test_expires_after_configured_days(auth_settings):
    now = datetime.now(UTC)
    token = create_access_token(uuid.uuid4(), now=now)
    payload = jwt.decode(token, options={"verify_signature": False})
    assert payload["exp"] - payload["iat"] == int(timedelta(days=30).total_seconds())


def test_expired_token_is_rejected(auth_settings):
    long_ago = datetime.now(UTC) - timedelta(days=31)
    with pytest.raises(InvalidToken):
        read_access_token(create_access_token(uuid.uuid4(), now=long_ago))


def test_token_signed_with_other_secret_is_rejected(auth_settings):
    forged = jwt.encode(
        {"sub": str(uuid.uuid4()), "exp": datetime.now(UTC) + timedelta(days=1)},
        "another-secret-that-is-also-32-bytes-long!!",
        algorithm="HS256",
    )
    with pytest.raises(InvalidToken):
        read_access_token(forged)


def test_unsigned_token_is_rejected(auth_settings):
    unsigned = jwt.encode(
        {"sub": str(uuid.uuid4()), "exp": datetime.now(UTC) + timedelta(days=1)},
        key=None,
        algorithm="none",
    )
    with pytest.raises(InvalidToken):
        read_access_token(unsigned)


@pytest.mark.parametrize("token", ["", "garbage", "a.b.c"])
def test_malformed_token_is_rejected(auth_settings, token):
    with pytest.raises(InvalidToken):
        read_access_token(token)


def test_subject_must_be_uuid(auth_settings):
    token = jwt.encode(
        {"sub": "not-a-uuid", "exp": datetime.now(UTC) + timedelta(days=1)},
        auth_settings.jwt_secret,
        algorithm="HS256",
    )
    with pytest.raises(InvalidToken):
        read_access_token(token)


def test_missing_secret(monkeypatch):
    monkeypatch.setenv("JWT_SECRET", "")
    get_settings.cache_clear()
    try:
        with pytest.raises(AuthNotConfigured):
            create_access_token(uuid.uuid4())
    finally:
        get_settings.cache_clear()
