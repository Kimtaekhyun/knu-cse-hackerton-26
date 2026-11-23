//
//  PasteColorPicker.swift
//  chalkdrop
//
//  붙여넣기 색 고르기: 검정 · 빨강 · 파랑 점 (#143). 고른 점은 같은 색 테두리.
//  고른 값은 기기에 저장되고, 모든 화면의 점이 같은 값을 보여 줘요.
//  앱 화면의 카드는 그대로 검정이고, 굿노트로 넘길 때(복사 · 끌어다 놓기)만 이 색을 써요.
//

import SwiftUI

struct PasteColorPicker: View {
    /// 좁은 곳(스플릿 뷰 등)은 "붙여넣기 색" 글자 없이 점만
    var compact = false
    @AppStorage(PasteColor.storageKey) private var raw = PasteColor.black.rawValue

    var body: some View {
        HStack(spacing: 10) {
            if !compact { Text("붙여넣기 색").ds(14, .medium, .dsSub) }
            ForEach(PasteColor.allCases, id: \.self) { option in
                let on = raw == option.rawValue
                Button { withAnimation(.easeOut(duration: 0.15)) { raw = option.rawValue } } label: {
                    Circle().fill(option.color)
                        .frame(width: on ? 18 : 22, height: on ? 18 : 22)
                        .frame(width: 28, height: 28)
                        .overlay { if on { Circle().stroke(option.color, lineWidth: 2) } }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("붙여넣기 색 \(option.title)")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}
