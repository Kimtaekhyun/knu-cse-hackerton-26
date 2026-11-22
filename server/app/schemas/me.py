"""내 계정 API(/me)의 요청 형식.

응답(내 정보)은 로그인 응답과 같은 UserOut(app/schemas/auth.py)을 쓴다.
"""

from typing import Annotated

from pydantic import AfterValidator, BaseModel, StringConstraints, field_validator

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
