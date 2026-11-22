//
//  MathText.swift
//  chalkdrop
//
//  카드 글자 안의 $...$ 구간을 수식으로 그려요 (#113).
//  서버는 수식 부분만 $...$ 로 감싼 LaTeX를 보내요. 복사 · 끌어다 놓기는 원문 그대로 두고,
//  화면에 보일 때만 SwiftMath로 그려요. 수식 문법이 틀리면 그 구간은 원문 글자로 보여 줘요.
//  코드 카드는 `echo $HOME` 처럼 $ 가 수식이 아니라서 언제나 글자 그대로 둬요.
//

import SwiftUI
import SwiftMath

struct MathText: View {
    let text: String
    var size: CGFloat = 20
    var weight: Font.Weight = .medium
    var color: Color = .black
    /// 줄 사이 간격
    var lineGap: CGFloat = 8
    /// false 면 $ 가 있어도 수식으로 보지 않아요 (코드 카드)
    var math: Bool = true

    var body: some View {
        if !math || !text.contains("$") {
            // 수식이 없거나 코드 카드면 예전처럼 글자 그대로 (들여쓰기 · 공백 유지)
            Text(text)
                .font(.system(size: size, weight: weight))
                .tracking(-size * 0.01)
                .foregroundStyle(color)
                .lineSpacing(lineGap)
        } else {
            VStack(alignment: .leading, spacing: lineGap) {
                ForEach(Array(MathLine.lines(text).enumerated()), id: \.offset) { _, line in
                    FlowRow(hSpacing: size * 0.25, vSpacing: lineGap) {
                        ForEach(Array(line.enumerated()), id: \.offset) { _, token in
                            tokenView(token)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tokenView(_ token: MathLine.Token) -> some View {
        switch token {
        case .word(let word):
            Text(word)
                .font(.system(size: size, weight: weight))
                .tracking(-size * 0.01)
                .foregroundStyle(color)
                .fixedSize()
        case .math(let latex):
            if let image = MathImageCache.image(latex, size: size) {
                Image(uiImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(color)
                    .frame(maxWidth: image.size.width, maxHeight: image.size.height)
                    .accessibilityLabel(latex)
            } else {
                Text("$\(latex)$")
                    .font(.system(size: size * 0.8, weight: weight, design: .monospaced))
                    .foregroundStyle(color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension Sticker {
    /// 그림으로 넘겨야 하는 수식이 있는지. 코드 카드의 $ 는 수식이 아니에요.
    var hasMath: Bool { cardType != "code" && text.contains("$") }
}

extension MathText {
    /// 카드들을 화면에 보이는 모양 그대로 한 장의 그림으로 그려요 (배경 투명, 3배, 카드 사이 빈 줄).
    /// 굿노트는 LaTeX를 그리지 못해서, 끌어다 놓기 · 복사할 때 이 그림을 넘겨요. 실패하면 nil.
    /// 코드 카드는 그림 안에서도 글자 그대로 (들여쓰기 유지).
    @MainActor
    static func image(_ cards: [Sticker], width: CGFloat, size: CGFloat = 20) -> UIImage? {
        let lineGap = size * 1.45 - 24
        let renderer = ImageRenderer(content:
            VStack(alignment: .leading, spacing: size * 1.45 + lineGap) {
                ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                    MathText(text: card.text, size: size, weight: .medium, lineGap: lineGap,
                             math: card.cardType != "code")
                }
            }
            .frame(width: width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        )
        renderer.scale = 3
        return renderer.uiImage
    }
}

// MARK: - 줄 나누기

enum MathLine {
    enum Token: Equatable {
        case word(String)
        case math(String)
    }

    /// 글자 전체를 줄마다 낱말 · 수식 조각으로 나눠요.
    /// $$...$$ 는 여러 줄에 걸쳐도 수식 하나로 봐요 (\begin{aligned} 를 여러 줄로 쓰는 경우).
    /// $...$ 는 한 줄 안에서만 짝을 맞춰요 (글자 속 $5 같은 게 다른 줄과 짝지어지지 않게).
    static func lines(_ text: String) -> [[Token]] {
        var lines: [[Token]] = [[]]
        let blocks = text.components(separatedBy: "$$")
        for (index, block) in blocks.enumerated() {
            if index % 2 == 1 && index < blocks.count - 1 {
                let latex = block.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
                if !latex.isEmpty { lines[lines.count - 1] += splitAtRelations(latex).map(Token.math) }
                continue
            }
            // 짝이 맞지 않는 마지막 $$ 는 글자로
            if index % 2 == 1 { lines[lines.count - 1].append(.word("$$")) }
            for (n, line) in block.components(separatedBy: "\n").enumerated() {
                if n > 0 { lines.append([]) }
                lines[lines.count - 1] += tokens(line)
            }
        }
        return lines
    }

    /// 한 줄을 낱말과 수식($...$) 조각으로 나눠요.
    /// 긴 수식은 맨 바깥의 = · + 앞에서 잘라 화면 폭에 맞게 줄바꿈되게 해요.
    static func tokens(_ line: String) -> [Token] {
        var tokens: [Token] = []
        let parts = line.components(separatedBy: "$")
        for (index, part) in parts.enumerated() {
            // 짝이 맞지 않는 마지막 $ 뒤는 글자로
            let isMath = index % 2 == 1 && index < parts.count - 1
            if isMath {
                let latex = part.trimmingCharacters(in: .whitespaces)
                guard !latex.isEmpty else { continue }
                tokens += splitAtRelations(latex).map(Token.math)
            } else {
                let text = (index % 2 == 1) ? "$" + part : part
                tokens += text.split(separator: " ").map { .word(String($0)) }
            }
        }
        return tokens
    }

    /// 중괄호 · \left…\right · \begin…\end 밖에 있는 = · + 앞에서 수식을 잘라요.
    static func splitAtRelations(_ latex: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        var depth = 0
        let chars = Array(latex)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\\" {
                // 명령 이름 · 이스케이프 글자는 통째로 넘겨요 (\{ 같은 건 깊이에 안 셈)
                var command = String(c)
                i += 1
                if i < chars.count {
                    command.append(chars[i])
                    i += 1
                    while i < chars.count, chars[i].isLetter, chars[i - 1].isLetter {
                        command.append(chars[i])
                        i += 1
                    }
                }
                // 이름이 꼭 같을 때만 (\leftarrow · \rightarrow 는 괄호가 아님)
                switch command {
                case "\\left", "\\begin": depth += 1
                case "\\right", "\\end": depth -= 1
                default: break
                }
                current += command
                continue
            }
            if c == "{" { depth += 1 }
            if c == "}" { depth -= 1 }
            if c == "=" || c == "+", depth == 0, !current.trimmingCharacters(in: .whitespaces).isEmpty {
                pieces.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
            current.append(c)
            i += 1
        }
        let last = current.trimmingCharacters(in: .whitespaces)
        if !last.isEmpty { pieces.append(last) }
        // 괄호가 맞지 않는 수식은 자르지 않아요
        return depth == 0 ? pieces : [latex]
    }
}

// MARK: - 수식 그림

enum MathImageCache {
    private static let cache = NSCache<NSString, UIImage>()
    private static let failed = NSCache<NSString, NSNumber>()

    /// 수식을 그림으로 그려요. 문법이 틀리면 nil.
    static func image(_ latex: String, size: CGFloat) -> UIImage? {
        let key = "\(size)|\(latex)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        if failed.object(forKey: key) != nil { return nil }
        let math = MTMathImage(latex: latex, fontSize: size, textColor: .black, labelMode: .text, textAlignment: .left)
        let (error, image) = math.asImage()
        guard error == nil, let image, image.size.width > 0 else {
            failed.setObject(1, forKey: key)
            return nil
        }
        cache.setObject(image, forKey: key)
        return image
    }
}

// MARK: - 줄바꿈 배치

/// 폭이 넘치면 다음 줄로 넘기는 가로 배치. 한 줄 안에서는 세로 가운데 맞춤.
struct FlowRow: Layout {
    var hSpacing: CGFloat = 4
    var vSpacing: CGFloat = 6

    private func rows(_ maxWidth: CGFloat, _ subviews: Subviews) -> [[(Int, CGSize)]] {
        var rows: [[(Int, CGSize)]] = [[]]
        var x: CGFloat = 0
        for (index, view) in subviews.enumerated() {
            var size = view.sizeThatFits(.unspecified)
            if size.width > maxWidth {
                // 한 조각이 폭보다 넓으면 폭에 맞춰 줄여요
                size = view.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            }
            if x > 0, x + hSpacing + size.width > maxWidth {
                rows.append([])
                x = 0
            }
            x += (x > 0 ? hSpacing : 0) + size.width
            rows[rows.count - 1].append((index, size))
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = rows(maxWidth, subviews)
        var width: CGFloat = 0
        var height: CGFloat = 0
        for (r, row) in rows.enumerated() {
            let rowWidth = row.map(\.1.width).reduce(0, +) + hSpacing * CGFloat(max(0, row.count - 1))
            width = max(width, rowWidth)
            height += (row.map(\.1.height).max() ?? 0) + (r > 0 ? vSpacing : 0)
        }
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(bounds.width, subviews) {
            let rowHeight = row.map(\.1.height).max() ?? 0
            var x = bounds.minX
            for (index, size) in row {
                subviews[index].place(at: CGPoint(x: x, y: y + (rowHeight - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + hSpacing
            }
            y += rowHeight + vSpacing
        }
    }
}

#Preview {
    MathText(text: """
    $D_u(D_uf) = \\frac{\\partial}{\\partial x} D_uf\\,h + \\frac{\\partial}{\\partial y} D_uf\\,k$
    = $f_{xx}h^2 + 2f_{xy}hk + f_{yy}k^2$
    = $f_{xx}\\left(h + \\frac{f_{xy}}{f_{xx}}k\\right)^2 + \\frac{k^2}{f_{xx}}(f_{xx}f_{yy} - f_{xy}^2)$
    로피탈 적용 $\\lim_{x\\to\\infty}$ 틀린 수식 $\\frac{a$
    """)
    .frame(width: 500)
    .padding()
}
