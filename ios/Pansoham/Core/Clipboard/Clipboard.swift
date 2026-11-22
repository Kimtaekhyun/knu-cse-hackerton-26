//
//  Clipboard.swift
//  chalkdrop
//
//  카드 글자를 클립보드에 복사 (수식이 있으면 그림으로)
//

import SwiftUI

enum Clipboard {
    /// 수식($...$)이 있으면 화면에 보이는 모양을 그림으로 넣어요 (#113).
    /// 굿노트는 LaTeX를 그리지 못해 글자로 넣으면 깨져요. 수식이 없으면 글자 그대로.
    @MainActor
    static func copy(_ text: String) {
        #if os(iOS) || os(visionOS)
        if text.contains("$"), let image = MathText.image(text, width: 600) {
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
