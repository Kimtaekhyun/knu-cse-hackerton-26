//
//  TimetableScreens.swift
//  chalkdrop
//
//  05 시간표 업로드 · 06 시간표 확인
//

import SwiftUI

// MARK: - 05 시간표 업로드

struct TimetableUploadScreen: View {
    @Environment(Router.self) private var router
    @State private var showPicker = false
    @State private var dropTargeted = false
    private var picked: Bool { router.timetableImage != nil }
    private func pick(_ image: UIImage) { router.timetableImage = image }

    /// 고른 캡처로 인식하러 가기
    private func next() {
        router.timetableManual = false
        router.push(.timetableConfirm)
    }

    /// 사진 없이 시간표 확인(06)으로 가서 과목을 직접 넣어요
    private func startManual() {
        router.timetableImage = nil
        router.timetableManual = true
        router.push(.timetableConfirm)
    }

    /// 아래 막대 설명 글자 옆 "시간표 직접 등록하기"
    private func manualButton(_ title: String = "시간표 직접 등록하기", size: CGFloat = 17) -> some View {
        Button(action: startManual) {
            Text(title).ds(size, .bold, .dsBlue).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func steps(below: Bool = false) -> [String] {
        ["에브리타임 앱에서 시간표 탭 열기",
         "설정 → 이미지로 저장",
         below ? "아래에서 저장한 이미지 고르기" : "오른쪽에서 저장한 이미지 고르기"]
    }

    var body: some View {
        Adaptive { wide } narrow: { narrow($0) }
            .imagePicker(isPresented: $showPicker, onPick: pick)
    }

    private var wide: some View {
        DesignCanvas {
            NavBar(backTitle: "뒤로", title: "시간표 등록", onBack: { router.pop() }) {
                Button { router.reset(to: .homeFirst) } label: {
                    Text("나중에 할게요").ds(17, .medium, .dsSub)
                }
                .buttonStyle(.plain)
            }

            // 안내 (제목 · 에브리타임 '이미지로 저장' 방법)
            VStack(alignment: .leading, spacing: 0) {
                Text("에브리타임 시간표를\n올려 주세요").ds(34, .bold, line: 1.35)
                    .frame(height: 124, alignment: .topLeading)
                Color.clear.frame(width: 1, height: 90)
                stepList(below: false, size: 20)
            }
            .at(89, 127)

            dropZone(width: 527, height: 586, preview: CGSize(width: 360, height: 260))
                .at(619, 112)

            BottomBar(caption: picked ? "이미지 1장 선택됨" : "선택된 이미지 없음") {
                manualButton()
            } trailing: {
                PrimaryButton(title: "다음", width: 280, enabled: picked, action: next)
            }
        }
    }

    /// 캡처 방법 1 · 2 · 3. 세로 화면은 업로드 영역이 아래라 `below`.
    private func stepList(below: Bool, size: CGFloat = 17) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(steps(below: below).enumerated()), id: \.offset) { index, step in
                HStack(spacing: 14) {
                    Text("\(index + 1)").ds(14, .bold, .white)
                        .frame(width: 28, height: 28)
                        .background(Color.black)
                        .clipShape(Circle())
                    Text(step).ds(size, .medium)
                }
            }
        }
    }

    /// 업로드 영역 (끌어다 놓기 · 사진 앨범에서 선택)
    private func dropZone(width: CGFloat, height: CGFloat, preview: CGSize) -> some View {
        VStack(spacing: 0) {
            pickedPreview(empty: 72, maxSize: preview)
            Color.clear.frame(width: 1, height: 24)
            Text(picked ? "시간표 캡처 1장을 골랐어요" : "시간표 캡처를 여기에 끌어다 놓으세요").ds(20, .bold)
            Color.clear.frame(width: 1, height: 8)
            Text("PNG, JPG · 한 장").ds(15, .regular, .dsSub)
            Color.clear.frame(width: 1, height: 28)
            SecondaryButton(title: picked ? "다른 이미지 선택" : "사진 앨범에서 선택") { showPicker = true }
        }
        .frame(width: width, height: height)
        .background(dropTargeted ? Color.dsBlueSoft : Color.dsPanel)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .stroke(dropTargeted ? Color.dsBlue : Color.black.opacity(0.14), style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
        )
        .contentShape(Rectangle())
        .imageDrop(isTargeted: $dropTargeted, onDrop: pick)
    }

    /// 고른 캡처 미리보기. 아직 없으면 + 동그라미.
    @ViewBuilder
    func pickedPreview(empty: CGFloat, maxSize: CGSize) -> some View {
        if let image = router.timetableImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: maxSize.width, maxHeight: maxSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            Image("plus-28")
                .frame(width: empty, height: empty)
                .background(Color.white)
                .clipShape(Circle())
        }
    }
}

