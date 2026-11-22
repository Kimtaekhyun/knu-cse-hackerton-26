//
//  PortraitCanvas.swift
//  chalkdrop
//
//  아이패드 세로 피그마 프레임(834 × 1194) 틀. 로그인 · 시간표 등록 · 시간표 확인 세로 화면이 같이 써요.
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

/// 세로 화면 위 막대 (뒤로 · 가운데 제목 · 오른쪽 버튼). `NavBar` 의 세로판.
struct PortraitNavBar<Trailing: View>: View {
    let backTitle: String
    let title: String
    var onBack: () -> Void = {}
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ZStack {
            Text(title).ds(17, .bold)
            HStack {
                Button(action: onBack) {
                    HStack(spacing: 2) {
                        Image("chevron-back-24")
                        Text(backTitle).ds(17, .medium)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                trailing
            }
            .padding(.leading, 36)
            .padding(.trailing, 48)
        }
        .frame(width: portraitWidth, height: 56)
    }
}

extension PortraitNavBar where Trailing == EmptyView {
    init(backTitle: String, title: String, onBack: @escaping () -> Void = {}) {
        self.init(backTitle: backTitle, title: title, onBack: onBack) { EmptyView() }
    }
}

/// 세로 화면 아래 막대 (왼쪽 설명 · 오른쪽 버튼). `BottomBar` 의 세로판.
struct PortraitBottomBar<Trailing: View, Accessory: View>: View {
    let caption: String
    var accessory: Accessory
    var trailing: Trailing

    init(caption: String, @ViewBuilder accessory: () -> Accessory, @ViewBuilder trailing: () -> Trailing) {
        self.caption = caption
        self.accessory = accessory()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 20) {
            Text(caption).ds(17, .medium, .dsSub)
            accessory
            Spacer()
            trailing
        }
        .padding(.horizontal, 48)
        .frame(width: portraitWidth, height: 104)
        .overlay(alignment: .top) { Rectangle().fill(Color.dsLine).frame(height: 1) }
    }
}

extension PortraitBottomBar where Accessory == EmptyView {
    init(caption: String, @ViewBuilder trailing: () -> Trailing) {
        self.init(caption: caption, accessory: { EmptyView() }, trailing: trailing)
    }
}

#Preview {
    LoginScreen().environment(Router())
}
