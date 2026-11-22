//
//  LocalKeyboard.swift
//  chalkdrop
//
//  키보드가 우리 앱 것인지 알려 줘요 (#115).
//  스플릿 뷰에서는 두 앱이 키보드 하나를 같이 써서, 옆 앱(굿노트)의 키보드도 우리 앱
//  키보드 영역(safe area)에 잡혀요. 그러면 화면 크기를 재는 GeometryReader 높이가 줄어
//  화면 전체가 작아지므로, 우리 앱 키보드일 때만 키보드 영역을 피해요.
//

import SwiftUI

@MainActor
@Observable
final class LocalKeyboard {
    static let shared = LocalKeyboard()

    /// 우리 앱 입력칸이 키보드를 띄웠는지
    private(set) var isShown = false

    private init() {
        #if os(iOS) || os(visionOS)
        let center = NotificationCenter.default
        center.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { note in
            // 값이 없으면 우리 앱 키보드로 봐요 (예전처럼 피하는 쪽이 안전)
            let local = note.userInfo?[UIResponder.keyboardIsLocalUserInfoKey] as? Bool ?? true
            MainActor.assumeIsolated { LocalKeyboard.shared.isShown = local }
        }
        center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { LocalKeyboard.shared.isShown = false }
        }
        #endif
    }
}

extension View {
    /// 옆 앱 키보드는 무시하고, 우리 앱 키보드만 피해요.
    func avoidsLocalKeyboardOnly() -> some View {
        modifier(LocalKeyboardAvoidance())
    }
}

private struct LocalKeyboardAvoidance: ViewModifier {
    private var keyboard = LocalKeyboard.shared

    func body(content: Content) -> some View {
        content.ignoresSafeArea(keyboard.isShown ? [] : .keyboard)
    }
}
