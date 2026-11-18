//
//  ProcessingScreen.swift
//  chalkdrop
//
//  10-1~3 처리 중 (판서 펴기 → 글씨 찾기 → 수식 정리)
//

import SwiftUI

// MARK: - 10 처리 중 (판서 펴기 → 글씨 찾기 → 수식 정리)

struct ProcessingScreen: View {
    @Environment(Router.self) private var router
    @State private var phase = 0         // 0 판서 펴기, 1 글씨 찾기, 2 수식 정리
    @State private var phaseStart = Date()   // 지금 단계가 시작된 때
    /// 여러 장일 때 지금 처리 중인 사진 (0부터). 한 장씩 차례로 처리해요 (10-2).
    @State private var current = 0

    /// 메인 `앨범에서 선택` 으로 고른 사진들. 촬영 화면에서 오면 비어 있어요.
    private var photos: [UIImage] { router.albumPhotos }
    private var total: Int { max(1, photos.count) }
    private var isBatch: Bool { photos.count > 1 }

    private let titles = ["판서를 반듯하게 펴고 있어요", "글씨와 수식을 찾고 있어요", "수식으로 정리하고 있어요"]
    private let details = ["기울기와 빛 반사를 지우는 중", "4곳 중 3곳 발견", "찾은 내용을 텍스트와 수식(LaTeX)으로 바꾸는 중"]
    private let steps = ["판서 펴기", "글씨 찾기", "수식 정리"]
    private let progress: [CGFloat] = [110, 215, 300]

    private struct Region {
        let label: String
        let x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat
    }
    private let regions: [Region] = [
        .init(label: "f(x) 정의 · 도함수", x: 30, y: 234, w: 282, h: 112.5),
        .init(label: "극한 계산", x: 330, y: 58.5, w: 258, h: 162),
        .init(label: "적분 풀이 → 발산", x: 330, y: 261, w: 258, h: 171),
        .init(label: "부등식 → x > e", x: 30, y: 360, w: 240, h: 76.5),
    ]
    private let cards: [(title: String, body: String?)] = [
        ("f(x) 정의 · 도함수", "f(x) = ln x / x,  f′(x) = (1 − ln x) / x² < 0"),
        ("극한 계산", "lim ln x / x = lim 1 / x = 0"),
        ("적분 풀이 → 발산", "∫₃^∞ (ln x / x) dx = ½[(ln x)²]₃^∞ = ∞"),
        ("부등식 → x > e", nil),
    ]

    var body: some View {
        // 피그마 타임라인: 단계마다 3.4초짜리. t 는 지금 단계에서 흐른 시간이에요.
        TimelineView(.animation) { context in
            let t = max(0, context.date.timeIntervalSince(phaseStart))
            Adaptive { canvas(t) } narrow: { narrow($0, t) }
        }
        .task { await run() }
    }

    private func canvas(_ t: Double) -> some View {
        DesignCanvas {
            photoBox(t).at(phase == 2 ? 110 : 297, 56)

            if phase == 2 {
                // 카드가 0.3초 간격으로 떠올라요
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                        let start = 0.3 + 0.3 * Double(index)
                        resultCard(title: card.title, body: card.body)
                            .opacity(tween(t, 0, 1, start, start + 0.3))
                            .offset(y: tween(t, 16, 0, start, start + 0.3))
                    }
                }
                .at(750, 56)
            }

            status
                .frame(width: DS.width)
                .at(0, 532)

            if isBatch {
                countPill.frame(width: DS.width).at(0, 18)
                batchStrip.frame(width: DS.width).at(0, 664)
            }

            Button(action: cancel) {
                Text(cancelTitle).ds(17, .medium, .dsSub)
                    .frame(width: 160, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .at(517, isBatch ? 770 : 760)
        }
    }

    // MARK: 여러 장 (10-2)

