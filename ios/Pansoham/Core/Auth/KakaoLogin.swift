//
//  KakaoLogin.swift
//  판서함
//
//  카카오 SDK 감싸기: 앱 시작 때 초기화, 카카오톡에서 돌아올 때 URL 처리, 로그인해서 카카오 토큰 받기.
//  네이티브 앱 키는 각자 `ios/Config/Local.xcconfig` 의 KAKAO_NATIVE_APP_KEY 가 Info.plist 를 거쳐 들어와요.
//  카카오 SDK 패키지(KakaoSDKCommon · KakaoSDKAuth · KakaoSDKUser)가 없으면 로그인만 안 되고 빌드는 돼요.
//

import Foundation

#if canImport(KakaoSDKUser)
import KakaoSDKAuth
import KakaoSDKCommon
import KakaoSDKUser
#endif

enum KakaoLoginError: LocalizedError {
    /// Local.xcconfig 에 키가 없거나 SDK 패키지가 없어요
    case notConfigured
    /// 사용자가 로그인 화면을 닫았어요 (오류 안내 없이 그대로 둬요)
    case cancelled
    /// 카카오가 실패를 알려 왔어요
    case failed

    var errorDescription: String? {
        switch self {
        case .notConfigured: "카카오 로그인 설정이 없어요. Local.xcconfig 의 KAKAO_NATIVE_APP_KEY 와 카카오 SDK 패키지를 확인해 주세요."
        case .cancelled: "카카오 로그인을 취소했어요."
        case .failed: "카카오 로그인을 마치지 못했어요. 다시 시도해 주세요."
        }
    }
}

@MainActor
enum KakaoLogin {
    /// Info.plist 의 KAKAO_NATIVE_APP_KEY (빈 값이면 설정 안 됨)
    private static var appKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "KAKAO_NATIVE_APP_KEY") as? String ?? "")
            .trimmingCharacters(in: .whitespaces)
    }

    private(set) static var isConfigured = false

    /// 앱 시작 때 한 번 불러요.
    static func configure() {
        #if canImport(KakaoSDKUser)
        guard !appKey.isEmpty else { return }
        KakaoSDK.initSDK(appKey: appKey)
        isConfigured = true
        #endif
    }

    /// 카카오톡 앱에서 로그인하고 돌아올 때 들어오는 URL. 카카오 것이면 처리하고 true.
    @discardableResult
    static func handle(_ url: URL) -> Bool {
        #if canImport(KakaoSDKUser)
        if AuthApi.isKakaoTalkLoginUrl(url) { return AuthController.handleOpenUrl(url: url) }
        #endif
        return false
    }

    /// 카카오톡으로 로그인해 보고, 카카오톡을 쓸 수 없으면(`NotSupported`) 카카오계정 화면으로 로그인해서
    /// 카카오 access token 을 받아요. (SDK 권장 방식: 설치 여부를 미리 묻지 않고 실패하면 바꿔요)
    static func accessToken() async throws -> String {
        #if canImport(KakaoSDKUser)
        guard isConfigured else { throw KakaoLoginError.notConfigured }
        do {
            do {
                // 기본값(.UniversalLink)은 카카오톡이 없으면 Safari로 열려서 실패를 알려 주지 않는다.
                // UniversalLinkOnly는 카카오톡이 없으면 NotSupported로 실패해서 카카오계정 로그인으로 넘어간다.
                return try await token {
                    UserApi.shared.loginWithKakaoTalk(launchMethod: .UniversalLinkOnly, completion: $0)
                }
            } catch let error as SdkError where reason(error) == .NotSupported {
                return try await token { UserApi.shared.loginWithKakaoAccount(completion: $0) }
            }
        } catch let error as SdkError where reason(error) == .Cancelled {
            throw KakaoLoginError.cancelled
        } catch is SdkError {
            throw KakaoLoginError.failed
        }
        #else
        throw KakaoLoginError.notConfigured
        #endif
    }

    #if canImport(KakaoSDKUser)
    private static func reason(_ error: SdkError) -> ClientFailureReason? {
        error.isClientFailed ? error.getClientError().reason : nil
    }

    /// 콜백 방식 로그인 함수를 async 로 바꿔요.
    private static func token(_ login: (@escaping (OAuthToken?, Error?) -> Void) -> Void) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            login { token, error in
                if let token { continuation.resume(returning: token.accessToken) }
                else { continuation.resume(throwing: error ?? KakaoLoginError.failed) }
            }
        }
    }
    #endif

    /// 카카오 쪽 토큰도 지워요. 실패해도 우리 앱 로그아웃에는 영향이 없어요.
    static func logout() {
        #if canImport(KakaoSDKUser)
        guard isConfigured else { return }
        UserApi.shared.logout { _ in }
        #endif
    }
}
