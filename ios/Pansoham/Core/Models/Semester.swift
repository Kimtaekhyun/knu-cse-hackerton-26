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

    /// 처음 보여 줄 학기: 올해 1학기
    static func current(_ date: Date = .now) -> Semester {
        Semester(year: Calendar.current.component(.year, from: date), term: .first)
    }
}
