//
//  ResultScreens.swift
//  chalkdrop
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
        // 원본(372 × 279, 서버 사진은 372 × 372·비율)에서 카드 너비가 틀에 꽉 차게 키우고, 세로는 가운데를 보여 줘요.
        let scale = width / max(sticker.w, 1)
        let top = sticker.y + (sticker.h - height / scale) / 2
        Group {
            if let photo = sticker.photo { Image(uiImage: photo).resizable() } else { Image("board-photo").resizable() }
        }
            .frame(width: 372 * scale, height: 372 * sticker.photoAspect * scale)
            .offset(x: -sticker.x * scale, y: -top * scale)
            .frame(width: width, height: height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// 원본 사진 + 카드 자리 표시 (372 × 279 기준, `scale` 로 크기 조절)
/// `photo` 를 넘기면 서버 사진을 그 비율(372 × 372·aspect) 그대로 보여 줘요.
struct MarkedPhoto: View {
    var stickers = SampleData.stickers
    var photo: UIImage? = nil
    var aspect: CGFloat = 279.0 / 372.0
    var scale: CGFloat = 1
    var radius: CGFloat = 16
    var shown = 4

    var body: some View {
        let height = 372 * aspect * scale
        ZStack(alignment: .topLeading) {
            if let photo {
                Image(uiImage: photo).resizable().frame(width: 372 * scale, height: height)
            } else {
                CoverPhoto(width: 372 * scale, height: 279 * scale)
            }
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
        .frame(width: 372 * scale, height: height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: - 12 결과 / 13 복사 완료

struct ResultScreen: View {
    @Environment(Router.self) private var router
    @State private var copiedCount: Int?     // 방금 복사한 카드 수 (알림이 떠 있는 동안)
    @State private var shown = 0
    @State private var showOriginal = false
    /// 여러 장일 때 보고 있는 사진 (12-2)
    @State private var photoTab = 0
    /// 판서 삭제 확인 창 · 삭제 중 · 실패 (#93)
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var deleteError: String?
    /// 지울 카드 (확인 창, #99)
    @State private var deletingCard: Sticker?
    /// 다시 찍기 확인 창 (#126)
    @State private var confirmRetake = false

    private var flow: CaptureFlow { .shared }
    /// 서버가 처리한 사진들. 비어 있으면(로그인 전 · 다른 화면에서 열 때) 샘플을 보여 줘요.
    private var live: [CaptureFlow.Job] { flow.results }
    private var isLive: Bool { !live.isEmpty }
    /// 방금 정리한 사진 수 (앨범에서 여러 장 고르면 2 이상)
    private var photoCount: Int { isLive ? live.count : router.processedCount }
    private var isBatch: Bool { photoCount > 1 }
    /// 사진 한 장의 카드
    private func stickers(of tab: Int) -> [Sticker] {
        isLive ? (live.indices.contains(tab) ? live[tab].stickers : []) : SampleData.stickers
    }
    /// 보고 있는 사진의 카드
    private var stickers: [Sticker] { stickers(of: photoTab) }
    private var totalCards: Int { (0..<photoCount).map { stickers(of: $0).count }.reduce(0, +) }
    private var title: String { totalCards == 0 ? "판서에서 글씨를 찾지 못했어요" : "판서 \(totalCards)개를 찾았어요" }
    /// 찍은 시각 ("11월 17일 10:42")
    private var takenText: String {
        guard isLive, let date = live[0].capture?.takenDate ?? Optional(live[0].takenAt) else { return "11월 17일 10:42" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 HH:mm"
        return formatter.string(from: date)
    }
    private func detail(_ tail: String) -> String {
        isBatch ? "사진 \(photoCount)장 · \(takenText) · \(tail)" : "\(takenText) · \(tail)"
    }
    /// 저장된 곳 ("자료구조 폴더" · "미분류함")
    private var place: String { isLive ? flow.placeTitle(of: live[0].capture) : "자료구조 폴더" }
    private var savedText: String { "\(place)에 저장했어요" }
    /// 왼쪽 위 돌아가기 글자: 과목 이름, 미분류면 "홈"
    private var backTitle: String {
        guard isLive else { return "자료구조" }
        return place.hasSuffix(" 폴더") ? String(place.dropLast(3)) : "홈"
    }
    /// 지금 탭의 사진 (서버 결과일 때)
    private var livePhoto: CaptureFlow.Job? { isLive && live.indices.contains(photoTab) ? live[photoTab] : nil }
    private var copyTitle: String {
        copiedCount != nil ? "복사됨" : isBatch ? "\(totalCards)개 모두 복사" : "모두 복사"
    }

    /// 사진 탭: "사진 1 · 카드 4"
    private var photoTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(0..<photoCount, id: \.self) { index in
                    let on = photoTab == index
                    Button { withAnimation(.easeInOut(duration: 0.15)) { photoTab = index } } label: {
                        Text("사진 \(index + 1) · 카드 \(stickers(of: index).count)").ds(14, .bold, on ? .white : .black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(on ? Color.black : Color.black.opacity(0.05), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

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
        .onAppear { shown = 999 }
        .fullScreenCover(isPresented: $showOriginal) { OriginalPhotoView(image: livePhoto?.image) }
        .alert(deleteTitle, isPresented: $confirmDelete) {
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive) { deletePhoto() }
        } message: {
            Text("\(isBatch ? "이 사진의 " : "")카드 \(stickers.count)개도 함께 지워지고 되돌릴 수 없어요.")
        }
        .deleteFailedAlert($deleteError)
        .alert("이 판서를 지우고 다시 찍을까요?", isPresented: $confirmRetake) {
            if alreadyMoved {
                Button("남기고 다시 찍기") { retake(deleting: false) }.keyboardShortcut(.defaultAction)
                Button("지우고 다시 찍기", role: .destructive) { retake(deleting: true) }
            } else {
                Button("지우고 다시 찍기", role: .destructive) { retake(deleting: true) }
                Button("남기고 다시 찍기") { retake(deleting: false) }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text(alreadyMoved ? "이미 굿노트로 옮긴 카드가 있어요. 남겨 두면 폴더에 그대로 있어요."
                              : "지우면 이 판서와 카드 \(stickers.count)개가 사라져요.")
        }
        .alert("카드를 삭제할까요?", isPresented: Binding(get: { deletingCard != nil }, set: { if !$0 { deletingCard = nil } })) {
            Button("취소", role: .cancel) { deletingCard = nil }
            Button("삭제", role: .destructive) { if let card = deletingCard { deleteCard(card) } }
        } message: {
            Text("삭제한 카드는 되돌릴 수 없어요.")
        }
        // 다른 곳(옮기지 않은 판서 목록 등)에서 결과를 열 때는 한 장 · 샘플로 보여 줘요.
        .onDisappear {
            if !router.stack.contains(.result) {
                router.processedCount = 1
                flow.results = []
                flow.openedFolder = nil
            }
        }
    }

    /// 다시 찍기: 찍은 직후 한 장 결과에서만 (예전 판서를 열었거나 여러 장이면 숨겨요, #126)
    private var canRetake: Bool { isLive && !isBatch && flow.openedFolder == nil }
    /// 이 판서 카드를 이미 복사 · 끌어다 놓았는지 → "남기고 다시 찍기"가 기본
    private var alreadyMoved: Bool {
        stickers.contains { $0.cardID.map(flow.movedCards.contains) ?? false }
    }
    private var retakeButton: some View {
        GrayButton(title: "다시 찍기") { confirmRetake = true }
    }

    /// 촬영 화면으로. 지우면 판서 · 카드를 서버에서 지워요 (실패해도 조용히 넘어가요)
    private func retake(deleting: Bool) {
        if deleting, let id = livePhoto?.id {
            Task { try? await SubjectCaptures.delete([id]) }
        }
        if router.stack.contains(.capture) {
            router.popTo(.capture)
        } else {
            // 앨범에서 골랐으면 메인 위에 촬영 화면을 새로 열어요
            router.popTo(.home)
            router.push(.capture)
        }
    }

    /// 사진 아래 삭제 버튼: 한 장이면 "이 판서 삭제", 여러 장이면 보고 있는 "사진 N 삭제"
    private var deleteLabel: String { isBatch ? "사진 \(photoTab + 1) 삭제" : "이 판서 삭제" }
    private var deleteTitle: String { isBatch ? "사진 \(photoTab + 1)을 삭제할까요?" : "판서를 삭제할까요?" }
    private var deleteButton: some View {
        DeleteButton(title: deleteLabel, busy: deleting) { confirmDelete = true }
    }

    /// 보고 있는 판서(사진) 한 장 지우기. 남은 사진이 없으면 이전 화면으로 (#93)
    private func deletePhoto() {
        guard let job = livePhoto else {
            // 샘플: 서버 없이 화면만 닫아요
            goBack()
            return
        }
        deleting = true
        Task {
            defer { deleting = false }
            do {
                try await SubjectCaptures.delete([job.id])
                if flow.results.count <= 1 {
                    goBack()
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        flow.results.removeAll { $0.id == job.id }
                        photoTab = min(photoTab, flow.results.count - 1)
                    }
                }
            } catch {
                deleteError = error.localizedDescription
            }
        }
    }

    /// 뒤로: 과목 폴더에서 열었으면 폴더로, 아니면 메인으로
    private func goBack() {
        if flow.openedFolder != nil { router.pop() } else { router.popTo(.home) }
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
            NavBar(backTitle: backTitle, title: "", onBack: { goBack() }) {
                originalButton
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(title).ds(34, .bold)
                Text(detail("카드를 굿노트로 끌어다 놓으세요")).ds(17, .regular, .dsSub)
            }
            .at(48, 96)

            // 여러 장이면 사진 탭이 들어가고 아래 내용이 한 줄 내려가요 (12-2)
            if isBatch {
                photoTabs.frame(width: 1098, alignment: .leading).at(48, 190)
            }
            let top: CGFloat = isBatch ? 252 : 200

            // 사진이 세로로 길면 아래 막대에 닿지 않게 줄여요
            let photoScale = min(1, (DS.height - top - 120) / (372 * (livePhoto?.aspect ?? 279.0 / 372.0)))
            MarkedPhoto(stickers: stickers, photo: livePhoto?.photo, aspect: livePhoto?.aspect ?? 279.0 / 372.0,
                        scale: photoScale, shown: shown)
                .id(photoTab).at(48, top)

            // 사진 아래 판서 삭제 (12-3 · 12-5)
            deleteButton
                .at(48, top + 372 * (livePhoto?.aspect ?? 279.0 / 372.0) * photoScale + 16)

            // 카드 (왼쪽 줄 1·3·5…, 오른쪽 줄 2·4·6…). 많으면 스크롤해요.
            ScrollView {
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) { ForEach(Array(stride(from: 0, to: stickers.count, by: 2)), id: \.self) { card($0) } }
                    VStack(spacing: 16) { ForEach(Array(stride(from: 1, to: stickers.count, by: 2)), id: \.self) { card($0) } }
                }
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .frame(width: 343 * 2 + 16, height: DS.height - top - 104, alignment: .top)
            .id(photoTab)
            .at(444, top)

            BottomBar(caption: savedText) {
                HStack(spacing: 12) {
                    if canRetake { retakeButton }
                    PrimaryButton(title: copyTitle, width: 280) { copyAll(thenGuide: true) }
                }
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
                Button { goBack() } label: {
                    HStack(spacing: 2) {
                        Image("chevron-back-24")
                        Text(backTitle).ds(17, .medium)
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
                        Text(title).ds(28, .bold)
                        Text(detail("카드를 길게 눌러 굿노트로 끌어다 놓으세요"))
                            .font(.system(size: 15))
                            .tracking(-0.15)
                            .foregroundStyle(Color.dsSub)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if isBatch { photoTabs }

                    MarkedPhoto(stickers: stickers, photo: livePhoto?.photo, aspect: livePhoto?.aspect ?? 279.0 / 372.0,
                                scale: photoWidth / 372, shown: shown)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, photoWidth < inner ? 12 : 0)
                        .background(Color.dsPanel)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    deleteButton

                    if columns == 2 {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 12) {
                                ForEach(Array(stride(from: 0, to: stickers.count, by: 2)), id: \.self) { card($0, width: cardWidth) }
                            }
                            VStack(spacing: 12) {
                                ForEach(Array(stride(from: 1, to: stickers.count, by: 2)), id: \.self) { card($0, width: cardWidth) }
                            }
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
                Text(savedText)
                    .font(.system(size: 15, weight: .medium))
                    .tracking(-0.15)
                    .foregroundStyle(Color.dsSub)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if canRetake { retakeButton }
                PrimaryButton(title: copyTitle, width: inner < 440 ? 150 : 200) {
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
        let sticker = stickers[index]
        return StickerCard(sticker: sticker, width: width,
                    onTap: { openCard(sticker) },
                    onCopy: { copy([sticker]) },
                    onDelete: { deletingCard = sticker })
            .id(sticker.cardID?.uuidString ?? "\(sticker.id)")
            .entrance(shown > 0, delay: 0.3 + 0.12 * Double(min(index, 8)), duration: 0.45, y: 20)
    }

    /// 카드 상세(17). 서버 카드면 그 카드를 고쳐요.
    private func openCard(_ sticker: Sticker) {
        CaptureFlow.shared.openedCard = sticker.cardID == nil ? nil : sticker
        router.push(.cardDetail)
    }

    /// 카드 한 장 지우기 (#99). 샘플은 지울 수 없어 그냥 닫아요.
    private func deleteCard(_ sticker: Sticker) {
        deletingCard = nil
        guard let id = sticker.cardID else { return }
        Task {
            do {
                try await CardAPI.delete(id)
                withAnimation(.easeInOut(duration: 0.2)) { flow.updateCard(removed: id) }
                await SubjectCaptures.unmoved.load(.unmoved)
            } catch {
                deleteError = error.localizedDescription
            }
        }
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
        Clipboard.copy(cards)
        CardAPI.markMovedQuietly(cards)
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
        // 여러 장이면 사진 순서대로 모든 카드를 이어 붙여요.
        let all = (0..<photoCount).flatMap { stickers(of: $0) }
        guard !all.isEmpty else { return }
        copy(all, thenGuide: thenGuide)
    }
}

// MARK: - 원본 사진 크게 보기

/// 결과 화면의 `원본 보기`. 찍은 판서 사진 전체를 검은 바탕에 크게 보여 줘요.
/// `image` 를 넘기면 그 사진을 보여 줘요 (시간표 확인의 원본 등).
struct OriginalPhotoView: View {
    var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Group {
                if let image { Image(uiImage: image).resizable() } else { Image("board-photo").resizable() }
            }
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
