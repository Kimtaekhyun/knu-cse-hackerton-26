//
//  SubjectScreens.swift
//  chalkdrop
//
//  15 과목 상세 · 수업별 / 16 과목 상세 · 카드 모아 보기
//

import SwiftUI

// MARK: - 과목 화면 공통 (위 막대 + 제목 + 보기 전환)

/// 뒤로 · 검색 · 더 보기가 있는 위 막대. 검색 중이면 검색창으로 바뀌어요.
struct FolderNavBar<MenuItems: View>: View {
    var backTitle: String
    var onBack: () -> Void
    @Binding var searching: Bool
    @Binding var query: String
    var canSearch: Bool
    let menu: MenuItems

    init(backTitle: String = "chalkdrop", onBack: @escaping () -> Void = {},
         searching: Binding<Bool> = .constant(false), query: Binding<String> = .constant(""),
         canSearch: Bool = true, @ViewBuilder menu: () -> MenuItems) {
        self.backTitle = backTitle
        self.onBack = onBack
        self._searching = searching
        self._query = query
        self.canSearch = canSearch
        self.menu = menu()
    }

    var body: some View {
        if searching {
            FolderSearchField(text: $query) { searching = false; query = "" }
                .padding(.horizontal, 48)
                .frame(width: DS.width, height: 56)
                .background(Color.white)
                .at(0, 24)
        } else {
            NavBar(backTitle: backTitle, title: "", onBack: onBack) {
                FolderActions(spacing: 24, canSearch: canSearch, onSearch: { searching = true }) { menu }
            }
        }
    }
}

/// 위 막대 오른쪽의 검색 · 더 보기 버튼
struct FolderActions<MenuItems: View>: View {
    var spacing: CGFloat = 20
    var canSearch = true
    var onSearch: () -> Void = {}
    @ViewBuilder var menu: MenuItems

    var body: some View {
        HStack(spacing: spacing) {
            if canSearch {
                Button(action: onSearch) { Image("search-24") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("검색")
            }
            Menu { menu } label: { Image("more-24") }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .accessibilityLabel("더 보기")
        }
    }
}

/// 검색창 (돋보기 · 입력 · 지우기 · 취소)
struct FolderSearchField: View {
    @Binding var text: String
    var onCancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image("search-24")
                TextField("검색", text: $text)
                    .font(.system(size: 17))
                    .focused($focused)
                    .submitLabel(.search)
                if !text.isEmpty {
                    Button { text = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Color.dsSub)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Color.black.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Button(action: onCancel) { Text("취소").ds(17, .medium) }
                .buttonStyle(.plain)
        }
        .onAppear { focused = true }
    }
}

/// 검색 결과가 없을 때
struct NoSearchResult: View {
    let query: String
    var body: some View {
        Text("‘\(query)’ 검색 결과가 없어요").ds(17, .medium, .dsSub)
            .padding(.vertical, 24)
    }
}

/// 과목 · 미분류함 더 보기 메뉴
struct FolderMenu: View {
    let router: Router
    /// 보기 전환 (예: ("카드 모아 보기", .subjectCards)). 없으면 빼요.
    var switchTo: (title: String, screen: Screen)? = nil

    var body: some View {
        Button { router.push(.capture) } label: { Label("판서 찍기", systemImage: "camera") }
        if let switchTo {
            Button { router.replace(switchTo.screen, direction: .fade) } label: {
                Label(switchTo.title, systemImage: "rectangle.grid.1x2")
            }
        }
        Button { router.push(.allSemesters) } label: { Label("전체 학기", systemImage: "folder") }
    }
}

/// 검색어가 글자들 중 하나에 들어 있는지 (빈 검색어면 모두 통과)
func matches(_ query: String, _ fields: [String]) -> Bool {
    let q = query.trimmingCharacters(in: .whitespaces)
    return q.isEmpty || fields.contains { $0.localizedCaseInsensitiveContains(q) }
}

