//
//  SubjectCaptures.swift
//  chalkdrop
//
//  과목 폴더(15 수업별 · 16 카드 모아 보기)에 보여 줄 서버 판서 (#85).
//  목록(`GET /captures?subject_id=`) → 처리 끝난 판서는 상세(카드) · 사진까지 받아 둬요.
//  로그인하지 않았거나 메인에서 샘플 폴더를 열었으면 쓰지 않아요 (샘플 화면 그대로).
//

import SwiftUI

@Observable
final class SubjectCaptures {
    static let shared = SubjectCaptures()

    enum State: Equatable { case idle, loading, loaded, failed(String) }

    /// 판서 한 장 + 받아 둔 사진
    struct Item: Identifiable {
        var capture: CaptureDTO
        /// 반듯하게 편 사진(처리 끝) 또는 찍은 사진. 못 받았으면 nil
        var photo: UIImage?
        var id: UUID { capture.id }
        var aspect: CGFloat {
            guard let photo, photo.size.width > 0 else { return 279.0 / 372.0 }
            return photo.size.height / photo.size.width
        }
        /// 카드 (카드 자리 · 사진 포함)
        var stickers: [Sticker] {
            capture.cards.sorted { $0.orderNo < $1.orderNo }.map {
                var sticker = $0.sticker(aspect: aspect)
                sticker.photo = photo
                sticker.photoAspect = aspect
                return sticker
            }
        }
        /// 결과 화면(12)에 넘길 모양
        var job: CaptureFlow.Job? {
            guard let photo else { return nil }
            return CaptureFlow.Job(id: capture.id, image: photo, takenAt: capture.takenDate ?? .now,
                                   capture: capture, rectified: capture.status == .done ? photo : nil)
        }
    }

    /// 수업 하나 = 같은 날(`class_date`) 찍은 판서들
    struct Lesson: Identifiable {
        let date: String          // "2026-11-17"
        let items: [Item]
        var id: String { date }
        var cardCount: Int { items.map(\.capture.cardCount).reduce(0, +) }
    }

    private(set) var subjectID: UUID?
    private(set) var state: State = .idle
    private(set) var items: [Item] = []

    /// 서버 판서를 쓰는지 (로그인 + 메인에서 실제 과목을 열었을 때)
    func isLive(_ subject: SemesterAPI.SubjectDTO?) -> Bool {
        AuthSession.shared.isLoggedIn && subject != nil
    }

    /// 최신 수업부터
    var lessons: [Lesson] {
        let groups: [String: [Item]] = Dictionary(grouping: items) { $0.capture.classDate }
        var result: [Lesson] = []
        for (date, group) in groups {
            let sorted = group.sorted { $0.capture.takenAt < $1.capture.takenAt }
            result.append(Lesson(date: date, items: sorted))
        }
        return result.sorted { $0.date > $1.date }
    }

    /// 이 과목 판서를 다 받았는지
    func isLoaded(_ subjectID: UUID?) -> Bool { state == .loaded && self.subjectID == subjectID }

    /// 모든 카드. 화면용 번호(`id`)는 겹치지 않게 1부터 다시 매겨요.
    var stickers: [(sticker: Sticker, item: Item)] {
        var number = 0
        return lessons.flatMap(\.items).flatMap { item in
            item.stickers.map { sticker in
                number += 1
                return (Sticker(id: number, title: sticker.title, kind: sticker.kind, text: sticker.text,
                                x: sticker.x, y: sticker.y, w: sticker.w, h: sticker.h,
                                photo: sticker.photo, photoAspect: sticker.photoAspect), item)
            }
        }
    }

    var cardCount: Int { items.map(\.capture.cardCount).reduce(0, +) }

    /// 과목 판서 불러오기. 같은 과목을 다시 열면 받아 둔 걸 먼저 보여 주고 새로 받아요.
    @MainActor
    func load(_ subjectID: UUID) async {
        if self.subjectID != subjectID {
            self.subjectID = subjectID
            items = []
            state = .loading
        } else if case .failed = state {
            state = .loading
        }
        do {
            let list = try await CaptureAPI.list(subjectId: subjectID)
            let old = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            let loaded = await withTaskGroup(of: Item.self) { group in
                for capture in list {
                    let cached = old[capture.id]
                    group.addTask { await Self.fill(capture, cached: cached) }
                }
                var result: [Item] = []
                for await item in group { result.append(item) }
                return result
            }
            guard self.subjectID == subjectID else { return }
            items = loaded
            state = .loaded
        } catch {
            guard self.subjectID == subjectID else { return }
            state = .failed(error.localizedDescription)
        }
    }

    /// 상세(카드) · 사진 받기. 실패해도 목록 정보만으로 보여 줘요.
    nonisolated private static func fill(_ capture: CaptureDTO, cached: Item?) async -> Item {
        let done = capture.status == .done
        // 처리가 끝났고 전에 받은 것과 같으면 다시 받지 않아요
        if let cached, cached.photo != nil, capture.status.isFinished,
           cached.capture.status == capture.status, cached.capture.cardCount == capture.cardCount {
            return cached
        }
        var detail = capture
        if done, capture.cardCount > 0, let full = try? await CaptureAPI.detail(capture.id) { detail = full }
        var photo = try? await CaptureAPI.image(capture.id, rectified: done)
        if photo == nil, done { photo = try? await CaptureAPI.image(capture.id) }
        // 4K 사진을 그대로 들고 있지 않게 줄여 둬요 (미리보기 · 카드 자리용)
        if let full = photo, max(full.size.width, full.size.height) > 1600 {
            let ratio = 1600 / max(full.size.width, full.size.height)
            photo = await full.byPreparingThumbnail(ofSize: CGSize(width: full.size.width * ratio,
                                                                   height: full.size.height * ratio)) ?? full
        }
        return Item(capture: detail, photo: photo)
    }
}

extension SubjectCaptures.Lesson {
    /// "11월 17일 (월)"
    var title: String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let day = parser.date(from: date) else { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 (E)"
        return formatter.string(from: day)
    }

    var isToday: Bool {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: .now) == date
    }

    /// "사진 2장 · 카드 5개"
    var summary: String { "사진 \(items.count)장 · 카드 \(cardCount)개" }

    /// 카드 제목 꼬리표 (최대 6개, 나머지는 "+N")
    var tags: (shown: [String], more: String?) {
        let titles = items.flatMap { $0.capture.cards.sorted { $0.orderNo < $1.orderNo }.map(\.title) }
        let shown = Array(titles.prefix(6))
        return (shown, titles.count > 6 ? "+\(titles.count - 6)" : nil)
    }

    /// 처리 중 · 실패 판서가 있으면 그 안내
    var statusNote: String? {
        let failed = items.filter { $0.capture.status == .failed }.count
        let working = items.filter { !$0.capture.status.isFinished }.count
        if working > 0 { return "\(working)장 정리 중" }
        if failed > 0 { return "\(failed)장 정리 실패" }
        return nil
    }
}
