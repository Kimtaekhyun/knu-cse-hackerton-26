"""판서 LaTeX 정리 (latex.normalize) 테스트.

실제로 앱에서 깨졌던 카드 원문을 그대로 넣어 두고, 새 문제가 나오면 여기에 한 줄씩 더한다.
"""

import pytest

from app.services.pipeline.latex import normalize

# 실제 카드에서 나온 문제 (2026-11-24)
REAL_CASES = [
    # Claude가 역슬래시를 두 번 씀 → \\frac 가 줄바꿈 + frac 글자로 그려짐 (D_u 판서)
    (
        r"$D_u(D_uf) = \\frac{\\partial}{\\partial x}D_ufh + \\frac{\\partial}{\\partial y}D_ufk$",
        r"$D_u(D_uf) = \frac{\partial}{\partial x}D_ufh + \frac{\partial}{\partial y}D_ufk$",
    ),
    (
        r"$= f_{xx}\\left(h + \\frac{f_{xy}}{f_{xx}}k\\right)^2$",
        r"$= f_{xx}\left(h + \frac{f_{xy}}{f_{xx}}k\right)^2$",
    ),
    # \textcircled · \tfrac 는 SwiftMath에 없음 (급수 판서)
    (
        r"$\textcircled{3}\ x=3: \sum_{n=0}^{\infty} \tfrac{1}{\sqrt{n}} "
        r": D\ (p=\tfrac{1}{2}\text{-series})$",
        r"③ $x=3: \sum_{n=0}^{\infty} \frac{1}{\sqrt{n}} : D\ (p=\frac{1}{2}\text{-series})$",
    ),
    (
        r"$\textcircled{1}\ \lim_{n\to\infty}\left|\frac{a_{n+1}}{a_n}\right|$",
        r"① $\lim_{n\to\infty}\left|\frac{a_{n+1}}{a_n}\right|$",
    ),
    (r"$1.\ \tfrac{3}{2}$ 표시", r"$1.\ \frac{3}{2}$ 표시"),
]


@pytest.mark.parametrize(("raw", "expected"), REAL_CASES)
def test_real_cards(raw, expected):
    assert normalize(raw) == expected


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        # 구분자
        (r"\(x^2\) 와 \[y\]", r"$x^2$ 와 $$y$$"),
        # 명령 바꾸기
        (r"$\dfrac{a}{b}$", r"$\frac{a}{b}$"),
        (r"$\operatorname{rank} A$", r"$\mathrm{rank} A$"),
        (r"$\boxed{x=1}$", r"${x=1}$"),
        (r"$\cancel{f(x)} + 1$", r"${f(x)} + 1$"),
        (r"$\cancelto{0}{x}$", r"${x}$"),
        (r"$a \xrightarrow{n\to\infty} b$", r"$a \to^{n\to\infty} b$"),
        (r"$a \xrightarrow[low]{} b$", r"$a \to b$"),
        (r"$\overset{def}{=}$", r"${=}^{def}$"),
        (r"$\underset{x\to 0}{\lim}$", r"${\lim}_{x\to 0}$"),
        (r"$\boxed{\boxed{x}}$", r"${{x}}$"),
        # 한글은 $ 밖으로
        (r"$x=3 일 때 y=2$", r"$x=3$ 일 때 $y=2$"),
        (r"$\text{수렴} \sum a_n$", r"수렴 $\sum a_n$"),
        # 중괄호 안 한글은 그대로 (빼면 식이 깨짐)
        (r"$\frac{거리}{시간}$", r"$\frac{거리}{시간}$"),
        # 영어 \text 는 그대로
        (r"$p\text{-series}$", r"$p\text{-series}$"),
        # $$ 안의 동그라미 숫자는 (3)
        ("$$\\textcircled{3}\n x=1$$", "$$(3)\n x=1$$"),
    ],
)
def test_rewrites(raw, expected):
    assert normalize(raw) == expected


@pytest.mark.parametrize(
    "unchanged",
    [
        "그냥 글자",
        r"$\frac{1}{2}$",
        r"$\begin{aligned} a &= b \\ c &= d \end{aligned}$",  # 진짜 줄바꿈 \\ 는 남김
        r"$\\[2pt]$",  # 줄 간격 \\[2pt] 는 구분자로 보지 않음
        r"가격 $5",  # 짝 없는 $
        r"$\leftarrow \rightarrow$",
        r"$\frac{a$",  # 괄호가 안 맞으면 그대로
        "1234\n-567",  # 숫자 정렬 블록
    ],
)
def test_unchanged(unchanged):
    assert normalize(unchanged) == unchanged
