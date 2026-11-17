//
//  SetupScreens.swift
//  판서함
//
//  04 로그인 · 05 시간표 업로드 · 06 시간표 확인
//

import SwiftUI

// MARK: - 04 로그인

struct LoginScreen: View {
    @Environment(Router.self) private var router

    var body: some View {
        Adaptive { wide } narrow: { narrow($0) }
    }

    private var wide: some View {
        DesignCanvas {
            // 앱 소개 (왼쪽 검은 면)
            ZStack(alignment: .topLeading) {
                Color.black
                VStack(spacing: 20) {
                    Image("app-logo")
                        .resizable()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    Text("앱 이름").ds(44, .bold, .white)
                    Text("찍으면 정리되는 판서 노트").ds(17, .regular, .dsSub)
                }
                .frame(width: 597)
                .at(0, 297)
            }
            .frame(width: 597, height: 834, alignment: .topLeading)

            // 로그인 버튼 영역
            VStack(alignment: .leading, spacing: 12) {
                Text("시작하기").ds(34, .bold)
                Text("로그인하고 수업 판서를\n과목별로 모아 보세요").ds(17, .regular, .dsSub, line: 1.55)
                Color.clear.frame(width: 1, height: 28)

                loginButton(icon: "kakao", title: "카카오로 계속하기", text: .black, fill: .dsKakao)
                loginButton(icon: "apple", title: "Apple로 계속하기", text: .white, fill: .black)

                Button { next() } label: {
                    Text("이메일로 계속하기").ds(15, .medium)
                        .frame(width: 380)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Color.clear.frame(width: 1, height: 12)
                Text("계속하면 이용약관과 개인정보처리방침에 동의하게 돼요.\n처음이면 시간표 등록으로 이어져요.")
                    .ds(13, .regular, .dsSub, line: 1.5)
            }
            .at(705.5, 235.5)
        }
    }

    private func next() { router.push(.timetableUpload) }

    private func loginButton(icon: String, title: String, text: Color, fill: Color, width: CGFloat = 380) -> some View {
        Button { next() } label: {
            HStack(spacing: 8) {
                Image(icon)
                Text(title).ds(17, .bold, text)
            }
            .frame(width: width, height: 56)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 05 시간표 업로드

struct TimetableUploadScreen: View {
    @Environment(Router.self) private var router
    @State private var picked = false

    private let steps = [
        "에브리타임 앱에서 시간표 탭 열기",
        "시간표 전체가 보이게 화면 캡처",
        "오른쪽에서 캡처 이미지 고르기",
    ]

    var body: some View {
        Adaptive { wide } narrow: { narrow($0) }
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

                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(spacing: 14) {
                            Text("\(index + 1)").ds(14, .bold, .white)
                                .frame(width: 28, height: 28)
                                .background(Color.black)
                                .clipShape(Circle())
                            Text(step).ds(17, .medium)
                        }
                    }
                }

                Color.clear.frame(width: 1, height: 40)
                Text("에브리타임은 공식 연동이 없어서 캡처 이미지로 시간표를 읽어요.")
                    .ds(14, .regular, .dsSub)
            }
            .at(48, 112)

            // 업로드 영역
            VStack(spacing: 0) {
                Image("plus-28")
                    .frame(width: 72, height: 72)
                    .background(Color.white)
                    .clipShape(Circle())
                Color.clear.frame(width: 1, height: 24)
                Text(picked ? "시간표 캡처 1장을 골랐어요" : "시간표 캡처를 여기에 끌어다 놓으세요").ds(20, .bold)
                Color.clear.frame(width: 1, height: 8)
                Text("PNG, JPG · 한 장").ds(15, .regular, .dsSub)
                Color.clear.frame(width: 1, height: 28)
                SecondaryButton(title: picked ? "다른 이미지 선택" : "사진 앨범에서 선택") { picked = true }
            }
            .frame(width: 527, height: 586)
            .background(Color.dsPanel)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(Color.black.opacity(0.14), style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
            )
            .at(619, 112)

            BottomBar(caption: picked ? "이미지 1장 선택됨" : "선택된 이미지 없음") {
                PrimaryButton(title: "다음", width: 280, enabled: picked) {
                    router.push(.timetableConfirm)
                }
            }
        }
    }
}

// MARK: - 06 시간표 확인

struct TimetableConfirmScreen: View {
    @Environment(Router.self) private var router
    @State private var subjects = SampleData.timetable

    private let days = ["월", "화", "수", "목", "금"]

    var body: some View {
        Adaptive { wide } narrow: { narrow($0) }
    }

