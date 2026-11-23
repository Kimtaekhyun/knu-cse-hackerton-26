"""로그인 API의 요청 · 응답 형식."""

import uuid
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, field_validator

from app.models import AuthProvider
from app.schemas.me import UserName, UserSettingsOut

EMAIL_MAX = 254
PASSWORD_MIN = 8
PASSWORD_MAX = 64

# 앞뒤 공백을 지우고 소문자로 맞춘다. 저장 · 비교 모두 이 값으로 한다
LoginEmail = Annotated[
    str, StringConstraints(strip_whitespace=True, to_lower=True, min_length=1, max_length=EMAIL_MAX)
]
# 가입할 때만 형식을 본다. 메일 인증이 없어서 "@와 점이 있는 공백 없는 글자" 정도만 확인한다
SignupEmail = Annotated[
    str,
    StringConstraints(
        strip_whitespace=True,
        to_lower=True,
        max_length=EMAIL_MAX,
        pattern=r"^[^@\s]+@[^@\s]+\.[^@\s]+$",
    ),
]


class KakaoLoginRequest(BaseModel):
    access_token: str = Field(
        min_length=1, max_length=4096, description="앱이 카카오 SDK로 받은 카카오 access token"
    )
    allow_duplicate_email: bool = Field(
        False,
        description="같은 이메일의 이메일 계정이 있어도 새 카카오 계정을 만든다 "
        "(409 email_account_exists 안내 창에서 '카카오로 새로 가입'을 고른 경우)",
    )


class EmailSignupRequest(BaseModel):
    email: SignupEmail
    password: str = Field(min_length=PASSWORD_MIN, max_length=PASSWORD_MAX)
    name: UserName


class EmailLoginRequest(BaseModel):
    email: LoginEmail
    password: str = Field(min_length=1, max_length=PASSWORD_MAX)


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    provider: AuthProvider
    name: str
    email: str | None
    school: str | None
    settings: UserSettingsOut

    @field_validator("settings", mode="before")
    @classmethod
    def default_settings(cls, settings: object) -> object:
        # 설정 행이 없는 사용자(예전 가입자 · 테스트용 사용자)는 기본값으로 보여 준다
        return UserSettingsOut() if settings is None else settings


class LoginResponse(BaseModel):
    access_token: str = Field(description="이후 요청에 Authorization: Bearer로 붙이는 우리 토큰")
    token_type: Literal["bearer"] = "bearer"
    is_new_user: bool = Field(
        description=(
            "아직 시간표를 등록하지 않았는지 (어느 학기에도 과목이 없음). "
            "true면 앱이 시간표 등록으로, false면 홈으로 보낸다"
        )
    )
    user: UserOut