/// 과목 이름 · 설명 · (수업별 | 카드 모아 보기)
struct SubjectHeader: View {
    let name: String
    let detail: String
    /// 0 수업별, 1 카드 모아 보기. nil 이면 전환 단추를 숨겨요.
    var mode: Int? = nil
    var onMode: (Int) -> Void = { _ in }

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(name).ds(34, .bold)
                Text(detail).ds(17, .regular, .dsSub)
            }
            Spacer()
            if let mode {
                HStack(spacing: 2) {
                    chip("수업별", on: mode == 0) { onMode(0) }
                    chip("카드 모아 보기", on: mode == 1) { onMode(1) }
                }
                .padding(4)
                .background(Color.black.opacity(0.05))
                .clipShape(Capsule())
            }
        }
        .frame(width: 1098)
        .at(48, 92)
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).ds(15, on ? .bold : .medium, on ? .black : .dsSub)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(on ? Color.white : Color.clear)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(on ? 0.12 : 0), radius: 1.5, x: 0, y: 1)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// 오른쪽 아래 촬영 버튼
struct CaptureFAB: View {
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Image("camera-30")
                .frame(width: 72, height: 72)
                .background(Color.black)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.22), radius: 14, x: 0, y: 10)
        }
        .buttonStyle(.plain)
        .zoomSource()
        .at(1082, 722)
    }
}

/// 판서 사진 미리보기 (168 × 112, 사진 일부를 잘라 보여 줘요)
struct LessonThumb: View {
    let x: CGFloat
    let y: CGFloat

    var body: some View {
        BoardPhoto(width: 168, height: 112, scaleX: 1.6667, scaleY: 1.8762, x: x, y: y, radius: 14)
    }
}

/// 서버 판서 사진 미리보기 (가운데를 채워 잘라요)
struct PhotoThumb: View {
    let photo: UIImage
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Image(uiImage: photo).resizable().scaledToFill()
            .frame(width: width, height: height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// 과목 판서를 못 불러왔을 때
struct FolderLoadFailed: View {
    let message: String
    var retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("판서를 불러오지 못했어요").ds(20, .bold)
            Text(message).ds(15, .regular, .dsSub)
            GrayButton(title: "다시 시도", action: retry)
        }
    }
}

/// 과목 제목 아래 설명. 서버 판서를 다 받았으면 "시간 · 판서 N장 · 카드 M개"
@MainActor
func folderDetailText(_ router: Router, sample: String) -> String {
    let store = SubjectCaptures.shared
    guard let subject = router.subject, store.isLive(subject), store.isLoaded(subject.id) else {
        return router.subjectDetail(sample)
    }
    return "\(subject.timeText) · 판서 \(store.items.count)장 · 카드 \(store.cardCount)개"
}

/// 회색 알약 모양 꼬리표
struct TagChip: View {
    let title: String
    var plain = false

    var body: some View {
        Text(title).ds(13, .medium, plain ? .dsSub : .black)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(plain ? Color.clear : Color.black.opacity(0.05))
            .clipShape(Capsule())
    }
}

// MARK: - 15 과목 상세 · 수업별

struct SubjectLessonsScreen: View {
    @Environment(Router.self) private var router
    private func folderDetail(_ sample: String) -> String { folderDetailText(router, sample: sample) }

    private struct Lesson: Identifiable {
        let id: Int
        let date: String
        let summary: String
        let today: Bool
        let thumbs: [(CGFloat, CGFloat)]
        let tags: [String]
        var more: String? = nil
        /// 서버 판서 사진 (있으면 샘플 미리보기 대신)
        var photos: [UIImage] = []
        /// 정리 중 · 실패 안내
        var note: String? = nil
        /// 결과 화면에 넘길 판서
        var jobs: [CaptureFlow.Job] = []
        /// 이 수업의 서버 판서 id (삭제용)
        var captureIDs: [UUID] = []

        /// 요약("사진 2장 · 카드 5개")의 숫자
        var counts: (photos: Int, cards: Int) {
            let numbers = summary.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            return (numbers.first ?? 0, numbers.dropFirst().first ?? 0)
        }
    }

