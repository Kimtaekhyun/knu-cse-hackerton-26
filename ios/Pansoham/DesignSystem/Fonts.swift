//
//  Fonts.swift
//  chalkdrop
//
//  앱에 넣은 글꼴을 등록해요. Info.plist 를 따로 두지 않으려고 실행할 때 직접 등록해요.
//  - Caveat (칠판 손글씨, SIL OFL 1.1 — Fonts/Caveat-OFL.txt)
//

import CoreText
import Foundation

enum AppFonts {
    static func register() {
        for name in ["Caveat"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