// MARK: - 06 시간표 확인

struct TimetableConfirmScreen: View {
    @Environment(Router.self) private var router
    @State private var subjects: [TimetableSubject] = []
    /// 서버에서 시간표를 읽는 상태
    @State private var load: LoadState = .idle
    /// 과목 추가 · 고치기 창. 열 때의 목록을 그대로 담아 둬요 (#111)
    @State private var editor: Editing?
    /// 원본 사진 크게 보기
    @State private var showOriginal = false
    /// `이대로 저장` 서버 요청 중
    @State private var saving = false
    @State private var saveError: String?
    /// 학기 고르기 창
    @State private var showSemesterPicker = false

    /// 사진 없이 직접 등록하는 중인지 (05 "시간표 직접 등록하기")
    var isManual: Bool { router.timetableManual }
    /// 지금 고른 학기 (안 골랐으면 올해 1학기)
    var semester: Semester { router.semester ?? .current() }

    var titleText: String { isManual ? "시간표를 직접 등록해 주세요" : "인식된 시간표를 확인해 주세요" }
    var detailText: String { isManual ? "과목 추가로 수업을 하나씩 넣어 주세요." : "잘못 읽힌 과목은 눌러서 고칠 수 있어요." }
    var backTitle: String { isManual ? "뒤로" : "다시 올리기" }
    var emptyText: String {
        isManual ? "아직 넣은 과목이 없어요. 과목 추가로 넣어 주세요." : "과목을 찾지 못했어요. 과목 추가로 직접 넣어 주세요."
    }

    /// 제목 오른쪽 학기 버튼
    func semesterChip(compact: Bool = false) -> some View {
        SemesterChip(title: semester.title, compact: compact) { showSemesterPicker = true }
    }

    private let days = ["월", "화", "수", "목", "금"]
    /// 에브리타임 '이미지로 저장' 비율 (가로 / 세로)
    private let photoRatio: CGFloat = 1158 / 1275

