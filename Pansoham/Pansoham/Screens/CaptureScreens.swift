//
//  CaptureScreens.swift
//  판서함
//
//  09 촬영 · 10-1~3 처리 중 · 11 오류(화면을 찾지 못함)
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

// MARK: - 09 촬영

struct CaptureScreen: View {
    @Environment(Router.self) private var router
    @State private var mode = 0      // 0 빔 화면, 1 칠판
    @State private var pen = 0       // 0 빨간 펜, 1 검은 펜
    @State private var showAlbum = false

    private let viewfinder = Color(red: 0x29 / 255, green: 0x29 / 255, blue: 0x2B / 255)

    var body: some View {
        // 피그마 타임라인: 모서리가 조여 들고(0.2~0.8초) 안내가 내려와요(0.9~1.35초)
        Motion(length: 1.4) { t in
            Adaptive { canvas(t) } narrow: { narrow($0, t) }
        }
        // 앨범에서 사진을 고르면 찍은 것처럼 처리 중 화면으로 넘어가요.
        .imagePicker(isPresented: $showAlbum) { _ in router.push(.processing) }
    }

    /// 셔터: 누르면 처리 중, 길게 누르면 "화면을 찾지 못함"(11) 화면 (데모용)
    func shutter() -> some View {
        Image("shutter-84")
            .contentShape(Circle())
            .onTapGesture { router.push(.processing) }
            .onLongPressGesture(minimumDuration: 0.6) { router.push(.captureError) }
            .accessibilityAddTraits(.isButton)
    }

    private func canvas(_ t: Double) -> some View {
        DesignCanvas(background: .black) {
            // 뷰파인더
            ZStack(alignment: .topLeading) {
                viewfinder
                CoverPhoto(width: 700, height: 420, radius: 4).at(200, 190)
                Image("viewfinder-corners")
                    .scaleEffect(tween(t, 1.12, 1, 0.2, 0.8, .spring))
                    .opacity(tween(t, 0, 1, 0.2, 0.5))
                    .at(180, 170)
                HStack(spacing: 8) {
                    Image("dot-blue-8")
                    Text("화면을 찾았어요 · 그대로 찍으세요").ds(14, .bold)
                }
                .padding(.leading, 14)
                .padding(.trailing, 16)
                .padding(.vertical, 8)
                .background(Color.white)
                .clipShape(Capsule())
                .frame(width: 1100)          // 사진(200~900) 가운데 = 550
                .opacity(tween(t, 0, 1, 0.9, 1.35))
                .at(0, 118 + tween(t, -12, 0, 0.9, 1.35))
            }
            .frame(width: DS.width, height: DS.height, alignment: .topLeading)

            // 닫기 · 저장 위치
            Button { router.pop() } label: {
                Image("close-22")
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.16))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .at(32, 44)

            Text("자료구조 폴더에 저장").ds(14, .bold, .white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.16))
                .clipShape(Capsule())
                .at(88, 48)

