//
//  Clipboard.swift
//  chalkdrop
//
//  카드 글자를 클립보드에 복사 (수식 카드가 있으면 그림으로)
//

import SwiftUI

enum Clipboard {
    /// 카드들을 빈 줄로 이어 넣어요.
    /// 수식($...$)이 있는 카드가 하나라도 있으면 화면에 보이는 모양을 그림으로 넣어요 (#113).
    /// 굿노트는 LaTeX를 그리지 못해 글자로 넣으면 깨져요. 코드 카드의 $ 는 수식이 아니라서 글자 그대로.
    @MainActor
    static func copy(_ cards: [Sticker]) {
        let text = cards.map(\.text).joined(separator: "\n\n")
        #if os(iOS) || os(visionOS)
        if cards.contains(where: \.hasMath), let image = MathText.image(cards, width: 600) {
            UIPasteboard.general.image = image
            return
        }
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