    /// "3장 중 1장째"
    private var countPill: some View {
        Text("\(total)장 중 \(current + 1)장째").ds(13, .bold, .dsBlue)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color.dsBlueSoft, in: Capsule())
    }

    /// 사진별 상태: 끝남 · 정리 중 · 대기
    private var batchStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(photos.indices, id: \.self) { index in
                    let state = index < current ? "완료" : index == current ? "정리 중" : "대기"
                    VStack(spacing: 6) {
                        Image(uiImage: photos[index])
                            .resizable()
                            .scaledToFill()
                            .frame(width: 88, height: 66)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                if index == current {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(Color.dsBlue, lineWidth: 2.5)
                                }
                            }
                            .opacity(index > current ? 0.45 : 1)
                        Text("\(index + 1) · \(state)").ds(12, .bold, index == current ? .dsBlue : .dsSub)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .fixedSize(horizontal: photos.count <= 8, vertical: true)
    }

    private var cancelTitle: String { isBatch ? "나머지 취소" : "취소" }

    /// 한 장일 때는 그냥 돌아가고, 여러 장일 때는 끝난 사진까지만 결과로 보여 줘요.
    private func cancel() {
        if isBatch && current > 0 {
            finish(done: current)
        } else {
            router.albumPhotos = []
            router.pop()
        }
    }

    private func finish(done: Int) {
        router.processedCount = max(1, done)
        router.albumPhotos = []
        router.replace(.result)
    }

    /// 지금 단계 설명 · 단계 표시 · 진행 막대
    private var status: some View {
        VStack(spacing: 0) {
            Text(titles[phase]).ds(28, .bold)
            Color.clear.frame(width: 1, height: 8)
            Text(details[phase]).ds(15, .regular, .dsSub)
            Color.clear.frame(width: 1, height: 22)
            HStack(spacing: 28) {
                ForEach(0..<3, id: \.self) { index in
                    if index < phase {
                        Text("✓ \(steps[index])").ds(14, .medium)
                    } else if index == phase {
                        HStack(spacing: 6) {
                            Image("dot-blue-8")
                            Text(steps[index]).ds(14, .bold)
                        }
                    } else {
                        Text(steps[index]).ds(14, .medium, .dsSub)
                    }
                }
            }
            Color.clear.frame(width: 1, height: 16)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.dsLine).frame(width: 320, height: 4)
                Capsule().fill(Color.dsBlue).frame(width: progress[phase], height: 4)
            }
        }
    }

    private func photoBox(_ t: Double) -> some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.06)

            if phase == 0 {
                // 기울어진 원본
                CoverPhoto(width: 520, height: 390, radius: 4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.dsBlue, lineWidth: 3))
                    .rotationEffect(.degrees(4))
                    .frame(width: 600, height: 450)
            } else {
                CoverPhoto(width: 600, height: 450)
            }

            if phase < 2 {
                // 훑는 빛
                LinearGradient(colors: [Color.dsBlue.opacity(0), Color.dsBlue.opacity(0.3)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(width: 600, height: 80)
                    .at(0, 145 + tween(t.truncatingRemainder(dividingBy: 3.4), -225, 180, 0, 1.5, .inOut))
                Rectangle().fill(Color.dsBlue).frame(width: 600, height: 3)
                    .at(0, 225 + tween(t.truncatingRemainder(dividingBy: 3.4), -225, 180, 0, 1.5, .inOut))
            }

            if phase >= 1 {
                ForEach(Array(regions.prefix(phase == 1 ? 3 : 4).enumerated()), id: \.offset) { index, region in
                    // 글씨 찾기 단계에서는 0.4초 간격으로 하나씩 나타나요
                    let start = 0.15 + 0.4 * Double(index)
                    let found = phase == 1 ? tween(t, 0, 1, start, start + 0.25) : 1
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.dsBlue.opacity(0.14))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.dsBlue, lineWidth: 2))
                        .frame(width: region.w, height: region.h)
                        .at(region.x, region.y)
                        .opacity(found)
                    Text(region.label).ds(11, .bold, .white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.dsBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .at(region.x, region.y - 22)
                        .opacity(found)
                }
            }
        }
        .frame(width: 600, height: 450, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func resultCard(title: String, body: String?) -> some View {
        VStack(alignment: .leading, spacing: body == nil ? 10 : 6) {
            HStack(spacing: 8) {
                Image("dot-blue-8")
                Text(title).ds(13, .bold)
            }
            if let body {
                Text(body)
                    .font(.system(size: 16, weight: .medium))
                    .tracking(-0.16)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Capsule().fill(Color.dsLine).frame(width: 220, height: 10)
                Capsule().fill(Color.dsLine).frame(width: 140, height: 10)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 334, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.black.opacity(0.1), lineWidth: 1))
    }

    /// 세 단계를 차례로 보여 주고 결과 화면으로 넘어가요.
    /// 여러 장이면 사진마다 되풀이해요. 두 번째 사진부터는 조금 빨리 넘어가요.
    private func run() async {
        do {
            for index in 0..<total {
                let fast = index > 0
                if fast {
                    phaseStart = Date()
                    withAnimation(.easeInOut(duration: 0.35)) { current = index; phase = 0 }
                }
                try await Task.sleep(for: .seconds(fast ? 1.0 : 1.8))
                phaseStart = Date()
                withAnimation(.easeInOut(duration: 0.45)) { phase = 1 }
                try await Task.sleep(for: .seconds(fast ? 1.0 : 1.8))
                phaseStart = Date()
                withAnimation(.easeInOut(duration: 0.45)) { phase = 2 }
                try await Task.sleep(for: .seconds(fast ? 1.4 : 2.4))
            }
            finish(done: total)
        } catch {
            // 화면을 벗어나면 그대로 멈춰요.
        }
    }
}

// MARK: - 좁은 화면 (스플릿 뷰)

extension ProcessingScreen {
    func narrow(_ size: CGSize, _ t: Double) -> some View {
        let inner = size.width - 40
        // 카드가 나오는 마지막 단계에서는 사진을 줄여 자리를 내줘요.
        let photoWidth = min(inner, 600) * (phase == 2 ? 0.62 : 1)
        return VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    photoBox(t).scaledBox(600, 450, to: photoWidth)

                    if phase == 2 {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                                let start = 0.3 + 0.3 * Double(index)
                                resultCard(title: card.title, body: card.body)
                                    .opacity(tween(t, 0, 1, start, start + 0.3))
                                    .offset(y: tween(t, 16, 0, start, start + 0.3))
                            }
                        }
                        .scaleEffect(min(1, inner / 334), anchor: .top)
                    }

                    status.scaleEffect(min(1, inner / 400), anchor: .top)

                    if isBatch { batchStrip }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 28)
                .padding(.bottom, 16)
            }
            .safeAreaInset(edge: .top) {
                if isBatch { countPill.padding(.top, 8) }
            }
            Button(action: cancel) {
                Text(cancelTitle).ds(17, .medium, .dsSub)
                    .frame(width: 160, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 16)
        }
        .background(Color.white.ignoresSafeArea())
    }
}
