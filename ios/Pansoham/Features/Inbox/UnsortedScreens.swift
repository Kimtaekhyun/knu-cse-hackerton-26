//
//  UnsortedScreens.swift
//  chalkdrop
//
//  19 미분류함 · 20 미분류함 · 과목으로 옮기기
//

import SwiftUI

struct UnsortedScreen: View {
    /// true 면 처음부터 "과목으로 옮기기" 창을 띄워요 (20 화면).
    var startsMoving = false

    @Environment(Router.self) private var router

    private struct Item: Identifiable, Equatable {
        let id: Int
        let date: String
        let shortDate: String
        let cards: Int
        let detail: String
        var x: CGFloat = 0, y: CGFloat = 0
        /// 서버 판서 (로그인했을 때)
        var captureID: UUID? = nil
        var photo: UIImage? = nil

        static func == (a: Item, b: Item) -> Bool { a.id == b.id && a.captureID == b.captureID }
    }

    private var store: SubjectCaptures { .unsorted }
    /// 서버 판서를 쓰는지 (로그인했을 때)
    private var isLive: Bool { AuthSession.shared.isLoggedIn }
    /// 화면에 보여 줄 목록: 로그인했으면 서버, 아니면 샘플
    private var items: [Item] {
        guard isLive else { return samples }
        return store.latest.enumerated().map { index, item in
            Item(id: index, date: item.dateText, shortDate: item.shortDateText, cards: item.capture.cardCount,
                 detail: item.cardSummary, captureID: item.id, photo: item.photo)
        }
    }

    @State private var samples: [Item] = [
        .init(id: 0, date: "11월 16일 (일) 21:14", shortDate: "11월 16일 21:14", cards: 4,
              detail: "카드 4개 · 스택의 연산, 큐의 연산 외 2개", x: -0.6333, y: -0.8443),
        .init(id: 1, date: "11월 15일 (토) 14:02", shortDate: "11월 15일 14:02", cards: 2,
              detail: "카드 2개 · 해시 함수, 충돌 처리", x: -0.0333, y: -0.1876),
        .init(id: 2, date: "11월 12일 (수) 19:40", shortDate: "11월 12일 19:40", cards: 6,
              detail: "카드 6개 · 프로세스 상태, 문맥 교환 외 4개", x: -0.3333, y: -0.5629),
    ]
    @State private var moving: Item?
    @State private var target = "자료구조"
    @State private var searching = false
    @State private var query = ""
    @State private var movingNow = false
    @State private var moveError: String?
    /// 지울 판서 (확인 창) · 삭제 중 · 실패 (#93)
    @State private var deletingItem: Item?
    @State private var deletingNow = false
    @State private var deleteError: String?
    private var shownItems: [Item] { items.filter { matches(query, [$0.date, $0.detail]) } }

    /// 옮길 과목: 로그인했으면 현재 학기 과목, 아니면 샘플
    private var subjects: [String] {
        isLive ? SemesterStore.shared.subjects.map(\.name) : SampleData.timetable.map(\.name)
    }
    private var firstSubject: String { subjects.first ?? "" }

    /// 위쪽 설명
    private var headerDetail: String {
        if isLive, !store.isLoaded(.unsorted) {
            if case .failed(let message) = store.state { return "불러오지 못했어요 · \(message)" }
            return "불러오는 중…"
        }
        return items.isEmpty ? "미분류 판서가 없어요 · 수업 시간 밖에서 찍으면 여기로 모여요"
            : "시간표 밖에서 찍은 판서 \(items.count)장 · 과목으로 옮겨 정리하세요"
    }

