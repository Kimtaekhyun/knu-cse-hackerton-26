//
//  LoginScreen.swift
//  chalkdrop
//
//  04 로그인 — 피그마 "chalkdrop 로그인 v2" (188:656)
//  처음 뜰 때 왼쪽 그림 세 덩어리(칠판 → 카드 → 노트)가 위에서 차례로 떨어지고,
//  오른쪽 로고 · 제목 · 버튼이 이어서 떠올라요.
//  세로 화면은 피그마 "chalkdrop 로그인 v2 · 세로" (209:660): 그림이 위, 글자 · 버튼이 아래.
//

import SwiftUI

// MARK: - 색 (v2 피그마 값)

private extension Color {
    static let ink = Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255)        // #111111
    static let sub = Color(red: 0x6B / 255, green: 0x6B / 255, blue: 0x70 / 255)        // #6B6B70
    static let panel = Color(red: 0xF2 / 255, green: 0xF3 / 255, blue: 0xF5 / 255)      // #F2F3F5
    static let board = Color(red: 0x1E / 255, green: 0x24 / 255, blue: 0x22 / 255)      // #1E2422
    static let chalk = Color(red: 0xED / 255, green: 0xED / 255, blue: 0xE8 / 255)      // #EDEDE8
    static let kakao = Color(red: 0xFE / 255, green: 0xE5 / 255, blue: 0x00 / 255)      // #FEE500
    static let border = Color(red: 0xE5 / 255, green: 0xE5 / 255, blue: 0xEA / 255)     // #E5E5EA
}

private extension Text {
    /// v2 글자: 자간을 피그마 px 값 그대로 받아요.
    func v2(_ size: CGFloat, _ weight: Font.Weight, _ color: Color, tracking: CGFloat = 0) -> some View {
        font(.system(size: size, weight: weight)).tracking(tracking).foregroundStyle(color).fixedSize()
    }

    /// 칠판 손글씨 (Caveat Bold)
    func chalk(_ size: CGFloat) -> some View {
        font(.custom("Caveat", size: size).weight(.bold)).foregroundStyle(Color.chalk).fixedSize()
    }
}

private extension View {
    /// 등장 애니메이션 한 줄: `at` 초에 시작해 `dur` 초 동안 (dx, dy) 만큼 떨어진 곳에서 제자리로 와요.
    /// 스프링 이징은 살짝 넘쳤다 돌아와서 "툭" 떨어지는 느낌이 나요.
    func enter(_ t: Double, at: Double, dur: Double = 0.7, dx: CGFloat = 0, dy: CGFloat = 0,
               scale: CGFloat = 1, ease: Ease = .spring) -> some View {
        let p = tween(t, 0, 1, at, at + dur, ease)
        return opacity(tween(t, 0, 1, at, at + dur * 0.45, .out))
            .scaleEffect(scale + (1 - scale) * p)
            .offset(x: dx * (1 - p), y: dy * (1 - p))
    }
}

// MARK: - 04 로그인

struct LoginScreen: View {
    @Environment(Router.self) private var router
    /// 카카오 로그인 중이면 버튼을 막고 돌아가는 표시를 보여 줘요.
    @State private var loggingIn = false
    @State private var errorMessage: String?
    /// 이메일 로그인 · 회원가입 창 (#120)
    @State private var emailSheet: EmailSheet?
    /// 첫 카카오 로그인인데 같은 이메일의 이메일 계정이 있어요 (409 email_account_exists). 그 이메일
    @State private var duplicateEmail: String?

    /// 이메일 창을 열 때 미리 채울 값
    private struct EmailSheet: Identifiable {
        let id = UUID()
        var email = ""
    }

