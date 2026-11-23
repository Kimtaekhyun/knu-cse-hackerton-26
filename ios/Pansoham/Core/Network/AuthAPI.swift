//
//  AuthAPI.swift
//  chalkdrop
//
//  로그인 (서버 `POST /api/v1/auth/kakao` · `/auth/email/signup` · `/auth/email/login`, `GET /api/v1/me`)
//
//  같은 이메일의 계정이 겹치면 서버가 409 로 답해요 (`APIError.conflict`, #120).
//  - 이메일 가입: `email_taken` · `kakao_account_exists`
//  - 첫 카카오 로그인: `email_account_exists` → "카카오로 새로 가입"을 고르면 `allowDuplicateEmail` 로 다시 보내요
//

import Foundation

enum AuthAPI {
    /// 서버가 돌려주는 내 정보
    struct UserDTO: Decodable, Equatable {
        let id: String
        /// "kakao" · "email"
        let provider: String
        let name: String
        let email: String?
        let school: String?
        /// 알림 설정 (#109)
        let settings: SettingsDTO?
    }

    /// 알림 켜짐 · 꺼짐. 알림 예약은 앱이 하고 서버는 값만 저장해요.
    struct SettingsDTO: Codable, Equatable {
        /// 옮기지 않은 판서 알림
        var notifyUnmoved: Bool
        /// 시험 기간 알림
        var notifyExam: Bool

        enum CodingKeys: String, CodingKey {
            case notifyUnmoved = "notify_unmoved", notifyExam = "notify_exam"
        }
    }

    struct LoginResponse: Decodable {
        /// 이후 요청에 `Authorization: Bearer` 로 붙이는 우리 서버 토큰
        let accessToken: String
        /// 아직 시간표를 등록하지 않았는지 (어느 학기에도 과목이 없음, #150). true면 시간표 등록으로 보내요
        let isNewUser: Bool
        let user: UserDTO

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case isNewUser = "is_new_user"
            case user
        }
    }

    /// 409 `code` 값
    enum ConflictCode {
        /// 이메일 가입: 같은 이메일의 이메일 계정이 있어요
        static let emailTaken = "email_taken"
        /// 이메일 가입: 같은 이메일의 카카오 계정이 있어요
        static let kakaoAccountExists = "kakao_account_exists"
        /// 첫 카카오 로그인: 같은 이메일의 이메일 계정이 있어요
        static let emailAccountExists = "email_account_exists"
    }

    private struct KakaoLoginRequest: Encodable {
        let access_token: String
        let allow_duplicate_email: Bool
    }

    /// 카카오 SDK로 받은 카카오 토큰을 서버에 보내 우리 토큰으로 바꿔요.
    /// `allowDuplicateEmail` 이면 같은 이메일의 이메일 계정이 있어도 새 카카오 계정을 만들어요.
    static func loginKakao(kakaoAccessToken: String, allowDuplicateEmail: Bool = false) async throws -> LoginResponse {
        try await APIClient.json("POST", path: "api/v1/auth/kakao",
                                 body: KakaoLoginRequest(access_token: kakaoAccessToken,
                                                         allow_duplicate_email: allowDuplicateEmail),
                                 as: LoginResponse.self)
    }

    /// 이메일 가입. 가입하면 바로 로그인한 토큰을 받아요.
    static func signupEmail(email: String, password: String, name: String) async throws -> LoginResponse {
        struct Body: Encodable { let email: String; let password: String; let name: String }
        return try await APIClient.json("POST", path: "api/v1/auth/email/signup",
                                        body: Body(email: email, password: password, name: name),
                                        as: LoginResponse.self)
    }

    /// 이메일 로그인. 없는 이메일과 틀린 비밀번호는 같은 오류 문구로 와요.
    static func loginEmail(email: String, password: String) async throws -> LoginResponse {
        struct Body: Encodable { let email: String; let password: String }
        return try await APIClient.json("POST", path: "api/v1/auth/email/login",
                                        body: Body(email: email, password: password),
                                        as: LoginResponse.self)
    }

    /// 내 정보. 저장된 토큰이 아직 유효한지 확인할 때 써요.
    static func me() async throws -> UserDTO {
        try await APIClient.json("GET", path: "api/v1/me", as: UserDTO.self)
    }

    /// 알림 설정 저장 (#109). 보낸 칸만 바꿔요.
    static func updateSettings(notifyUnmoved: Bool? = nil, notifyExam: Bool? = nil) async throws -> SettingsDTO {
        struct Body: Encodable { let notify_unmoved: Bool?; let notify_exam: Bool? }
        return try await APIClient.json("PATCH", path: "api/v1/me/settings",
                                        body: Body(notify_unmoved: notifyUnmoved, notify_exam: notifyExam),
                                        as: SettingsDTO.self)
    }

    /// 이름 저장 (#122). 보낸 칸만 바꿔요.
    static func updateName(_ name: String) async throws -> UserDTO {
        struct Body: Encodable { let name: String }
        return try await APIClient.json("PATCH", path: "api/v1/me", body: Body(name: name), as: UserDTO.self)
    }

    /// 학교 저장 (#105). 빈 글자를 보내면 학교를 비워요 (#122). 보낸 칸만 바꿔요.
    static func updateSchool(_ school: String) async throws -> UserDTO {
        struct Body: Encodable { let school: String }
        return try await APIClient.json("PATCH", path: "api/v1/me", body: Body(school: school), as: UserDTO.self)
    }
}
