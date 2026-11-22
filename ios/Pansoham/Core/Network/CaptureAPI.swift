//
//  CaptureAPI.swift
//  chalkdrop
//
//  판서 API (#66, #67). 올리기 → 처리 상태 확인 → 결과 카드, 실패하면 다시 처리.
//  서버 형식은 server/app/schemas/capture.py 와 같아요.
//

import SwiftUI

/// 판서 한 장 (서버 `CaptureDetail`)
struct CaptureDTO: Decodable, Identifiable, Hashable {
    /// 처리 단계. 처리 중 화면(10-1/2/3)과 1:1
    enum Status: String, Decodable {
        case uploaded, rectifying, segmenting, interpreting, done, failed

        /// 처리 중 화면 단계 (0 판서 펴기, 1 글씨 찾기, 2 수식 정리)
        var phase: Int {
            switch self {
            case .uploaded, .rectifying: 0
            case .segmenting: 1
            case .interpreting, .done, .failed: 2
            }
        }
        var isFinished: Bool { self == .done || self == .failed }
    }

    let id: UUID
    let semesterId: UUID
    /// nil 이면 미분류함
    let subjectId: UUID?
    let takenAt: String
    /// 수업 날짜 "2026-11-17" (서울 기준). 과목 폴더는 이 값으로 수업을 묶어요.
    let classDate: String
    let status: Status
    /// rectify(화면을 못 찾음) · segment · interpret · unknown
    let failReason: String?
    let cardCount: Int
    /// 아직 옮기지 않은 카드 수
    let unmovedCount: Int
    /// 목록 응답에는 없고 상세에만 있어요
    var cards: [CardDTO] = []

    enum CodingKeys: String, CodingKey {
        case id, status, cards
        case semesterId = "semester_id", subjectId = "subject_id", takenAt = "taken_at", classDate = "class_date"
        case failReason = "fail_reason", cardCount = "card_count", unmovedCount = "unmoved_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        semesterId = try c.decode(UUID.self, forKey: .semesterId)
        subjectId = try c.decodeIfPresent(UUID.self, forKey: .subjectId)
        takenAt = try c.decode(String.self, forKey: .takenAt)
        classDate = try c.decodeIfPresent(String.self, forKey: .classDate) ?? String(takenAt.prefix(10))
        status = try c.decode(Status.self, forKey: .status)
        failReason = try c.decodeIfPresent(String.self, forKey: .failReason)
        cardCount = try c.decode(Int.self, forKey: .cardCount)
        unmovedCount = try c.decodeIfPresent(Int.self, forKey: .unmovedCount) ?? 0
        cards = try c.decodeIfPresent([CardDTO].self, forKey: .cards) ?? []
    }

    /// 찍은 시각 (서버는 소수점 초가 붙기도 해요)
    var takenDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: takenAt) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: takenAt)
    }
}

/// 판서에서 찾은 카드 한 장 (서버 `CardOut`)
struct CardDTO: Decodable, Identifiable, Hashable {
    struct Box: Decodable, Hashable {
        /// 반듯하게 편 사진 기준 0~1
        var x: Double, y: Double, w: Double, h: Double
    }

    let id: UUID
    let orderNo: Int
    let title: String
    /// text · math · code
    let cardType: String
    let content: String
    let bbox: Box

    enum CodingKeys: String, CodingKey {
        case id, title, content, bbox
        case orderNo = "order_no", cardType = "card_type"
    }

    var kindTitle: String {
        switch cardType {
        case "math": "수식"
        case "code": "코드"
        default: "텍스트"
        }
    }

    /// 화면용 카드. 자리는 너비 372 · 높이 `372 × aspect` 사진 기준으로 바꿔요.
    func sticker(aspect: CGFloat) -> Sticker {
        let height = 372 * aspect
        return Sticker(id: orderNo, title: title, kind: kindTitle, text: content,
                       x: bbox.x * 372, y: bbox.y * height, w: bbox.w * 372, h: bbox.h * height)
    }
}

/// 지금 찍으면 저장될 곳 (서버 `Destination`)
struct CaptureDestination: Decodable {
    let subjectId: UUID?
    let subjectName: String?

    enum CodingKeys: String, CodingKey {
        case subjectId = "subject_id", subjectName = "subject_name"
    }

