//
//  PortraitCanvas.swift
//  chalkdrop
//
//  아이패드 세로 피그마 프레임(834 × 1194) 틀. 로그인 · 시간표 등록 세로 화면이 같이 써요.
//

import SwiftUI

let portraitWidth: CGFloat = 834
let portraitHeight: CGFloat = 1194

/// 세로 피그마 프레임(834 × 1194)을 화면에 맞춰 보여 주는 틀 (`DesignCanvas` 의 세로판)
struct PortraitCanvas<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / portraitWidth, geo.size.height / portraitHeight)
            content
                .frame(width: portraitWidth, height: portraitHeight, alignment: .topLeading)
                .clipped()
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color.white.ignoresSafeArea())
        .ignoresSafeArea()
    }
}

#Preview {
    LoginScreen().environment(Router())
}
