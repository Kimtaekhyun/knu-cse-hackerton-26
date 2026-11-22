"""사람이 입력한 이름(과목 이름 · 사용자 이름 등)에 공통으로 쓰는 검사."""

import unicodedata


def clean_text(text: str) -> str:
    """한글을 NFC로 맞추고 제어 문자(NUL · 줄바꿈 등)를 거절한다.

    iOS 입력과 서버 인식 결과의 정규화가 다르면 눈에 같은 '자료구조'가
    다른 문자열이 되어 중복 검사 · 이름 병합을 피해 간다. NUL은 Postgres에 넣을 수 없다.
    """
    if any(unicodedata.category(ch) == "Cc" for ch in text):
        raise ValueError("쓸 수 없는 문자가 있어요.")
    return unicodedata.normalize("NFC", text)
