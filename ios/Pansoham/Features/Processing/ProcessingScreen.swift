//
//  ProcessingScreen.swift
//  chalkdrop
//
//  10-1~3 처리 중 (판서 펴기 → 글씨 찾기 → 수식 정리)
//  로그인했으면 사진을 서버에 올리고 처리 상태를 1초마다 확인해 단계를 보여 줘요 (#78).
//  로그인 전에는 서버 없이 정해진 연출로 보여 줘요 (디자인 확인용).
//

import SwiftUI

// MARK: - 10 처리 중 (판서 펴기 → 글씨 찾기 → 수식 정리)

struct ProcessingScreen: View {
    @Environment(Router.self) private var router
    @State private var phase = 0         // 0 판서 펴기, 1 글씨 찾기, 2 수식 정리
    @State private var phaseStart = Date()   // 지금 단계가 시작된 때
    /// 여러 장일 때 지금 처리 중인 사진 (0부터). 한 장씩 차례로 처리해요 (10-2).
    @State private var current = 0
    /// 서버가 찾은 카드 (지금 사진 처리가 끝났을 때)
    @State private var liveCards: [CardDTO] = []
    /// 반듯하게 편 사진 (지금 사진 처리가 끝났을 때)
    @State private var rectified: UIImage?
    /// 서버에 연결하지 못했을 때 문구
    @State private var errorMessage: String?
    /// 취소를 눌렀는지. 늦게 도착한 응답이 화면을 바꾸지 않게 해요 (#101)
    @State private var stopped = false

    private var flow: CaptureFlow { .shared }
    /// 찍었거나 앨범에서 고른 사진들
    private var photos: [UIImage] { flow.jobs.map(\.image) }
    private var total: Int { max(1, photos.count) }
    private var isBatch: Bool { photos.count > 1 }

