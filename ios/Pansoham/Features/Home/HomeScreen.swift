//
//  HomeScreen.swift
//  chalkdrop
//
//  07 메인 · 처음 (판서 0장) / 08 메인 (판서가 쌓인 뒤)
//  로그인했으면 수업 중 · 오늘 수업 · 이번 주를 메인 화면 API(`GET /home`)로 보여 줘요 (#107).
//

import SwiftUI

struct HomeScreen: View {
    /// true 면 07 "처음" 화면, false 면 08 화면
    var isFirst = false

    @Environment(Router.self) private var router
    /// 내 계정에서 고친 이름 (메인 아이콘에 첫 글자, #144)
    @AppStorage("profileName") private var profileName = "김마린"
    @State private var appeared = false
    /// 촬영 버튼이 펼쳐져 있는지 (08-1)
    @State private var menuOpen = false
    @State private var showAlbum = false
    /// 앨범에서 고른 사진. 2장 이상이면 확인 창(08-2)을 띄워요.
    @State private var picked: [UIImage] = []

    private var homeStore: HomeStore { HomeStore.shared }
    /// 서버 메인 값 (로그인 전이면 nil → 샘플)
    private var home: HomeAPI.HomeDTO? { live ? homeStore.home : nil }
    /// 서버 값을 쓰는지 (로그인했는지)
    private var live: Bool { AuthSession.shared.isLoggedIn }
    /// 07(처음) 화면인지. 로그인했으면 정리한 판서가 0장일 때, 아니면 들어온 화면(07 · 08) 그대로
    private var firstScreen: Bool { home.map { $0.totalCaptures == 0 } ?? isFirst }

    /// 08 에서만 카드 · 알림 · 막대가 차례로 나타나요. 07 은 처음부터 다 보여요.
    private var shown: Bool { firstScreen || appeared }

    private var counts: [Int] { firstScreen ? [0, 0, 0, 0, 0, 0] : [12, 8, 5, 3, 0, 3] }

    var body: some View {
        // 피그마 타임라인: 07 은 3.2초, 08 은 2.8초 되풀이 (안내 말풍선 · 수업 중 점)
        Motion(loop: firstScreen ? 3.2 : 2.8) { t in
            Adaptive { canvas(t) } narrow: { narrow($0, t) }
        }
            .onAppear { appeared = true }
            .task {
                // 메인 화면 값(수업 중 · 오늘 수업 · 이번 주)은 학기와 따로 받아요
                async let homeValues: Void = HomeStore.shared.reload()
                await SemesterStore.shared.reload()
                await homeValues
                // 로그인했으면 미분류함 수 · 아직 옮기지 않은 판서도 받아요
                guard AuthSession.shared.isLoggedIn else { return }
                async let unsorted: Void = SubjectCaptures.unsorted.load(.unsorted)
                async let unmoved: Void = SubjectCaptures.unmoved.load(.unmoved)
                // 시험 복습 D-7 · D-1 알림 (#125)
                LocalNotifications.shared.scheduleExam(HomeStore.shared.home?.exam,
                                                       captures: SemesterStore.shared.subjects.map(\.captureCount).reduce(0, +))
                _ = await (unsorted, unmoved)
            }
            .overlay {
                if picked.count > 1 {
                    AlbumReviewSheet(photos: $picked,
                                     onMore: { showAlbum = true },
                                     onCancel: { withAnimation { picked = [] } },
                                     onStart: { startProcessing(picked) })
                        .transition(.opacity)
                }
            }
            .multiImagePicker(isPresented: $showAlbum, maxCount: maxAlbumPhotos - picked.count) { images in
                let all = Array((picked + images).prefix(maxAlbumPhotos))
                // 한 장만 고르면 확인 없이 바로 정리해요.
                if all.count == 1 { startProcessing(all) } else { withAnimation { picked = all } }
            }
    }

    /// 고른 사진을 처리 중 화면으로 넘겨요.
    private func startProcessing(_ photos: [UIImage]) {
        router.albumPhotos = photos
        picked = []
        router.push(.processing)
    }

    private func captureMenu(size: CGFloat) -> some View {
        CaptureMenu(isOpen: $menuOpen, size: size,
                    onCamera: { router.push(.capture) },
                    onAlbum: { showAlbum = true })
    }

