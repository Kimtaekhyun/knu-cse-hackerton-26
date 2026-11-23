//
//  PasteColor.swift
//  chalkdrop
//
//  붙여넣기 색 (#143). 굿노트로 넘기는 글자 · 수식 · 손글씨를 이 색으로.
//  글자는 색 입힌 글자(HTML · RTF)로 넘겨서 굿노트에서도 고칠 수 있어요. 검정이면 지금처럼 일반 글자만.
//

import SwiftUI
import UniformTypeIdentifiers

enum PasteColor: String, CaseIterable {
    case black, red, blue

    static let storageKey = "pasteColor"
    /// 지금 고른 색 (기본 검정)
    static var current: PasteColor {
        UserDefaults.standard.string(forKey: storageKey).flatMap(PasteColor.init) ?? .black
    }

    var title: String {
        switch self {
        case .black: "검정"
        case .red: "빨강"
        case .blue: "파랑"
        }
    }

    /// iOS 기본색
    var uiColor: UIColor {
        switch self {
        case .black: .black
        case .red: .systemRed
        case .blue: .systemBlue
        }
    }
    var color: Color { Color(uiColor: uiColor) }

    // MARK: 색 입힌 글자

    /// 굿노트가 읽는 순서대로: HTML → RTF → 일반 글자
    func richRepresentations(_ text: String, size: CGFloat = 20) -> [(type: UTType, data: Data)] {
        var result: [(UTType, Data)] = []
        if let html = html(text, size: size).data(using: .utf8) { result.append((.html, html)) }
        if let rtf = rtf(text, size: size) { result.append((.rtf, rtf)) }
        if let plain = text.data(using: .utf8) { result.append((.utf8PlainText, plain)) }
        return result
    }

    private func html(_ text: String, size: CGFloat) -> String {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br>")
        return "<meta charset=\"utf-8\"><span style=\"color:\(hex);font-size:\(Int(size))px;font-family:-apple-system\">\(escaped)</span>"
    }

    private func rtf(_ text: String, size: CGFloat) -> Data? {
        let attributed = NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: size, weight: .medium),
            .foregroundColor: uiColor,
        ])
        return try? attributed.data(from: NSRange(location: 0, length: attributed.length),
                                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }

    private var hex: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
