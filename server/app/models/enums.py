"""DB enum. Postgres native enum으로 만들어져 선언 순서대로 정렬되고 그 외 값은 들어갈 수 없다."""

import enum


class AuthProvider(enum.Enum):
    kakao = "kakao"
    email = "email"


class CaptureStatus(enum.Enum):
    """처리 단계. 10-1/2/3 처리 화면과 1:1"""

    uploaded = "uploaded"
    rectifying = "rectifying"
    segmenting = "segmenting"
    interpreting = "interpreting"
    done = "done"
    failed = "failed"


class SemesterTerm(enum.Enum):
    """1학기 · 여름 · 2학기 · 겨울"""

    first = "first"
    summer = "summer"
    second = "second"
    winter = "winter"


class CardType(enum.Enum):
    """표 인식이 다시 들어오면 table 추가"""

    text = "text"
    math = "math"
    code = "code"
