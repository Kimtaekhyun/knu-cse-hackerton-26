"""이름 검사 공용 함수(app/schemas/text.py)가 과목 · 사용자 이름에 같은 규칙을 적용하는지."""

import unicodedata

import pytest

from app.schemas.text import clean_text


def test_nfd_is_normalized_to_nfc():
    # iOS 입력은 NFD로 올 수 있다. 눈에 같은 글자가 다른 문자열이 되지 않게 NFC로 맞춘다
    nfd = unicodedata.normalize("NFD", "자료구조")
    assert nfd != "자료구조"
    assert clean_text(nfd) == "자료구조"


@pytest.mark.parametrize("text", ["자료\u0000구조", "민\n석", "탭\t문자"])
def test_control_characters_are_rejected(text):
    with pytest.raises(ValueError, match="쓸 수 없는 문자"):
        clean_text(text)


def test_plain_text_is_unchanged():
    assert clean_text("경북대학교 컴퓨터학부") == "경북대학교 컴퓨터학부"