    private func canvas(_ t: Double) -> some View {
        DesignCanvas {
            topBar
            leftColumn(t).at(24, 112)
            rightColumn.at(408, 112)

            if firstScreen && !menuOpen {
                // 첫 촬영 안내
                Group {
                    Button { router.push(.capture) } label: {
                        Text("여기를 눌러 첫 판서를 찍어 보세요").ds(15, .bold, .white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .zoomSource()
                    .at(910, 664)
                    Image("tooltip-tail").at(1109, 706)
                }
                .offset(y: t < 0.7 ? tween(t, 0, -8, 0, 0.7, .inOut)
                           : t < 1.4 ? tween(t, -8, 0, 0.7, 1.4, .inOut)
                           : t < 2.1 ? tween(t, 0, -8, 1.4, 2.1, .inOut)
                           : tween(t, -8, 0, 2.1, 2.8, .inOut))
            } else if showsBellDot {
                Image("bell-dot").at(1092, 49).allowsHitTesting(false)
            }

            // 촬영 버튼: 누르면 `앨범에서 선택` · `사진 촬영` 으로 펼쳐져요 (08-1)
            CaptureMenuDim(isOpen: $menuOpen)
                .frame(width: DS.width, height: DS.height)
            captureMenu(size: 72)
                .padding(.trailing, 40)
                .padding(.bottom, 40)
                .frame(width: DS.width, height: DS.height, alignment: .bottomTrailing)
        }
    }

    // MARK: 위 막대

    private var topBar: some View {
        HStack {
            Text("chalkdrop").ds(34, .bold)
            Spacer()
            HStack(spacing: 20) {
                Button { router.push(.pending) } label: { Image("bell") }
                    .buttonStyle(.plain)
                Button { router.push(.account) } label: {
                    Text(profileInitial).ds(15, .bold, .white)
                        .frame(width: 34, height: 34)
                        .background(Color.black)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 40)
        .frame(width: DS.width, height: 76)
        .at(0, 24)
    }

    // MARK: 왼쪽 (오늘)

    private func leftColumn(_ t: Double) -> some View {
        VStack(alignment: .leading, spacing: 32) {
            nowCard(t)
            todayList()
            if !firstScreen { pendingPanel() }
        }
    }

    private func nowCard(_ t: Double, width: CGFloat = 340) -> some View {
        // 수업 중 점: 0.6초마다 1 ↔ 0.25 (08 에만 있어요)
        let dot = firstScreen ? 1
            : t < 0.6 ? tween(t, 1, 0.25, 0, 0.6, .inOut)
            : t < 1.2 ? tween(t, 0.25, 1, 0.6, 1.2, .inOut)
            : t < 1.8 ? tween(t, 1, 0.25, 1.2, 1.8, .inOut)
            : tween(t, 0.25, 1, 1.8, 2.4, .inOut)
        return nowCardBody(dot, width: width)
    }

    private func nowCardBody(_ dot: Double, width: CGFloat) -> some View {
        let card = nowCardContent
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                // 수업 중일 때만 점이 깜빡여요
                Image("dot-blue-8").opacity(card.inClass ? dot : 0.25)
                Text(card.label).ds(14, .bold, .white)
            }
            Color.clear.frame(width: 1, height: 14)
            Text(card.title).ds(34, .bold, .white).lineLimit(1).minimumScaleFactor(0.6)
            Color.clear.frame(width: 1, height: 4)
            Text(card.detail).ds(15, .regular, .dsSub)
            Color.clear.frame(width: 1, height: 20)
            if let progress = card.progress {
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.2)).frame(width: width - 48, height: 6)
                    Capsule().fill(Color.dsBlue).frame(width: (width - 48) * progress, height: 6)
                }
                Color.clear.frame(width: 1, height: 10)
                HStack {
                    Text(card.left).ds(12, .medium, .dsSub)
                    Spacer()
                    Text(card.right).ds(12, .medium, .white)
                }
                .frame(width: width - 48)
                Color.clear.frame(width: 1, height: 20)
            }
        }
        .padding(.top, 22)
        .padding(.bottom, 24)
        .padding(.horizontal, 24)
        .frame(width: width, alignment: .leading)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func todayList(_ width: CGFloat = 340) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("오늘 수업").ds(20, .bold)
            Color.clear.frame(width: 1, height: 6)
            if live {
                let now = Self.nowMinute()
                if home == nil {
                    Text("불러오는 중…").ds(15, .regular, .dsSub).padding(.vertical, 10)
                } else if todayClasses.isEmpty {
                    Text("오늘은 수업이 없어요").ds(15, .regular, .dsSub).padding(.vertical, 10)
                }
                ForEach(Array(todayClasses.enumerated()), id: \.offset) { _, lesson in
                    let ongoing = lesson.startMinute <= now && now < lesson.endMinute
                    todayRow(time: lesson.start, name: lesson.name, bold: ongoing,
                             muted: now >= lesson.endMinute, width: width) {
                        if ongoing {
                            nowPill
                        } else if now >= lesson.endMinute {
                            Text("끝남").ds(13, .regular, .dsSub)
                        } else {
                            Text(Self.after(lesson.startMinute - now)).ds(13, .regular, .dsSub)
                        }
                    }
                }
            } else {
                todayRow(time: "10:30", name: "자료구조", bold: true, width: width) { nowPill }
                todayRow(time: "13:00", name: "컴퓨터구조", width: width) { Text("2시간 뒤").ds(13, .regular, .dsSub) }
                todayRow(time: "15:00", name: "이산수학", width: width) { Text("4시간 뒤").ds(13, .regular, .dsSub) }
            }
        }
    }

    private var nowPill: some View {
        Text("지금").ds(12, .bold, .white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.dsBlue)
            .clipShape(Capsule())
    }

    private func todayRow<Trailing: View>(time: String, name: String, bold: Bool = false, muted: Bool = false,
                                          width: CGFloat = 340, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            HStack(spacing: 16) {
                Text(time).ds(15, .medium, .dsSub)
                Text(name).ds(17, bold ? .bold : .medium, muted ? .dsSub : .black).lineLimit(1)
            }
            Spacer()
            trailing()
        }
        .padding(.vertical, 10)
        .frame(width: width)
    }

    /// 아직 옮기지 않은 판서 (08 에만 있어요). 0장이어도 틀과 개수(0)는 남겨요 (#124).
    private func pendingPanel(_ width: CGFloat = 340) -> some View {
        let notes = PendingNote.current
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    Text("아직 옮기지 않은 판서").ds(16, .bold)
                    Text("\(notes.count)").ds(12, .bold, .white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.dsBlue)
                        .clipShape(Capsule())
                }
                Spacer()
                Button { router.push(.pending) } label: {
                    Text("모두 보기").ds(13, .medium, .dsSub)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            ForEach(Array(notes.prefix(2).enumerated()), id: \.element.id) { index, note in
                pendingRow(note)
                    .entrance(shown, delay: 0.5 + 0.12 * Double(index), duration: 0.35, y: 12)
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 12)
        .padding(.horizontal, 16)
        .frame(width: width)
        .background(Color.dsBlueSoft)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func pendingRow(_ note: PendingNote) -> some View {
        Button { note.open(router) } label: {
            HStack(spacing: 12) {
                note.thumb(width: 52, height: 40, scale: 1.6667, radius: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title).ds(14, .bold)
                    Text(note.detail).ds(12, .regular, .dsSub)
                }
                Spacer(minLength: 0)
                Image("chevron-right-18")
            }
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: 오른쪽 (과목 폴더)

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(semesterLabel).ds(20, .bold)
                Spacer()
                Button { router.push(.allSemesters) } label: {
                    HStack(spacing: 2) {
                        Text("전체 학기").ds(15, .bold)
                        Image("chevron-18").rotationEffect(.degrees(180))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(width: 746)

            // 과목 폴더 (3칸씩, 두 줄을 넘으면 스크롤)
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(236), spacing: 19), count: 3),
                          alignment: .leading, spacing: 16) {
                    ForEach(Array(folders.enumerated()), id: \.offset) { index, folder in
                        folderCard(folder)
                            .entrance(appeared, delay: 0.10 + 0.07 * Double(min(index, 6)), duration: 0.4, y: 16)
                    }
                }
            }
            .frame(width: 746, height: 166 * 2 + 16)
            .scrollBounceBehavior(.basedOnSize)

            weekChart
        }
    }

    // MARK: 과목 폴더 데이터

    /// 메인의 폴더 한 칸
    struct Folder {
        var name: String
        var detail: String
        var count: Int
        var style: SubjectCard.Style = .gray
        var symbol: String? = nil
        var open: () -> Void
    }

    private var store: SemesterStore { SemesterStore.shared }

    private var semesterLabel: String {
        if store.isLive { return store.current?.label ?? "아직 등록한 학기가 없어요" }
        return "2026년 2학기"
    }

    /// 로그인했으면 서버의 현재 학기 과목, 아니면 샘플 폴더
    private var folders: [Folder] {
        let unsorted = Folder(name: "미분류함", detail: "시간표 밖에서 찍은 판서",
                              count: store.isLive ? SubjectCaptures.unsorted.items.count : counts[5], style: .dashed) { router.push(.unsorted) }
        guard store.isLive else {
            let samples: [(String, String, Screen)] = [
                ("자료구조", "월 10:30–12:00", firstScreen ? .subjectEmpty : .subjectLessons),
                ("컴퓨터구조", "화 13:00–14:30", firstScreen ? .subjectEmpty : .subjectLessons),
                ("확률과 통계", "수 09:00–10:30", firstScreen ? .subjectEmpty : .subjectLessons),
                ("이산수학", "목 15:00–16:30", firstScreen ? .subjectEmpty : .subjectLessons),
                ("운영체제", "금 10:30–12:00", .subjectEmpty),
            ]
            return samples.enumerated().map { index, sample in
                Folder(name: sample.0, detail: sample.1, count: counts[index], style: index == 0 ? .blue : .gray) {
                    router.subject = nil
                    router.push(sample.2)
                }
            } + [unsorted]
        }
        guard store.current != nil else {
            return [Folder(name: "시간표 등록", detail: "에브리타임 시간표 올리기", count: 0, style: .dashed, symbol: "+") {
                router.startNewSemester()
            }, unsorted]
        }
        return store.subjects.enumerated().map { index, subject in
            Folder(name: subject.name, detail: subject.timeText, count: subject.captureCount,
                   style: subject.id == ongoingSubjectID ? .blue : .gray) {
                router.subject = subject
                router.push(subject.captureCount == 0 ? .subjectEmpty : .subjectLessons)
            }
        } + [unsorted]
    }

    private func folderCard(_ folder: Folder) -> some View {
        SubjectCard(name: folder.name, detail: folder.detail, count: folder.count,
                    style: folder.style, symbol: folder.symbol, action: folder.open)
    }

    // MARK: 이번 주

    private var weekChart: some View {
        let bars = weekBars

        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 10) {
                    Text("이번 주").ds(20, .bold)
                    Text(weekSummary).ds(15, .medium, .dsSub)
                }
                Spacer()
                if let compare = weekCompare { Text(compare).ds(15, .bold) }
            }
            .frame(width: 746)

            HStack(alignment: .bottom, spacing: 12) {
                ForEach(Array(bars.enumerated()), id: \.offset) { index, bar in
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: bar.height <= 6 ? 3 : 8, style: .continuous)
                            .fill(bar.today ? Color.dsBlue
                                  : bar.height <= 6 ? Color.black.opacity(0.05) : Color.black.opacity(0.14))
                            .frame(width: 82, height: shown ? bar.height : 6)
                            .animation(.easeOut(duration: 0.6).delay(0.5 + 0.06 * Double(index)), value: shown)
                        Text(bar.day).ds(13, bar.today ? .bold : .regular, bar.today ? .black : .dsSub)
                    }
                }
            }
            .frame(height: 106, alignment: .bottom)
        }
        .padding(.top, 40)
        .frame(width: 744, height: 301, alignment: .topLeading)
    }
}

