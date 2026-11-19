//
//  Router.swift
//  chalkdrop
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

/// 화면이 바뀌는 방향. 화면 전환 애니메이션(`NavTransition`)이 보고 고른다.
enum NavDirection {
    /// 새 화면이 오른쪽에서 밀고 들어와요
    case forward
    /// 이전 화면이 왼쪽에서 돌아와요
    case back
    /// 처음부터 다시 쌓을 때는 겹쳐 사라져요
    case fade
    /// 촬영 버튼에서 촬영 화면이 커지며 나와요
    case zoomIn
    /// 촬영 화면이 촬영 버튼 쪽으로 줄어들며 닫혀요
    case zoomOut
}

@Observable
final class Router {
    var stack: [Screen] = [.onboarding]
    /// 마지막 화면 이동의 방향
    private(set) var direction: NavDirection = .fade { didSet { moves += 1 } }
    /// 화면 이동 횟수. 겹치는 두 화면 중 어느 쪽을 위에 그릴지(`zIndex`) 정할 때 써요.
    private(set) var moves = 0
    /// 촬영 화면이 커져 나오는 기준점 (화면 안 비율). 촬영 버튼의 `zoomSource()` 가 채워요.
    var zoomAnchor: UnitPoint = .bottomTrailing
    /// 앱 화면 전체의 위치 · 크기 (화면 좌표). `zoomAnchor` 를 비율로 바꿀 때 써요.
    var bounds: CGRect = .zero

    /// 화면 좌표의 점을 화면 안 비율로
    func anchor(for point: CGPoint) -> UnitPoint {
        guard bounds.width > 0, bounds.height > 0 else { return .bottomTrailing }
        return UnitPoint(x: (point.x - bounds.minX) / bounds.width,
                         y: (point.y - bounds.minY) / bounds.height)
    }
    /// 시간표 업로드(05)에서 고른 캡처. 시간표 확인(06)에서 원본으로 보여 줘요.
    var timetableImage: UIImage?
    /// 메인 `앨범에서 선택` 으로 고른 판서 사진들. 처리 중(10)이 한 장씩 차례로 처리해요.
    var albumPhotos: [UIImage] = []
    /// 방금 처리한 사진 수. 2장 이상이면 결과(12)가 사진 탭을 보여 줘요.
    var processedCount = 1

    init() {
        // 특정 화면부터 열어 보기: 실행 인자에 `-startScreen home` 처럼 화면 이름을 넣어요.
        if let name = UserDefaults.standard.string(forKey: "startScreen"), let screen = Screen(rawValue: name) {
            stack = [screen]
        } else if AuthSession.shared.isLoggedIn {
            // 저장된 로그인이 있으면 바로 홈. 토큰이 무효면 `ContentView` 가 로그인 화면으로 보내요.
            stack = [.home]
        }
    }

    var current: Screen { stack.last ?? .onboarding }

    func push(_ screen: Screen) {
        direction = screen == .capture ? .zoomIn : .forward
        stack.append(screen)
    }
    func pop() {
        direction = current == .capture ? .zoomOut : .back
        if stack.count > 1 { stack.removeLast() } else if current != .onboarding { stack = [.home] }
    }
    /// 지금 화면을 다른 화면으로 바꾸기 (뒤로 가도 돌아오지 않아요)
    func replace(_ screen: Screen, direction: NavDirection = .forward) {
        self.direction = direction
        if !stack.isEmpty { stack.removeLast() }
        stack.append(screen)
    }
    /// 처음부터 다시 쌓기
    func reset(to screen: Screen, direction: NavDirection = .forward) {
        self.direction = direction
        stack = [screen]
    }
    /// 시간표 확인(06)의 "다시 올리기": 업로드(05)에서 왔으면 뒤로, 내 계정 등에서 바로 왔으면 업로드 화면으로 바꿔요.
    func backToUpload() {
        if stack.dropLast().last == .timetableUpload { pop() } else { replace(.timetableUpload, direction: .back) }
    }
    /// 쌓인 화면 중 가장 가까운 `screen` 까지 돌아가기. 없으면 새로 시작.
    func popTo(_ screen: Screen) {
        direction = current == .capture ? .zoomOut : .back
        if let i = stack.lastIndex(of: screen) { stack = Array(stack[...i]) } else { stack = [screen] }
    }
}