    /// 지울 수업 (확인 창) · 삭제 중 · 실패 · 지운 샘플 (#93)
    @State private var deletingLesson: Lesson?
    @State private var deletingNow = false
    @State private var deleteError: String?
    @State private var hiddenSamples: Set<Int> = []

    @State private var searching = false
    @State private var query = ""
    private var store: SubjectCaptures { .shared }
    /// 서버 판서를 보여 주는지 (로그인 + 실제 과목)
    private var isLive: Bool { store.isLive(router.subject) }
    private var allLessons: [Lesson] {
        guard isLive else { return lessons.filter { !hiddenSamples.contains($0.id) } }
        return store.lessons.enumerated().map { index, lesson in
            let tags = lesson.tags
            return Lesson(id: index, date: lesson.title, summary: lesson.summary, today: lesson.isToday,
                          thumbs: [], tags: tags.shown, more: tags.more,
                          photos: lesson.items.compactMap(\.photo), note: lesson.statusNote,
                          jobs: lesson.items.compactMap(\.job), captureIDs: lesson.items.map(\.id))
        }
    }
    private var shownLessons: [Lesson] { allLessons.filter { matches(query, [$0.date] + $0.tags) } }

    private let lessons: [Lesson] = [
        .init(id: 0, date: "11월 17일 (월)", summary: "사진 2장 · 카드 5개", today: true,
              thumbs: [(-0.3333, -0.5629), (-0.0333, -0.8443)],
              tags: ["스택의 연산", "분할 정복 점화식", "주의", "결론", "예시 코드"]),
        .init(id: 1, date: "11월 10일 (월)", summary: "사진 3장 · 카드 8개", today: false,
              thumbs: [(-0.6333, -0.1501), (-0.6333, -0.8443), (-0.0333, -0.1876)],
              tags: ["큐의 연산", "원형 큐 인덱스", "덱", "큐 vs 스택", "오버플로 조건", "예시 코드"], more: "+2"),
        .init(id: 2, date: "11월 3일 (월)", summary: "사진 4장 · 카드 4개", today: false,
              thumbs: [(-0.3333, -0.5629), (-0.0333, -0.8443), (-0.6333, -0.1501), (-0.6333, -0.8443)],
              tags: ["연결 리스트", "노드 삽입", "노드 삭제", "이중 연결 리스트"]),
    ]

    var body: some View {
        lessonDeleteAlert(Adaptive { wide } narrow: { narrow($0) })
    }

    private var wide: some View {
        DesignCanvas {
            FolderNavBar(onBack: { router.popTo(.home) }, searching: $searching, query: $query) {
                FolderMenu(router: router, switchTo: ("카드 모아 보기", .subjectCards))
            }
            SubjectHeader(name: router.subjectName("자료구조"), detail: folderDetail("월 10:30–12:00 · 판서 12장 · 카드 34개"), mode: 0) { mode in
                if mode == 1 { router.replace(.subjectCards, direction: .fade) }
            }

            // 수업 목록
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if let status = liveStatus { status.frame(width: 1098).padding(.top, 120) }
                    else if shownLessons.isEmpty { NoSearchResult(query: query) }
                    ForEach(shownLessons) { lesson in
                        Button { open(lesson) } label: { row(lesson) }
                            .buttonStyle(.plain)
                            .contextMenu { deleteMenu(lesson) }
                    }
                }
                .padding(.bottom, 120)
            }
            .frame(width: 1098, height: 638, alignment: .top)
            .at(48, 196)

            // 아래로 갈수록 흐려지기
            LinearGradient(colors: [.white.opacity(0), .white], startPoint: .top, endPoint: .bottom)
                .frame(width: DS.width, height: 80)
                .allowsHitTesting(false)
                .at(0, 754)

