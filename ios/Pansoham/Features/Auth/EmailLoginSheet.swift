//
//  EmailLoginSheet.swift
//  chalkdrop
//
//  로그인 화면(04) "이메일로 계속하기" 창: 이메일 로그인 · 회원가입 (#120).
//  피그마 화면이 없어서 과목 추가 창(SubjectEditorSheet)처럼 기본 폼으로 만들었어요.
//  입력 검사는 서버 규칙과 같아요 (이메일 형식 · 비밀번호 8~64자 · 이름 1~50자).
//  가입하면 바로 로그인하지 않고 "회원가입 완료"를 띄운 뒤 로그인 탭으로 바꿔요 (이메일은 채운 채로).
//  가입 직후 그 이메일로 처음 로그인하면 시간표 등록(05)으로 가요.
//

import SwiftUI

struct EmailLoginSheet: View {
    enum Mode: String, CaseIterable {
        case login = "로그인"
        case signup = "회원가입"
    }

    /// 로그인 · 가입이 끝났어요. 처음 가입이면 true
    let onDone: (_ isNewUser: Bool) -> Void
    /// "카카오로 가입한 이메일이에요" 안내에서 카카오로 로그인을 골랐어요
    let onKakao: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode
    @State private var email: String
    @State private var password = ""
    @State private var passwordAgain = ""
    @State private var name = ""
    @State private var working = false
    @State private var failure: String?
    /// 가입하려는 이메일이 카카오 계정의 것이에요 (409 kakao_account_exists)
    @State private var kakaoNotice: String?
    /// "회원가입 완료" 안내
    @State private var signedUp = false
    /// 이 창에서 방금 가입한 이메일. 이 이메일로 로그인하면 처음 쓰는 사용자로 보고 시간표 등록으로 보내요.
    @State private var signedUpEmail: String?
    @FocusState private var passwordFocused: Bool

    init(mode: Mode = .login, email: String = "",
         onDone: @escaping (_ isNewUser: Bool) -> Void, onKakao: @escaping () -> Void) {
        _mode = State(initialValue: mode)
        _email = State(initialValue: email)
        self.onDone = onDone
        self.onKakao = onKakao
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("방식", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    TextField("이메일", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField(mode == .signup ? "비밀번호 (8~64자)" : "비밀번호", text: $password)
                        .textContentType(mode == .signup ? .newPassword : .password)
                        .focused($passwordFocused)
                    if mode == .signup {
                        SecureField("비밀번호 확인", text: $passwordAgain)
                            .textContentType(.newPassword)
                    }
                } footer: {
                    if let problem { Text(problem).foregroundStyle(.red) }
                }

                if mode == .signup {
                    Section("이름") {
                        TextField("내 계정에 보일 이름", text: $name)
                            .textContentType(.name)
                    }
                }

                Section {
                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if working { ProgressView() } else { Text(mode.rawValue).bold() }
                            Spacer()
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
            .navigationTitle("이메일로 계속하기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
            }
            .disabled(working)
            .alert(mode == .signup ? "가입하지 못했어요" : "로그인하지 못했어요",
                   isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("확인", role: .cancel) {}
            } message: {
                Text(failure ?? "")
            }
            .alert("카카오로 가입한 이메일이에요",
                   isPresented: Binding(get: { kakaoNotice != nil }, set: { if !$0 { kakaoNotice = nil } })) {
                Button("취소", role: .cancel) {}
                Button("카카오로 로그인") {
                    dismiss()
                    onKakao()
                }
            } message: {
                Text(kakaoNotice ?? "")
            }
            .alert("회원가입 완료", isPresented: $signedUp) {
                Button("로그인하기") { passwordFocused = true }
            } message: {
                Text("가입한 이메일과 비밀번호로 로그인해 주세요.")
            }
        }
    }

    // MARK: 입력 검사 (서버와 같은 규칙)

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespaces) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    /// 글자 수는 서버(파이썬 len)처럼 유니코드 코드 포인트로 세요.
    /// 화면 글자 수(`count`)로 세면 이모지 · 국기처럼 한 글자가 여러 코드 포인트인 입력을 앱은 통과시키고 서버는 거절해요.
    private func length(_ text: String) -> Int { text.unicodeScalars.count }

    private var emailLooksValid: Bool {
        length(trimmedEmail) <= 254 && trimmedEmail.wholeMatch(of: /[^@\s]+@[^@\s]+\.[^@\s]+/) != nil
    }

    /// 입력칸 아래 빨간 안내. 아직 입력하지 않은 칸은 탓하지 않아요.
    private var problem: String? {
        if !email.isEmpty, mode == .signup, !emailLooksValid { return "이메일 형식이 맞지 않아요." }
        guard mode == .signup else { return nil }
        if !password.isEmpty, !(8...64).contains(length(password)) { return "비밀번호는 8~64자로 입력해 주세요." }
        if !passwordAgain.isEmpty, passwordAgain != password { return "비밀번호가 서로 달라요." }
        if length(trimmedName) > 50 { return "이름은 50자까지 입력할 수 있어요." }
        return nil
    }

    private var canSubmit: Bool {
        guard !working, !trimmedEmail.isEmpty, !password.isEmpty, length(password) <= 64 else { return false }
        guard mode == .signup else { return true }
        return emailLooksValid && length(password) >= 8 && passwordAgain == password
            && !trimmedName.isEmpty && length(trimmedName) <= 50
    }

    // MARK: 보내기

    private func submit() {
        guard canSubmit else { return }
        working = true
        Task {
            defer { working = false }
            do {
                switch mode {
                case .login:
                    try await AuthSession.shared.loginWithEmail(email: trimmedEmail, password: password)
                    onDone(signedUpEmail == trimmedEmail.lowercased())
                case .signup:
                    try await AuthSession.shared.signupWithEmail(email: trimmedEmail, password: password,
                                                                 name: trimmedName)
                    showLogin()
                }
            } catch let APIError.conflict(code, message, _) where code == AuthAPI.ConflictCode.kakaoAccountExists {
                kakaoNotice = message
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    /// 가입이 끝나면 로그인 탭으로 바꾸고 이메일만 남겨요. 비밀번호는 다시 입력해요.
    private func showLogin() {
        signedUpEmail = trimmedEmail.lowercased()
        mode = .login
        password = ""
        passwordAgain = ""
        name = ""
        signedUp = true
    }
}
