//
//  Clipboard.swift
//  chalkdrop
//
//  글자를 클립보드에 복사
//

import SwiftUI

enum Clipboard {
    static func copy(_ text: String) {
        #if os(iOS) || os(visionOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
