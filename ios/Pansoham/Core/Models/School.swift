//
//  School.swift
//  chalkdrop
//
//  학교 목록 (#105). 서버는 학교 이름을 학사일정(academic_calendars.school)과 글자 그대로 맞춰 봐서,
//  철자가 틀리지 않게 학사일정이 있는 학교만 골라요. 서버에 학교 목록 API가 없어 앱에 둬요.
//

import Foundation

enum School {
    /// 학사일정이 있는 학교
    static let supported = ["경북대학교"]

    /// 검색어가 들어간 학교 (빈 칸이면 전체)
    static func search(_ query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? supported : supported.filter { $0.localizedCaseInsensitiveContains(q) }
    }
}
