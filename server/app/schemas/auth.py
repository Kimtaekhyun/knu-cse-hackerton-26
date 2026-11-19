"""로그인 API의 요청 · 응답 형식."""

import uuid
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

from app.models import AuthProvider


class KakaoLoginRequest(BaseModel):
    access_token: str = Field(
        min_length=1, max_length=4096, description="앱이 카카오 SDK로 받은 카카오 access token"
    )


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    provider: AuthProvider
    name: str
    email: str | None
    school: str | None


class LoginResponse(BaseModel):
    access_token: str = Field(description="이후 요청에 Authorization: Bearer로 붙이는 우리 토큰")
    token_type: Literal["bearer"] = "bearer"
    is_new_user: bool = Field(
        description="이번 로그인으로 처음 가입했는지 (앱이 첫 화면을 고를 때)"
    )
    user: UserOut