    /// "자료구조 폴더" · 과목이 없으면 "미분류함"
    var placeTitle: String { subjectName.map { "\($0) 폴더" } ?? "미분류함" }
}

enum CaptureAPI {
    /// 판서 사진은 글씨가 읽혀야 해서 4K 그대로 올려요 (서버 제한 10MB 안쪽)
    static let maxSide: CGFloat = 4096

    /// 올리기. `id` 는 앱이 만들어서, 답을 못 받아 다시 보내도 같은 판서로 처리돼요.
    static func upload(_ image: UIImage, id: UUID, takenAt: Date, subjectId: UUID? = nil) async throws -> CaptureDTO {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        var fields = ["id": id.uuidString, "taken_at": formatter.string(from: takenAt)]
        if let subjectId { fields["subject_id"] = subjectId.uuidString }
        return try await APIClient.uploadImage(path: "api/v1/captures", image: image, fields: fields,
                                               maxSide: maxSide, as: CaptureDTO.self)
    }

    /// 처리 상태 · 결과 카드
    static func detail(_ id: UUID) async throws -> CaptureDTO {
        try await APIClient.json("GET", path: "api/v1/captures/\(id.uuidString)", as: CaptureDTO.self)
    }

    /// 목록 (최신부터). 미분류함은 `unsorted: true`, 과목 폴더는 `subjectId`,
    /// 아직 옮기지 않은 카드가 남은 판서는 `unmoved: true`
    static func list(subjectId: UUID? = nil, unsorted: Bool = false, unmoved: Bool = false) async throws -> [CaptureDTO] {
        var query: [URLQueryItem] = []
        if unmoved { query.append(URLQueryItem(name: "unmoved", value: "true")) }
        if let subjectId { query.append(URLQueryItem(name: "subject_id", value: subjectId.uuidString)) }
        if unsorted { query.append(URLQueryItem(name: "unsorted", value: "true")) }
        let data = try await APIClient.raw("GET", path: "api/v1/captures", query: query)
        guard let list = try? JSONDecoder().decode([CaptureDTO].self, from: data) else { throw APIError.invalidResponse }
        return list
    }

    /// 실패한 판서 다시 처리. `skipRectify` 면 화면을 못 찾아도 사진 그대로 써요 (11 "그대로 쓰기").
    static func retry(_ id: UUID, skipRectify: Bool) async throws -> CaptureDTO {
        struct Body: Encodable { let skip_rectify: Bool }
        return try await APIClient.json("POST", path: "api/v1/captures/\(id.uuidString)/retry",
                                        body: Body(skip_rectify: skipRectify), as: CaptureDTO.self)
    }

    /// 과목으로 옮기기. nil 이면 미분류함으로
    static func move(_ id: UUID, to subjectId: UUID?) async throws -> CaptureDTO {
        struct Body: Encodable {
            let subject_id: UUID?
            // nil 도 꼭 보내야 해서 직접 써요 (기본은 nil 이면 칸을 빼 버려요)
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(subject_id, forKey: .subject_id)
            }
            enum CodingKeys: CodingKey { case subject_id }
        }
        return try await APIClient.json("PATCH", path: "api/v1/captures/\(id.uuidString)",
                                        body: Body(subject_id: subjectId), as: CaptureDTO.self)
    }

    static func delete(_ id: UUID) async throws {
        try await APIClient.raw("DELETE", path: "api/v1/captures/\(id.uuidString)")
    }

    /// 사진 받기. `rectified` 는 반듯하게 편 사진 (처리가 끝난 뒤에만 있어요)
    static func image(_ id: UUID, rectified: Bool = false) async throws -> UIImage {
        let data = try await APIClient.raw("GET", path: "api/v1/captures/\(id.uuidString)/image",
                                           query: [URLQueryItem(name: "kind", value: rectified ? "rectified" : "original")],
                                           timeout: 60)
        guard let image = UIImage(data: data) else { throw APIError.invalidResponse }
        return image
    }

    /// 지금 찍으면 어디에 저장되는지 (촬영 화면의 "○○ 폴더에 저장")
    static func destination() async throws -> CaptureDestination {
        try await APIClient.json("GET", path: "api/v1/captures/destination", as: CaptureDestination.self)
    }
}
