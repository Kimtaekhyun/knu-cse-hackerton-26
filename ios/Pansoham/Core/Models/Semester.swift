//
//  Semester.swift
//  chalkdrop
//
//  학기 (연도 + 1학기 · 2학기 · 여름 · 겨울 계절학기)
//

import Foundation

struct Semester: Hashable {
    enum Term: String, CaseIterable, Identifiable {
        case first, second, summer, winter

        var id: Self { self }

        var title: String {
            switch self {
            case .first: "1학기"
            case .second: "2학기"
            case .summer: "여름 계절학기"
            case .winter: "겨울 계절학기"
            }
        }
    }

    var year: Int
    var term: Term

    /// 화면에 보여 줄 이름 (예: "2026년 2학기")
    var title: String { "\(year)년 \(term.title)" }

    /// 오늘 날짜 기준 학기. 서버 `GET /semesters/suggested` 와 같은 규칙이에요 (판서 자동 분류와도 같음).
    /// 3~6월 1학기 · 7~8월 여름학기 · 9~12월 2학기 · 1~2월 지난해 겨울학기.
    /// 서버를 못 부를 때(로그인 안 함 등) 학기 선택의 처음 값으로 써요.
    static func current(_ date: Date = .now) -> Semester {
        let parts = Calendar.current.dateComponents([.year, .month], from: date)
        let year = parts.year ?? 2026, month = parts.month ?? 3
        switch month {
        case 3...6: return Semester(year: year, term: .first)
        case 7...8: return Semester(year: year, term: .summer)
        case 9...12: return Semester(year: year, term: .second)
        default: return Semester(year: year - 1, term: .winter)
        }
    }

    /// 시간 순서 비교용 (1학기 → 여름 → 2학기 → 겨울)
    var order: Int {
        let index: [Term: Int] = [.first: 0, .summer: 1, .second: 2, .winter: 3]
        return year * 4 + (index[term] ?? 0)
    }
}