    private var wide: some View {
        DesignCanvas {
            NavBar(backTitle: "다시 올리기", title: "시간표 확인", onBack: { router.pop() })

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
            }
            .frame(width: 300, height: 452, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .at(48, 210)

            // 시간표 목록
            VStack(alignment: .leading, spacing: 0) {
                ForEach(subjects) { subject in
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(subject.name).ds(17, .bold)
                            Text(subject.time).ds(15, .regular, .dsSub)
                        }
                        Spacer(minLength: 0)
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
                    withAnimation(.easeInOut(duration: 0.2)) { subjects = SampleData.timetable }
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
            }
            .at(380, 210)

            BottomBar(caption: "과목 \(subjects.count)개를 찾았어요") {
                PrimaryButton(title: "이대로 저장", width: 280) {
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
}

// MARK: - 좁은 화면 (스플릿 뷰)

extension LoginScreen {
    func narrow(_ size: CGSize) -> some View {
        let inner = min(size.width - 40, 380)
        return VStack(spacing: 0) {
            // 앱 소개 (위쪽 검은 면)
            VStack(spacing: 14) {
                Image("app-logo")
                    .resizable()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                Text("앱 이름").ds(34, .bold, .white)
                Text("찍으면 정리되는 판서 노트").ds(15, .regular, .dsSub)
            }
            .frame(maxWidth: .infinity)
            .frame(height: size.height * 0.38)
            .background(Color.black.ignoresSafeArea(edges: .top))

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("시작하기").ds(28, .bold)
                    Text("로그인하고 수업 판서를 과목별로 모아 보세요").dsWrap(15, .regular, .dsSub)
                    Color.clear.frame(width: 1, height: 12)
                    loginButton(icon: "kakao", title: "카카오로 계속하기", text: .black, fill: .dsKakao, width: inner)
                    loginButton(icon: "apple", title: "Apple로 계속하기", text: .white, fill: .black, width: inner)
                    Button { router.push(.timetableUpload) } label: {
                        Text("이메일로 계속하기").ds(15, .medium)
                            .frame(width: inner, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Text("계속하면 이용약관과 개인정보처리방침에 동의하게 돼요. 처음이면 시간표 등록으로 이어져요.")
                        .dsWrap(13, .regular, .dsSub)
                }
                .frame(width: inner, alignment: .leading)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.white.ignoresSafeArea())
    }
}

extension TimetableUploadScreen {
    func narrow(_ size: CGSize) -> some View {
        let inner = size.width - 40
        return NarrowPage(backTitle: "뒤로", barTitle: "시간표 등록", onBack: { router.pop() },
                          title: "에브리타임 시간표를 올려 주세요",
                          detail: "시간표가 있으면 수업 시간에 찍은 판서가 그 과목 폴더로 자동 정리돼요.",
                          trailing: {
            Button { router.reset(to: .homeFirst) } label: { Text("나중에 할게요").ds(15, .medium, .dsSub) }
                .buttonStyle(.plain)
        }, content: {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
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
                Image("plus-28")
                    .frame(width: 64, height: 64)
                    .background(Color.white)
                    .clipShape(Circle())
                Color.clear.frame(width: 1, height: 18)
                Text(picked ? "시간표 캡처 1장을 골랐어요" : "시간표 캡처를 여기에 끌어다 놓으세요")
                    .dsWrap(18, .bold)
                    .multilineTextAlignment(.center)
                Color.clear.frame(width: 1, height: 6)
                Text("PNG, JPG · 한 장").ds(14, .regular, .dsSub)
                Color.clear.frame(width: 1, height: 20)
                SecondaryButton(title: picked ? "다른 이미지 선택" : "사진 앨범에서 선택", width: min(220, inner - 48)) { picked = true }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 36)
            .frame(width: inner)
            .background(Color.dsPanel)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.black.opacity(0.14), style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
            )

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
        return NarrowPage(backTitle: "다시 올리기", barTitle: "시간표 확인", onBack: { router.pop() },
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
            }
            .frame(width: 300, height: 452, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .scaledBox(300, 452, to: 150)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(subjects) { subject in
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(subject.name).ds(17, .bold)
                            Text(subject.time).ds(15, .regular, .dsSub)
                        }
                        Spacer(minLength: 0)
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
                    withAnimation(.easeInOut(duration: 0.2)) { subjects = SampleData.timetable }
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
            }
        }, bottom: {
            NarrowBottomBar(caption: "과목 \(subjects.count)개를 찾았어요") {
                PrimaryButton(title: "이대로 저장", width: inner < 440 ? 150 : 200) { router.reset(to: .homeFirst) }
            }
        })
    }
}
