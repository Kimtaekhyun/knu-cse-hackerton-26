import pytest

from app.models import CardType
from app.services.pipeline.regions import card_type_of, parse_regions


def answer(line: str) -> str:
    """Gemini가 보낸 것 같은 JSON 글자. line은 역슬래시를 그대로 둔 채 넣는다"""
    return (
        '{"regions": [{"box_2d": [1, 2, 3, 4], "title": "t", "kind": "text", '
        '"card_type": "math", "lines": ["' + line + '"]}]}'
    )


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("$\\lim x$", "$\\lim x$"),  # \l 은 JSON 오류
        ("$\\frac{1}{2}$", "$\\frac{1}{2}$"),  # \f 는 폼피드로 바뀔 뻔함
        ("$\\times$", "$\\times$"),  # \t 는 탭으로 바뀔 뻔함
        ("$\\\\lim$", "$\\lim$"),  # 제대로 두 번 쓴 역슬래시는 그대로
        ('따옴표 \\"', '따옴표 "'),
    ],
)
def test_parse_regions_keeps_latex_backslashes(raw, expected):
    (region,) = parse_regions(answer(raw)).regions
    assert region.lines == [expected]


@pytest.mark.parametrize("text", ["", '{"regions": [', "not json"])
def test_parse_regions_rejects_broken_answer(text):
    """ValueError면 Gemini 호출부가 다시 묻는다"""
    with pytest.raises(ValueError):
        parse_regions(text)


def test_unknown_card_type_is_text():
    (region,) = parse_regions(answer("x").replace('"math"', '"table"')).regions
    assert card_type_of(region) == CardType.text
