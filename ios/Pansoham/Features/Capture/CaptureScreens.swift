//
//  CaptureScreens.swift
//  chalkdrop
//
//  09 촬영 · 11 오류(화면을 찾지 못함)
//  촬영은 무음 카메라(`SilentCamera`)로 해요. 수업 중이라 셔터음이 나면 안 돼요 (#78).
//

import SwiftUI

// MARK: - 09 촬영

struct CaptureScreen: View {
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @State private var showAlbum = false
    @State private var camera = SilentCamera()
    /// 찍을 때 화면이 하얗게 번쩍 (소리 대신 찍혔다고 알려 줘요)
    @State private var flash = false
    /// 찍은 횟수. 바뀔 때마다 햅틱을 줘요
    @State private var shots = 0

    let viewfinder = Color(red: 0x29 / 255, green: 0x29 / 255, blue: 0x2B / 255)

    var body: some View {
        // 피그마 타임라인: 모서리가 조여 들고(0.2~0.8초) 안내가 내려와요(0.9~1.35초)
        Motion(length: 1.4) { t in
            Adaptive { canvas(t) } narrow: { narrow($0, t) }
        }
        .overlay {
            Color.white.opacity(flash ? 0.85 : 0).ignoresSafeArea().allowsHitTesting(false)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: shots)
        .task { await camera.start() }
        .task { await CaptureFlow.shared.loadDestination() }
        .onDisappear { camera.stop() }
        // 홈으로 나가면 카메라를 끄고, 돌아오면 다시 켜요 (배터리 · 발열)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await camera.start() } } else { camera.stop() }
        }
        // 앨범에서 사진을 고르면 찍은 것처럼 처리 중 화면으로 넘어가요.
        .imagePicker(isPresented: $showAlbum) { process($0) }
    }

    /// "자료구조 폴더에 저장" · "미분류함에 저장". 로그인 전에는 디자인 문구 그대로
    private var placeText: String {
        let flow = CaptureFlow.shared
        guard flow.isLive else { return "자료구조 폴더에 저장" }
        return "\(flow.destination?.placeTitle ?? "미분류함")에 저장"
    }

    /// 셔터: 무음으로 찍어요. 카메라를 쓸 수 없으면(시뮬레이터 등) 앨범을 열어요.
    func shutter() -> some View {
        Button(action: shoot) {
            Image("shutter-84").contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(camera.isCapturing ? 0.5 : 1)
        .disabled(camera.isCapturing)
        .accessibilityLabel("판서 찍기")
    }

    private func shoot() {
        guard camera.status == .running else {
            showAlbum = true
            return
        }
        shots += 1
        flash = true
        withAnimation(.easeOut(duration: 0.3)) { flash = false }
        Task {
            if let photo = await camera.capture() { process(photo) }
        }
    }

    /// 찍은(고른) 사진을 처리 중 화면으로 넘겨요
    private func process(_ photo: UIImage) {
        router.albumPhotos = [photo]
        router.push(.processing)
    }

    /// 뷰파인더 안: 카메라 미리보기, 아니면 권한 · 카메라 없음 안내
    @ViewBuilder
    func viewfinderContent() -> some View {
        switch camera.status {
        case .running:
            CameraPreview(camera: camera)
        case .idle:
            viewfinder
        case .denied:
            cameraNotice(title: "카메라 권한이 꺼져 있어요",
                         detail: "설정에서 chalkdrop 의 카메라를 켜 주세요.",
                         button: "설정 열기") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        case .unavailable:
            cameraNotice(title: "이 기기에서는 카메라를 쓸 수 없어요",
                         detail: "셔터를 누르면 앨범에서 판서 사진을 고를 수 있어요.",
                         button: "앨범에서 고르기") { showAlbum = true }
        }
    }

    private func cameraNotice(title: String, detail: String, button: String, action: @escaping () -> Void) -> some View {
        ZStack {
            viewfinder
            VStack(spacing: 10) {
                Text(title).dsWrap(20, .bold, .white).multilineTextAlignment(.center)
                Text(detail).dsWrap(15, .regular, .white.opacity(0.7)).multilineTextAlignment(.center)
                Button(action: action) {
                    Text(button).ds(15, .bold)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .padding(24)
        }
    }

    /// 위쪽 안내: 화면 인식은 서버가 하니까, 찍기 전에는 찍는 법만 알려 줘요
    func guidePill() -> some View {
        HStack(spacing: 8) {
            Image("dot-blue-8")
            Text("칠판 · 화면의 네 모서리가 들어오게 찍어 주세요").ds(14, .bold)
        }
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .padding(.vertical, 8)
        .background(Color.white)
        .clipShape(Capsule())
    }

    private func canvas(_ t: Double) -> some View {
        DesignCanvas(background: .black) {
            // 뷰파인더: 오른쪽 조작부(160)를 뺀 자리 전체가 카메라 미리보기
            ZStack(alignment: .topLeading) {
                viewfinder
                viewfinderContent()
                    .frame(width: DS.width - 160, height: DS.height)
                // 찍을 범위 안내 모서리 (누르면 그 아래 미리보기에 초점이 맞도록 터치는 통과)
                Image("viewfinder-corners")
                    .scaleEffect(tween(t, 1.12, 1, 0.2, 0.8, .spring))
                    .opacity(tween(t, 0, 1, 0.2, 0.5) * (camera.status == .running ? 1 : 0))
                    .allowsHitTesting(false)
                    .at(180, 170)
                guidePill()
                    .frame(width: 1100)          // 모서리(200~900) 가운데 = 550
                    .opacity(tween(t, 0, 1, 0.9, 1.35) * (camera.status == .running ? 1 : 0))
                    .allowsHitTesting(false)
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

            Text(placeText).ds(14, .bold, .white)
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
        }
    }
}

// MARK: - 11 오류 · 화면을 찾지 못함

struct CaptureErrorScreen: View {
    @Environment(Router.self) private var router
    /// 다시 처리 요청 중
    @State private var retrying = false
    @State private var errorMessage: String?

    private var flow: CaptureFlow { .shared }
    /// 실패한 판서 (로그인 전 연출이면 nil)
    private var failed: CaptureFlow.Job? { flow.failed }
    /// 화면(칠판 · 모니터)을 못 찾은 실패인지. 아니면 글씨 찾기 · 정리 중 실패
    private var isRectify: Bool { (failed?.capture?.failReason ?? "rectify") == "rectify" }
    /// 사진 해상도가 서버 상한을 넘어 열지 않은 실패 (#130). 다시 처리해도 같으므로 "다시 찍기"만 보여 줘요.
    private var isTooLarge: Bool { failed?.capture?.failReason == "too_large" }

    private var tips: [String] {
        if isTooLarge { return ["앱 카메라로 다시 찍어 주세요", "앨범에서는 다른 사진을 골라 주세요"] }
        return isRectify
            ? ["화면 전체가 들어오게 한 걸음 뒤에서", "빛 반사가 심하면 조금 옆으로 비켜서"]
            : ["잠시 뒤 다시 시도해 주세요", "글씨가 흐리면 가까이에서 다시 찍어 주세요"]
    }
    private var badge: String {
        if isTooLarge { return "사진이 너무 커요" }
        return isRectify ? "화면 모서리가 잘렸어요" : "정리하다 멈췄어요"
    }
    private var headline: String {
        if isTooLarge { return "사진이 너무 커서 정리하지 못했어요" }
        return isRectify ? "화면을 찾지 못했어요" : "판서를 정리하지 못했어요"
    }
    private var message: String {
        if isTooLarge { return "사진 해상도가 너무 커요. 다시 찍거나 다른 사진을 골라 주세요" }
        return isRectify ? "화면 네 모서리가 모두 나오게 다시 찍어 주세요" : "서버에서 판서를 정리하다 문제가 생겼어요"
    }
    /// 화면을 못 찾았으면 "그대로 쓰기"(사진 그대로 처리), 아니면 "다시 시도"
    private var useTitle: String { isRectify ? "그대로 쓰기" : "다시 시도" }

    var body: some View {
        Adaptive { wide } narrow: { narrow($0) }
            .alert("다시 처리하지 못했어요", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    /// 실패한 사진 (로그인 전 연출이면 디자인 예시 사진)
    @ViewBuilder
    private func photo(width: CGFloat, height: CGFloat) -> some View {
        if let image = failed?.image {
            Image(uiImage: image).resizable().scaledToFit()
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            CoverPhoto(width: width, height: height, radius: 4)
        }
    }

    /// 그대로 쓰기 · 다시 시도: 서버에 다시 처리를 맡기고 처리 중 화면으로
    private func useAnyway() {
        guard let failed, let capture = failed.capture else {
            router.replace(.result)   // 로그인 전 연출
            return
        }
        guard !retrying else { return }
        retrying = true
        Task {
            defer { retrying = false }
            do {
                var job = failed
                job.capture = try await CaptureAPI.retry(capture.id, skipRectify: isRectify)
                flow.resume(job)
                router.replace(.processing)
            } catch APIError.unauthorized {
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// 다시 찍기: 실패한 판서를 지우고 촬영 화면으로 (앨범에서 왔으면 홈으로).
    /// 지우지 못해도 조용히 넘어가요 (처리 중 취소 #101 과 같음, #126)
    private func retake() {
        if let id = failed?.capture?.id {
            Task { try? await SubjectCaptures.delete([id]) }
        }
        flow.failed = nil
        router.pop()
    }

    private var wide: some View {
        DesignCanvas {
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    Color(red: 0x29 / 255, green: 0x29 / 255, blue: 0x2B / 255)
                    photo(width: 420, height: 250).at(30, 20)
                    Text(badge).ds(13, .bold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white)
                        .clipShape(Capsule())
                        .at(24, 24)
                }
                .frame(width: 480, height: 290, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                Color.clear.frame(width: 1, height: 36)
                Text(headline).ds(34, .bold)
                Color.clear.frame(width: 1, height: 10)
                Text(message).ds(17, .regular, .dsSub)
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

            BottomBar(caption: "") {
                HStack(spacing: 12) {
                    // 해상도 초과는 다시 처리해도 같아서 "그대로 쓰기 · 다시 시도"를 숨겨요
                    if !isTooLarge {
                        Button(action: useAnyway) {
                            Text(useTitle).ds(17, .bold)
                                .padding(.horizontal, 24)
                                .frame(height: 56)
                                .background(Color.black.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(retrying)
                    }
                    PrimaryButton(title: "다시 찍기", action: retake)
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
                Text(placeText).ds(14, .bold, .white)
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

            guidePill()
                .opacity(tween(t, 0, 1, 0.9, 1.35) * (camera.status == .running ? 1 : 0))
                .offset(y: tween(t, -12, 0, 0.9, 1.35))

            // 카메라 미리보기 (피그마 740 × 460 비율을 너비에 맞춰요)
            viewfinderContent()
                .frame(width: boxWidth, height: boxWidth * 460 / 740)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, 16)

            Spacer(minLength: 16)

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

extension CaptureErrorScreen {
    func narrow(_ size: CGSize) -> some View {
        let inner = size.width - 40
        return VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        Color(red: 0x29 / 255, green: 0x29 / 255, blue: 0x2B / 255)
                        photo(width: 420, height: 250).at(30, 20)
                        Text(badge).ds(13, .bold)
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
                    Text(headline).ds(28, .bold)
                    Color.clear.frame(width: 1, height: 8)
                    Text(message)
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
                HStack(spacing: 10) {
                    if isTooLarge {
                        PrimaryButton(title: "다시 찍기", width: inner, action: retake)
                    } else {
                        GrayButton(title: useTitle, action: useAnyway).disabled(retrying)
                        PrimaryButton(title: "다시 찍기", width: max(120, inner - 130), action: retake)
                    }
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
