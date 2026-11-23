"""로그인 토큰(JWT) 발급 · 확인과 이메일 로그인 비밀번호 해시.

우리 서버가 JWT_SECRET으로 서명한 토큰만 받는다.
리프레시 토큰은 없다. 유효 기간(JWT_EXPIRE_DAYS)이 지나면 앱에서 다시 로그인한다.
비밀번호는 argon2로 해시해서 저장하고 원문은 저장하지 않는다.
"""

import uuid
from datetime import UTC, datetime, timedelta

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError

from app.core.config import get_settings

ALGORITHM = "HS256"
_hasher = PasswordHasher()


class AuthNotConfigured(Exception):
    """서버에 JWT_SECRET이 설정되지 않음"""


class InvalidToken(Exception):
    """서명이 틀리거나, 만료됐거나, 형식이 이상한 토큰"""


def _secret() -> str:
    secret = get_settings().jwt_secret
    if not secret:
        raise AuthNotConfigured("JWT_SECRET이 설정되지 않았어요.")
    return secret


def create_access_token(user_id: uuid.UUID, now: datetime | None = None) -> str:
    """사용자 id를 담은 토큰을 만든다. now는 테스트에서 시각을 정할 때만 쓴다."""
    now = now or datetime.now(UTC)
    expires = now + timedelta(days=get_settings().jwt_expire_days)
    payload = {"sub": str(user_id), "iat": now, "exp": expires}
    return jwt.encode(payload, _secret(), algorithm=ALGORITHM)


def read_access_token(token: str) -> uuid.UUID:
    """토큰을 확인하고 사용자 id를 돌려준다. 받을 수 없는 토큰이면 InvalidToken."""
    secret = _secret()
    try:
        payload = jwt.decode(
            token, secret, algorithms=[ALGORITHM], options={"require": ["sub", "exp"]}
        )
        return uuid.UUID(payload["sub"])
    except (jwt.InvalidTokenError, ValueError, TypeError) as error:
        raise InvalidToken(str(error)) from error


def hash_password(password: str) -> str:
    """비밀번호 해시. 같은 비밀번호도 매번 다른 값이 나온다 (솔트가 들어감)."""
    return _hasher.hash(password)


def verify_password(password: str, hashed: str | None) -> bool:
    """비밀번호가 맞는지. 해시가 없거나(카카오 계정) 형식이 이상해도 예외 없이 False."""
    if not hashed:
        return False
    try:
        return _hasher.verify(hashed, password)
    except (VerificationError, InvalidHashError):
        return False