    /// 사진 미리보기
    @ViewBuilder
    private func thumb(_ item: Item, width: CGFloat = 168, height: CGFloat = 112) -> some View {
        if let photo = item.photo {
            PhotoThumb(photo: photo, width: width, height: height)
        } else if item.captureID != nil {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.05))
                .frame(width: width, height: height)
        } else {
            LessonThumb(x: item.x, y: item.y).scaledBox(168, 112, to: width)
        }
    }

    /// 판서를 누르면 그 판서의 결과 화면 (서버 판서일 때)
    private func open(_ item: Item) {
        guard let id = item.captureID, let job = store.items.first(where: { $0.id == id })?.job else { return }
        CaptureFlow.shared.open([job], folder: "미분류함")
        router.push(.result)
    }

    /// 서버에서 다시 받기 (로그인했을 때). 옮길 과목도 함께
    private func reload() async {
        guard isLive else { return }
        if SemesterStore.shared.subjects.isEmpty { await SemesterStore.shared.reload() }
        await store.load(.unsorted)
        if startsMoving, moving == nil, let first = items.first {
            target = firstSubject
            withAnimation(.easeOut(duration: 0.3)) { moving = first }
        }
    }

    /// 판서 지우기. 서버 판서면 `DELETE /captures/{id}` 뒤에 목록에서 빼요 (#93).
    private func delete(_ item: Item) {
        guard isLive, let id = item.captureID else {
            withAnimation(.easeInOut(duration: 0.25)) { samples.removeAll { $0.id == item.id } }
            deletingItem = nil
            return
        }
        deletingNow = true
        Task {
            defer { deletingNow = false; deletingItem = nil }
            do {
                try await SubjectCaptures.delete([id])
            } catch {
                deleteError = error.localizedDescription
            }
        }
    }

    /// 줄마다 "삭제" 버튼 (19-1)
    private func deleteButton(_ item: Item, width: CGFloat, height: CGFloat, size: CGFloat, radius: CGFloat) -> some View {
        Button { deletingItem = item } label: {
            Text(deletingNow && deletingItem == item ? "삭제 중…" : "삭제").ds(size, .bold, .dsSub)
                .frame(width: width, height: height)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.black.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(deletingNow)
    }

    /// 고른 과목으로 옮기기. 서버 판서면 `PATCH /captures/{id}` 뒤에 목록에서 빼요.
    private func move(_ item: Item) {
        guard isLive, let id = item.captureID else {
            withAnimation(.easeInOut(duration: 0.25)) {
                samples.removeAll { $0.id == item.id }
                moving = nil
            }
            return
        }
        guard let subject = SemesterStore.shared.subjects.first(where: { $0.name == target }) else { return }
        movingNow = true
        Task {
            defer { movingNow = false }
            do {
                _ = try await CaptureAPI.move(id, to: subject.id)
                withAnimation(.easeInOut(duration: 0.25)) {
                    store.remove(id)
                    moving = nil
                }
            } catch {
                moveError = error.localizedDescription
            }
        }
    }

    var body: some View {
        Adaptive { wide } narrow: { narrow($0) }
            .task { await reload() }
            .alert("판서를 삭제할까요?", isPresented: Binding(get: { deletingItem != nil && !deletingNow },
                                                         set: { if !$0, !deletingNow { deletingItem = nil } })) {
                Button("취소", role: .cancel) { deletingItem = nil }
                Button("삭제", role: .destructive) { if let item = deletingItem { delete(item) } }
            } message: {
                Text("카드 \(deletingItem?.cards ?? 0)개도 함께 지워지고 되돌릴 수 없어요.")
            }
            .deleteFailedAlert($deleteError)
            .alert("옮기지 못했어요", isPresented: Binding(get: { moveError != nil }, set: { if !$0 { moveError = nil } })) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(moveError ?? "")
            }
    }

    private var wide: some View {
        DesignCanvas {
            FolderNavBar(onBack: { router.popTo(.home) }, searching: $searching, query: $query) {
                FolderMenu(router: router)
            }
            SubjectHeader(name: "미분류함", detail: headerDetail)

            // 미분류 목록. 판서가 많으면 스크롤돼요 (과목 폴더 15 와 같은 방식)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if shownItems.isEmpty && !items.isEmpty { NoSearchResult(query: query) }
                    ForEach(shownItems) { item in
                        HStack(spacing: 20) {
                            Button { open(item) } label: {
                                HStack(spacing: 20) {
                                    thumb(item)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(item.date).ds(20, .bold)
                                        Text(item.detail).ds(15, .regular, .dsSub)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            deleteButton(item, width: 88, height: 48, size: 16, radius: 14)
                            Button {
                                target = firstSubject
                                withAnimation(.easeOut(duration: 0.3)) { moving = item }
                            } label: {
                                Text("과목으로 옮기기").ds(16, .bold)
                                    .frame(width: 180, height: 48)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.black.opacity(0.12), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 20)
                        .frame(width: 1098)
                        .overlay(alignment: .bottom) {
                            if item != items.last { Rectangle().fill(Color.dsLine).frame(height: 1) }
                        }
                    }
                }
                .padding(.bottom, 40)
            }
            .frame(width: 1098, height: DS.height - 196, alignment: .top)
            .at(48, 196)

            if let moving {
                // 어둡게 깔기
                Color.black.opacity(0.4)
                    .frame(width: DS.width, height: DS.height)
                    .onTapGesture { close() }
                    .transition(.opacity)

                moveDialog(moving)
                    .at(357, 192)
                    .transition(.opacity.combined(with: .offset(y: 40)).animation(.easeOut(duration: 0.4).delay(0.05)))
            }
        }
        .onAppear {
            if startsMoving, !isLive { withAnimation(.easeOut(duration: 0.3)) { moving = items.first } }
        }
    }

    /// 과목 선택 창
    private func moveDialog(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("어느 과목으로 옮길까요?").ds(22, .bold)
            Color.clear.frame(width: 1, height: 6)
            Text("\(item.shortDate) · 카드 \(item.cards)개").ds(15, .regular, .dsSub)
            Color.clear.frame(width: 1, height: 16)

            if subjects.isEmpty {
                Text("옮길 과목이 없어요. 시간표를 먼저 등록해 주세요.").ds(15, .regular, .dsSub)
                    .padding(.vertical, 14)
            }
            ForEach(subjects, id: \.self) { subject in
                let on = target == subject
                Button { target = subject } label: {
                    HStack {
                        Text(subject).ds(17, on ? .bold : .medium)
                        Spacer()
                        Image(on ? "radio-on-24" : "radio-off-24")
                    }
                    .padding(.vertical, 14)
                    .frame(width: 424)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Color.clear.frame(width: 1, height: 16)
            HStack(spacing: 10) {
                Button { close() } label: {
                    Text("취소").ds(17, .bold)
                        .frame(width: 120, height: 56)
                        .background(Color.black.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                PrimaryButton(title: movingNow ? "옮기는 중…" : "\(target)로 옮기기", width: 294,
                              enabled: !movingNow && subjects.contains(target)) {
                    move(item)
                }
            }
        }
        .padding(.top, 28)
        .padding(.bottom, 24)
        .padding(.horizontal, 28)
        .frame(width: 480, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.2)) { moving = nil }
    }
}

// MARK: - 좁은 화면 (스플릿 뷰)

extension UnsortedScreen {
    func narrow(_ size: CGSize) -> some View {
        NarrowPage(backTitle: "chalkdrop", onBack: { router.popTo(.home) },
                   title: "미분류함",
                   detail: headerDetail,
                   trailing: {
            FolderActions(onSearch: { searching = true }) { FolderMenu(router: router) }
        }, content: {
            if searching { FolderSearchField(text: $query) { searching = false; query = "" } }
            VStack(alignment: .leading, spacing: 0) {
                if shownItems.isEmpty && !items.isEmpty { NoSearchResult(query: query) }
                ForEach(shownItems) { item in
                    HStack(alignment: .top, spacing: 14) {
                        Button { open(item) } label: { thumb(item, width: 120, height: 80) }
                            .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.date).dsWrap(17, .bold)
                            Text(item.detail).dsWrap(14, .regular, .dsSub)
                            HStack(spacing: 8) {
                            deleteButton(item, width: 64, height: 38, size: 14, radius: 12)
                            Button {
                                target = firstSubject
                                withAnimation(.easeOut(duration: 0.3)) { moving = item }
                            } label: {
                                Text("과목으로 옮기기").ds(14, .bold)
                                    .padding(.horizontal, 14)
                                    .frame(height: 38)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.black.opacity(0.12), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            }
                            .padding(.top, 4)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 18)
                    .overlay(alignment: .bottom) {
                        if item != items.last { Rectangle().fill(Color.dsLine).frame(height: 1) }
                    }
                }
            }
            .padding(.bottom, 24)
        }, bottom: { EmptyView() })
        .overlay {
            if let moving {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture { close() }
                    moveDialog(moving)
                        .scaleEffect(min(1, (size.width - 32) / 480))
                        .transition(.opacity.combined(with: .offset(y: 40)).animation(.easeOut(duration: 0.4).delay(0.05)))
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            if startsMoving, !isLive { withAnimation(.easeOut(duration: 0.3)) { moving = items.first } }
        }
    }
}