// MARK: - 좁은 화면 (스플릿 뷰)

extension HomeScreen {
    func narrow(_ size: CGSize, _ t: Double) -> some View {
        let inner = size.width - 40
        // 반쪽 폭이면 폴더 3칸, 더 좁으면 2칸
        let folderColumns = inner >= 500 ? 3 : 2
        let cardWidth = (inner - 12 * CGFloat(folderColumns - 1)) / CGFloat(folderColumns)
        // 안내 말풍선 움직임 (07)
        let bob = t < 0.7 ? tween(t, 0, -8, 0, 0.7, .inOut)
            : t < 1.4 ? tween(t, -8, 0, 0.7, 1.4, .inOut)
            : t < 2.1 ? tween(t, 0, -8, 1.4, 2.1, .inOut)
            : tween(t, -8, 0, 2.1, 2.8, .inOut)

        return VStack(spacing: 0) {
            // 위 막대
            HStack {
                Text("chalkdrop").ds(28, .bold)
                Spacer()
                HStack(spacing: 20) {
                    Button { router.push(.pending) } label: {
                        Image("bell").overlay(alignment: .topLeading) {
                            if showsBellDot { Image("bell-dot").offset(x: 16, y: -1) }
                        }
                    }
                    .buttonStyle(.plain)
                    Button { router.push(.account) } label: {
                        Text(profileInitial).ds(15, .bold, .white)
                            .frame(width: 34, height: 34)
                            .background(Color.black)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 60)
            .avoidsWindowControls()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    nowCard(t, width: inner)
                    todayList(inner)
                    if !firstScreen { pendingPanel(inner) }

                    // 과목 폴더
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text(semesterLabel).ds(20, .bold)
                            Spacer()
                            Button { router.push(.allSemesters) } label: {
                                HStack(spacing: 2) {
                                    Text("전체 학기").ds(15, .bold)
                                    Image("chevron-18").rotationEffect(.degrees(180))
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        // 폴더 목록은 서버 응답에 따라 개수가 바뀌어요. 한 번만 꺼내 개수와 내용을 같은 값으로 써요
                        // (따로 읽으면 이전 개수로 만든 칸이 줄어든 목록을 읽어 범위 초과로 멈춰요, #87).
                        let items = folders
                        NarrowGrid(count: items.count, columns: folderColumns) { index in
                            folderCard(items[index])
                                .scaledBox(236, 166, to: cardWidth)
                            .entrance(appeared, delay: 0.1 + 0.07 * Double(index), duration: 0.4, y: 16)
                        }
                    }

                    narrowWeek(inner)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 110)
            }
        }
        .background(Color.white.ignoresSafeArea())
        .overlay { CaptureMenuDim(isOpen: $menuOpen) }
        .overlay(alignment: .bottomTrailing) {
            VStack(alignment: .trailing, spacing: 0) {
                if firstScreen && !menuOpen {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("여기를 눌러 첫 판서를 찍어 보세요").ds(15, .bold, .white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Image("tooltip-tail").padding(.trailing, 23)
                    }
                    .offset(y: bob)
                    .padding(.bottom, 8)
                }
                captureMenu(size: 64)
            }
            .padding(20)
        }
    }

    /// 이번 주 막대 그래프 (너비에 맞춰 막대 굵기를 정해요)
    private func narrowWeek(_ width: CGFloat) -> some View {
        let bars = weekBars
        let bar = (width - 8 * 6) / 7
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("이번 주").ds(20, .bold)
                Text(weekSummary).ds(14, .medium, .dsSub)
                Spacer(minLength: 0)
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(0..<7, id: \.self) { index in
                    let height = bars[index].height
                    let today = bars[index].today
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: height <= 6 ? 3 : 8, style: .continuous)
                            .fill(today ? Color.dsBlue : height <= 6 ? Color.black.opacity(0.05) : Color.black.opacity(0.14))
                            .frame(width: bar, height: shown ? height : 6)
                            .animation(.easeOut(duration: 0.6).delay(0.5 + 0.06 * Double(index)), value: shown)
                        Text(bars[index].day).ds(13, today ? .bold : .regular, today ? .black : .dsSub)
                    }
                }
            }
            .frame(height: 100, alignment: .bottom)
            if let compare = weekCompare { Text(compare).ds(15, .bold) }
        }
    }
}

