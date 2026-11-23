//
//  AuthSession.swift
//  판서함
//
//  로그인 상태. 우리 서버 토큰(JWT)을 Keychain에 두고, 모든 API 요청에 붙여요 (`APIClient`).
//  - 로그인: 카카오 토큰 → 서버 `POST /auth/kakao` → 우리 토큰 저장
//  - 이메일: 서버 `POST /auth/email/signup` · `/auth/email/login` → 우리 토큰 저장 (#120)
//  - 앱 시작: 저장된 토큰이 있으면 바로 홈으로 가고, `GET /me` 로 아직 유효한지 확인
//  - 토큰을 붙인 요청이 401이면 토큰을 지우고 로그인 화면으로 (`ContentView` 가 `isLoggedIn` 을 보고 이동)
//

import Foundation

@Observable
final class AuthSession {
    static let shared = AuthSession()

    private static let tokenKey = "accessToken"

    /// 우리 서버 토큰. 없으면 로그인 전이에요.
    private(set) var accessToken: String?
    /// 마지막으로 받은 내 정보 (앱을 켠 뒤 `/me` 확인 전에는 비어 있을 수 있어요)
    private(set) var user: AuthAPI.UserDTO?

    var isLoggedIn: Bool { accessToken != nil }

    /// 첫 카카오 로그인이 "같은 이메일의 이메일 계정이 있어요"(409)로 멈췄을 때 받아 둔 카카오 토큰.
    /// "카카오로 새로 가입"을 고르면 카카오 로그인을 다시 띄우지 않고 이 토큰으로 다시 보내요.
    private var pendingKakaoToken: String?

    private init() {
        accessToken = Keychain.read(Self.tokenKey)
    }

    /// 카카오로 로그인해요. 처음 가입한 사용자면 true.
    /// 같은 이메일의 이메일 계정이 있으면 `APIError.conflict(email_account_exists)` 를 던져요.
    func loginWithKakao() async throws -> Bool {
        let kakaoToken = try await KakaoLogin.accessToken()
        return try await finishKakao(kakaoToken, allowDuplicateEmail: false)
    }

    /// "카카오로 새로 가입": 받아 둔 카카오 토큰으로 같은 이메일이어도 가입해요.
    func signupWithKakaoAnyway() async throws -> Bool {
        guard let kakaoToken = pendingKakaoToken else { throw KakaoLoginError.failed }
        return try await finishKakao(kakaoToken, allowDuplicateEmail: true)
    }

    /// 이메일로 가입만 해요. 로그인은 따로 해요 (가입 완료 안내 → 로그인, #120).
    /// 서버가 함께 준 토큰은 저장하지 않아요. 같은 이메일의 계정이 있으면 `APIError.conflict` 를 던져요.
    func signupWithEmail(email: String, password: String, name: String) async throws {
        _ = try await AuthAPI.signupEmail(email: email, password: password, name: name)
    }

    /// 이메일로 로그인해요.
    func loginWithEmail(email: String, password: String) async throws {
        save(try await AuthAPI.loginEmail(email: email, password: password))
    }

    private func finishKakao(_ kakaoToken: String, allowDuplicateEmail: Bool) async throws -> Bool {
        do {
            let response = try await AuthAPI.loginKakao(kakaoAccessToken: kakaoToken,
                                                        allowDuplicateEmail: allowDuplicateEmail)
            pendingKakaoToken = nil
            save(response)
            return response.isNewUser
        } catch {
            if case let APIError.conflict(code, _, _) = error, code == AuthAPI.ConflictCode.emailAccountExists {
                pendingKakaoToken = kakaoToken
            }
            throw error
        }
    }

    /// 받은 우리 토큰과 내 정보를 저장해요 (카카오 · 이메일 공통).
    private func save(_ response: AuthAPI.LoginResponse) {
        Keychain.save(response.accessToken, for: Self.tokenKey)
        accessToken = response.accessToken
        user = response.user
        // 내 계정 화면의 이름 · 학교 (앱에서 고칠 수 있는 값이라 로그인할 때만 서버 값으로 채워요)
        UserDefaults.standard.set(response.user.name, forKey: "profileName")
        if let school = response.user.school { UserDefaults.standard.set(school, forKey: "profileSchool") }
    }

    /// 앱을 켰을 때 저장된 토큰이 아직 유효한지 확인해요.
    /// 무효(401)면 `APIClient` 가 `didExpire()` 를 불러 로그아웃돼요. 서버에 못 붙으면 토큰을 그대로 둬요.
    func refresh() async {
        guard isLoggedIn else { return }
        if let me = try? await AuthAPI.me() { user = me }
    }

    /// 로그아웃: 우리 토큰을 지우고 카카오 쪽도 로그아웃해요.
    func logout() {
        clear()
        KakaoLogin.logout()
    }

    /// 서버가 토큰을 거절했을 때 (`APIClient` 가 불러요)
    func didExpire() {
        clear()
    }

    private func clear() {
        Keychain.delete(Self.tokenKey)
        accessToken = nil
        user = nil
    }
}
