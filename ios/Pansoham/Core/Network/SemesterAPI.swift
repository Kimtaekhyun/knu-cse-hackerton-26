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

    private struct SubjectBody: Encodable {
        let name: String
        let slots: [SlotDTO]
    }

    /// `PUT /semesters/timetable` 본문: 고른 학기 + 과목 전체
    private struct TermTimetableBody: Encodable {
        let year: Int
        let term: String
        let subjects: [SubjectBody]
        let make_current: Bool
    }

    private struct SuggestedDTO: Decodable {
        let year: Int
        let term: String
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

    /// 오늘 날짜 기준 기본 학기 (06 학기 선택의 처음 값). 못 부르면 앱 규칙(`Semester.current()`)으로.
    static func suggested() async -> Semester {
        guard AuthSession.shared.isLoggedIn,
              let dto = try? await APIClient.json("GET", path: "api/v1/semesters/suggested", as: SuggestedDTO.self),
              let term = Semester.Term(rawValue: dto.term) else { return .current() }
        return Semester(year: dto.year, term: term)
    }

    /// 06 `이대로 저장`. 서버가 학기 찾기 · 만들기 · 현재 학기 지정 · 과목 저장을 한 번에 해요 (#76).
    /// 같은 요청을 다시 보내도(연속 탭 · 재시도) 학기가 하나만 생겨요.
    /// `makeCurrent` 가 false 면 지난 학기로 넣고 현재 학기는 그대로 둬요.
    @discardableResult
    static func saveTimetable(_ subjects: [TimetableSubject], semester: Semester,
                              makeCurrent: Bool = true) async throws -> SemesterDTO {
        let body = TermTimetableBody(
            year: semester.year, term: semester.term.rawValue,
            subjects: subjects.map { subject in
                SubjectBody(name: subject.name, slots: Slot.parse(subject.time).map {
                    SlotDTO(weekday: $0.weekday, start: Slot.clock($0.start), end: Slot.clock($0.end))
                })
            },
            make_current: makeCurrent
        )
        return try await APIClient.json("PUT", path: "api/v1/semesters/timetable", body: body, as: SemesterDTO.self)
    }
}