    var body: some View {
        Adaptive { wide } narrow: { narrow($0) }
            .task { if load == .idle { await analyze() } }
            .sheet(item: $editor) { editing in
                SubjectEditorSheet(subject: editing.subject, others: editing.others) { name, time in
                    save(name: name, time: time, editing: editing.subject?.id)
                }
            }
            .fullScreenCover(isPresented: $showOriginal) { OriginalPhotoView(image: router.timetableImage) }
            .alert("저장하지 못했어요", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
            .sheet(isPresented: $showSemesterPicker) {
                SemesterPickerSheet(semester: semester) { router.semester = $0 }
            }
    }

    private var wide: some View {
        DesignCanvas {
            NavBar(backTitle: backTitle, title: "시간표 확인", onBack: { router.backToUpload() })

            VStack(alignment: .leading, spacing: 10) {
                Text(titleText).ds(34, .bold)
                Text(detailText).ds(17, .regular, .dsSub)
            }
            .at(48, 104)

            // 오른쪽 위 학기 (제목 줄 높이에 맞춰요)
            semesterChip()
                .frame(width: DS.width - 96, alignment: .trailing)
                .at(48, 108)

            // 원본: 에브리타임 '이미지로 저장' 비율(1158 × 1275)에 맞춘 박스
            photoBox(height: 452).at(48, 210)

            // 시간표 목록. 과목이 많으면 아래 막대(y 730) 위까지만 보이고 스크롤돼요.
            // 스크롤 막대가 삭제 버튼과 겹치지 않게 목록 오른쪽에 여백(scrollGutter)을 두고 그 안에 막대가 나와요.
            ScrollView { subjectList(width: 655).frame(width: 655 + Self.scrollGutter, alignment: .leading) }
                .frame(width: 655 + Self.scrollGutter, height: 730 - 210, alignment: .topLeading)
                .at(491, 210)

            BottomBar(caption: caption) {
                PrimaryButton(title: saving ? "저장 중…" : "이대로 저장", width: 280, enabled: load == .loaded && !saving) {
                    save()
                }
            }
        }
    }

    /// 목록 오른쪽 스크롤 막대 자리 (삭제 버튼과 겹치지 않게)
    static let scrollGutter: CGFloat = 20

    /// 원본 시간표 사진. 에브리타임 '이미지로 저장' 은 주말 수업 유무와 관계없이 1158 × 1275 라
    /// 박스를 그 비율로 두고 사진을 비율 그대로 맞춰요. 누르면 크게 보여 줘요.
    func photoBox(height: CGFloat) -> some View {
        let width = (height * photoRatio).rounded()
        return ZStack(alignment: .bottomTrailing) {
            Color.dsPanel
            if let image = router.timetableImage {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(width: width, height: height)
                Text("탭해서 크게 보기").ds(12, .bold, .white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.black.opacity(0.72), in: Capsule())
                    .padding(12)
            } else {
                // 사진 없이 열었을 때(개발용 `-startScreen timetableConfirm`)는 빈 표만
                sampleGrid
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.black.opacity(0.1), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { if router.timetableImage != nil { showOriginal = true } }
    }

    /// 사진이 없을 때 자리 표시 (월~금 · 9~5시 빈 표)
    private var sampleGrid: some View {
        GeometryReader { geo in
            let head: CGFloat = 22, side: CGFloat = 22
            let col = (geo.size.width - side) / 5, row = (geo.size.height - head) / 9
            ZStack(alignment: .topLeading) {
                Color.white
                ForEach(0..<5, id: \.self) { index in
                    Text(days[index]).ds(10, .medium, .dsSub)
                        .frame(width: col).at(side + col * CGFloat(index), 5)
                    Rectangle().fill(Color.dsLine).frame(width: 1, height: geo.size.height)
                        .at(side + col * CGFloat(index), 0)
                }
                ForEach(0..<9, id: \.self) { hour in
                    Rectangle().fill(Color.dsLine).frame(width: geo.size.width, height: 1)
                        .at(0, head + row * CGFloat(hour))
                    Text("\((8 + hour) % 12 + 1)").ds(10, .medium, .dsSub)
                        .at(5, head + row * CGFloat(hour) + 2)
                }
            }
        }
    }

    /// 과목 목록 · 과목 추가 (불러오는 중 · 실패면 그 상태)
    func subjectList(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if load == .loaded {
                if subjects.isEmpty {
                    Text(emptyText).ds(15, .regular, .dsSub).padding(.vertical, 14)
                }
                ForEach(subjects) { subject in
                    HStack(spacing: 14) {
                        Button { edit(subject) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(subject.name).ds(17, .bold)
                                    Text(subject.time).ds(15, .regular, .dsSub)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                subjects.removeAll { $0.id == subject.id }
                            }
                        } label: {
                            Image("minus-circle-28")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 14)
                    .frame(width: width)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.dsLine).frame(height: 1)
                    }
                }

                Button {
                    edit(nil)
                } label: {
                    HStack(spacing: 10) {
                        Image("plus-20")
                        Text("과목 추가").ds(17, .bold)
                    }
                    .padding(.vertical, 20)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text("시간이 정해지지 않은 과목(사이버강의 등)은 미분류함에서 직접 옮겨요.")
                    .ds(14, .regular, .dsSub)
            } else {
                statusView(width: width)
            }
        }
        .padding(.bottom, 24)
    }

    enum LoadState: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    /// 05 에서 고른 캡처를 서버로 보내 과목 목록을 채워요.
    /// 캡처 없이 열면(내 계정 › 시간표 수정) 서버의 현재 학기 과목을, 그것도 없으면 샘플 과목을 보여 줘요.
    private func analyze() async {
        // 학기 선택 처음 값: 오늘 날짜 기준 (서버 규칙). 시간표 수정이면 아래에서 저장된 학기로 바꿔요.
        if router.semester == nil, router.timetableImage != nil || isManual {
            router.semester = await SemesterAPI.suggested()
        }
        // 직접 등록: 빈 목록에서 과목 추가로 채워요
        if isManual {
            load = .loaded
            return
        }
        guard let image = router.timetableImage else {
            let store = SemesterStore.shared
            await store.reload()
            subjects = store.current.map { $0.subjects?.map(\.timetableSubject) ?? [] } ?? SampleData.timetable
            // 시간표 수정: 저장된 현재 학기를 학기 버튼에 미리 넣어 둬요
            if router.semester == nil {
                if let saved = store.current?.semester { router.semester = saved } else { router.semester = await SemesterAPI.suggested() }
            }
            load = .loaded
            return
        }
        load = .loading
        do {
            subjects = try await TimetableAPI.parse(image)
            load = .loaded
        } catch {
            load = .failed(error.localizedDescription)
        }
    }

    /// 아래 막대 설명
    private var caption: String {
        switch load {
        case .idle, .loading: "시간표를 읽는 중이에요"
        case .failed: "시간표를 읽지 못했어요"
        case .loaded: isManual ? "과목 \(subjects.count)개를 넣었어요" : "과목 \(subjects.count)개를 찾았어요"
        }
    }

    /// 과목 목록 자리에 보여 줄 분석 중 · 실패 표시
    @ViewBuilder
    private func statusView(width: CGFloat) -> some View {
        if case .failed(let message) = load {
            VStack(alignment: .leading, spacing: 16) {
                Text(message).dsWrap(15, .regular, .dsSub)
                SecondaryButton(title: "다시 시도", width: 160) { Task { await analyze() } }
            }
            .padding(.vertical, 20)
            .frame(width: width, alignment: .leading)
        } else {
            HStack(spacing: 12) {
                ProgressView()
                Text("시간표를 읽고 있어요. 1분 정도 걸릴 수 있어요.").dsWrap(15, .regular, .dsSub)
            }
            .padding(.vertical, 20)
            .frame(width: width, alignment: .leading)
        }
    }

    /// `이대로 저장`. 로그인했으면 서버에 학기 · 과목을 저장하고 메인으로, 아니면 화면만 넘겨요.
    private func save() {
        guard AuthSession.shared.isLoggedIn else {
            router.reset(to: .homeFirst)
            return
        }
        saving = true
        Task {
            defer { saving = false }
            do {
                // 지금 현재 학기보다 앞선 학기(새 학기 추가로 지난 학기를 넣을 때)면 현재 학기는 그대로 둬요.
                let current = SemesterStore.shared.current?.semester
                let makeCurrent = current.map { semester.order >= $0.order } ?? true
                let saved = try await SemesterAPI.saveTimetable(subjects, semester: semester, makeCurrent: makeCurrent)
                if makeCurrent { SemesterStore.shared.use(saved) } else { await SemesterStore.shared.reload() }
                router.timetableImage = nil
                router.reset(to: .home)
            } catch {
                saveError = error.localizedDescription
            }
        }
    }

    /// 과목 고치기 (nil 이면 새로 추가)
    func edit(_ subject: TimetableSubject?) {
        // 지금 화면에 남아 있는 과목만 겹침 검사에 넘겨요 (지운 과목은 빠짐)
        editor = Editing(subject: subject, others: subjects.filter { $0.id != subject?.id })
    }

    /// 창 하나를 열 때의 값
    struct Editing: Identifiable {
        let id = UUID()
        /// nil 이면 새 과목 추가
        let subject: TimetableSubject?
        /// 시간이 겹치는지 볼 다른 과목들
        let others: [TimetableSubject]
    }

    private func save(name: String, time: String, editing editingID: UUID?) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if let id = editingID, let i = subjects.firstIndex(where: { $0.id == id }) {
                subjects[i].name = name
                subjects[i].time = time
            } else {
                subjects.append(TimetableSubject(name: name, time: time))
            }
        }
    }
}