// MARK: - 메인 화면 값 (서버 · 샘플)

extension HomeScreen {
    /// 수업 중 카드에 들어갈 글자
    struct NowCard {
        var label: String
        var title: String
        var detail: String
        var inClass = false
        /// 진행 막대 (nil 이면 막대 없음)
        var progress: CGFloat?
        var left = ""
        var right = ""
    }

    /// 메인 오른쪽 위 아이콘 글자: 이름 첫 글자 ("배한결" → "배")
    var profileInitial: String {
        String(profileName.trimmingCharacters(in: .whitespaces).prefix(1)).ifEmpty("김")
    }

    /// 종 아이콘 점: 옮기지 않은 판서가 있을 때만 (#144)
    var showsBellDot: Bool { !firstScreen && !PendingNote.current.isEmpty }

    /// 지금 수업 중인 과목. 이 과목 폴더만 하늘색이에요 (#144)
    var ongoingSubjectID: UUID? {
        let now = Self.nowMinute()
        return todayClasses.first { $0.startMinute <= now && now < $0.endMinute }?.subjectId
    }

    /// 오늘 수업 (시작 시각 순)
    var todayClasses: [HomeAPI.ClassDTO] { (home?.today ?? []).sorted { $0.startMinute < $1.startMinute } }

    /// 수업 중 → 다음 수업 → 오늘 끝 · 수업 없음 순으로 골라요.
    /// 서버의 `now_class` 대신 오늘 수업과 지금 시각으로 계산해서, 화면을 켜 둔 채 수업이 바뀌어도 맞게 보여요.
    var nowCardContent: NowCard {
        guard live else {
            return NowCard(label: "수업 중", title: "자료구조", detail: "12:00에 끝나요", inClass: true,
                           progress: 0.6, left: "10:30", right: "42분 남음")
        }
        guard home != nil else { return NowCard(label: "오늘", title: "불러오는 중…", detail: " ") }
        let now = Self.nowMinute()
        if let lesson = todayClasses.first(where: { $0.startMinute <= now && now < $0.endMinute }) {
            let length = max(1, lesson.endMinute - lesson.startMinute)
            return NowCard(label: "수업 중", title: lesson.name, detail: "\(lesson.end)에 끝나요", inClass: true,
                           progress: CGFloat(now - lesson.startMinute) / CGFloat(length),
                           left: lesson.start, right: Self.remaining(lesson.endMinute - now))
        }
        if let next = todayClasses.first(where: { $0.startMinute > now }) {
            return NowCard(label: "다음 수업", title: next.name, detail: "\(next.start)에 시작해요",
                           progress: 0, left: "\(next.start)–\(next.end)", right: Self.after(next.startMinute - now))
        }
        if todayClasses.isEmpty {
            return NowCard(label: "오늘", title: "수업 없는 날", detail: "찍은 판서는 미분류함에 모여요")
        }
        return NowCard(label: "오늘", title: "수업 끝", detail: "오늘 수업 \(todayClasses.count)개를 마쳤어요")
    }

