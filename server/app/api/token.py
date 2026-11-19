"""로그인 토큰(Authorization: Bearer)으로 현재 사용자를 찾는 FastAPI 의존성.

학기 · 과목 API(#50)의 app/api/deps.py get_current_user를 이 함수로 바꿔 끼우면
모든 API가 로그인한 사용자 기준으로 동작한다.
"""

from typing import Annotated

from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.security import AuthNotConfigured, InvalidToken, read_access_token
from app.db.session import get_db
from app.models import User

bearer = HTTPBearer(auto_error=False, description="POST /auth/kakao가 돌려준 access_token")


def _unauthorized() -> HTTPException:
    return HTTPException(401, "로그인이 필요해요.", headers={"WWW-Authenticate": "Bearer"})


def get_token_user(
    db: Annotated[Session, Depends(get_db)],
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
) -> User:
    """토큰이 없거나, 틀리거나, 만료됐거나, 사용자가 지워졌으면 401."""
    if credentials is None:
        raise _unauthorized()
    try:
        user_id = read_access_token(credentials.credentials)
    except AuthNotConfigured as error:
        raise HTTPException(503, "서버에 로그인 설정이 없어요.") from error
    except InvalidToken as error:
        raise _unauthorized() from error
    user = db.get(User, user_id)
    if user is None:
        raise _unauthorized()
    return user


TokenUserDep = Annotated[User, Depends(get_token_user)]