    private let titles = ["판서를 반듯하게 펴고 있어요", "글씨와 수식을 찾고 있어요", "수식으로 정리하고 있어요"]
    private var details: [String] {
        let found = flow.isLive ? "글씨 · 수식 덩어리를 나누는 중" : "4곳 중 3곳 발견"
        return ["기울기와 빛 반사를 지우는 중", found, "찾은 내용을 텍스트와 수식(LaTeX)으로 바꾸는 중"]
    }
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
        .task { await start() }
        .alert("판서를 올리지 못했어요", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("다시 시도") { Task { await runLive() } }
            Button("돌아가기", role: .cancel) { cancel() }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// 서버 결과일 때 보여 줄 카드 (카드 칸에는 4개까지)
    private var shownCards: [(title: String, body: String?)] {
        guard flow.isLive else { return cards }
        return liveCards.prefix(4).map { ($0.title, $0.content) }
    }
    /// 카드가 나와서 사진을 왼쪽으로 옮길지
    private var showsCards: Bool { phase == 2 && (!flow.isLive || !liveCards.isEmpty) }

    private func canvas(_ t: Double) -> some View {
        DesignCanvas {
            photoBox(t).at(showsCards ? 110 : 297, 56)

            if showsCards {
                // 카드가 0.3초 간격으로 떠올라요
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(shownCards.enumerated()), id: \.offset) { index, card in
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
    /// 서버는 올라간 판서를 계속 처리해요 (나중에 과목 폴더에서 볼 수 있어요).
    private func cancel() {
        guard !stopped else { return }
        stopped = true
        errorMessage = nil
        discardUnfinished()
        let done = flow.isLive ? flow.results.count : current
        if isBatch && done > 0 {
            finish(done: done)
        } else {
            router.albumPhotos = []
            flow.jobs = []
            router.pop()
        }
    }

    /// 취소하면 아직 끝나지 않은 판서는 서버에서도 지워요 (결과로 보여 줄 끝난 판서는 남겨요).
    /// id 는 앱이 올리기 전에 만든 값이라, 업로드 답을 못 받았어도 같은 id 로 지울 수 있어요.
    /// 올리던 요청이 지우기보다 늦게 서버에 닿을 수 있어서, 없다고 하면(404) 잠시 뒤 한 번 더 지워요.
    private func discardUnfinished() {
        guard flow.isLive else { return }
        let kept = Set(flow.results.map(\.id))
        let ids = flow.jobs.map(\.id).filter { !kept.contains($0) }
        guard !ids.isEmpty else { return }
        // 화면이 닫혀도 끝까지 지우도록 화면과 묶이지 않은 작업으로 돌려요
        Task {
            for id in ids {
                do {
                    try await CaptureAPI.delete(id)
                } catch APIError.notFound {
                    try? await Task.sleep(for: .seconds(3))
                    try? await CaptureAPI.delete(id)
                } catch {
                    // 지우지 못해도 앱 동작에는 영향 없어요 (판서가 미분류함 등에 남을 뿐)
                }
            }
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

    /// 지금 처리 중인 사진 (찍었거나 앨범에서 고른 것). 없으면 디자인 예시 사진.
    @ViewBuilder
    private func shownPhoto(width: CGFloat, height: CGFloat, radius: CGFloat = 0) -> some View {
        if photos.indices.contains(current) {
            Image(uiImage: photos[current])
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            CoverPhoto(width: width, height: height, radius: radius)
        }
    }

    private func photoBox(_ t: Double) -> some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.06)

            if phase == 0 {
                // 기울어진 원본
                shownPhoto(width: 520, height: 390, radius: 4)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.dsBlue, lineWidth: 3))
                    .rotationEffect(.degrees(4))
                    .frame(width: 600, height: 450)
            } else {
                shownPhoto(width: 600, height: 450)
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

            if flow.isLive, phase == 2, let rectified, !liveCards.isEmpty {
                // 서버 결과: 반듯하게 편 사진 위에 카드 자리
                liveBoard(rectified)
            } else if phase >= 1, !flow.isLive {
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

    /// 반듯하게 편 사진을 600 × 450 칸에 맞춰 넣고, 카드 자리(0~1 좌표)를 그려요
    private func liveBoard(_ image: UIImage) -> some View {
        let aspect = image.size.width > 0 ? image.size.height / image.size.width : 0.75
        let size = aspect > 0.75 ? CGSize(width: 450 / aspect, height: 450) : CGSize(width: 600, height: 600 * aspect)
        let origin = CGPoint(x: (600 - size.width) / 2, y: (450 - size.height) / 2)
        return ZStack(alignment: .topLeading) {
            Color.white
            Image(uiImage: image).resizable().frame(width: size.width, height: size.height).at(origin.x, origin.y)
            ForEach(liveCards) { card in
                let x = origin.x + card.bbox.x * size.width, y = origin.y + card.bbox.y * size.height
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.dsBlue.opacity(0.14))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.dsBlue, lineWidth: 2))
                    .frame(width: card.bbox.w * size.width, height: card.bbox.h * size.height)
                    .at(x, y)
                Text("\(card.orderNo)").ds(11, .bold, .white)
                    .frame(width: 20, height: 20)
                    .background(Color.dsBlue, in: Circle())
                    .at(x + 4, y + 4)
            }
        }
        .frame(width: 600, height: 450, alignment: .topLeading)
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

    /// 촬영 · 앨범에서 넘겨준 사진으로 시작해요. 오류 화면의 "다시 처리"는 `flow.jobs` 를 미리 채워 둬요.
    private func start() async {
        if !router.albumPhotos.isEmpty {
            flow.begin(router.albumPhotos)
            router.albumPhotos = []
        }
        if flow.isLive {
            if flow.destination == nil { await flow.loadDestination() }
            await runLive()
        } else {
            await runDemo()
        }
    }

    /// 서버 처리: 사진마다 올리기 → 1초마다 상태 확인 → 끝나면 카드를 잠깐 보여 주고 다음 사진.
    /// 연결이 끊기면 알림을 띄우고, "다시 시도"하면 지금 사진부터 이어 해요 (같은 id 라 두 번 올라가지 않아요).
    private func runLive() async {
        do {
            for index in current..<flow.jobs.count {
                try checkAlive(index)
                if index != current || phase != 0 { show(index: index, phase: 0) }
                liveCards = []
                rectified = nil

                var capture: CaptureDTO
                if let saved = flow.jobs[index].capture, saved.status != .failed {
                    capture = saved
                } else {
                    let job = flow.jobs[index]
                    capture = try await CaptureAPI.upload(job.image, id: job.id, takenAt: job.takenAt)
                }
                try checkAlive(index)
                flow.jobs[index].capture = capture

                while !capture.status.isFinished {
                    if capture.status.phase != phase { show(index: index, phase: capture.status.phase) }
                    try await Task.sleep(for: .seconds(1))
                    capture = try await CaptureAPI.detail(capture.id)
                    try checkAlive(index)
                    flow.jobs[index].capture = capture
                }

                if capture.status == .failed {
                    // 한 장이면 오류 화면, 여러 장이면 건너뛰고 다음 사진
                    if flow.jobs.count == 1 {
                        flow.failed = flow.jobs[index]
                        router.replace(.captureError)
                        return
                    }
                    continue
                }

                // 끝: 반듯하게 편 사진 위에 카드 자리 · 카드를 잠깐 보여 줘요
                let image = try? await CaptureAPI.image(capture.id, rectified: true)
                try checkAlive(index)
                flow.jobs[index].rectified = image
                rectified = image
                show(index: index, phase: 2)
                withAnimation(.easeInOut(duration: 0.45)) { liveCards = capture.cards }
                flow.results.append(flow.jobs[index])
                try await Task.sleep(for: .seconds(capture.cards.isEmpty ? 0.6 : 1.8))
            }
            guard !stopped else { return }
            if flow.results.isEmpty, let first = flow.jobs.first {
                // 여러 장이 모두 실패했으면 첫 사진으로 오류 화면
                flow.failed = first
                router.replace(.captureError)
            } else {
                finish(done: flow.results.count)
            }
        } catch is CancellationError {
            // 화면을 벗어나면 그대로 멈춰요.
        } catch APIError.unauthorized {
            // 로그인 화면으로 가요 (`ContentView`)
        } catch {
            // 취소한 뒤 늦게 끝난 요청이면 알림을 띄우지 않아요
            guard !stopped, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// 취소했거나 화면을 나갔거나, 목록이 비워졌으면 그만해요 (비운 목록에 쓰다 튕기지 않게)
    private func checkAlive(_ index: Int) throws {
        if stopped || Task.isCancelled || !flow.jobs.indices.contains(index) { throw CancellationError() }
    }

    private func show(index: Int, phase newPhase: Int) {
        phaseStart = Date()
        withAnimation(.easeInOut(duration: 0.45)) {
            current = index
            phase = newPhase
        }
    }

    /// 세 단계를 차례로 보여 주고 결과 화면으로 넘어가요. (로그인 전 연출)
    /// 여러 장이면 사진마다 되풀이해요. 두 번째 사진부터는 조금 빨리 넘어가요.
    private func runDemo() async {
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
        let photoWidth = min(inner, 600) * (showsCards ? 0.62 : 1)
        return VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    photoBox(t).scaledBox(600, 450, to: photoWidth)

                    if showsCards {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(shownCards.enumerated()), id: \.offset) { index, card in
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
