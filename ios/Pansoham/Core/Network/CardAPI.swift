//
//  CardAPI.swift
//  chalkdrop
//
//  카드 API (#88): 수정 · 되돌리기 · 옮김 표시 · 삭제 · 손글씨 스티커. 앱 연결은 #99.
//

import SwiftUI

enum CardAPI {
    /// 보낸 것만 고쳐요 (nil 은 빼고 보내요)
    static func update(_ id: UUID, title: String? = nil, content: String? = nil, cardType: String? = nil) async throws -> CardDTO {
        struct Body: Encodable { let title: String?; let content: String?; let card_type: String? }
        return try await APIClient.json("PATCH", path: "api/v1/cards/\(id.uuidString)",
                                        body: Body(title: title, content: content, card_type: cardType), as: CardDTO.self)
    }

    /// 원래대로 되돌리기 (처음 인식 결과로)
    static func revert(_ id: UUID) async throws -> CardDTO {
        try await APIClient.json("POST", path: "api/v1/cards/\(id.uuidString)/revert", as: CardDTO.self)
    }

    static func delete(_ id: UUID) async throws {
        try await APIClient.raw("DELETE", path: "api/v1/cards/\(id.uuidString)")
    }

    /// 옮김 표시 (굿노트로 복사 · 드래그). 한 번에 100장까지
    static func markMoved(_ ids: [UUID], moved: Bool = true) async throws {
        struct Body: Encodable { let card_ids: [UUID]; let moved: Bool }
        for start in stride(from: 0, to: ids.count, by: 100) {
            let chunk = Array(ids[start..<min(start + 100, ids.count)])
            _ = try await APIClient.json("PUT", path: "api/v1/cards/moved",
                                         body: Body(card_ids: chunk, moved: moved), as: [CardDTO].self)
        }
    }

    /// 복사 · 드래그한 카드를 옮김 표시하고 "아직 옮기지 않은 판서"를 새로 받아요. 실패해도 조용히 넘어가요.
    static func markMovedQuietly(_ stickers: [Sticker]) {
        let ids = stickers.compactMap(\.cardID)
        guard !ids.isEmpty, AuthSession.shared.isLoggedIn else { return }
        Task { @MainActor in
            guard (try? await markMoved(ids)) != nil else { return }
            await SubjectCaptures.unmoved.load(.unmoved)
        }
    }

    /// 손글씨 스티커 (필기만 남긴 투명 PNG). 한 번 받은 건 다시 받지 않아요.
    private static let cache = NSCache<NSUUID, UIImage>()
    static func image(_ id: UUID) async -> UIImage? {
        if let cached = cache.object(forKey: id as NSUUID) { return cached }
        guard let data = try? await APIClient.raw("GET", path: "api/v1/cards/\(id.uuidString)/image", timeout: 60),
              let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: id as NSUUID)
        return image
    }
}
