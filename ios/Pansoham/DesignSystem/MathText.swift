//
//  MathText.swift
//  chalkdrop
//
//  카드 글자 안의 $...$ 구간을 수식으로 그려요 (#113).
//  서버는 수식 부분만 $...$ 로 감싼 LaTeX를 보내요. 복사 · 끌어다 놓기는 원문 그대로 두고,
//  화면에 보일 때만 SwiftMath로 그려요. 수식 문법이 틀리면 그 구간은 원문 글자로 보여 줘요.
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

    var body: some View {
        if !text.contains("$") {
            // 수식이 없으면 예전처럼 글자 그대로
            Text(text)
                .font(.system(size: size, weight: weight))
                .tracking(-size * 0.01)
                .foregroundStyle(color)
                .lineSpacing(lineGap)
        } else {
            VStack(alignment: .leading, spacing: lineGap) {
                ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                    FlowRow(hSpacing: size * 0.25, vSpacing: lineGap) {
                        ForEach(Array(MathLine.tokens(line).enumerated()), id: \.offset) { _, token in
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

// MARK: - 줄 나누기

enum MathLine {
    enum Token: Equatable {
        case word(String)
        case math(String)
    }

    /// 한 줄을 낱말과 수식 조각으로 나눠요.
    /// 긴 수식은 맨 바깥의 = · + 앞에서 잘라 화면 폭에 맞게 줄바꿈되게 해요.
    static func tokens(_ line: String) -> [Token] {
        var tokens: [Token] = []
        // $$...$$ 도 $...$ 와 똑같이 다뤄요
        let parts = line.replacingOccurrences(of: "$$", with: "$").components(separatedBy: "$")
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

    /// 중괄호 · \left…\right 밖에 있는 = · + 앞에서 수식을 잘라요.
    static func splitAtRelations(_ latex: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        var depth = 0
        let chars = Array(latex)
        var i = 0
        func startsWith(_ word: String) -> Bool {
            let w = Array(word)
            return i + w.count <= chars.count && Array(chars[i..<i + w.count]) == w
        }
        while i < chars.count {
            let c = chars[i]
            if c == "\\" {
                if startsWith("\\left") { depth += 1 }
                if startsWith("\\right") { depth -= 1 }
                // 명령 이름 · 이스케이프 글자는 통째로 넘겨요 (\{ 같은 건 깊이에 안 셈)
                current.append(c)
                i += 1
                if i < chars.count {
                    current.append(chars[i])
                    i += 1
                    while i < chars.count, chars[i].isLetter, chars[i - 1].isLetter {
                        current.append(chars[i])
                        i += 1
                    }
                }
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