    /// 이번 주 막대 (월~일). 가장 많은 날이 72, 판서가 없는 날은 6
    var weekBars: [(day: String, height: CGFloat, today: Bool)] {
        let names = ["월", "화", "수", "목", "금", "토", "일"]
        guard let week = home?.week else {
            let sample: [CGFloat] = firstScreen ? [6, 6, 6, 6, 6, 6, 6] : [54, 36, 24, 72, 6, 6, 6]
            return names.indices.map { (names[$0], sample[$0], !firstScreen && $0 == 3) }
        }
        let counts = (week.days + Array(repeating: 0, count: 7)).prefix(7)
        let most = max(1, counts.max() ?? 1)
        let todayIndex = Self.dayIndex(weekStart: week.start)
        return names.indices.map { index in
            let count = counts[index]
            let height: CGFloat = count == 0 ? 6 : max(14, 72 * CGFloat(count) / CGFloat(most))
            return (names[index], height, index == todayIndex)
        }
    }

    /// "판서 31장 정리" · "아직 정리한 판서가 없어요"
    var weekSummary: String {
        guard let week = home?.week else { return firstScreen ? "아직 정리한 판서가 없어요" : "판서 31장 정리" }
        return week.total == 0 ? "이번 주에 정리한 판서가 없어요" : "판서 \(week.total)장 정리"
    }

