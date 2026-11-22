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
    nonisolated static let maxImageSide: CGFloat = 2048
    /// 서버가 Gemini 재시도 · 분당 제한으로 1분 넘게 걸릴 수 있어서 넉넉히 기다려요.
    static let timeout: TimeInterval = 180

    /// 이미지 한 장을 multipart(`image` 칸)로 올리고 JSON 답을 `type` 으로 읽어요.
    /// `fields` 는 함께 보낼 글자 칸 (판서의 `id` · `taken_at` 등), `maxSide` 는 줄일 긴 변 길이예요.
    static func uploadImage<T: Decodable>(path: String, image: UIImage, fields: [String: String] = [:],
                                          maxSide: CGFloat = maxImageSide, as type: T.Type) async throws -> T {
        // 줄이기 · JPEG 압축은 4K 사진이면 1초 가까이 걸려서 메인 스레드 밖에서 해요 (화면이 멈추지 않게, #101)
        guard let jpeg = await jpegData(image, maxSide: maxSide) else { throw APIError.invalidResponse }
        // 압축하는 동안 취소했으면(처리 중 화면에서 나가면) 보내지 않아요
        try Task.checkCancellation()

        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
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

    /// 답을 JSON 으로 읽지 않고 그대로 받아요 (사진 받기 · 204 빈 답 등).
    @discardableResult
    static func raw(_ method: String, path: String, query: [URLQueryItem] = [],
                    timeout: TimeInterval = 30) async throws -> Data {
        var url = APIConfig.baseURL.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        return try await data(for: request)
    }

    /// 로그인 토큰을 붙여 보내고 답을 `type` 으로 읽어요.
    private static func send<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let data = try await data(for: request)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.invalidResponse
        }
    }

    /// 로그인 토큰을 붙여 보내고 답 본문을 받아요.
    /// 토큰을 붙여 보낸 요청이 401이면 토큰이 만료 · 무효라서 로그아웃 처리하고 `.unauthorized` 를 던져요.
    private static func data(for request: URLRequest) async throws -> Data {
        var request = request
        let token = AuthSession.shared.accessToken
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            // 화면을 나가서 요청이 취소된 건 연결 실패가 아니에요. 오류 알림을 띄우지 않게 취소로 넘겨요 (#101)
            throw CancellationError()
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
        return data
    }

    /// 줄이고 JPEG 로 바꿔요. 백그라운드에서 돌아요.
    @concurrent
    private nonisolated static func jpegData(_ image: UIImage, maxSide: CGFloat) async -> Data? {
        resized(image, maxSide: maxSide).jpegData(compressionQuality: 0.9)
    }

    /// 긴 변이 `maxSide` 를 넘으면 비율을 지켜 줄여요.
    private nonisolated static func resized(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide else { return image }
        let scale = maxSide / longest
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
