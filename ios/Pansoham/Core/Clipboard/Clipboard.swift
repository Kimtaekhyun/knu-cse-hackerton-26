//
//  Clipboard.swift
//  chalkdrop
//
//  카드 글자를 클립보드에 복사 (수식 카드가 있으면 그림으로)
//

import SwiftUI
import UniformTypeIdentifiers

enum Clipboard {
    /// 카드들을 빈 줄로 이어 넣어요.
    /// 수식($...$)이 있는 카드가 하나라도 있으면 화면에 보이는 모양을 그림으로 넣어요 (#113).
    /// 굿노트는 LaTeX를 그리지 못해 글자로 넣으면 깨져요. 코드 카드의 $ 는 수식이 아니라서 글자 그대로.
    /// 붙여넣기 색(#143)이 검정이 아니면 글자는 색 입힌 글자(HTML · RTF + 일반 글자), 그림은 그 색으로 그려요.
    @MainActor
    static func copy(_ cards: [Sticker]) {
        let text = cards.map(\.text).joined(separator: "\n\n")
        let color = PasteColor.current
        #if os(iOS) || os(visionOS)
        if cards.contains(where: \.hasMath), let image = MathText.image(cards, width: 600, color: color.color) {
            UIPasteboard.general.image = image
            return
        }
        guard color != .black else {
            UIPasteboard.general.string = text
            return
        }
        // 한 항목에 HTML · RTF · 일반 글자를 함께 넣어요 (굿노트는 색 글자로, 다른 앱은 읽을 수 있는 걸로)
        var item: [String: Any] = [:]
        for (type, data) in color.richRepresentations(text) { item[type.identifier] = data }
        UIPasteboard.general.items = [item]
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