            // 오른쪽 조작부
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.55)
                // 앨범
                Button { showAlbum = true } label: {
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.9))
                        Capsule().fill(Color.black).frame(width: 32, height: 3).at(10, 16)
                        Capsule().fill(Color.black).frame(width: 26, height: 3).at(10, 26)
                        Capsule().fill(Color.black).frame(width: 20, height: 3).at(10, 36)
                    }
                    .frame(width: 52, height: 52, alignment: .topLeading)
                }
                .buttonStyle(.plain)
                .at(54, 230)
                Text("앨범").ds(12, .medium, .white).at(69, 288)

                // 셔터
                shutter()
                    .at(38, 375)
            }
            .frame(width: 160, height: DS.height, alignment: .topLeading)
            .at(1034, 0)

            // 펜 색
            HStack(spacing: 8) {
                penChip("빨간 펜", index: 0)
                penChip("검은 펜", index: 1)
            }
            .at(476, 700)

            // 촬영 모드
            HStack(spacing: 4) {
                modeChip("빔 화면", index: 0)
                modeChip("칠판", index: 1)
            }
            .padding(4)
            .background(Color.white.opacity(0.16))
            .clipShape(Capsule())
            .at(463.5, 744)
        }
    }

    private func penChip(_ title: String, index: Int) -> some View {
        let on = pen == index
        return Button { pen = index } label: {
            Text(title).ds(13, .bold, on ? .white : .white.opacity(0.6))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .overlay(Capsule().stroke(on ? Color.white : Color.white.opacity(0.3), lineWidth: 1.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func modeChip(_ title: String, index: Int) -> some View {
        let on = mode == index
        return Button { withAnimation(.easeInOut(duration: 0.15)) { mode = index } } label: {
            Text(title).ds(15, .bold, on ? .black : .white)
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(on ? Color.white : Color.clear)
                .clipShape(Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 10 처리 중 (판서 펴기 → 글씨 찾기 → 수식 정리)

struct ProcessingScreen: View {
    @Environment(Router.self) private var router
    @State private var phase = 0         // 0 판서 펴기, 1 글씨 찾기, 2 수식 정리
    @State private var phaseStart = Date()   // 지금 단계가 시작된 때

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

            Button { router.pop() } label: {
                Text("취소").ds(17, .medium, .dsSub)
                    .frame(width: 120, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .at(537, 760)
        }
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
    private func run() async {
        do {
            try await Task.sleep(for: .seconds(1.8))
            phaseStart = Date()
            withAnimation(.easeInOut(duration: 0.45)) { phase = 1 }
            try await Task.sleep(for: .seconds(1.8))
            phaseStart = Date()
            withAnimation(.easeInOut(duration: 0.45)) { phase = 2 }
            try await Task.sleep(for: .seconds(2.4))
            router.replace(.result)
        } catch {
            // 화면을 벗어나면 그대로 멈춰요.
        }
    }
}

// MARK: - 11 오류 · 화면을 찾지 못함

struct CaptureErrorScreen: View {
    @Environment(Router.self) private var router

    private let tips = [
        "화면 전체가 들어오게 한 걸음 뒤에서",
        "빛 반사가 심하면 조금 옆으로 비켜서",
        "칠판이라면 촬영 모드를 칠판으로",
    ]

    var body: some View {
        Adaptive { wide } narrow: { narrow($0) }
    }

    private var wide: some View {
        DesignCanvas {
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    Color(red: 0x29 / 255, green: 0x29 / 255, blue: 0x2B / 255)
                    CoverPhoto(width: 420, height: 250, radius: 4).at(170, 90)
                    Text("화면 모서리가 잘렸어요").ds(13, .bold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white)
                        .clipShape(Capsule())
                        .at(24, 24)
                }
                .frame(width: 480, height: 290, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                Color.clear.frame(width: 1, height: 36)
                Text("화면을 찾지 못했어요").ds(34, .bold)
                Color.clear.frame(width: 1, height: 10)
                Text("화면 네 모서리가 모두 나오게 다시 찍어 주세요").ds(17, .regular, .dsSub)
                Color.clear.frame(width: 1, height: 28)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(tips, id: \.self) { tip in
                        HStack(spacing: 12) {
                            Image("bullet-6")
                            Text(tip).ds(15, .medium)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .background(Color.dsPanel)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .frame(width: DS.width)
            .at(0, 60)

            BottomBar(caption: "사진은 미분류함에 남겨 둘게요") {
                HStack(spacing: 12) {
                    Button { router.replace(.result) } label: {
                        Text("그대로 쓰기").ds(17, .bold)
                            .padding(.horizontal, 24)
                            .frame(height: 56)
                            .background(Color.black.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    PrimaryButton(title: "다시 찍기") { router.pop() }
                }
            }
        }
    }
}

// MARK: - 좁은 화면 (스플릿 뷰)

extension CaptureScreen {
    func narrow(_ size: CGSize, _ t: Double) -> some View {
        let boxWidth = size.width - 32
        return VStack(spacing: 0) {
            // 닫기 · 저장 위치
            HStack(spacing: 12) {
                Button { router.pop() } label: {
                    Image("close-22")
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.16))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                Text("자료구조 폴더에 저장").ds(14, .bold, .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.16))
                    .clipShape(Capsule())
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .avoidsWindowControls()

            Spacer(minLength: 16)

            HStack(spacing: 8) {
                Image("dot-blue-8")
                Text("화면을 찾았어요 · 그대로 찍으세요").ds(14, .bold)
            }
            .padding(.leading, 14)
            .padding(.trailing, 16)
            .padding(.vertical, 8)
            .background(Color.white)
            .clipShape(Capsule())
            .opacity(tween(t, 0, 1, 0.9, 1.35))
            .offset(y: tween(t, -12, 0, 0.9, 1.35))

            // 사진 + 모서리 표시 (피그마 740 × 460 조각을 너비에 맞춰요)
            ZStack(alignment: .topLeading) {
                CoverPhoto(width: 700, height: 420, radius: 4).at(20, 20)
                Image("viewfinder-corners")
                    .scaleEffect(tween(t, 1.12, 1, 0.2, 0.8, .spring))
                    .opacity(tween(t, 0, 1, 0.2, 0.5))
            }
            .scaledBox(740, 460, to: boxWidth)
            .padding(.top, 16)

            Spacer(minLength: 16)

            HStack(spacing: 8) {
                penChip("빨간 펜", index: 0)
                penChip("검은 펜", index: 1)
            }
            HStack(spacing: 4) {
                modeChip("빔 화면", index: 0)
                modeChip("칠판", index: 1)
            }
            .padding(4)
            .background(Color.white.opacity(0.16))
            .clipShape(Capsule())
            .padding(.top, 12)

            // 앨범 · 셔터
            HStack {
                Button { showAlbum = true } label: {
                    VStack(spacing: 6) {
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.9))
                            Capsule().fill(Color.black).frame(width: 32, height: 3).at(10, 16)
                            Capsule().fill(Color.black).frame(width: 26, height: 3).at(10, 26)
                            Capsule().fill(Color.black).frame(width: 20, height: 3).at(10, 36)
                        }
                        .frame(width: 52, height: 52, alignment: .topLeading)
                        Text("앨범").ds(12, .medium, .white)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                shutter()
                Spacer()
                Color.clear.frame(width: 52, height: 52)
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0x29 / 255, green: 0x29 / 255, blue: 0x2B / 255).ignoresSafeArea())
    }
}

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
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 28)
                .padding(.bottom, 16)
            }
            Button { router.pop() } label: {
                Text("취소").ds(17, .medium, .dsSub)
                    .frame(width: 120, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 16)
        }
        .background(Color.white.ignoresSafeArea())
    }
}

extension CaptureErrorScreen {
    func narrow(_ size: CGSize) -> some View {
        let inner = size.width - 40
        return VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        Color(red: 0x29 / 255, green: 0x29 / 255, blue: 0x2B / 255)
                        CoverPhoto(width: 420, height: 250, radius: 4).at(170, 90)
                        Text("화면 모서리가 잘렸어요").ds(13, .bold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white)
                            .clipShape(Capsule())
                            .at(24, 24)
                    }
                    .frame(width: 480, height: 290, alignment: .topLeading)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .scaledBox(480, 290, to: min(480, inner))

                    Color.clear.frame(width: 1, height: 28)
                    Text("화면을 찾지 못했어요").ds(28, .bold)
                    Color.clear.frame(width: 1, height: 8)
                    Text("화면 네 모서리가 모두 나오게 다시 찍어 주세요")
                        .dsWrap(15, .regular, .dsSub)
                        .multilineTextAlignment(.center)
                    Color.clear.frame(width: 1, height: 24)

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(tips, id: \.self) { tip in
                            HStack(spacing: 12) {
                                Image("bullet-6")
                                Text(tip).dsWrap(15, .medium)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .background(Color.dsPanel)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .padding(.horizontal, 20)
                .padding(.top, 32)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            VStack(spacing: 10) {
                Text("사진은 미분류함에 남겨 둘게요").ds(14, .medium, .dsSub)
                HStack(spacing: 10) {
                    GrayButton(title: "그대로 쓰기") { router.replace(.result) }
                    PrimaryButton(title: "다시 찍기", width: max(120, inner - 130)) { router.pop() }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .top) { Rectangle().fill(Color.dsLine).frame(height: 1) }
        }
        .background(Color.white.ignoresSafeArea())
    }
}