// MARK: - 좁은 화면 (스플릿 뷰)

extension TimetableUploadScreen {
    /// 아이패드 세로처럼 넓은 세로 창은 피그마 세로 디자인, 스플릿 뷰처럼 좁은 창은 한 줄 배치.
    @ViewBuilder
    func narrow(_ size: CGSize) -> some View {
        if size.width >= 700 { portrait } else { compact(size) }
    }

    /// 세로 화면 — 피그마 "05 시간표 업로드 · 세로" (834 × 1194)
    /// 안내는 위, 업로드 영역은 남는 높이를 채워 화면 가운데를 차지해요.
    private var portrait: some View {
        PortraitCanvas {
            ZStack(alignment: .topLeading) {
                PortraitNavBar(backTitle: "뒤로", title: "시간표 등록", onBack: { router.pop() }) {
                    Button { router.reset(to: .homeFirst) } label: {
                        Text("나중에 할게요").ds(17, .medium, .dsSub)
                    }
                    .buttonStyle(.plain)
                }
                .at(0, 24)

                // 안내
                VStack(alignment: .leading, spacing: 0) {
                    Text("에브리타임 시간표를 올려 주세요").ds(34, .bold, line: 1.35)
                        .frame(height: 87, alignment: .topLeading)
                    stepList(below: true)
                }
                .at(57, 134)

                dropZone(width: 738, height: 555, preview: CGSize(width: 560, height: 300))
                    .at(48, 462)

                PortraitBottomBar(caption: picked ? "이미지 1장 선택됨" : "선택된 이미지 없음") {
                    manualButton()
                } trailing: {
                    PrimaryButton(title: "다음", width: 280, enabled: picked, action: next)
                }
                .at(0, 1090)
            }
            .frame(width: portraitWidth, height: portraitHeight, alignment: .topLeading)
        }
    }

