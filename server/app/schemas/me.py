"""내 계정 API(/me)의 요청 · 응답 형식.

내 정보 응답은 로그인 응답과 같은 UserOut(app/schemas/auth.py)을 쓰고,
그 안의 알림 설정(settings)은 여기 UserSettingsOut을 쓴다.
"""

from typing import Annotated

from pydantic import AfterValidator, BaseModel, ConfigDict, StringConstraints, field_validator

from app.schemas.text import clean_text

NAME_MAX = 50
SCHOOL_MAX = 50

UserName = Annotated[
    str,
    StringConstraints(strip_whitespace=True, min_length=1, max_length=NAME_MAX),
    AfterValidator(clean_text),
]
# 학사일정(academic_calendars.school)과 글자로 맞춰 보므로 이름과 같은 정규화를 한다
SchoolName = Annotated[
    str,
    StringConstraints(strip_whitespace=True, max_length=SCHOOL_MAX),
    AfterValidator(clean_text),
]


class ProfileUpdate(BaseModel):
    """보낸 것만 바꾼다. 학교는 빈 값("")이나 null이면 비운다.

    "안 보냄"과 "null을 보냄"을 구분해야 해서 저장할 때 model_fields_set으로 보낸 칸을 확인한다.
    """

    name: UserName | None = None
    school: SchoolName | None = None

    @field_validator("name")
    @classmethod
    def name_is_required(cls, name: str | None) -> str:
        # 기본값(None)에는 실행되지 않으므로, 이름에 null을 직접 보낸 경우만 걸린다
        if name is None:
            raise ValueError("이름은 비울 수 없어요.")
        return name


class UserSettingsOut(BaseModel):
    """알림 설정. 알림 예약은 앱이 하고 서버는 켜짐 · 꺼짐만 저장한다 (#21)"""

    model_config = ConfigDict(from_attributes=True)

    # 옮기지 않은 판서 알림
    notify_unmoved: bool = True
    # 시험 기간 알림
    notify_exam: bool = True


class SettingsUpdate(BaseModel):
    """보낸 것만 바꾼다. null은 켜짐 · 꺼짐이 아니라서 거절한다"""

    notify_unmoved: bool | None = None
    notify_exam: bool | None = None

    @field_validator("notify_unmoved", "notify_exam")
    @classmethod
    def not_null(cls, value: bool | None) -> bool:
        # 기본값(None)에는 실행되지 않으므로, null을 직접 보낸 경우만 걸린다
        if value is None:
            raise ValueError("켜짐(true)이나 꺼짐(false)으로 보내 주세요.")
        return value
