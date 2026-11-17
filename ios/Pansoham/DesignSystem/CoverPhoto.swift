//
//  CoverPhoto.swift
//  판서함
//
//  틀을 꽉 채우게 잘라 보여 주는 판서 사진
//

import SwiftUI

/// 틀을 꽉 채우게 잘라 보여 주는 판서 사진 (피그마 object-cover)
struct CoverPhoto: View {
    let width: CGFloat
    let height: CGFloat
    var radius: CGFloat = 0

    var body: some View {
        Image("board-photo")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
