//
//  AccountScreen.swift
//  chalkdrop
//
//  23 내 계정
//

import SwiftUI

struct AccountScreen: View {
    @Environment(Router.self) private var router
    /// 시험 기간 알림 · 옮기지 않은 판서 알림 (로그인했으면 서버 값, #109)
    @State private var examAlert = true
    @State private var pendingAlert = true
    @State private var settingsError: String?
    /// 알림 권한을 거절한 채 스위치를 켰을 때 (#125)
    @State private var notifyDenied = false
    @AppStorage("profileName") private var name = "김마린"
    @AppStorage("profileSchool") private var school = "경북대학교"
    @State private var editingProfile = false
    @State private var draftName = ""
    /// 서버에 저장된 학교 (로그인했을 때, #105)
    @State private var liveSchool: String?
    @State private var pickingSchool = false
    @State private var savingSchool = false
    @State private var schoolError: String?
    @State private var nameError: String?
    @State private var confirmingDelete = false
    @State private var confirmingLogout = false

    private var isLive: Bool { AuthSession.shared.isLoggedIn }
    /// 화면에 보여 줄 학교: 로그인했으면 서버 값, 아니면 기기에 저장한 값. 없으면 nil
    private var shownSchool: String? {
        let value = isLive ? liveSchool : school
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    var body: some View {
        Adaptive { wide } narrow: { narrow($0) }
            .overlay {
                if pickingSchool {
                    ZStack {
                        Color.black.opacity(0.2).ignoresSafeArea()
                            .onTapGesture { if !savingSchool { closePicker() } }
                        GeometryReader { geo in
                            SchoolPicker(current: shownSchool, saving: savingSchool, onCancel: closePicker, onSave: saveSchool)
                                .scaleEffect(min(1, (geo.size.width - 32) / 540))
                                .frame(maxWidth: .infinity)
                                .padding(.top, min(150, geo.size.height * 0.15))
                        }
                    }
                    .transition(.opacity)
                }
            }
            .task {
                guard isLive, let me = try? await AuthAPI.me() else { return }
                liveSchool = me.school
                // 기기에 둔 이름을 서버 이름으로 맞춰요 (#122)
                name = me.name
                if let settings = me.settings {
                    examAlert = settings.notifyExam
                    pendingAlert = settings.notifyUnmoved
                    LocalNotifications.shared.apply(cleanup: settings.notifyUnmoved, exam: settings.notifyExam)
                }
            }
            .alert("알림이 꺼져 있어요", isPresented: $notifyDenied) {
                Button("취소", role: .cancel) {}
                Button("설정 열기") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .keyboardShortcut(.defaultAction)
            } message: {
                Text("설정에서 판서함 알림을 켜 주세요.")
            }
            .alert("알림 설정을 저장하지 못했어요", isPresented: Binding(get: { settingsError != nil }, set: { if !$0 { settingsError = nil } })) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(settingsError ?? "")
            }
            .alert("이름을 저장하지 못했어요", isPresented: Binding(get: { nameError != nil }, set: { if !$0 { nameError = nil } })) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(nameError ?? "")
            }
            .alert("학교를 저장하지 못했어요", isPresented: Binding(get: { schoolError != nil }, set: { if !$0 { schoolError = nil } })) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(schoolError ?? "")
            }
            .alert("프로필 수정", isPresented: $editingProfile) {
                TextField("이름", text: $draftName)
                Button("취소", role: .cancel) {}
                Button("저장") {
                    let newName = draftName.trimmingCharacters(in: .whitespaces)
                    if !newName.isEmpty, newName != name { saveName(newName) }
                }
            }
            .alert("로그아웃할까요?", isPresented: $confirmingLogout) {
                Button("취소", role: .cancel) {}
                Button("로그아웃", role: .destructive) { logout() }
            } message: {
                Text("다시 카카오로 로그인하면 시간표와 판서를 그대로 볼 수 있어요.")
            }
            .alert("계정을 삭제할까요?", isPresented: $confirmingDelete) {
                Button("취소", role: .cancel) {}
                // 서버 계정 삭제 API는 아직 없어요 (#58 범위 밖). 지금은 로그아웃만 해요.
                Button("삭제", role: .destructive) { logout() }
            } message: {
                Text("찍은 판서와 카드가 모두 지워지고 되돌릴 수 없어요.")
            }
    }

    /// 알림 토글 저장: 로그인했으면 `PATCH /me/settings`, 실패하면 원래 값으로 되돌려요.
    private func saveSettings(exam: Bool? = nil, unmoved: Bool? = nil) {
        guard isLive else { return }
        Task {
            // 켤 때 알림 권한을 거절해 둔 상태면 설정 앱 안내 (#125)
            if exam == true || unmoved == true, await LocalNotifications.shared.isDenied() { notifyDenied = true }
            do {
                let saved = try await AuthAPI.updateSettings(notifyUnmoved: unmoved, notifyExam: exam)
                examAlert = saved.notifyExam
                pendingAlert = saved.notifyUnmoved
                let notifications = LocalNotifications.shared
                notifications.apply(cleanup: saved.notifyUnmoved, exam: saved.notifyExam)
                // 다시 켰으면 지금 데이터로 다시 예약
                if exam == true {
                    notifications.scheduleExam(HomeStore.shared.home?.exam,
                                               captures: SemesterStore.shared.subjects.map(\.captureCount).reduce(0, +))
                }
                if unmoved == true { notifications.unsortedChanged(count: SubjectCaptures.unsorted.items.count) }
            } catch {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if let exam { examAlert = !exam }
                    if let unmoved { pendingAlert = !unmoved }
                }
                settingsError = error.localizedDescription
            }
        }
    }

    private func closePicker() {
        withAnimation(.easeOut(duration: 0.2)) { pickingSchool = false }
    }

    /// 이름 저장: 로그인했으면 `PATCH /me`, 아니면 기기에만. 실패하면 원래 이름 그대로 (#122)
    private func saveName(_ value: String) {
        guard isLive else { name = value; return }
        Task {
            do {
                name = try await AuthAPI.updateName(value).name
            } catch {
                nameError = error.localizedDescription
            }
        }
    }

    /// 학교 저장: 로그인했으면 `PATCH /me`, 아니면 기기에만. 빈 글자면 학교 비우기
    private func saveSchool(_ value: String) {
        guard isLive else {
            school = value
            closePicker()
            return
        }
        savingSchool = true
        Task {
            defer { savingSchool = false }
            do {
                liveSchool = try await AuthAPI.updateSchool(value).school
                closePicker()
            } catch {
                schoolError = error.localizedDescription
            }
        }
    }

    /// 프로필 카드 아래 "학교" 칸 (23-3 · 23-5)
    private func schoolGroup(_ width: CGFloat) -> some View {
        group("학교", width) {
            Button { withAnimation(.easeOut(duration: 0.2)) { pickingSchool = true } } label: {
                HStack {
                    if let shownSchool {
                        Text(shownSchool).ds(16, .medium)
                        Spacer()
                        Text("변경").ds(16, .regular, .dsSub)
                    } else {
                        Text("학교를 입력해 주세요").ds(16, .medium, .dsBlue)
                        Spacer()
                    }
                    Image("chevron-right-18")
                }
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// 저장된 로그인 토큰과 카카오 로그인을 지우고 로그인 화면으로
    private func logout() {
        AuthSession.shared.logout()
        router.reset(to: .login, direction: .fade)
    }

    private var wide: some View {
        DesignCanvas {
            NavBar(backTitle: "chalkdrop", title: "", onBack: { router.pop() })
            Text("내 계정").ds(34, .bold).at(48, 92)

            profileCard().at(48, 164)
            schoolGroup(340).at(48, 560)

            settings(710).at(436, 104)
        }
    }

    /// 설정 묶음 세 개
    private func settings(_ width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            group("학기", width) {
                row("현재 학기", value: SemesterStore.shared.current?.label ?? (SemesterStore.shared.isLive ? "없음" : "2026년 2학기"), chevron: true) { router.push(.allSemesters) }
                divider
                row("시간표 수정", chevron: true) {
                    // 06 이 서버의 현재 학기 과목을 불러와요. 학기는 고정 (#146)
                    router.startTimetableEdit()
                }
            }
            group("알림", width) {
                toggleRow("시험 기간 알림", isOn: $examAlert) { saveSettings(exam: $0) }
                divider
                toggleRow("정리 알림", isOn: $pendingAlert) { saveSettings(unmoved: $0) }
            }
            group("계정", width) {
                row("로그아웃") { confirmingLogout = true }
                divider
                row("계정 삭제", color: .red) { confirmingDelete = true }
            }
        }
    }

    // MARK: 프로필 카드

    private func profileCard(_ width: CGFloat = 340) -> some View {
        VStack(spacing: 0) {
            Text(String(name.prefix(1))).ds(36, .bold, .white)
                .frame(width: 88, height: 88)
                .background(Color.black)
                .clipShape(Circle())
            Color.clear.frame(width: 1, height: 16)
            Text(name)
                .font(.system(size: 24, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(.black)
            Color.clear.frame(width: 1, height: 4)
            Text(shownSchool ?? "학교 미입력").ds(15, .regular, .dsSub)
            Color.clear.frame(width: 1, height: 20)
            SecondaryButton(title: "프로필 수정", width: width - 48) {
                draftName = name
                editingProfile = true
            }
        }
        .padding(.horizontal, 24)
        // 통계 숫자를 뺀 뒤에도 카드 높이(피그마 368)는 그대로 두고, 남은 내용을 위아래 가운데에 둬요.
        .frame(width: width, height: 368)
        .background(Color.dsPanel)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    // MARK: 설정 묶음

    private func group<Content: View>(_ title: String, _ width: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).ds(13, .bold, .dsSub)
            VStack(spacing: 0) { content() }
                .padding(.leading, 20)
                .padding(.trailing, 16)
                .frame(width: width)
                .background(Color.dsPanel)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.black.opacity(0.07)).frame(height: 1)
    }

    private func row(_ title: String, value: String? = nil, chevron: Bool = false,
                     color: Color = .black, action: @escaping () -> Void = {}) -> some View {
        Button(action: action) {
            HStack {
                Text(title).ds(16, .medium, color)
                Spacer()
                HStack(spacing: 4) {
                    if let value { Text(value).ds(16, .regular, .dsSub) }
                    if chevron { Image("chevron-right-18") }
                }
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>, onChange: @escaping (Bool) -> Void = { _ in }) -> some View {
        HStack {
            Text(title).ds(16, .medium)
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isOn.wrappedValue.toggle() }
                onChange(isOn.wrappedValue)
            } label: {
                if isOn.wrappedValue {
                    Image("toggle-on")
                } else {
                    // 꺼진 모양 (피그마에는 켜진 모양만 있어서 같은 크기로 그렸어요)
                    Capsule().fill(Color.black.opacity(0.14))
                        .frame(width: 46, height: 28)
                        .overlay(alignment: .leading) {
                            Circle().fill(Color.white).frame(width: 22, height: 22).padding(.leading, 3)
                        }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 13)
    }
}

// MARK: - 좁은 화면 (스플릿 뷰)

extension AccountScreen {
    func narrow(_ size: CGSize) -> some View {
        let inner = size.width - 40
        return NarrowPage(backTitle: "chalkdrop", onBack: { router.pop() }, title: "내 계정",
                          trailing: { EmptyView() }, content: {
            profileCard(inner)
            schoolGroup(inner)
            settings(inner).padding(.top, 8)
        }, bottom: { EmptyView() })
    }
}
