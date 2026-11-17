//
//  ResultScreens.swift
//  판서함
//
//  12 결과 · 13 복사 완료
//

import SwiftUI

/// 원본 사진에서 카드 자리만 잘라 보여 주는 손글씨 조각
struct InkCrop: View {
    let sticker: Sticker
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        // 원본(372 × 279)에서 카드 너비가 틀에 꽉 차게 키우고, 세로는 가운데를 보여 줘요.
        let scale = width / sticker.w
        let top = sticker.y + (sticker.h - height / scale) / 2
        Image("board-photo")
            .resizable()
            .frame(width: 372 * scale, height: 279 * scale)
            .offset(x: -sticker.x * scale, y: -top * scale)
            .frame(width: width, height: height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// 원본 사진 + 카드 자리 표시 (372 × 279 기준, `scale` 로 크기 조절)
struct MarkedPhoto: View {
    var stickers = SampleData.stickers
    var scale: CGFloat = 1
    var radius: CGFloat = 16
    var shown = 4

    var body: some View {
        ZStack(alignment: .topLeading) {
            CoverPhoto(width: 372 * scale, height: 279 * scale)
            ForEach(stickers) { sticker in
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.dsBlue.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Color.dsBlue, lineWidth: 2))
                    .frame(width: sticker.w * scale, height: sticker.h * scale)
                    .at(sticker.x * scale, sticker.y * scale)
                    .opacity(sticker.id <= shown ? 1 : 0)
                    .animation(.easeOut(duration: 0.25).delay(0.1 + 0.12 * Double(sticker.id - 1)), value: shown)
                Text("\(sticker.id)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.dsBlue)
                    .clipShape(Circle())
                    .at(sticker.x * scale + 4, sticker.y * scale + 4)
                    .opacity(sticker.id <= shown ? 1 : 0)
                    .animation(.easeOut(duration: 0.25).delay(0.1 + 0.12 * Double(sticker.id - 1)), value: shown)
            }
        }
        .frame(width: 372 * scale, height: 279 * scale, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: - 12 결과 / 13 복사 완료

struct ResultScreen: View {
    @Environment(Router.self) private var router
    @State private var copiedCount: Int?     // 방금 복사한 카드 수 (알림이 떠 있는 동안)
    @State private var shown = 0
    @State private var showOriginal = false

    private let stickers = SampleData.stickers

    var body: some View {
        GeometryReader { geo in
            // 스플릿 뷰처럼 세로로 긴 창이면 좁은 화면용 배치를 써요.
            if DS.isNarrow(geo.size) {
                narrow(geo.size)
            } else {
                wide
            }
        }
        // 피그마 타임라인: 자리 표시는 0.1초부터, 카드는 0.3초부터 0.12초 간격으로 나타나요.
        .onAppear { shown = 4 }
        .fullScreenCover(isPresented: $showOriginal) { OriginalPhotoView() }
    }

    private var originalButton: some View {
        Button { showOriginal = true } label: {
            Text("원본 보기").ds(17, .medium, .dsSub)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 넓은 화면 (피그마 그대로)

    private var wide: some View {
        DesignCanvas {
            NavBar(backTitle: "자료구조", title: "", onBack: { router.popTo(.home) }) {
                originalButton
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("판서 4개를 찾았어요").ds(34, .bold)
                Text("11월 17일 10:42 · 카드를 굿노트로 끌어다 놓으세요").ds(17, .regular, .dsSub)
            }
            .at(48, 96)

            MarkedPhoto(shown: shown).at(48, 200)

            // 카드 (왼쪽 줄 1·3, 오른쪽 줄 2·4)
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) { card(0); card(2) }
                VStack(spacing: 16) { card(1); card(3) }
            }
            .at(444, 200)

            BottomBar(caption: "자료구조 폴더에 저장했어요") {
                PrimaryButton(title: copiedCount == nil ? "모두 복사" : "복사됨", width: 280) { copyAll(thenGuide: true) }
            }

            if let copiedCount {
                Button { router.push(.splitView) } label: { toast(copiedCount, hint: "굿노트에 붙여 넣으세요") }
                    .buttonStyle(.plain)
                    .frame(width: DS.width)
                    .at(0, 654)
                    .transition(.opacity.combined(with: .offset(y: 40)))
            }
        }
    }

    // MARK: 좁은 화면 (굿노트와 반반 나눠 쓸 때)

    private func narrow(_ size: CGSize) -> some View {
        let side: CGFloat = 20
        let inner = size.width - side * 2
        let columns = inner >= 520 ? 2 : 1
        let cardWidth = (inner - 12 * CGFloat(columns - 1)) / CGFloat(columns)
        // 사진은 창 높이의 1/3 정도까지만 차지해요.
        let photoWidth = min(inner, size.height * 0.34 * 372 / 279)

        return VStack(spacing: 0) {
            // 위 막대
            HStack {
                Button { router.popTo(.home) } label: {
                    HStack(spacing: 2) {
                        Image("chevron-back-24")
                        Text("자료구조").ds(17, .medium)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                originalButton
            }
            .padding(.leading, 12)
            .padding(.trailing, side)
            .frame(height: 52)
            .avoidsWindowControls()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("판서 4개를 찾았어요").ds(28, .bold)
                        Text("11월 17일 10:42 · 카드를 길게 눌러 굿노트로 끌어다 놓으세요")
                            .font(.system(size: 15))
                            .tracking(-0.15)
                            .foregroundStyle(Color.dsSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    MarkedPhoto(scale: photoWidth / 372, shown: shown)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, photoWidth < inner ? 12 : 0)
                        .background(Color.dsPanel)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    if columns == 2 {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 12) { card(0, width: cardWidth); card(2, width: cardWidth) }
                            VStack(spacing: 12) { card(1, width: cardWidth); card(3, width: cardWidth) }
                        }
                    } else {
                        VStack(spacing: 12) {
                            ForEach(stickers.indices, id: \.self) { card($0, width: cardWidth) }
                        }
                    }
                }
                .padding(.horizontal, side)
                .padding(.top, 4)
                .padding(.bottom, 20)
            }

            // 아래 막대
            HStack(spacing: 12) {
                Text("자료구조 폴더에 저장했어요")
                    .font(.system(size: 15, weight: .medium))
                    .tracking(-0.15)
                    .foregroundStyle(Color.dsSub)
                    .lineLimit(2)
                Spacer(minLength: 0)
                PrimaryButton(title: copiedCount == nil ? "모두 복사" : "복사됨", width: inner < 440 ? 150 : 200) {
                    copyAll(thenGuide: false)
                }
            }
            .padding(.horizontal, side)
            .padding(.vertical, 14)
            .overlay(alignment: .top) { Rectangle().fill(Color.dsLine).frame(height: 1) }
            .overlay(alignment: .top) {
                if let copiedCount {
                    toast(copiedCount, hint: inner < 440 ? nil : "굿노트에 붙여 넣으세요")
                        .offset(y: -68)
                        .transition(.opacity.combined(with: .offset(y: 40)))
                }
            }
        }
        .background(Color.white.ignoresSafeArea())
    }

    // MARK: 공통 조각

    private func card(_ index: Int, width: CGFloat = 343) -> some View {
        StickerCard(sticker: stickers[index], width: width,
                    onTap: { router.push(.cardDetail) },
                    onCopy: { copy([stickers[index]]) })
            .entrance(shown > 0, delay: 0.3 + 0.12 * Double(index), duration: 0.45, y: 20)
    }

    /// 복사 완료 알림
    private func toast(_ count: Int, hint: String?) -> some View {
        HStack(spacing: 12) {
            Image("check-circle-24")
            Text("카드 \(count)개를 복사했어요").ds(15, .bold, .white)
            if let hint { Text(hint).ds(15, .medium, .dsSub) }
        }
        .padding(.leading, 18)
        .padding(.trailing, 24)
        .padding(.vertical, 14)
        .background(Color.black)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 12)
    }

    /// 카드 글자를 클립보드에 넣고 알림을 잠깐 띄워요.
    /// `thenGuide` 면 알림 뒤에 스플릿 뷰 안내로 넘어가고, 아니면 알림만 사라져요.
    private func copy(_ cards: [Sticker], thenGuide: Bool = false) {
        Clipboard.copy(cards.map(\.text).joined(separator: "\n\n"))
        withAnimation(.easeOut(duration: 0.5).delay(0.1)) { copiedCount = cards.count }
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            if thenGuide {
                if router.current == .result || router.current == .copied { router.push(.splitView) }
            } else {
                withAnimation(.easeIn(duration: 0.25)) { copiedCount = nil }
            }
        }
    }

    /// 모두 복사. 넓은 화면에서만 스플릿 뷰 안내로 넘어가요 (좁은 화면은 이미 나눠 쓰는 중).
    private func copyAll(thenGuide: Bool) {
        guard copiedCount == nil else { return }
        copy(stickers, thenGuide: thenGuide)
    }
}

// MARK: - 원본 사진 크게 보기

/// 결과 화면의 `원본 보기`. 찍은 판서 사진 전체를 검은 바탕에 크게 보여 줘요.
struct OriginalPhotoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image("board-photo")
                .resizable()
                .scaledToFit()
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button { dismiss() } label: {
                Image("close-22")
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.16))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(20)
            .accessibilityLabel("닫기")
        }
    }
}
