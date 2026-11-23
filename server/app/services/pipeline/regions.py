"""판서 사진에서 필기 덩어리(카드)를 AI에게 묻는다 (segment 단계).

프롬프트와 답 형식은 pipeline/note_pipeline.py(test 브랜치)와 같고, 카드 종류(card_type)만 더했다.
어느 AI(Gemini · Claude)에 보낼지는 services/llm.py가 정한다.
"""

import json
import re

from pydantic import BaseModel, Field

from app.models import CardType
from app.services import llm


class NoteRegion(BaseModel):
    box_2d: list[int] = Field(
        description="덩어리를 감싸는 상자 [ymin, xmin, ymax, xmax]. 이미지를 0~1000으로 본 좌표"
    )
    title: str = Field(description="이 덩어리가 무엇인지 짧게 (예: f'(x) 부호 확인, 로피탈 계산)")
    kind: str = Field(
        description=(
            "aligned: 숫자가 여러 줄로 열을 맞춰 쌓인 블록 (세로셈·나눗셈·진리표 등). "
            "text: 그 밖의 필기"
        )
    )
    card_type: str = Field(
        description="code: 프로그램 코드·터미널 명령 / math: 수식이 중심 / text: 그 밖의 필기"
    )
    lines: list[str] = Field(
        description="덩어리 안의 손글씨를 쓰인 순서대로 한 줄씩. 수식 부분만 $...$ 로 감싼 LaTeX"
    )


class NoteRegions(BaseModel):
    regions: list[NoteRegion]


PROMPT = """
이 이미지는 강의 화면(또는 칠판) 사진이야. 손으로 쓴 필기를 '의미 단위 덩어리'로 나눠 줘.

[규칙]
1. 한 덩어리 = 한 가지 내용 (하나의 풀이 과정, 하나의 메모, 하나의 강조 표시 묶음).
   같은 풀이의 여러 줄은 한 덩어리로 묶고, 서로 다른 내용은 나눠.
   →, = 로 시작하는 줄은 바로 위 줄과 같은 풀이이므로 반드시 같은 덩어리에 넣어.
2. 프로젝터 화면이라면 슬라이드에 원래 인쇄된 글자와 수식은 덩어리에 넣지 마.
   인쇄된 글자 위에 친 동그라미·밑줄만 있는 곳은 덩어리로 만들지 마.
3. box_2d는 그 덩어리의 손글씨를 빠짐없이 감싸되 최대한 꼭 맞게.
4. lines에는 쓰여 있는 내용만 옮겨. 해설을 덧붙이지 말고, 읽을 수 없으면 [?].
5. 덩어리는 위에서 아래, 왼쪽에서 오른쪽 순서로.

[있는 그대로 옮기기]
6. 필기를 '추출'하는 게 목적이야. 계산이 틀려 보여도 고치거나 다시 계산하지 말고 쓰인 그대로 옮겨.
7. 빨강·검정·노랑·파랑 등 펜 색이 달라도 모두 필기야.
   다른 색으로 덧쓴 값, 동그라미 친 값도 빠뜨리지 마.

[숫자 정렬 블록]
8. 세로셈·나눗셈·진리표처럼 숫자가 여러 줄로 열을 맞춰 쌓인 필기는 kind를 "aligned", 그 밖은 "text".
   어떤 연산인지는 따지지 말고, 위에 쓴 결과·중간 줄·맨 아래 값·다른 색으로 쓴 값까지
   그 풀이 전체를 한 덩어리로 묶어.
   lines에는 줄마다 숫자·부호만 공백 없이 옮기고 $ 로 감싸지 마. 점선·화살표는 빼.

[카드 종류]
9. card_type은 프로그램 코드나 터미널 명령이면 "code", 수식이 중심이면 "math", 그 밖은 "text".

[수식 표기]
10. 앱이 그릴 수 있는 LaTeX만 써. 분수는 \\frac 만 쓰고 \\tfrac · \\dfrac 는 쓰지 마.
    동그라미 숫자는 \\textcircled 대신 ① ② ③ 같은 글자로 $ 밖에 써.
"""


def _fix_escape(match):
    """JSON에서 올바른 이스케이프만 두고, 나머지 역슬래시는 두 개로 바꾼다."""
    s = match.group(0)
    valid = (
        s in ("\\\\", '\\"', "\\/")
        or re.fullmatch(r"\\u[0-9a-fA-F]{4}", s)
        or (len(s) == 2 and s[1] in "bfnrt")
    )
    return s if valid else "\\" + s


def parse_regions(text: str) -> NoteRegions:
    """Gemini 답(JSON 글자)을 읽는다. 끊기거나 깨진 답이면 ValueError (Gemini가 다시 묻는다).

    모델이 LaTeX 역슬래시를 하나만 보낼 때가 있다. \\lim 은 JSON 오류가 나고,
    \\frac·\\times 는 \\f(폼피드)·\\t(탭)으로 바뀌어 수식이 깨지므로 먼저 고친다.
    한계: 진짜 줄바꿈 바로 뒤에 영어 글자가 붙으면(\\nThen) LaTeX 명령으로 보고 글자 그대로 남긴다.
    """
    if not text:
        raise ValueError("빈 답")
    fixed = re.sub(r'\\(\\|"|/|u[0-9a-fA-F]{4}|[a-zA-Z]+|.)', _fix_escape, text)
    return NoteRegions.model_validate(json.loads(fixed, strict=False))


def card_type_of(region: NoteRegion) -> CardType:
    """AI가 모르는 값을 주면 text로 본다"""
    try:
        return CardType(region.card_type)
    except ValueError:
        return CardType.text


def ask_regions(image_jpeg: bytes) -> tuple[list[NoteRegion], dict]:
    """보정본(JPEG)을 보내 덩어리 목록을 받는다. 끝내 실패하면 llm.LLMError"""
    result, info = llm.ask_image_json(
        image_jpeg, "image/jpeg", PROMPT, NoteRegions, task="note", gemini_parse=parse_regions
    )
    return result.regions, info
