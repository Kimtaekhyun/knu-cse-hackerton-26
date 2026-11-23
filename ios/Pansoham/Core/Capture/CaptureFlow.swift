//
//  CaptureFlow.swift
//  chalkdrop
//
//  판서 한 번 처리하는 동안 화면끼리 나눠 쓰는 상태 (#78).
//  촬영(09) · 앨범 → 처리 중(10) → 결과(12) 또는 오류(11) → 다시 처리 순서로 넘겨요.
//
//  로그인하지 않았으면(카카오 로그인 전 · 디자인 확인용) 서버 없이 예전 연출과 샘플 카드로 보여 줘요.
//

import SwiftUI

@Observable
final class CaptureFlow {
    static let shared = CaptureFlow()

    /// 처리할 사진 한 장
    struct Job: Identifiable {
        /// 서버 판서 id. 앱이 먼저 만들어서 올려요 (다시 보내도 같은 판서)
        let id: UUID
        /// 찍은(고른) 사진
        let image: UIImage
        let takenAt: Date
        /// 서버가 알려 준 상태 · 결과
        var capture: CaptureDTO?
        /// 반듯하게 편 사진 (처리가 끝나면 받아요). 카드 자리는 이 사진 기준이에요.
        var rectified: UIImage?

        /// 카드 자리를 그릴 사진
        var photo: UIImage { rectified ?? image }
        /// 사진 세로 ÷ 가로
        var aspect: CGFloat { photo.size.width > 0 ? photo.size.height / photo.size.width : 279.0 / 372.0 }

        /// 결과 화면용 카드
        var stickers: [Sticker] {
            (capture?.cards ?? []).sorted { $0.orderNo < $1.orderNo }.map {
                var sticker = $0.sticker(aspect: aspect)
                sticker.photo = photo
                sticker.photoAspect = aspect
                return sticker
            }
        }
    }

    /// 지금 처리 중인 사진들
    var jobs: [Job] = []
    /// 처리가 끝난 사진들. 결과 화면(12)이 보여 줘요. 비어 있으면 결과 화면은 샘플을 보여 줘요.
    var results: [Job] = []
    /// 처리에 실패한 사진. 오류 화면(11)이 보여 줘요.
    var failed: Job?
    /// 지금 찍으면 저장될 곳 ("자료구조 폴더" · "미분류함")
    var destination: CaptureDestination?
    /// 이번에 복사 · 끌어다 놓기 한 카드 (결과 "다시 찍기"에서 남기기를 기본으로, #126)
    var movedCards: Set<UUID> = []

    /// 카드 상세(17)에서 고칠 서버 카드 (결과 · 카드 모아 보기에서 눌렀을 때, #99)
    var openedCard: Sticker?

    /// 카드를 고치거나 지웠을 때 결과 화면 · 받아 둔 목록에 반영
    @MainActor
    func updateCard(_ card: CardDTO? = nil, removed: UUID? = nil) {
        for index in results.indices {
            guard var capture = results[index].capture else { continue }
            if let removed { capture.cards.removeAll { $0.id == removed } }
            if let card, let at = capture.cards.firstIndex(where: { $0.id == card.id }) { capture.cards[at] = card }
            results[index].capture = capture
        }
        SubjectCaptures.updateCard(card, removed: removed)
    }

    /// 과목 폴더(15 · 16)에서 저장된 판서를 열었으면 그 과목 이름. 결과 화면 뒤로 가기가 폴더로 돌아가요.
    var openedFolder: String?

    /// 서버로 처리하는지 (로그인했을 때만)
    var isLive: Bool { AuthSession.shared.isLoggedIn }

    /// 새로 찍은(고른) 사진들로 시작
    func begin(_ photos: [UIImage], takenAt: Date = .now) {
        jobs = photos.map { Job(id: UUID(), image: $0, takenAt: takenAt) }
        results = []
        failed = nil
        openedFolder = nil
    }

    /// 과목 폴더에서 저장된 판서 열기 (처리 없이 바로 결과 화면)
    func open(_ saved: [Job], folder: String) {
        jobs = []
        results = saved
        failed = nil
        openedFolder = folder
    }

    /// 실패한 사진을 다시 처리할 때 (이미 올린 판서라 다시 올리지 않아요)
    func resume(_ job: Job) {
        jobs = [job]
        results = []
        failed = nil
    }

    /// 저장될 곳을 서버에 물어봐요 (실패해도 괜찮아요)
    func loadDestination() async {
        guard isLive else { return }
        destination = try? await CaptureAPI.destination()
    }

    /// 판서가 저장된 곳 이름 ("자료구조 폴더" · "미분류함")
    func placeTitle(of capture: CaptureDTO?) -> String {
        if let openedFolder { return openedFolder == "미분류함" ? openedFolder : "\(openedFolder) 폴더" }
        guard let capture else { return destination?.placeTitle ?? "미분류함" }
        guard let subjectId = capture.subjectId else { return "미분류함" }
        if let destination, destination.subjectId == subjectId { return destination.placeTitle }
        return "과목 폴더"
    }
}