    /// 스플릿 뷰처럼 좁은 창
    private func compact(_ size: CGSize) -> some View {
        let inner = size.width - 40
        return NarrowPage(backTitle: "뒤로", barTitle: "시간표 등록", onBack: { router.pop() },
                          title: "에브리타임 시간표를 올려 주세요",
                          trailing: {
            Button { router.reset(to: .homeFirst) } label: { Text("나중에 할게요").ds(15, .medium, .dsSub) }
                .buttonStyle(.plain)
        }, content: {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(steps().enumerated()), id: \.offset) { index, step in
                    HStack(spacing: 12) {
                        Text("\(index + 1)").ds(13, .bold, .white)
                            .frame(width: 26, height: 26)
                            .background(Color.black)
                            .clipShape(Circle())
                        Text(step).dsWrap(16, .medium)
                    }
                }
            }
            .padding(.vertical, 4)

            // 업로드 영역
            VStack(spacing: 0) {
                pickedPreview(empty: 64, maxSize: CGSize(width: inner - 48, height: 220))
                Color.clear.frame(width: 1, height: 18)
                Text(picked ? "시간표 캡처 1장을 골랐어요" : "시간표 캡처를 여기에 끌어다 놓으세요")
                    .dsWrap(18, .bold)
                    .multilineTextAlignment(.center)
                Color.clear.frame(width: 1, height: 6)
                Text("PNG, JPG · 한 장").ds(14, .regular, .dsSub)
                Color.clear.frame(width: 1, height: 20)
                SecondaryButton(title: picked ? "다른 이미지 선택" : "사진 앨범에서 선택", width: min(220, inner - 48)) { showPicker = true }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 36)
            .frame(width: inner)
            .background(dropTargeted ? Color.dsBlueSoft : Color.dsPanel)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(dropTargeted ? Color.dsBlue : Color.black.opacity(0.14), style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
            )
            .imageDrop(isTargeted: $dropTargeted, onDrop: pick)

        }, bottom: {
            // 좁은 창은 자리가 모자라서 짧게
            NarrowBottomBar(caption: picked ? "이미지 1장 선택됨" : nil) {
                manualButton("직접 등록", size: 15)
            } trailing: {
                PrimaryButton(title: "다음", width: inner < 440 ? 150 : 200, enabled: picked, action: next)
            }
        })
    }
}

