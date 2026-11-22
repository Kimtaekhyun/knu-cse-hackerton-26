//
//  TimetableAPI.swift
//  판서함
//
//  시간표 캡처 → 과목 후보 (서버 `POST /api/v1/timetable/parse`)
//

import SwiftUI

enum TimetableAPI {
    struct SlotDTO: Codable, Hashable {
        /// 0=월 … 6=일
        let weekday: Int
        /// "HH:MM"
        let start: String
        let end: String
    }

    struct SubjectDTO: Decodable {
        let name: String
        let slots: [SlotDTO]
    }

    struct TimetableParseResponse: Decodable {
        let subjects: [SubjectDTO]
    }

    /// 캡처를 올려 과목 후보를 받아요. 화면에 바로 쓸 수 있게 `TimetableSubject` 로 바꿔 줘요.
    static func parse(_ image: UIImage) async throws -> [TimetableSubject] {
        let response = try await APIClient.uploadImage(
            path: "api/v1/timetable/parse", image: image, as: TimetableParseResponse.self
        )
        return response.subjects.map { TimetableSubject(name: $0.name, time: timeText($0.slots)) }
    }

    /// 화면에 보여 줄 요일 · 시간 글자.
    /// 시간이 모두 같으면 "화 · 목 10:30–12:00", 다르면 "화 10:30–12:00 · 목 13:00–14:30", 없으면 "".
    static func timeText(_ slots: [SlotDTO]) -> String {
        let days = ["월", "화", "수", "목", "금", "토", "일"]
        func day(_ slot: SlotDTO) -> String { days.indices.contains(slot.weekday) ? days[slot.weekday] : "?" }
        guard let first = slots.first else { return "" }
        if slots.allSatisfy({ $0.start == first.start && $0.end == first.end }) {
            return slots.map(day).joined(separator: " · ") + " \(first.start)–\(first.end)"
        }
        return slots.map { "\(day($0)) \($0.start)–\($0.end)" }.joined(separator: " · ")
    }
}
