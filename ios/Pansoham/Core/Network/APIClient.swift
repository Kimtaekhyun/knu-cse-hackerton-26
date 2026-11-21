//
//  APIClient.swift
//  판서함
//
//  서버 요청 도구. 서버 주소 설정 · 이미지 올리기 · 오류 문구를 맡아요.
//

import SwiftUI

enum APIConfig {
    /// 서버 주소. `ios/Config/*.xcconfig` 의 `API_BASE_URL` 이 Info.plist 를 거쳐 들어와요 (#22).
    /// 실기기 iPad 는 각자 `Local.xcconfig` 에 서버 Mac 주소를 적어요.
    /// 스킴 실행 인자로는 바꾸지 않아요 (공유 스킴에 개인 IP 가 커밋되는 문제가 있었음).
    static let baseURL: URL = {
        if let text = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           !text.isEmpty, let url = URL(string: text) {
            return url
        }
        return URL(string: "http://localhost:8000")!
    }()
}

enum APIError: LocalizedError {
    /// 서버가 알려 준 실패 이유 (`detail`)
    case server(String)
    case unreachable
    case invalidResponse
    /// 로그인 토큰이 만료되거나 무효예요 (다시 로그인해야 해요)
    case unauthorized
    /// 서버가 404 로 답했어요 (예: 아직 현재 학기가 없음)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .server(let message), .notFound(let message): message
        case .unauthorized: "로그인이 만료됐어요. 다시 로그인해 주세요."
        case .unreachable: "서버에 연결할 수 없어요. 서버가 켜져 있는지 확인해 주세요."
        case .invalidResponse: "서버 응답을 읽지 못했어요."
        }
    }
}

enum APIClient {
    /// 올리기 전에 줄이는 긴 변 길이 (서버 10MB 제한 · 업로드 시간 때문)
    static let maxImageSide: CGFloat = 2048
    /// 서버가 Gemini 재시도 · 분당 제한으로 1분 넘게 걸릴 수 있어서 넉넉히 기다려요.
    static let timeout: TimeInterval = 180

    /// 이미지 한 장을 multipart(`image` 칸)로 올리고 JSON 답을 `type` 으로 읽어요.
    static func uploadImage<T: Decodable>(path: String, image: UIImage, as type: T.Type) async throws -> T {
        guard let jpeg = resized(image).jpegData(compressionQuality: 0.9) else { throw APIError.invalidResponse }

        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"upload.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(jpeg)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: APIConfig.baseURL.appending(path: path), timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return try await send(request, as: type)
    }

    /// JSON 본문을 보내고 JSON 답을 `type` 으로 읽어요.
    static func json<B: Encodable, T: Decodable>(_ method: String, path: String, body: B,
                                                 as type: T.Type, timeout: TimeInterval = 30) async throws -> T {
        var request = URLRequest(url: APIConfig.baseURL.appending(path: path), timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await send(request, as: type)
    }

    /// 본문 없이 보내고 JSON 답을 `type` 으로 읽어요 (GET 등).
    static func json<T: Decodable>(_ method: String, path: String,
                                   as type: T.Type, timeout: TimeInterval = 30) async throws -> T {
        var request = URLRequest(url: APIConfig.baseURL.appending(path: path), timeoutInterval: timeout)
        request.httpMethod = method
        return try await send(request, as: type)
    }

    /// 로그인 토큰을 붙여 보내고 답을 읽어요.
    /// 토큰을 붙여 보낸 요청이 401이면 토큰이 만료 · 무효라서 로그아웃 처리하고 `.unauthorized` 를 던져요.
    private static func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        var request = request
        let token = AuthSession.shared.accessToken
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch is URLError {
            throw APIError.unreachable
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401, token != nil {
                AuthSession.shared.didExpire()
                throw APIError.unauthorized
            }
            if let failure = try? JSONDecoder().decode(ServerFailure.self, from: data) {
                if http.statusCode == 404 { throw APIError.notFound(failure.detail) }
                throw APIError.server(failure.detail)
            }
            throw APIError.invalidResponse
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.invalidResponse
        }
    }

    /// 긴 변이 `maxImageSide` 를 넘으면 비율을 지켜 줄여요.
    private static func resized(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxImageSide else { return image }
        let scale = maxImageSide / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// FastAPI 오류 응답 `{"detail": "..."}`
    private struct ServerFailure: Decodable {
        let detail: String
    }
}