            CaptureFAB { router.push(.capture) }
        }
        .task { await reload() }
        
    }

    /// 수업 줄 길게 누르기 메뉴 (15-1)
    @ViewBuilder
    private func deleteMenu(_ lesson: Lesson) -> some View {
        Button(role: .destructive) { deletingLesson = lesson } label: {
            Label("이 날 판서 모두 삭제", systemImage: "trash")
        }
    }

    /// 수업 지우기 확인 창 (15-2)
    func lessonDeleteAlert<V: View>(_ view: V) -> some View {
        let lesson = deletingLesson
        let counts = lesson?.counts ?? (photos: 0, cards: 0)
        return view
            .alert("\(lesson?.date ?? "") 판서 \(counts.photos)장을 삭제할까요?",
                   isPresented: Binding(get: { lesson != nil && !deletingNow },
                                        set: { if !$0, !deletingNow { deletingLesson = nil } })) {
                Button("취소", role: .cancel) { deletingLesson = nil }
                Button("삭제", role: .destructive) { if let lesson { delete(lesson) } }
            } message: {
                Text("카드 \(counts.cards)개도 함께 지워지고 되돌릴 수 없어요.")
            }
            .deleteFailedAlert($deleteError)
    }

    /// 그날 판서 모두 지우기. 다 지워지면 빈 폴더(18)로 바꿔요 (#93)
    private func delete(_ lesson: Lesson) {
        guard isLive else {
            withAnimation(.easeInOut(duration: 0.25)) { _ = hiddenSamples.insert(lesson.id) }
            deletingLesson = nil
            return
        }
        deletingNow = true
        Task {
            defer { deletingNow = false; deletingLesson = nil }
            do {
                try await SubjectCaptures.delete(lesson.captureIDs)
            } catch {
                deleteError = error.localizedDescription
            }
            await reload()
        }
    }

    /// 판서 · 수업을 누르면: 서버 판서면 그 판서들의 결과 화면, 샘플이면 샘플 결과
    private func open(_ lesson: Lesson) {
        if isLive {
            guard !lesson.jobs.isEmpty else { return }
            CaptureFlow.shared.open(lesson.jobs, folder: router.subjectName(""))
        }
        router.push(.result)
    }

    /// 서버 판서 불러오기. 하나도 없으면 빈 폴더 화면(18)으로 바꿔요.
    private func reload() async {
        guard isLive, let id = router.subject?.id else { return }
        await store.load(id)
        if store.isLoaded(id), store.items.isEmpty { router.replace(.subjectEmpty, direction: .fade) }
    }

    /// 불러오는 중 · 실패 (서버 판서일 때만)
    private var liveStatus: AnyView? {
        guard isLive, !store.isLoaded(router.subject?.id) else { return nil }
        if case .failed(let message) = store.state {
            return AnyView(FolderLoadFailed(message: message) { Task { await reload() } })
        }
        return store.items.isEmpty ? AnyView(ProgressView().controlSize(.large)) : nil
    }

    private func row(_ lesson: Lesson) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 10) {
                    Text(lesson.date).ds(20, .bold)
                    if lesson.today {
                        Text("오늘").ds(12, .bold, .white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 3)
                            .background(Color.dsBlue)
                            .clipShape(Capsule())
                    }
                }
                Spacer()
                HStack(spacing: 2) {
                    if let note = lesson.note { Text(note).ds(15, .medium, .dsBlue).padding(.trailing, 8) }
                    Text(lesson.summary).ds(15, .medium, .dsSub)
                    Image("chevron-right-20")
                }
            }
            HStack(spacing: 12) {
                ForEach(Array(lesson.thumbs.enumerated()), id: \.offset) { _, thumb in
                    LessonThumb(x: thumb.0, y: thumb.1)
                }
                ForEach(Array(lesson.photos.enumerated()), id: \.offset) { _, photo in
                    PhotoThumb(photo: photo, width: 168, height: 112)
                }
            }
            HStack(spacing: 8) {
                ForEach(lesson.tags, id: \.self) { TagChip(title: $0) }
                if let more = lesson.more { TagChip(title: more, plain: true) }
            }
        }
        .padding(.vertical, 22)
        .frame(width: 1098, alignment: .leading)
        .overlay(alignment: .bottom) {
            if lesson.id < allLessons.count - 1 {
                Rectangle().fill(Color.dsLine).frame(height: 1)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - 16 과목 상세 · 카드 모아 보기

struct SubjectCardsScreen: View {
    @Environment(Router.self) private var router
    private func folderDetail(_ sample: String) -> String { folderDetailText(router, sample: sample) }
    @State private var filter = "전체"
    @State private var selection: Set<Int> = [1, 2, 3]
    @State private var copiedCount: Int?     // 좁은 화면에서 방금 복사한 카드 수
    @State private var searching = false
    @State private var query = ""

    private var store: SubjectCaptures { .shared }
    /// 서버 판서를 보여 주는지 (로그인 + 실제 과목)
    private var isLive: Bool { store.isLive(router.subject) }
    /// 서버 카드와 그 카드의 판서
    private var liveCards: [(sticker: Sticker, item: SubjectCaptures.Item)] { isLive ? store.stickers : [] }
    private var all: [Sticker] { isLive ? liveCards.map(\.sticker) : SampleData.subjectStickers }
    private var filters: [(name: String, count: Int)] {
        guard isLive else { return [("전체", 34), ("수식", 9), ("코드", 6), ("텍스트", 19)] }
        return [("전체", all.count)] + ["수식", "코드", "텍스트"].map { kind in (kind, all.filter { $0.kind == kind }.count) }
    }

    private var visible: [Sticker] {
        (filter == "전체" ? all : all.filter { $0.kind == filter })
            .filter { matches(query, [$0.title, $0.text]) }
    }

    /// 카드를 세 줄에 차례로 나눠 담아요 (1·4·7 / 2·5·8 / 3·6·9).
    private var columns: [[Sticker]] {
        var result: [[Sticker]] = [[], [], []]
        for (index, sticker) in visible.enumerated() { result[index % 3].append(sticker) }
        return result
    }

    var body: some View {
        Adaptive { wide } narrow: { narrow($0) }
    }

    private var wide: some View {
        DesignCanvas {
            FolderNavBar(onBack: { router.popTo(.home) }, searching: $searching, query: $query) {
                FolderMenu(router: router, switchTo: ("수업별로 보기", .subjectLessons))
            }
            SubjectHeader(name: router.subjectName("자료구조"), detail: folderDetail("월 10:30–12:00 · 판서 12장 · 카드 34개"), mode: 1) { mode in
                if mode == 0 { router.replace(.subjectLessons, direction: .fade) }
            }

            if let status = liveStatus { status.frame(width: DS.width).at(0, 380) }

            // 필터
            HStack(spacing: 8) {
                ForEach(filters, id: \.name) { item in
                    let on = filter == item.name
                    Button { withAnimation(.easeInOut(duration: 0.15)) { filter = item.name } } label: {
                        Text("\(item.name) \(item.count)").ds(14, .bold, on ? .white : .black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(on ? Color.black : Color.black.opacity(0.05))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .at(48, 196)

            // 카드 격자
            ScrollView(.vertical, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                        VStack(spacing: 16) {
                            ForEach(column) { sticker in
                                StickerCard(sticker: sticker, width: 355,
                                            selected: selection.contains(sticker.id),
                                            onTap: { open(sticker) },
                                            onCopy: { toggle(sticker.id) },
                                            onSelect: { toggle(sticker.id) })
                            }
                        }
                        .frame(width: 355, alignment: .top)
                    }
                }
                .padding(1)
                .padding(.bottom, 24)
            }
            .frame(width: 1100, height: 478, alignment: .topLeading)
            .at(47, 251)

            // 선택 막대
            HStack {
                HStack(spacing: 20) {
                    Text("\(selection.count)개 선택됨").ds(17, .bold)
                    Button { selection = Set(visible.map(\.id)) } label: {
                        Text("모두 선택").ds(17, .medium, .dsSub)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                HStack(spacing: 12) {
                    Button { selection = [] } label: {
                        Text("취소").ds(17, .bold)
                            .padding(.horizontal, 24)
                            .frame(height: 56)
                            .background(Color.black.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    PrimaryButton(title: "\(selection.count)개 복사", enabled: !selection.isEmpty) {
                        Clipboard.copy(selectedCards)
                        CardAPI.markMovedQuietly(selectedCards)
                        router.push(.splitView)
                    }
                }
            }
            .padding(.horizontal, 48)
            .frame(width: DS.width, height: 104)
            .background(Color.white)
            .overlay(alignment: .top) { Rectangle().fill(Color.dsLine).frame(height: 1) }
            .at(0, 730)
        }
        .task { await reload() }
    }

    /// 카드를 누르면: 서버 카드면 그 판서의 결과 화면, 샘플이면 카드 상세
    private func open(_ sticker: Sticker) {
        // 서버 카드면 그 카드를 카드 상세(17)에서 고쳐요 (#99)
        CaptureFlow.shared.openedCard = isLive ? sticker : nil
        router.push(.cardDetail)
    }

    private func reload() async {
        guard isLive, let id = router.subject?.id else { return }
        if !store.isLoaded(id) { selection = [] }
        await store.load(id)
        if store.isLoaded(id), store.items.isEmpty { router.replace(.subjectEmpty, direction: .fade) }
    }

    /// 불러오는 중 · 실패 (서버 판서일 때만)
    private var liveStatus: AnyView? {
        guard isLive, !store.isLoaded(router.subject?.id) else { return nil }
        if case .failed(let message) = store.state {
            return AnyView(FolderLoadFailed(message: message) { Task { await reload() } })
        }
        return store.items.isEmpty ? AnyView(ProgressView().controlSize(.large)) : nil
    }

    private func toggle(_ id: Int) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }
}

// MARK: - 18 과목 상세 · 빈 상태

struct SubjectEmptyScreen: View {
    @Environment(Router.self) private var router

    var body: some View {
        Adaptive { wide } narrow: { narrow($0) }
    }

    private var wide: some View {
        DesignCanvas {
            FolderNavBar(onBack: { router.pop() }, canSearch: false) { FolderMenu(router: router) }
            SubjectHeader(name: router.subjectName("운영체제"), detail: router.subjectDetail("금 10:30–12:00 · 판서 0장"), mode: 0)

            VStack(spacing: 0) {
                Image("folder-empty-72")
                Color.clear.frame(width: 1, height: 20)
                Text("아직 찍은 판서가 없어요").ds(22, .bold)
                Color.clear.frame(width: 1, height: 8)
                Text(router.subjectHint("금요일 10:30 수업 시간에 찍으면 여기로 모여요")).ds(17, .regular, .dsSub)
                Color.clear.frame(width: 1, height: 28)
                PrimaryButton(title: "판서 찍기") { router.push(.capture) }.zoomSource()
            }
            .frame(width: DS.width)
            .at(0, 330)
        }
        .task { await reload() }
    }

    /// 판서 수는 0 이었지만 그사이 찍은 판서가 있으면 수업별(15)로 바꿔요.
    func reload() async {
        let store = SubjectCaptures.shared
        guard store.isLive(router.subject), let id = router.subject?.id else { return }
        await store.load(id)
        if store.isLoaded(id), !store.items.isEmpty { router.replace(.subjectLessons, direction: .fade) }
    }
}

// MARK: - 좁은 화면 (스플릿 뷰)


extension SubjectLessonsScreen {
    func narrow(_ size: CGSize) -> some View {
        NarrowPage(backTitle: "chalkdrop", onBack: { router.popTo(.home) },
                   title: router.subjectName("자료구조"), detail: folderDetail("월 10:30–12:00 · 판서 12장 · 카드 34개"),
                   trailing: {
            FolderActions(onSearch: { searching = true }) {
                FolderMenu(router: router, switchTo: ("카드 모아 보기", .subjectCards))
            }
        }, content: {
            if searching { FolderSearchField(text: $query) { searching = false; query = "" } }
            NarrowModeToggle(mode: 0) { mode in
                if mode == 1 { router.replace(.subjectCards, direction: .fade) }
            }

            VStack(alignment: .leading, spacing: 0) {
                if let status = liveStatus { status.frame(maxWidth: .infinity).padding(.top, 80) }
                else if shownLessons.isEmpty { NoSearchResult(query: query) }
                ForEach(shownLessons) { lesson in
                    Button { open(lesson) } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                HStack(spacing: 8) {
                                    Text(lesson.date).ds(18, .bold)
                                    if lesson.today {
                                        Text("오늘").ds(12, .bold, .white)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 3)
                                            .background(Color.dsBlue)
                                            .clipShape(Capsule())
                                    }
                                }
                                Spacer(minLength: 0)
                                Image("chevron-right-20")
                            }
                            HStack(spacing: 8) {
                                Text(lesson.summary).ds(14, .medium, .dsSub)
                                if let note = lesson.note { Text(note).ds(14, .medium, .dsBlue) }
                            }
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(Array(lesson.thumbs.enumerated()), id: \.offset) { _, thumb in
                                        LessonThumb(x: thumb.0, y: thumb.1).scaledBox(168, 112, to: 132)
                                    }
                                    ForEach(Array(lesson.photos.enumerated()), id: \.offset) { _, photo in
                                        PhotoThumb(photo: photo, width: 132, height: 88)
                                    }
                                }
                            }
                            Flow(spacing: 8) {
                                ForEach(lesson.tags, id: \.self) { TagChip(title: $0) }
                                if let more = lesson.more { TagChip(title: more, plain: true) }
                            }
                        }
                        .padding(.vertical, 18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .bottom) {
                            if lesson.id < allLessons.count - 1 { Rectangle().fill(Color.dsLine).frame(height: 1) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu { deleteMenu(lesson) }
                }
            }
            .padding(.bottom, 80)
        }, bottom: { EmptyView() })
        .overlay(alignment: .bottomTrailing) {
            NarrowFAB { router.push(.capture) }.padding(20)
        }
        .task { await reload() }
        
    }
}

extension SubjectCardsScreen {
    func narrow(_ size: CGSize) -> some View {
        let inner = size.width - 40
        let columnCount = inner >= 520 ? 2 : 1
        let cardWidth = (inner - 12 * CGFloat(columnCount - 1)) / CGFloat(columnCount)
        return NarrowPage(backTitle: "chalkdrop", onBack: { router.popTo(.home) },
                          title: router.subjectName("자료구조"), detail: folderDetail("월 10:30–12:00 · 판서 12장 · 카드 34개"),
                          trailing: {
            FolderActions(onSearch: { searching = true }) {
                FolderMenu(router: router, switchTo: ("수업별로 보기", .subjectLessons))
            }
        }, content: {
            if searching { FolderSearchField(text: $query) { searching = false; query = "" } }
            NarrowModeToggle(mode: 1) { mode in
                if mode == 0 { router.replace(.subjectLessons, direction: .fade) }
            }
            if let status = liveStatus { status.frame(maxWidth: .infinity).padding(.top, 80) }

            Flow(spacing: 8) {
                ForEach(filters, id: \.name) { item in
                    let on = filter == item.name
                    Button { withAnimation(.easeInOut(duration: 0.15)) { filter = item.name } } label: {
                        Text("\(item.name) \(item.count)").ds(14, .bold, on ? .white : .black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(on ? Color.black : Color.black.opacity(0.05))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            // 카드 (너비에 따라 한 줄 또는 두 줄)
            HStack(alignment: .top, spacing: 12) {
                ForEach(0..<columnCount, id: \.self) { column in
                    VStack(spacing: 12) {
                        ForEach(visible.indices.filter { $0 % columnCount == column }, id: \.self) { index in
                            let sticker = visible[index]
                            StickerCard(sticker: sticker, width: cardWidth,
                                        selected: selection.contains(sticker.id),
                                        onTap: { open(sticker) },
                                        onCopy: { toggle(sticker.id) },
                                        onSelect: { toggle(sticker.id) })
                        }
                    }
                    .frame(width: cardWidth, alignment: .top)
                }
            }
        }, bottom: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(selection.count)개 선택됨").ds(15, .bold)
                    Button { selection = Set(visible.map(\.id)) } label: {
                        Text("모두 선택").ds(14, .medium, .dsSub)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
                GrayButton(title: "취소") { selection = [] }
                PrimaryButton(title: "\(selection.count)개 복사", width: inner < 440 ? 120 : 180, enabled: !selection.isEmpty) {
                    copySelection()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.white)
            .overlay(alignment: .top) { Rectangle().fill(Color.dsLine).frame(height: 1) }
            .overlay(alignment: .top) {
                if let copiedCount {
                    HStack(spacing: 10) {
                        Image("check-circle-24")
                        Text("카드 \(copiedCount)개를 복사했어요").ds(15, .bold, .white)
                    }
                    .padding(.leading, 18)
                    .padding(.trailing, 24)
                    .padding(.vertical, 14)
                    .background(Color.black)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 16, x: 0, y: 12)
                    .offset(y: -68)
                    .transition(.opacity.combined(with: .offset(y: 40)))
                }
            }
        })
        .task { await reload() }
    }

    /// 고른 카드 (화면 순서)
    var selectedCards: [Sticker] {
        all.filter { selection.contains($0.id) }
    }

    /// 고른 카드의 글자를 클립보드에 넣고 알림을 잠깐 띄워요.
    private func copySelection() {
        Clipboard.copy(selectedCards)
        CardAPI.markMovedQuietly(selectedCards)
        withAnimation(.easeOut(duration: 0.5).delay(0.1)) { copiedCount = selection.count }
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(.easeIn(duration: 0.25)) { copiedCount = nil }
        }
    }
}

extension SubjectEmptyScreen {
    func narrow(_ size: CGSize) -> some View {
        NarrowPage(backTitle: "chalkdrop", onBack: { router.pop() },
                   title: router.subjectName("운영체제"), detail: router.subjectDetail("금 10:30–12:00 · 판서 0장"),
                   trailing: { FolderActions(canSearch: false) { FolderMenu(router: router) } }, content: {
            NarrowModeToggle(mode: 0)

            VStack(spacing: 0) {
                Image("folder-empty-72")
                Color.clear.frame(width: 1, height: 20)
                Text("아직 찍은 판서가 없어요").ds(22, .bold)
                Color.clear.frame(width: 1, height: 8)
                Text(router.subjectHint("금요일 10:30 수업 시간에 찍으면 여기로 모여요"))
                    .dsWrap(15, .regular, .dsSub)
                    .multilineTextAlignment(.center)
                Color.clear.frame(width: 1, height: 24)
                PrimaryButton(title: "판서 찍기") { router.push(.capture) }.zoomSource()
            }
            .frame(maxWidth: .infinity)
            .padding(.top, size.height * 0.14)
        }, bottom: { EmptyView() })
        .task { await reload() }
    }
}

// MARK: - 과목 제목 (메인에서 연 과목, 없으면 샘플)

extension Router {
    func subjectName(_ sample: String) -> String { subject?.name ?? sample }

    func subjectDetail(_ sample: String) -> String {
        subject.map { "\($0.timeText) · 판서 \($0.captureCount)장" } ?? sample
    }

    /// 빈 폴더 안내: 첫 수업 시간에 찍으면 모인다는 문구
    func subjectHint(_ sample: String) -> String {
        guard let subject else { return sample }
        guard let slot = subject.slots.min(by: { ($0.weekday, $0.start) < ($1.weekday, $1.start) }) else {
            return "시간이 없는 과목이라 미분류함에서 옮겨 와요"
        }
        let day = Slot.days.indices.contains(slot.weekday) ? Slot.days[slot.weekday] : "?"
        return "\(day)요일 \(slot.start) 수업 시간에 찍으면 여기로 모여요"
    }
}
