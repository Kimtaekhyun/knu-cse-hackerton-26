//
//  HomeAPI.swift
//  chalkdrop
//
//  메인 화면 API (#95, #107). 수업 중 · 오늘 수업 · 이번 주 판서를 한 번에 받아요.
//  서버 형식은 server/app/schemas/home.py 와 같아요.
//

import SwiftUI

enum HomeAPI {
    /// 수업 칸 하나 ("수업 중" 카드 · "오늘 수업" 한 줄)
    struct ClassDTO: Decodable, Hashable {
        let subjectId: UUID
        let name: String
        /// "10:30"
        let start: String
        let end: String

        enum CodingKeys: String, CodingKey {
            case name, start, end
            case subjectId = "subject_id"
        }

        /// 하루 시작부터 몇 분째인지 ("10:30" → 630)
        var startMinute: Int { Self.minutes(start) }
        var endMinute: Int { Self.minutes(end) }

        private static func minutes(_ text: String) -> Int {
            let parts = text.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2 else { return 0 }
            return parts[0] * 60 + parts[1]
        }
    }

    /// 이번 주 막대 그래프 (정리가 끝난 판서만 세요)
    struct WeekDTO: Decodable, Hashable {
        /// 이번 주 월요일 ("2026-11-16")
        let start: String
        /// 월 … 일 7칸
        let days: [Int]
        let total: Int
        let lastWeekTotal: Int

        enum CodingKeys: String, CodingKey {
            case start, days, total
            case lastWeekTotal = "last_week_total"
        }
    }

    /// 진행 중이거나 다가오는 시험 (학사일정 기준). 로컬 알림 시험 복습에 써요 (#125)
    struct ExamDTO: Decodable, Hashable {
        /// "midterm" · "final"
        let kind: String
        /// "2026-12-14"
        let startsOn: String
        let daysLeft: Int
        let inProgress: Bool

        enum CodingKeys: String, CodingKey {
            case kind
            case startsOn = "starts_on", daysLeft = "days_left", inProgress = "in_progress"
        }

        /// "중간" · "기말"
        var title: String { kind == "midterm" ? "중간" : "기말" }
        var startDate: Date? {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: startsOn)
        }
    }

    /// `GET /home` 응답. 시험(`exam`)은 메인에 자리가 없어 로컬 알림에만 써요.
    struct HomeDTO: Decodable, Hashable {
        /// 오늘 요일의 수업 전부 (끝난 수업 포함), 시작 시각 순
        let today: [ClassDTO]
        let week: WeekDTO
        /// 정리가 끝난 판서 전체 수. 0이면 07(처음) 화면
        let totalCaptures: Int
        /// 학교 · 학사일정이 없거나 기말까지 끝났으면 nil
        let exam: ExamDTO?

        enum CodingKeys: String, CodingKey {
            case today, week, exam
            case totalCaptures = "total_captures"
        }
    }

    static func home() async throws -> HomeDTO {
        try await APIClient.json("GET", path: "api/v1/home", as: HomeDTO.self)
    }
}

/// 메인 화면 값. 로그인하지 않았으면 서버를 부르지 않고 메인이 샘플을 보여 줘요.
@MainActor
@Observable
final class HomeStore {
    static let shared = HomeStore()

    /// 서버에서 받은 값. nil 이면(로그인 전 · 아직 못 받음) 샘플
    private(set) var home: HomeAPI.HomeDTO?

    func reload() async {
        guard AuthSession.shared.isLoggedIn else {
            home = nil
            return
        }
        // 실패하면 마지막으로 받은 값을 그대로 둬요 (처음이면 샘플)
        if let fresh = try? await HomeAPI.home() { home = fresh }
    }
}