    var body: some View {
        Adaptive { wide } narrow: { narrow($0) }
            .alert("로그인하지 못했어요", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("이 이메일로 가입한 계정이 있어요", isPresented: Binding(
                get: { duplicateEmail != nil }, set: { if !$0 { duplicateEmail = nil } }
            ), presenting: duplicateEmail) { email in
                Button("이메일로 로그인") { emailSheet = EmailSheet(email: email) }
                Button("카카오로 새로 가입") { signupWithKakaoAnyway() }
                Button("취소", role: .cancel) {}
            } message: { email in
                Text("\(email)(으)로 이메일 가입한 계정이 있어요. 이메일로 로그인하면 그 계정의 시간표와 판서를 볼 수 있어요. 카카오로 새로 가입하면 별개의 빈 계정이 만들어져요.")
            }
            .sheet(item: $emailSheet) { sheet in
                EmailLoginSheet(email: sheet.email) { isNewUser in
                    emailSheet = nil
                    finish(isNewUser: isNewUser)
                } onKakao: {
                    loginWithKakao()
                }
            }
    }

    /// 이메일로 계속하기: 로그인 · 회원가입 창을 열어요.
    private func openEmail() { emailSheet = EmailSheet() }

    /// 로그인이 끝나면 아직 시간표를 등록하지 않은 사용자는 시간표 등록, 아니면 홈.
    /// `isNewUser` 는 서버가 정해요 (어느 학기에도 과목이 없으면 true, #150).
    private func finish(isNewUser: Bool) {
        router.timetableEditing = false
        router.reset(to: isNewUser ? .timetableUpload : .home)
    }

    /// 카카오 로그인 → 서버 토큰 저장 → 시간표가 없으면 시간표 등록, 아니면 홈
    private func loginWithKakao() {
        runKakao { try await AuthSession.shared.loginWithKakao() }
    }

    /// 같은 이메일 안내에서 "카카오로 새로 가입"을 골랐어요. 카카오 로그인을 다시 띄우지 않아요.
    private func signupWithKakaoAnyway() {
        runKakao { try await AuthSession.shared.signupWithKakaoAnyway() }
    }

    private func runKakao(_ login: @escaping () async throws -> Bool) {
        guard !loggingIn else { return }
        loggingIn = true
        Task {
            defer { loggingIn = false }
            do {
                finish(isNewUser: try await login())
            } catch KakaoLoginError.cancelled {
                // 사용자가 닫은 경우는 안내하지 않아요
            } catch let APIError.conflict(code, _, email) where code == AuthAPI.ConflictCode.emailAccountExists {
                duplicateEmail = email ?? ""
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var wide: some View {
        DesignCanvas {
            Motion(length: 2.2) { t in
                ZStack(alignment: .topLeading) {
                    illustration(t)
                        .enter(t, at: 0, dur: 0.5, scale: 0.97, ease: .out)
                        .at(24, 24)
                    intro(t)
                    buttons(t, width: 437).at(669, 593)
                    terms
                        .frame(width: 437)
                        .enter(t, at: 1.3, dur: 0.5, ease: .out)
                        .at(669, 749)
                }
                .frame(width: DS.width, height: DS.height, alignment: .topLeading)
            }
        }
    }

    // MARK: 오른쪽 소개

    /// 로고 왼쪽 위가 (x, y). 가로 화면은 (669, 88), 세로 화면은 (48, 600).
    private func intro(_ t: Double, x: CGFloat = 669, y: CGFloat = 88) -> some View {
        ZStack(alignment: .topLeading) {
            // 로고: 튀어나오면서 파란 선이 오른쪽으로 한 번 훑고 돌아와요.
            LogoMark(split: t < 0.85 ? tween(t, 512, 740, 0.45, 0.85, .inOut)
                                     : tween(t, 740, 512, 0.85, 1.35, .inOut))
                .frame(width: 56, height: 51)
                .enter(t, at: 0.25, dur: 0.6, scale: 0.5)
                .at(x, y)
            Text("chalkdrop").v2(26, .bold, .ink, tracking: -1.04)
                .enter(t, at: 0.4, dur: 0.5, dx: -14, ease: .out)
                .at(x + 66, y + 8)

            // 제목은 줄마다 따로 떠올라요 (줄 높이 1.25)
            VStack(alignment: .leading, spacing: 2) {
                Text("찍고, 끌어서,").v2(44, .bold, .ink, tracking: -1.32)
                    .enter(t, at: 0.5, dy: 28)
                Text("노트에 놓으세요.").v2(44, .bold, .ink, tracking: -1.32)
                    .enter(t, at: 0.62, dy: 28)
            }
            .at(x, y + 83)

            Text("칠판·프로젝터 사진에서 필기만 카드로 뽑아\n필기 앱으로 바로 옮길 수 있어요.")
                .v2(18, .medium, .sub, tracking: -0.36)
                .lineSpacing(7)
                .enter(t, at: 0.8, dur: 0.5, dy: 12, ease: .out)
                .at(x, y + 213)
        }
    }

    // MARK: 로그인 버튼

    private func buttons(_ t: Double, width: CGFloat) -> some View {
        VStack(spacing: 12) {
            loginButton(fill: .kakao, action: loginWithKakao) {
                if loggingIn {
                    ProgressView().tint(.black.opacity(0.85))
                } else {
                    Image("login-kakao")
                }
                Text("카카오로 계속하기").v2(17, .bold, .black.opacity(0.85), tracking: -0.34)
            }
            .enter(t, at: 1.05, dy: 30)
            loginButton(fill: .white, stroke: .border, action: openEmail) {
                Text("이메일로 계속하기").v2(17, .bold, .ink, tracking: -0.34)
            }
            .enter(t, at: 1.15, dy: 30)
        }
        .disabled(loggingIn)
        .frame(width: width)
    }

    private func loginButton<Label: View>(fill: Color, stroke: Color? = nil, action: @escaping () -> Void,
                                          @ViewBuilder label: () -> Label) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button(action: action) {
            HStack(spacing: 10) { label() }
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(fill, in: shape)
                .overlay { if let stroke { shape.strokeBorder(stroke, lineWidth: 1.5) } }
                .contentShape(shape)
        }
        .buttonStyle(.plain)
    }

    private var terms: some View {
        Text("계속하면 \(Text("이용약관").underline())과 \(Text("개인정보 처리방침").underline())에 동의하게 돼요.")
            .font(.system(size: 13))
            .tracking(-0.26)
            .foregroundStyle(Color.sub)
            .multilineTextAlignment(.center)
            .lineSpacing(5)
    }

    // MARK: 왼쪽 그림 패널 (549 × 786) · 세로 화면은 위쪽 (786 × 520)

    /// `portrait` 면 칠판은 왼쪽 위 그대로, 노트는 오른쪽으로 옮기고 카드를 노트 위 놓을 자리에 둬요.
    private func illustration(_ t: Double, portrait: Bool = false) -> some View {
        ZStack(alignment: .topLeading) {
            Color.panel

            HStack(spacing: 6) {
                Image("login-camera-16")
                Text("강의 사진").v2(13, .bold, .sub, tracking: -0.26)
            }
            .enter(t, at: 0.15, dur: 0.4, dx: -10, ease: .out)
            .at(58, 28)

            // 세 덩어리가 위에서 차례로 떨어져요: 칠판 → 끌려 나오는 카드 → 노트
            boardPhoto(t)
                .rotationEffect(.degrees(-4 - 8 * (1 - tween(t, 0, 1, 0.15, 0.95, .spring))))
                .enter(t, at: 0.15, dur: 0.8, dy: -120)
                .position(x: 216.2, y: 157.2)

            // 칠판에서 카드까지 이어지는 점선이 위에서 아래로 그려져요.
            let path = portrait ? CGSize(width: 200, height: 150) : CGSize(width: 130, height: 170)
            Image("login-drag-path")
                .resizable()
                .frame(width: path.width, height: path.height)
                .mask(alignment: .top) {
                    Rectangle().frame(height: path.height * tween(t, 0, 1, 1.15, 1.65, .inOut))
                }
                .at(portrait ? 200 : 232, portrait ? 170 : 168)

            notePage(t)
                .enter(t, at: 0.49, dur: 0.8, dy: -120)
                .at(portrait ? 382 : 120, portrait ? 160 : 440)

            dragCard(t)
                .rotationEffect(.degrees(5 + 10 * (1 - tween(t, 0, 1, 0.32, 1.12, .spring))))
                .enter(t, at: 0.32, dur: 0.8, dy: -120)
                .position(x: portrait ? 526 : 360, y: portrait ? 388.4 : 380.4)
        }
        .frame(width: portrait ? 786 : 549, height: portrait ? 520 : 786, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    /// 칠판 사진 (330 × 218, -4° 기울임)
    private func boardPhoto(_ t: Double) -> some View {
        ZStack(alignment: .topLeading) {
            Color.board
            Text("Merge Sort").underline().chalk(28).at(22, 10)
            Text("T(n) = 2T(n/2) + n").chalk(25).at(22, 56)

            // 추출 영역: 칠판이 자리 잡은 뒤 파란 상자가 톡 튀어나와요.
            Text("= O(n log n)").chalk(30)
                .padding(.horizontal, 10)
                .frame(height: 42)
                .background {
                    let box = RoundedRectangle(cornerRadius: 8, style: .continuous)
                    box.fill(Color.dsBlue.opacity(0.2 * tween(t, 0, 1, 0.95, 1.25)))
                        .overlay(box.strokeBorder(Color.dsBlue, lineWidth: 2.5)
                            .scaleEffect(tween(t, 0.7, 1, 0.95, 1.4, .bounce))
                            .opacity(tween(t, 0, 1, 0.95, 1.1)))
                }
                .at(14, 98)

            Text("depth = log n").chalk(22).at(22, 156)

            Image("login-recursion-tree").at(209, 22)
            Text("n").chalk(18).at(261.5, 26.5)
            Text("n/2").chalk(16).at(228, 96)
            Text("n/2").chalk(16).at(284, 96)
            ForEach([212.5, 244.5, 272.5, 302.5], id: \.self) { x in
                Text("n/4").chalk(12).at(x, 162.5)
            }
        }
        .frame(width: 330, height: 218, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 20, y: 20)
    }

    /// 칠판에서 끌려 나오는 수식 카드 (220 폭, 5° 기울임)
    private func dragCard(_ t: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("수식").v2(12, .bold, .dsBlue)
            Text("T(n) = O(n log n)").v2(22, .bold, .black)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: 220, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.dsBlue, lineWidth: 2))
        .overlay(alignment: .topLeading) {
            // 점선이 다 그려지면 손이 카드를 집어요.
            Image("login-drag-hand")
                .enter(t, at: 1.55, dur: 0.5, dx: 14, dy: 14, scale: 0.6)
                .offset(x: 198, y: 64)
        }
        .shadow(color: Color.dsBlue.opacity(0.22), radius: 12, y: 24)
    }

    /// 노트 페이지 (380 × 330)
    private func notePage(_ t: Double) -> some View {
        ZStack(alignment: .topLeading) {
            Color.white
            Text("알고리즘 · 11월 17일").v2(13, .bold, .sub, tracking: -0.26).at(18, 13)
            Image("login-note-lines").at(0, 44)

            Text("분할 정복: 나누고, 풀고, 합친다")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.black)
                .lineSpacing(3.75)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(width: 250)
                .background(Color(red: 0xF7 / 255, green: 0xF8 / 255, blue: 0xFA / 255),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(red: 0xEB / 255, green: 0xEB / 255, blue: 0xED / 255), lineWidth: 1))
                .enter(t, at: 1.1, dur: 0.5, dx: -18, ease: .out)
                .at(22, 122)

            // 놓을 자리: 점선 상자가 살짝 커지며 나타나요.
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.dsBlue, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                Text("여기에 놓기").v2(13, .bold, .dsBlue, tracking: -0.26)
            }
            .frame(width: 336, height: 72)
            .enter(t, at: 1.35, dur: 0.6, scale: 0.94)
            .at(22, 192)
        }
        .frame(width: 380, height: 330, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.ink.opacity(0.1), radius: 20, y: 20)
    }
}

