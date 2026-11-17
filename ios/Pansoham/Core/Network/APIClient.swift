//
//  APIClient.swift
//  판서함
//
//  서버 요청 도구. 서버 주소 설정 · 이미지 올리기 · 오류 문구를 맡아요.
//

import SwiftUI

enum APIConfig {
    /// 서버 주소. 실행 인자에 `-apiBaseURL http://192.168.0.10:8000` 처럼 넣으면 그 주소를 써요.
    /// 없으면 시뮬레이터에서 같은 Mac 의 서버로 가는 `http://localhost:8000`.
    static var baseURL: URL {
        if let text = UserDefaults.standard.string(forKey: "apiBaseURL"), let url = URL(string: text) {
            return url
        }
        return URL(string: "http://localhost:8000")!
    }
}

enum APIError: LocalizedError {
    /// 서버가 알려 준 실패 이유 (`detail`)
    case server(String)
    case unreachable
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .server(let message): message
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

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.upload(for: request, from: body)
        } catch is URLError {
            throw APIError.unreachable
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if let failure = try? JSONDecoder().decode(ServerFailure.self, from: data) {
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
