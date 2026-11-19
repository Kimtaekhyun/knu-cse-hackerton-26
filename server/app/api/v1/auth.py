"""로그인 API. 카카오 토큰을 확인하고 우리 토큰(JWT)을 발급한다."""

from collections.abc import Iterator
from typing import Annotated

import httpx
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.api.token import TokenUserDep
from app.core.config import get_settings
from app.core.security import create_access_token
from app.db.session import get_db
from app.schemas.auth import KakaoLoginRequest, LoginResponse, UserOut
from app.services import auth as auth_service
from app.services import social_auth

router = APIRouter(tags=["auth"])


def kakao_http() -> Iterator[httpx.Client]:
    """카카오 API용 HTTP 클라이언트. 테스트에서 가짜 응답을 돌려주는 클라이언트로 바꿔 끼운다."""
    with httpx.Client(timeout=social_auth.TIMEOUT) as client:
        yield client


@router.post("/auth/kakao", response_model=LoginResponse)
def login_kakao(
    body: KakaoLoginRequest,
    db: Annotated[Session, Depends(get_db)],
    http: Annotated[httpx.Client, Depends(kakao_http)],
):
    """카카오 로그인. 처음이면 가입(사용자 · 기본 설정 생성)까지 한다.

    카카오 호출이 막히므로 async가 아닌 일반 함수로 둔다 (FastAPI가 스레드에서 돌린다).
    """
    settings = get_settings()
    if not settings.jwt_secret or settings.kakao_app_id is None:
        raise HTTPException(503, "서버에 로그인 설정이 없어요.")
    try:
        profile = social_auth.fetch_profile(http, body.access_token, settings.kakao_app_id)
    except social_auth.KakaoAuthError as error:
        raise HTTPException(
            401, "카카오 로그인을 확인하지 못했어요. 다시 로그인해 주세요."
        ) from error
    except social_auth.KakaoUnavailable as error:
        message = "카카오 서버에 연결하지 못했어요. 잠시 뒤 다시 시도해 주세요."
        raise HTTPException(502, message) from error
    user, is_new = auth_service.login_kakao(db, profile)
    return LoginResponse(
        access_token=create_access_token(user.id),
        is_new_user=is_new,
        user=UserOut.model_validate(user),
    )


@router.get("/me", response_model=UserOut)
def me(user: TokenUserDep):
    """내 정보. 앱이 자동 로그인할 때 저장된 토큰이 아직 유효한지 확인하는 데 쓴다."""
    return user
