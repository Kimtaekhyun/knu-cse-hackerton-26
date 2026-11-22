//
//  AuthAPI.swift
//  판서함
//
//  로그인 (서버 `POST /api/v1/auth/kakao`, `GET /api/v1/me`)
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
        /// 이번 로그인으로 처음 가입했는지
        let isNewUser: Bool
        let user: UserDTO

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case isNewUser = "is_new_user"
            case user
        }
    }

    private struct KakaoLoginRequest: Encodable {
        let access_token: String
    }

    /// 카카오 SDK로 받은 카카오 토큰을 서버에 보내 우리 토큰으로 바꿔요.
    static func loginKakao(kakaoAccessToken: String) async throws -> LoginResponse {
        try await APIClient.json("POST", path: "api/v1/auth/kakao",
                                 body: KakaoLoginRequest(access_token: kakaoAccessToken),
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

    /// 학교 저장 (#105). 보낸 칸만 바꿔요.
    static func updateSchool(_ school: String) async throws -> UserDTO {
        struct Body: Encodable { let school: String }
        return try await APIClient.json("PATCH", path: "api/v1/me", body: Body(school: school), as: UserDTO.self)
    }
}
