//
//  Router.swift
//  판서함
//
//  화면 목록과 화면 이동 (뒤로 가기 · 바꾸기 · 처음부터)
//

import SwiftUI

enum Screen: String, Hashable, CaseIterable {
    case onboarding, login, timetableUpload, timetableConfirm
    case homeFirst, home
    case capture, processing, captureError
    case result, copied, splitView, cardDetail
    case subjectLessons, subjectCards, subjectEmpty
    case unsorted, unsortedMove
    case allSemesters, pastSemester, account
    case pending
}

@Observable
final class Router {
    var stack: [Screen] = [.onboarding]
    /// 시간표 업로드(05)에서 고른 캡처. 시간표 확인(06)에서 원본으로 보여 줘요.
    var timetableImage: UIImage?

    init() {
        // 특정 화면부터 열어 보기: 실행 인자에 `-startScreen home` 처럼 화면 이름을 넣어요.
        if let name = UserDefaults.standard.string(forKey: "startScreen"), let screen = Screen(rawValue: name) {
            stack = [screen]
        }
    }

    var current: Screen { stack.last ?? .onboarding }

    func push(_ screen: Screen) { stack.append(screen) }
    func pop() {
        if stack.count > 1 { stack.removeLast() } else if current != .onboarding { stack = [.home] }
    }
    /// 지금 화면을 다른 화면으로 바꾸기 (뒤로 가도 돌아오지 않아요)
    func replace(_ screen: Screen) {
        if !stack.isEmpty { stack.removeLast() }
        stack.append(screen)
    }
    /// 처음부터 다시 쌓기
    func reset(to screen: Screen) { stack = [screen] }
    /// 쌓인 화면 중 가장 가까운 `screen` 까지 돌아가기. 없으면 새로 시작.
    func popTo(_ screen: Screen) {
        if let i = stack.lastIndex(of: screen) { stack = Array(stack[...i]) } else { stack = [screen] }
    }
}
