//
//  SemesterStore.swift
//  chalkdrop
//
//  지금 학기 · 과목을 서버에서 받아 여러 화면(메인 · 과목 상세 · 내 계정)이 같이 써요.
//  로그인하지 않았으면(이메일로 계속하기 등) 서버를 부르지 않고 샘플 화면을 그대로 보여 줘요.
//

import SwiftUI

@MainActor
@Observable
final class SemesterStore {
    static let shared = SemesterStore()

    enum State: Equatable {
        /// 로그인 안 함 · 아직 안 불러옴 → 샘플을 보여 줘요
        case sample
        case loading
        /// 서버에서 받음. `current` 가 nil 이면 아직 시간표를 등록하지 않았어요
        case loaded
        case failed(String)
    }

    private(set) var state: State = .sample
    private(set) var current: SemesterAPI.SemesterDTO?

    /// 서버 데이터를 쓰는 중인지 (아니면 각 화면의 샘플)
    var isLive: Bool { state == .loaded }
    var subjects: [SemesterAPI.SubjectDTO] { current?.subjects ?? [] }

    func reload() async {
        guard AuthSession.shared.isLoggedIn else {
            state = .sample
            current = nil
            return
        }
        if state != .loaded { state = .loading }
        do {
            current = try await SemesterAPI.current()
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// 저장 · 학기 변경 직후 바로 반영
    func use(_ semester: SemesterAPI.SemesterDTO?) {
        current = semester
        state = .loaded
    }
}
