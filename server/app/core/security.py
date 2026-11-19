"""로그인 토큰(JWT) 발급 · 확인. 우리 서버가 JWT_SECRET으로 서명한 토큰만 받는다.

리프레시 토큰은 없다. 유효 기간(JWT_EXPIRE_DAYS)이 지나면 앱에서 다시 로그인한다.
"""

import uuid
from datetime import UTC, datetime, timedelta

import jwt

from app.core.config import get_settings

ALGORITHM = "HS256"


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
