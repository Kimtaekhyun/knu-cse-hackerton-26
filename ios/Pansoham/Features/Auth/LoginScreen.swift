//
//  LoginScreen.swift
//  chalkdrop
//
//  04 로그인
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
                    Text("chalkdrop").ds(44, .bold, .white)
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
                Text("chalkdrop").ds(34, .bold, .white)
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
