"""판서 카드의 LaTeX를 앱(SwiftMath)이 그릴 수 있는 모양으로 정리한다.

AI 답을 카드로 저장하기 전에 한 번 거친다 (코드 카드는 빼고).
AI가 Gemini든 Claude든 같은 출구를 지난다.
- 역슬래시: \\\\frac 처럼 두 번 쓴 명령을 \\frac 로
  (Claude가 JSON을 한 번 더 이스케이프할 때가 있다)
- 구분자: \\( … \\) 는 $ … $, \\[ … \\] 는 $$ … $$ 로 (앱은 $ 만 수식으로 본다)
- SwiftMath에 없는 명령을 있는 명령으로
  (\\tfrac · \\boxed · \\cancel · \\xrightarrow · \\overset 등)
- 수식 안의 동그라미 숫자 · 한글은 $ 밖 글자로 뺀다 (수학 글꼴에 그 글자가 없다)

한계
- \\\\ 바로 뒤에 영어 글자를 붙인 진짜 줄바꿈(a \\\\b)은 명령으로 보고 하나로 줄인다.
- 중괄호 안의 한글(\\frac{한}{2})은 빼면 식이 깨지므로 그대로 둔다.
"""

import re

HANGUL = re.compile(r"[가-힣ㄱ-ㅎㅏ-ㅣ]")
# 한글 낱말 사이의 빈칸까지 한 덩어리로
HANGUL_WORDS = re.compile(r"[가-힣ㄱ-ㅎㅏ-ㅣ]+(?:\s+[가-힣ㄱ-ㅎㅏ-ㅣ]+)*")
COMMAND = re.compile(r"\\(?:[a-zA-Z]+|[\s\S])")
# 수식에서 빼낸 뒤 앞뒤에 남으면 버리는 빈칸 명령
SPACING = re.compile(r"^(?:\s|\\ |\\,|\\;|\\:|\\!|\\quad(?![a-zA-Z])|\\qquad(?![a-zA-Z]))+")
SPACING_END = re.compile(r"(?:\s|\\ |\\,|\\;|\\:|\\!|\\quad|\\qquad)+$")

# 이름만 바꾸면 되는 명령
RENAMES = {"tfrac": "frac", "dfrac": "frac", "operatorname": "mathrm"}
# 감싼 내용만 남기는 명령 (표시는 잃지만 식은 보인다)
UNWRAPS = {"boxed", "fbox", "cancel", "bcancel", "xcancel"}
# 글자를 단 화살표 → 화살표 위첨자로
ARROWS = {
    "xrightarrow": "\\to",
    "xleftarrow": "\\leftarrow",
    "xRightarrow": "\\Rightarrow",
    "xLeftarrow": "\\Leftarrow",
}


def normalize(content: str) -> str:
    """카드 글자 전체를 정리한다. 수식이 없으면 그대로 돌려준다."""
    text = fix_double_escapes(content)
    text = unify_delimiters(text)
    return rewrite_segments(text)


def fix_double_escapes(text: str) -> str:
    """\\\\frac → \\frac. 진짜 줄바꿈 \\\\ 는 보통 뒤에 빈칸 · & · 줄 끝이 와서 남는다."""
    return re.sub(r"\\\\(?=[a-zA-Z])", lambda _: "\\", text)


def unify_delimiters(text: str) -> str:
    """\\( \\) → $, \\[ \\] → $$. \\\\[2pt] 같은 줄 간격은 건드리지 않는다."""
    text = re.sub(r"(?<!\\)\\[()]", lambda _: "$", text)
    return re.sub(r"(?<!\\)\\[\[\]]", lambda _: "$$", text)


def rewrite_segments(text: str) -> str:
    """$$…$$ (여러 줄 가능) 와 줄마다의 $…$ 를 찾아 안쪽만 고친다. 짝이 없는 $ 는 글자로 둔다."""
    blocks = text.split("$$")
    out: list[str] = []
    for index, block in enumerate(blocks):
        if index % 2 == 1 and index < len(blocks) - 1:
            out.append("$$" + rewrite_commands(block, circled_out=False) + "$$")
            continue
        if index % 2 == 1:
            out.append("$$")
        out.append("\n".join(rewrite_inline(line) for line in block.split("\n")))
    return "".join(out)


def rewrite_inline(line: str) -> str:
    """한 줄의 $…$ 구간을 고친다. 동그라미 숫자 · 한글은 $ 밖으로 뺀다."""
    parts = line.split("$")
    out: list[str] = []
    for index, part in enumerate(parts):
        is_math = index % 2 == 1 and index < len(parts) - 1
        if not is_math:
            out.append(("$" if index % 2 == 1 else "") + part)
            continue
        pieces = []
        for kind, value in split_out(rewrite_commands(part, circled_out=True)):
            if kind == "text":
                pieces.append(value.strip())
                continue
            value = SPACING_END.sub("", SPACING.sub("", value))
            if value:
                pieces.append(f"${value}$")
        out.append(" ".join(p for p in pieces if p))
    return "".join(out)


