//
//  SplitViewScreen.swift
//  판서함
//
//  14 스플릿 뷰 (굿노트로 끌어다 놓기 안내)
//

import SwiftUI

// MARK: - 14 스플릿 뷰

struct SplitViewScreen: View {
    @Environment(Router.self) private var router

    private let stickers = SampleData.stickers

    var body: some View {
        // 피그마 타임라인: 2.85초 되풀이 (카드를 집어서 → 끌고 → 놓기)
        Motion(loop: 2.85) { t in canvas(t) }
            .contentShape(Rectangle())
            .onTapGesture { router.popTo(.home) }
    }

    private func canvas(_ t: Double) -> some View {
        DesignCanvas(background: .black) {
            // 판서함 (왼쪽 앱)
            ZStack(alignment: .topLeading) {
                Color.white
                VStack(alignment: .leading, spacing: 12) {
                    Text("판서함").ds(28, .bold)
                    Text("자료구조 · 오늘 10:42").ds(15, .regular, .dsSub)
                    Color.clear.frame(width: 1, height: 4)
                    ForEach(stickers) { sticker in
                        StickerCard(sticker: sticker, width: 348)
                            .opacity(sticker.id == 2 ? 0.3 : 1)
                    }
                }
                .at(20, 20)
            }
            .frame(width: 388, height: 794, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .at(8, 32)

            // 굿노트 (오른쪽 앱)
            ZStack(alignment: .topLeading) {
                Color.white
                HStack {
                    Text("자료구조 노트").ds(15, .bold)
                    Spacer()
                    Text("굿노트").ds(13, .medium, .dsSub)
                }
                .padding(.horizontal, 24)
                .frame(width: 782, height: 56)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.dsLine).frame(height: 1) }

                notePaper(t).at(71, 76)
            }
            .frame(width: 782, height: 794, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .at(404, 32)

            // 가운데 손잡이
            RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.5))
                .frame(width: 4, height: 56)
                .at(396, 397)

            // 끌려가는 카드
            StickerCard(sticker: stickers[1], width: 360)
                .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 18)
                .scaleEffect(t < 1.6 ? tween(t, 0.96, 1.04, 0.3, 0.6) : tween(t, 1.04, 1, 1.6, 1.9, .bounce))
                .rotationEffect(.degrees(tween(t, 0, 3, 0.3, 0.6)))
                .frame(width: 368.927, height: 198.594)
                .offset(x: tween(t, -469.83, 0, 0.3, 1.6, .inOut), y: tween(t, -106, 0, 0.3, 1.6, .inOut))
                .at(497.83, 436)

            Text("카드를 길게 눌러 굿노트로 끌어다 놓으세요").ds(14, .bold, .white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.black)
                .clipShape(Capsule())
                .opacity(tween(t, 0, 1, 2.0, 2.45))
                .at(656.5, 770 + tween(t, 20, 0, 2.0, 2.45))
        }
    }

    /// 줄 노트 한 장
    private func notePaper(_ t: Double) -> some View {
        ZStack(alignment: .topLeading) {
            Color.white
            ForEach(0..<20, id: \.self) { index in
                Rectangle().fill(Color.black.opacity(0.06))
                    .frame(width: 640, height: 1)
                    .at(-1, 59 + CGFloat(index) * 32)
            }
            Capsule().fill(Color.black).frame(width: 200, height: 10).at(39, 27)
            Capsule().fill(Color.black.opacity(0.8)).frame(width: 300, height: 4).at(39, 81)
            Capsule().fill(Color.black.opacity(0.8)).frame(width: 240, height: 4).at(39, 113)
            Capsule().fill(Color.black.opacity(0.8)).frame(width: 360, height: 4).at(39, 145)

            // 먼저 붙여 둔 카드
            ZStack(alignment: .topLeading) {
                Color.white
                Capsule().fill(Color.black).frame(width: 180, height: 5).at(17, 29)
                Capsule().fill(Color.black).frame(width: 240, height: 5).at(17, 51)
            }
            .frame(width: 300, height: 96, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.black.opacity(0.1), lineWidth: 1))
            .at(39, 189)

            // 놓을 자리
            Text("여기에 놓기").ds(13, .bold, .black.opacity(0.5))
                .frame(width: 320, height: 110)
                .background(Color.dsBlue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.dsBlue, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                )
                .opacity(t < 1.7 ? tween(t, 0, 1, 0.5, 0.9) : tween(t, 1, 0, 1.7, 2.0, .in))
                .at(39, 319)
        }
        .frame(width: 640, height: 700, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.dsLine, lineWidth: 1))
    }
}