// MARK: - 좁은 화면 (스플릿 뷰)

extension LoginScreen {
    /// 아이패드 세로처럼 넓은 세로 창은 피그마 세로 디자인, 스플릿 뷰처럼 좁은 창은 한 줄 배치.
    @ViewBuilder
    func narrow(_ size: CGSize) -> some View {
        if size.width >= 700 { portrait } else { compact(size) }
    }

    /// 세로 화면 — 피그마 "chalkdrop 로그인 v2 · 세로" (834 × 1194)
    private var portrait: some View {
        PortraitCanvas {
            Motion(length: 2.2) { t in
                ZStack(alignment: .topLeading) {
                    illustration(t, portrait: true)
                        .enter(t, at: 0, dur: 0.5, scale: 0.97, ease: .out)
                        .at(24, 24)
                    intro(t, x: 48, y: 600)
                    buttons(t, width: 738).at(48, 989)
                    terms
                        .frame(width: 738)
                        .enter(t, at: 1.3, dur: 0.5, ease: .out)
                        .at(48, 1145)
                }
                .frame(width: portraitWidth, height: portraitHeight, alignment: .topLeading)
            }
        }
    }

    /// 스플릿 뷰처럼 좁은 창
    private func compact(_ size: CGSize) -> some View {
        let inner = min(size.width - 40, 437)
        return Motion(length: 2.0) { t in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        LogoMark(split: t < 0.75 ? tween(t, 512, 740, 0.35, 0.75, .inOut)
                                                 : tween(t, 740, 512, 0.75, 1.25, .inOut))
                            .frame(width: 44, height: 40)
                            .enter(t, at: 0.1, dur: 0.6, scale: 0.5)
                        Text("chalkdrop").v2(22, .bold, .ink, tracking: -0.88)
                            .enter(t, at: 0.25, dur: 0.5, dx: -12, ease: .out)
                    }
                    Color.clear.frame(height: 36)
                    Text("찍고, 끌어서,").v2(34, .bold, .ink, tracking: -1.02)
                        .enter(t, at: 0.35, dy: 24)
                    Text("노트에 놓으세요.").v2(34, .bold, .ink, tracking: -1.02)
                        .enter(t, at: 0.47, dy: 24)
                    Color.clear.frame(height: 16)
                    Text("칠판·프로젝터 사진에서 필기만 카드로 뽑아 필기 앱으로 바로 옮길 수 있어요.")
                        .font(.system(size: 16, weight: .medium))
                        .tracking(-0.32)
                        .foregroundStyle(Color.sub)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                        .enter(t, at: 0.6, dur: 0.5, dy: 12, ease: .out)
                    Color.clear.frame(height: 40)
                    buttons(t, width: inner)
                    Color.clear.frame(height: 20)
                    terms
                        .frame(width: inner)
                        .enter(t, at: 1.2, dur: 0.5, ease: .out)
                }
                .frame(width: inner, alignment: .leading)
                .padding(.vertical, 48)
                // 내용이 창보다 짧으면 위아래 가운데에 둬요 (길면 지금처럼 스크롤).
                .frame(maxWidth: .infinity, minHeight: size.height)
            }
        }
        .background(Color.white.ignoresSafeArea())
    }
}