    /// "지난주보다 8장 더" · "지난주보다 3장 덜" · "지난주와 같아요". 둘 다 0이면 안 보여요
    var weekCompare: String? {
        guard let week = home?.week else { return firstScreen ? nil : "지난주보다 8장 더" }
        let diff = week.total - week.lastWeekTotal
        if week.total == 0 && week.lastWeekTotal == 0 { return nil }
        if diff > 0 { return "지난주보다 \(diff)장 더" }
        if diff < 0 { return "지난주보다 \(-diff)장 덜" }
        return "지난주와 같아요"
    }

    /// 지금이 하루 시작부터 몇 분째인지
    static func nowMinute(_ date: Date = .now) -> Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// 이번 주 월요일("2026-11-16")부터 오늘이 몇 번째 날인지 (0 = 월). 이번 주가 아니면 nil
    static func dayIndex(weekStart: String, today: Date = .now) -> Int? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let start = formatter.date(from: weekStart) else { return nil }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                           to: calendar.startOfDay(for: today)).day ?? -1
        return (0..<7).contains(days) ? days : nil
    }

    /// 시작까지 남은 시간: "42분 뒤" · "2시간 뒤"
    static func after(_ minutes: Int) -> String {
        if minutes < 60 { return "\(max(1, minutes))분 뒤" }
        return "\(Int((Double(minutes) / 60).rounded()))시간 뒤"
    }

    /// 끝까지 남은 시간: "42분 남음" · "1시간 12분 남음"
    static func remaining(_ minutes: Int) -> String {
        if minutes < 60 { return "\(max(1, minutes))분 남음" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60)시간 남음" : "\(minutes / 60)시간 \(rest)분 남음"
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