def rewrite_commands(latex: str, *, circled_out: bool) -> str:
    """SwiftMath에 없는 명령을 바꾼다. circled_out이면 맨 바깥 \\textcircled 는 split_out이 뺀다."""
    for old, new in RENAMES.items():
        latex = re.sub(rf"\\{old}(?![a-zA-Z])", lambda _, n=new: "\\" + n, latex)
    latex = replace_command(latex, UNWRAPS, 1, lambda _, a: "{" + a[0] + "}")
    latex = replace_command(latex, {"cancelto"}, 2, lambda _, a: "{" + a[1] + "}")
    latex = replace_command(
        latex,
        set(ARROWS),
        1,
        lambda name, a: ARROWS[name] + ("^{" + a[0] + "}" if a[0].strip() else ""),
        optional=True,
    )
    latex = replace_command(
        latex, {"overset", "stackrel"}, 2, lambda _, a: f"{{{a[1]}}}^{{{a[0]}}}"
    )
    latex = replace_command(latex, {"underset"}, 2, lambda _, a: f"{{{a[1]}}}_{{{a[0]}}}")
    if not circled_out:
        latex = replace_command(latex, {"textcircled"}, 1, lambda _, a: f"({a[0].strip()})")
    return latex


def replace_command(latex, names, count, build, *, optional=False):
    """\\name[선택]{인자}… 를 build(name, 인자들)로 바꾼다. 인자를 못 읽으면 그대로 둔다."""
    pattern = re.compile(r"\\(" + "|".join(sorted(names, key=len, reverse=True)) + r")(?![a-zA-Z])")
    out = []
    i = 0
    while match := pattern.search(latex, i):
        end = match.end()
        if optional:
            end = skip_optional(latex, end)
        args = []
        for _ in range(count):
            read = read_group(latex, end)
            if read is None:
                break
            args.append(read[0])
            end = read[1]
        if len(args) < count:
            out.append(latex[i : match.end()])
            i = match.end()
            continue
        # 인자 안에 같은 명령이 또 있을 수 있어서 안쪽도 고친다
        args = [replace_command(a, names, count, build, optional=optional) for a in args]
        out.append(latex[i : match.start()] + build(match.group(1), args))
        i = end
    out.append(latex[i:])
    return "".join(out)


def skip_optional(latex: str, i: int) -> int:
    """[…] 선택 인자를 건너뛴다 (\\xrightarrow[아래]{위} 의 아래 글자는 버린다)"""
    j = skip_spaces(latex, i)
    if j < len(latex) and latex[j] == "[":
        close = latex.find("]", j)
        if close != -1:
            return close + 1
    return i


def read_group(latex: str, i: int) -> tuple[str, int] | None:
    """i부터 인자 하나를 읽는다: {…} (중첩 가능), \\명령, 글자 하나. (내용, 끝 위치)"""
    i = skip_spaces(latex, i)
    if i >= len(latex):
        return None
    if latex[i] == "{":
        depth = 0
        j = i
        while j < len(latex):
            c = latex[j]
            if c == "\\":
                j += 2
                continue
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    return latex[i + 1 : j], j + 1
            j += 1
        return None
    if latex[i] == "\\":
        command = command_at(latex, i)
        return command, i + len(command)
    if latex[i] in "}^_&":
        return None
    return latex[i], i + 1


def command_at(latex: str, i: int) -> str:
    """i의 역슬래시부터 명령 하나 (\\frac · \\{ · 끝에 홀로 남은 \\)"""
    match = COMMAND.match(latex, i)
    return match.group(0) if match else "\\"


def skip_spaces(latex: str, i: int) -> int:
    while i < len(latex) and latex[i] == " ":
        i += 1
    return i


def split_out(latex: str) -> list[tuple[str, str]]:
    """맨 바깥(중괄호 · \\left…\\right 밖)의 \\textcircled · 한글 \\text · 한글 글자를
    ("text", 글자) 로 빼고 나머지는 ("math", LaTeX) 로 둔다."""
    pieces: list[tuple[str, str]] = []
    math = ""
    depth = 0
    i = 0

    def flush():
        nonlocal math
        if math.strip():
            pieces.append(("math", math))
        math = ""

    while i < len(latex):
        c = latex[i]
        if c == "\\":
            command = command_at(latex, i)
            name = command[1:]
            if depth == 0 and name in ("textcircled", "text"):
                read = read_group(latex, i + len(command))
                if read is not None and (name == "textcircled" or HANGUL.search(read[0])):
                    flush()
                    label = circled(read[0]) if name == "textcircled" else read[0]
                    pieces.append(("text", label))
                    i = read[1]
                    continue
            if name in ("left", "begin"):
                depth += 1
            elif name in ("right", "end"):
                depth -= 1
            math += command
            i += len(command)
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        if depth == 0 and HANGUL.match(c):
            word = HANGUL_WORDS.match(latex, i)
            end = word.end() if word else i + 1
            flush()
            pieces.append(("text", latex[i:end]))
            i = end
            continue
        math += c
        i += 1
    flush()
    if depth != 0:
        # 괄호가 맞지 않는 식은 나누지 않는다 (앱이 원문으로 보여 준다)
        return [("math", latex)]
    return pieces


def circled(raw: str) -> str:
    """0~20 은 ⓪①…⑳, 그 밖은 (글자)"""
    label = raw.strip()
    if label.isdigit():
        n = int(label)
        if n == 0:
            return "⓪"
        if 1 <= n <= 20:
            return chr(0x2460 + n - 1)
    return f"({label})"