extension TimetableConfirmScreen {
    /// 아이패드 세로처럼 넓은 세로 창은 피그마 세로 디자인, 스플릿 뷰처럼 좁은 창은 한 줄 배치.
    @ViewBuilder
    func narrow(_ size: CGSize) -> some View {
        if size.width >= 700 { portrait } else { compact(size) }
    }

    /// 세로 화면 — 피그마 "06-2 시간표 확인 · 원본 사진 맞춤 · 세로" (834 × 1194)
    /// 사진 판은 위에 가로로 꽉, 과목 목록은 아래 (많으면 스크롤).
    private var portrait: some View {
        PortraitCanvas {
            ZStack(alignment: .topLeading) {
                PortraitNavBar(backTitle: backTitle, title: "시간표 확인", onBack: { router.backToUpload() })
                    .at(0, 24)

                VStack(alignment: .leading, spacing: 10) {
                    Text(titleText).ds(34, .bold)
                    Text(detailText).ds(17, .regular, .dsSub)
                }
                .at(48, 104)

                semesterChip()
                    .frame(width: portraitWidth - 96, alignment: .trailing)
                    .at(48, 108)

                photoBox(height: 372)
                    .frame(width: 738, height: 404)
                    .background(Color.dsPanel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .at(48, 204)

                ScrollView { subjectList(width: 738).frame(width: 738 + Self.scrollGutter, alignment: .leading) }
                    .frame(width: 738 + Self.scrollGutter, height: 1090 - 632, alignment: .topLeading)
                    .at(48, 632)

                PortraitBottomBar(caption: caption) {
                    PrimaryButton(title: saving ? "저장 중…" : "이대로 저장", width: 280, enabled: load == .loaded && !saving) {
                        save()
                    }
                }
                .at(0, 1090)
            }
            .frame(width: portraitWidth, height: portraitHeight, alignment: .topLeading)
        }
    }

    /// 스플릿 뷰처럼 좁은 창
    private func compact(_ size: CGSize) -> some View {
        let inner = size.width - 40
        return NarrowPage(backTitle: backTitle, barTitle: "시간표 확인", onBack: { router.backToUpload() },
                          title: titleText,
                          detail: detailText,
                          trailing: { semesterChip(compact: true) }, content: {
            // 원본 (작게)
            photoBox(height: 452)
                .scaledBox((452 * photoRatio).rounded(), 452, to: min(inner, 300))
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 0) {
                if load == .loaded {
                    if subjects.isEmpty {
                        Text(emptyText).dsWrap(15, .regular, .dsSub).padding(.vertical, 14)
                    }
                    ForEach(subjects) { subject in
                        HStack(spacing: 14) {
                            Button { edit(subject) } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(subject.name).ds(17, .bold)
                                        Text(subject.time).ds(15, .regular, .dsSub)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { subjects.removeAll { $0.id == subject.id } }
                            } label: { Image("minus-circle-28") }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 14)
                        .frame(width: inner)
                        .overlay(alignment: .bottom) { Rectangle().fill(Color.dsLine).frame(height: 1) }
                    }
                    Button {
                        edit(nil)
                    } label: {
                        HStack(spacing: 10) {
                            Image("plus-20")
                            Text("과목 추가").ds(17, .bold)
                        }
                        .padding(.vertical, 18)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Text("시간이 정해지지 않은 과목(사이버강의 등)은 미분류함에서 직접 옮겨요.").dsWrap(13, .regular, .dsSub)
                } else {
                    statusView(width: inner)
                }
            }
        }, bottom: {
            NarrowBottomBar(caption: caption) {
                PrimaryButton(title: saving ? "저장 중…" : "이대로 저장", width: inner < 440 ? 150 : 200, enabled: load == .loaded && !saving) { save() }
            }
        })
    }
}
