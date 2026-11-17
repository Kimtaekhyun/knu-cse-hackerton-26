//
//  AccountScreen.swift
//  chalkdrop
//
//  23 내 계정
//

import SwiftUI

struct AccountScreen: View {
    @Environment(Router.self) private var router
    @State private var classAlert = true
    @State private var pendingAlert = true
    @AppStorage("profileName") private var name = "김마린"
    @AppStorage("profileSchool") private var school = "경북대학교"
    /// 촬영 화면이 처음 열릴 때 고를 값 (0 빔 화면 · 1 칠판 / 0 빨간 펜 · 1 검은 펜)
    @AppStorage(CaptureDefaults.modeKey) private var captureMode = 0
    @AppStorage(CaptureDefaults.penKey) private var penColor = 0
    @State private var editingProfile = false
    @State private var draftName = ""
    @State private var draftSchool = ""
    @State private var confirmingDelete = false

    var body: some View {
        Adaptive { wide } narrow: { narrow($0) }
            .alert("프로필 수정", isPresented: $editingProfile) {
                TextField("이름", text: $draftName)
                TextField("학교", text: $draftSchool)
                Button("취소", role: .cancel) {}
                Button("저장") {
                    let newName = draftName.trimmingCharacters(in: .whitespaces)
                    if !newName.isEmpty { name = newName }
                    school = draftSchool.trimmingCharacters(in: .whitespaces)
                }
            }
            .alert("계정을 삭제할까요?", isPresented: $confirmingDelete) {
                Button("취소", role: .cancel) {}
                Button("삭제", role: .destructive) { router.reset(to: .login) }
            } message: {
                Text("찍은 판서와 카드가 모두 지워지고 되돌릴 수 없어요.")
            }
    }

    private var wide: some View {
        DesignCanvas {
            NavBar(backTitle: "chalkdrop", title: "", onBack: { router.pop() })
            Text("내 계정").ds(34, .bold).at(48, 92)

            profileCard().at(48, 164)

            settings(710).at(436, 104)
        }
    }

    /// 설정 묶음 네 개
    private func settings(_ width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            group("학기", width) {
                row("현재 학기", value: "2026년 2학기", chevron: true) { router.push(.allSemesters) }
                divider
                row("시간표 수정", chevron: true) { router.push(.timetableConfirm) }
            }
            group("촬영", width) {
                pickerRow("기본 촬영 모드", options: CaptureDefaults.modes, selection: $captureMode)
                divider
                pickerRow("기본 펜 색", options: CaptureDefaults.pens, selection: $penColor)
            }
            group("알림", width) {
                toggleRow("수업 시작 알림", isOn: $classAlert)
                divider
                toggleRow("옮기지 않은 판서 알림", isOn: $pendingAlert)
            }
            group("계정", width) {
                row("로그아웃") { router.reset(to: .login) }
                divider
                row("계정 삭제", color: .dsSub) { confirmingDelete = true }
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
            Text(school).ds(15, .regular, .dsSub)
            Color.clear.frame(width: 1, height: 4)
            Text("카카오 계정으로 로그인됨").ds(13, .regular, .dsSub)
            Color.clear.frame(width: 1, height: 20)
            SecondaryButton(title: "프로필 수정", width: width - 48) {
                draftName = name
                draftSchool = school
                editingProfile = true
            }
            Color.clear.frame(width: 1, height: 24)
            HStack(alignment: .top) {
                stat("28", "찍은 판서")
                Spacer()
                stat("96", "정리된 카드")
                Spacer()
                stat("81", "옮긴 카드")
            }
        }
        .padding(.top, 28)
        .padding(.bottom, 24)
        .padding(.horizontal, 24)
        .frame(width: width)
        .background(Color.dsPanel)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(.black)
            Text(label).ds(12, .medium, .dsSub)
        }
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

    /// 누르면 고를 수 있는 메뉴가 뜨는 줄 (오른쪽에 지금 값)
    private func pickerRow(_ title: String, options: [String], selection: Binding<Int>) -> some View {
        Menu {
            Picker(title, selection: selection) {
                ForEach(options.indices, id: \.self) { Text(options[$0]).tag($0) }
            }
        } label: {
            HStack {
                Text(title).ds(16, .medium)
                Spacer()
                HStack(spacing: 4) {
                    Text(options[min(selection.wrappedValue, options.count - 1)]).ds(16, .regular, .dsSub)
                    Image("chevron-right-18")
                }
            }
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title).ds(16, .medium)
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isOn.wrappedValue.toggle() }
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
            settings(inner).padding(.top, 8)
        }, bottom: { EmptyView() })
    }
}
