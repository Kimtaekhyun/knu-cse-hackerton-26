//
//  CoverPhoto.swift
//  chalkdrop
//
//  판서 사진 자리 (사진이 없을 때 보여 주는 회색 빈 상자)
//

import SwiftUI

/// 판서 사진 자리. 찍은 사진이 없을 때(로그인 전 연출 · 사진을 못 불러왔을 때) 회색 빈 상자를 보여 줘요.
/// 예전에는 피그마 예시 판서 사진을 보여 줬지만, 실제 강의 사진이라 저작권 · 초상권 문제로 지웠어요.
struct CoverPhoto: View {
    let width: CGFloat
    let height: CGFloat
    var radius: CGFloat = 0

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color.black.opacity(0.05))
            .frame(width: width, height: height)
    }
}
