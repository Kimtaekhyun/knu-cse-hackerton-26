"""로그인 API. 카카오 토큰이나 이메일 · 비밀번호를 확인하고 우리 토큰(JWT)을 발급한다.

같은 이메일의 계정이 겹칠 때는 409에 {code, message}를 담아 앱이 code로 안내 창을 고르게 한다.

내 정보 조회 · 수정(GET · PATCH /me)은 app/api/v1/me.py에 있다.
"""

from collections.abc import Iterator
from typing import Annotated

import httpx
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.core.config import get_settings
from app.core.security import create_access_token
from app.db.session import get_db
from app.models import AuthProvider, User
from app.schemas.auth import (
    EmailLoginRequest,
    EmailSignupRequest,
    KakaoLoginRequest,
    LoginResponse,
    UserOut,
)
from app.services import auth as auth_service
from app.services import social_auth

router = APIRouter(tags=["auth"])

DbDep = Annotated[Session, Depends(get_db)]
WRONG_LOGIN = "이메일 또는 비밀번호가 맞지 않아요."
EMAIL_TAKEN = {
    AuthProvider.email: ("email_taken", "이미 가입한 이메일이에요."),
    AuthProvider.kakao: (
        "kakao_account_exists",
        "카카오로 가입한 이메일이에요. 카카오로 로그인해 주세요.",
    ),
}


def _conflict(code: str, message: str, **extra: str) -> HTTPException:
    return HTTPException(409, {"code": code, "message": message, **extra})


def _require_jwt_secret() -> None:
    if not get_settings().jwt_secret:
        raise HTTPException(503, "서버에 로그인 설정이 없어요.")


def _login_response(db: Session, user: User) -> LoginResponse:
    """로그인 응답. is_new_user는 아직 시간표를 등록하지 않았는지다
    (가입 · 이메일 로그인 · 카카오 로그인 모두 같은 기준, #150).
    True면 앱이 시간표 등록(05)으로, False면 홈으로 보낸다."""
    return LoginResponse(
        access_token=create_access_token(user.id),
        is_new_user=auth_service.needs_timetable(db, user),
        user=UserOut.model_validate(user),
    )


def kakao_http() -> Iterator[httpx.Client]:
    """카카오 API용 HTTP 클라이언트. 테스트에서 가짜 응답을 돌려주는 클라이언트로 바꿔 끼운다."""
    with httpx.Client(timeout=social_auth.TIMEOUT) as client:
        yield client


@router.post("/auth/kakao", response_model=LoginResponse)
def login_kakao(
    body: KakaoLoginRequest,
    db: DbDep,
    http: Annotated[httpx.Client, Depends(kakao_http)],
):
    """카카오 로그인. 처음이면 가입(사용자 · 기본 설정 생성)까지 한다.

    처음 가입인데 같은 이메일의 이메일 계정이 있으면 409 email_account_exists.
    앱이 "카카오로 새로 가입"을 고르면 allow_duplicate_email: true로 다시 보낸다.

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
    try:
        user = auth_service.login_kakao(db, profile, body.allow_duplicate_email)
    except auth_service.EmailAccountExists as error:
        # 이메일은 카카오가 확인한 본인 것이다. 앱이 이메일 로그인 칸을 미리 채운다
        message = "이 이메일로 가입한 계정이 있어요."
        raise _conflict("email_account_exists", message, email=error.email) from error
    return _login_response(db, user)


@router.post("/auth/email/signup", response_model=LoginResponse, status_code=201)
def signup_email(body: EmailSignupRequest, db: DbDep):
    """이메일 가입. 사용자 · 기본 설정을 만들고 바로 로그인한 토큰을 준다.

    같은 이메일의 계정이 있으면 409 (email_taken · kakao_account_exists).
    """
    _require_jwt_secret()
    try:
        user = auth_service.signup_email(db, body)
    except auth_service.EmailTaken as error:
        raise _conflict(*EMAIL_TAKEN[error.provider]) from error
    return _login_response(db, user)


@router.post("/auth/email/login", response_model=LoginResponse)
def login_email(body: EmailLoginRequest, db: DbDep):
    """이메일 로그인. 없는 이메일과 틀린 비밀번호는 같은 401이라 가입 여부가 드러나지 않는다."""
    _require_jwt_secret()
    user = auth_service.login_email(db, body.email, body.password)
    if user is None:
        raise HTTPException(401, WRONG_LOGIN)
    return _login_response(db, user)
