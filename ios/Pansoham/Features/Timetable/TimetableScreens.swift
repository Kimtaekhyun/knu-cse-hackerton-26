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

    private func steps(below: Bool = false) -> [String] {
        ["에브리타임 앱에서 시간표 탭 열기",
         "시간표 전체가 보이게 화면 캡처",
         below ? "아래에서 캡처 이미지 고르기" : "오른쪽에서 캡처 이미지 고르기"]
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

            // 안내
            VStack(alignment: .leading, spacing: 0) {
                Text("에브리타임 시간표를\n올려 주세요").ds(34, .bold, line: 1.35)
                Color.clear.frame(width: 1, height: 14)
                Text("시간표가 있으면 수업 시간에 찍은 판서가\n그 과목 폴더로 자동 정리돼요.")
                    .ds(17, .regular, .dsSub, line: 1.55)
                Color.clear.frame(width: 1, height: 36)

                stepList(below: false)

                Color.clear.frame(width: 1, height: 40)
                Text("에브리타임은 공식 연동이 없어서 캡처 이미지로 시간표를 읽어요.")
                    .ds(14, .regular, .dsSub)
            }
            .at(48, 112)

            dropZone(width: 527, height: 586, preview: CGSize(width: 360, height: 260))
                .at(619, 112)

            BottomBar(caption: picked ? "이미지 1장 선택됨" : "선택된 이미지 없음") {
                PrimaryButton(title: "다음", width: 280, enabled: picked) {
                    router.push(.timetableConfirm)
                }
            }
        }
    }

    /// 캡처 방법 1 · 2 · 3. 세로 화면은 업로드 영역이 아래라 `below`.
    private func stepList(below: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(steps(below: below).enumerated()), id: \.offset) { index, step in
                HStack(spacing: 14) {
                    Text("\(index + 1)").ds(14, .bold, .white)
                        .frame(width: 28, height: 28)
                        .background(Color.black)
                        .clipShape(Circle())
                    Text(step).ds(17, .medium)
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
    /// 고치는 중인 과목 (nil 이면 새 과목 추가)
    @State private var editingID: UUID?
    @State private var showEditor = false
    @State private var draftName = ""
    @State private var draftTime = ""

    private let days = ["월", "화", "수", "목", "금"]

    var body: some View {
        Adaptive { wide } narrow: { narrow($0) }
            .task { if load == .idle { await analyze() } }
            .alert(editingID == nil ? "과목 추가" : "과목 고치기", isPresented: $showEditor) {
                TextField("과목 이름", text: $draftName)
                TextField("요일 · 시간 (예: 월 10:30–12:00)", text: $draftTime)
                Button("취소", role: .cancel) {}
                Button(editingID == nil ? "추가" : "저장") { saveDraft() }
            }
    }

    private var wide: some View {
        DesignCanvas {
            NavBar(backTitle: "다시 올리기", title: "시간표 확인", onBack: { router.backToUpload() })

            VStack(alignment: .leading, spacing: 10) {
                Text("인식된 시간표를 확인해 주세요").ds(34, .bold)
                Text("잘못 읽힌 과목은 눌러서 고칠 수 있어요.").ds(17, .regular, .dsSub)
            }
            .at(48, 104)

            // 원본 캡처
            ZStack(alignment: .topLeading) {
                Color.dsPanel
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    Text(day).ds(12, .medium, .dsSub).at(44 + CGFloat(index) * 50, 16)
                }
                block(x: 36, y: 98, opacity: 1)
                block(x: 86, y: 202, opacity: 0.85)
                block(x: 136, y: 46, opacity: 1)
                block(x: 186, y: 306, opacity: 0.85)
                block(x: 236, y: 98, opacity: 1)
                // 05 에서 고른 캡처가 있으면 그걸 보여 줘요.
                if let image = router.timetableImage {
                    Color.dsPanel
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(width: 300, height: 452)
                }
            }
            .frame(width: 300, height: 452, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .at(48, 210)

            // 시간표 목록. 과목이 많으면 아래 막대(y 730) 위까지만 보이고 스크롤돼요.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if load == .loaded {
                        if subjects.isEmpty {
                            Text("과목을 찾지 못했어요. 과목 추가로 직접 넣어 주세요.").ds(15, .regular, .dsSub).padding(.vertical, 14)
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
                            .frame(width: 766)
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
                        statusView(width: 766)
                    }
                }
                .padding(.bottom, 24)
            }
            .frame(width: 766, height: 730 - 210, alignment: .topLeading)
            .at(380, 210)

            BottomBar(caption: caption) {
                PrimaryButton(title: "이대로 저장", width: 280, enabled: load == .loaded) {
                    router.reset(to: .homeFirst)
                }
            }
        }
    }

    private func block(x: CGFloat, y: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.black.opacity(opacity))
            .frame(width: 44, height: 66)
            .at(x, y)
    }

    enum LoadState: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    /// 05 에서 고른 캡처를 서버로 보내 과목 목록을 채워요.
    /// 캡처가 없으면(개발용 `-startScreen timetableConfirm`) 샘플 과목을 보여 줘요.
    private func analyze() async {
        guard let image = router.timetableImage else {
            subjects = SampleData.timetable
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
        case .loaded: "과목 \(subjects.count)개를 찾았어요"
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

    /// 과목 고치기 (nil 이면 새로 추가)
    func edit(_ subject: TimetableSubject?) {
        editingID = subject?.id
        draftName = subject?.name ?? ""
        draftTime = subject?.time ?? ""
        showEditor = true
    }

    private func saveDraft() {
        let name = draftName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            if let id = editingID, let i = subjects.firstIndex(where: { $0.id == id }) {
                subjects[i].name = name
                subjects[i].time = draftTime
            } else {
                subjects.append(TimetableSubject(name: name, time: draftTime))
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
                // 위 막대
                ZStack {
                    Text("시간표 등록").ds(17, .bold)
                    HStack {
                        Button { router.pop() } label: {
                            HStack(spacing: 2) {
                                Image("chevron-back-24")
                                Text("뒤로").ds(17, .medium)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Button { router.reset(to: .homeFirst) } label: {
                            Text("나중에 할게요").ds(17, .medium, .dsSub)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.leading, 36)
                    .padding(.trailing, 48)
                }
                .frame(width: portraitWidth, height: 56)
                .at(0, 24)

                // 안내
                VStack(alignment: .leading, spacing: 0) {
                    Text("에브리타임 시간표를\n올려 주세요").ds(34, .bold, line: 1.35)
                    Color.clear.frame(width: 1, height: 14)
                    Text("시간표가 있으면 수업 시간에 찍은 판서가\n그 과목 폴더로 자동 정리돼요.")
                        .ds(17, .regular, .dsSub, line: 1.55)
                    Color.clear.frame(width: 1, height: 36)
                    stepList(below: true)
                }
                .at(48, 112)

                dropZone(width: 738, height: 555, preview: CGSize(width: 560, height: 300))
                    .at(48, 462)

                Text("에브리타임은 공식 연동이 없어서 캡처 이미지로 시간표를 읽어요.")
                    .ds(14, .regular, .dsSub)
                    .at(48, 1037)

                // 아래 막대
                HStack {
                    Text(picked ? "이미지 1장 선택됨" : "선택된 이미지 없음").ds(17, .medium, .dsSub)
                    Spacer()
                    PrimaryButton(title: "다음", width: 280, enabled: picked) {
                        router.push(.timetableConfirm)
                    }
                }
                .padding(.horizontal, 48)
                .frame(width: portraitWidth, height: 104)
                .overlay(alignment: .top) { Rectangle().fill(Color.dsLine).frame(height: 1) }
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
                          detail: "시간표가 있으면 수업 시간에 찍은 판서가 그 과목 폴더로 자동 정리돼요.",
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

            Text("에브리타임은 공식 연동이 없어서 캡처 이미지로 시간표를 읽어요.").dsWrap(13, .regular, .dsSub)
        }, bottom: {
            NarrowBottomBar(caption: picked ? "이미지 1장 선택됨" : "선택된 이미지 없음") {
                PrimaryButton(title: "다음", width: inner < 440 ? 150 : 200, enabled: picked) {
                    router.push(.timetableConfirm)
                }
            }
        })
    }
}

extension TimetableConfirmScreen {
    func narrow(_ size: CGSize) -> some View {
        let inner = size.width - 40
        return NarrowPage(backTitle: "다시 올리기", barTitle: "시간표 확인", onBack: { router.backToUpload() },
                          title: "인식된 시간표를 확인해 주세요",
                          detail: "잘못 읽힌 과목은 눌러서 고칠 수 있어요.",
                          trailing: { EmptyView() }, content: {
            // 원본 캡처 (작게)
            ZStack(alignment: .topLeading) {
                Color.dsPanel
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    Text(day).ds(12, .medium, .dsSub).at(44 + CGFloat(index) * 50, 16)
                }
                block(x: 36, y: 98, opacity: 1)
                block(x: 86, y: 202, opacity: 0.85)
                block(x: 136, y: 46, opacity: 1)
                block(x: 186, y: 306, opacity: 0.85)
                block(x: 236, y: 98, opacity: 1)
                // 05 에서 고른 캡처가 있으면 그걸 보여 줘요.
                if let image = router.timetableImage {
                    Color.dsPanel
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(width: 300, height: 452)
                }
            }
            .frame(width: 300, height: 452, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .scaledBox(300, 452, to: 150)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 0) {
                if load == .loaded {
                    if subjects.isEmpty {
                        Text("과목을 찾지 못했어요. 과목 추가로 직접 넣어 주세요.").dsWrap(15, .regular, .dsSub).padding(.vertical, 14)
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
                PrimaryButton(title: "이대로 저장", width: inner < 440 ? 150 : 200, enabled: load == .loaded) { router.reset(to: .homeFirst) }
            }
        })
    }
}
