//
//  SemesterAPI.swift
//  chalkdrop
//
//  학기 · 과목 (서버 `api/v1/semesters`, `api/v1/subjects`, #50)
//  로그인 토큰이 있어야 해요 (#58).
//

import Foundation

enum SemesterAPI {
    typealias SlotDTO = TimetableAPI.SlotDTO

    struct SubjectDTO: Decodable, Hashable, Identifiable {
        let id: UUID
        let name: String
        let slots: [SlotDTO]
        /// 처리가 끝난 판서 수 (폴더의 "12장")
        let captureCount: Int

        enum CodingKeys: String, CodingKey {
            case id, name, slots
            case captureCount = "capture_count"
        }

        /// "월 10:30–12:00" 같은 글자. 시간이 없으면 "시간 없음"
        var timeText: String {
            let text = TimetableAPI.timeText(slots)
            return text.isEmpty ? "시간 없음" : text
        }

        /// 시간표 확인(06) 목록에 넣을 모양
        var timetableSubject: TimetableSubject { TimetableSubject(name: name, time: TimetableAPI.timeText(slots)) }
    }

    struct SemesterDTO: Decodable, Hashable, Identifiable {
        let id: UUID
        let year: Int
        /// "first" · "second" · "summer" · "winter"
        let term: String
        /// "2026년 2학기"
        let label: String
        let isCurrent: Bool
        let subjectCount: Int
        let captureCount: Int
        /// 학기 하나를 열었을 때만 와요
        let subjects: [SubjectDTO]?

        /// 06 학기 고르기에 넣을 모양
        var semester: Semester? { Semester.Term(rawValue: term).map { Semester(year: year, term: $0) } }

        enum CodingKeys: String, CodingKey {
            case id, year, term, label, subjects
            case isCurrent = "is_current"
            case subjectCount = "subject_count"
            case captureCount = "capture_count"
        }
    }

    private struct CreateBody: Encodable {
        let year: Int
        let term: String
        let make_current: Bool
    }

    private struct SubjectBody: Encodable {
        let name: String
        let slots: [SlotDTO]
    }

    private struct TimetableBody: Encodable {
        let subjects: [SubjectBody]
    }

    static func list() async throws -> [SemesterDTO] {
        try await APIClient.json("GET", path: "api/v1/semesters", as: [SemesterDTO].self)
    }

    /// 현재 학기. 아직 없으면 nil (서버 404)
    static func current() async throws -> SemesterDTO? {
        do {
            return try await APIClient.json("GET", path: "api/v1/semesters/current", as: SemesterDTO.self)
        } catch APIError.notFound(_) {
            return nil
        }
    }

    static func detail(_ id: UUID) async throws -> SemesterDTO {
        try await APIClient.json("GET", path: "api/v1/semesters/\(id.uuidString)", as: SemesterDTO.self)
    }

    /// 이 학기를 현재 학기로
    static func makeCurrent(_ id: UUID) async throws {
        _ = try await APIClient.json("PUT", path: "api/v1/semesters/\(id.uuidString)/current", body: [String: String](),
                                     as: SemesterDTO.self)
    }

    /// 06 `이대로 저장`. 06 에서 고른 학기를 찾거나 만들어 현재 학기로 두고, 과목 목록을 통째로 저장해요.
    @discardableResult
    static func saveTimetable(_ subjects: [TimetableSubject], semester: Semester) async throws -> SemesterDTO {
        let year = semester.year, term = semester.term.rawValue
        let semesterID: UUID
        if let existing = try await list().first(where: { $0.year == year && $0.term == term }) {
            semesterID = existing.id
            if !existing.isCurrent { try await makeCurrent(existing.id) }
        } else {
            semesterID = try await APIClient.json("POST", path: "api/v1/semesters",
                                                  body: CreateBody(year: year, term: term, make_current: true),
                                                  as: SemesterDTO.self).id
        }
        let body = TimetableBody(subjects: subjects.map { subject in
            SubjectBody(name: subject.name, slots: Slot.parse(subject.time).map {
                SlotDTO(weekday: $0.weekday, start: Slot.clock($0.start), end: Slot.clock($0.end))
            })
        })
        return try await APIClient.json("PUT", path: "api/v1/semesters/\(semesterID.uuidString)/timetable",
                                        body: body, as: SemesterDTO.self)
    }
}
