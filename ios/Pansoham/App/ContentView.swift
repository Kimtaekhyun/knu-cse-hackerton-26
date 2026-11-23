import SwiftUI

/// 지금 보여 줄 화면을 고르는 곳.
struct ContentView: View {
    @State private var router = Router()
    private var auth = AuthSession.shared

    var body: some View {
        ZStack {
            screen
                .id(router.current)
                .transition(NavTransition(router: router))
                .zIndex(Double(router.direction.drawsBelow ? -router.moves : router.moves))
        }
        .animation(router.direction.animation, value: router.current)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { router.bounds = $0 }
        .environment(router)
            .preferredColorScheme(.light)
        // 저장된 토큰이 아직 유효한지 확인 (무효면 아래 onChange 가 로그인 화면으로 보내요)
        .task {
            await auth.refresh()
            if auth.isLoggedIn { LocalNotifications.shared.requestOnce() }
            // 시연: 세 알림을 10초 간격으로 (#125)
            if ProcessInfo.processInfo.arguments.contains("-notifyDemo") {
                await SemesterStore.shared.reload()
                LocalNotifications.shared.demo()
            }
        }
        // 알림을 눌렀을 때 그 화면으로 (#125)
        .onChange(of: LocalNotifications.shared.pendingRoute) { _, route in
            guard let route else { return }
            LocalNotifications.shared.pendingRoute = nil
            open(route)
        }
        // 로그아웃되거나 토큰이 만료되면 로그인 화면으로
        .onChange(of: auth.isLoggedIn) { _, loggedIn in
            // 로그인 직후 알림 권한을 한 번 물어봐요 (#125)
            if loggedIn { LocalNotifications.shared.requestOnce() }
            if !loggedIn, ![.login, .onboarding].contains(router.current) {
                router.reset(to: .login, direction: .fade)
            }
        }
    }

    /// 알림 → 과목 폴더 · 미분류함 · 메인 (로그인했을 때만)
    private func open(_ route: LocalNotifications.Route) {
        guard auth.isLoggedIn else { return }
        Task {
            if SemesterStore.shared.subjects.isEmpty { await SemesterStore.shared.reload() }
            router.reset(to: .home, direction: .fade)
            switch route {
            case .home: break
            case .unsorted: router.push(.unsorted)
            case .subject(let id):
                guard let subject = SemesterStore.shared.subjects.first(where: { $0.id == id }) else { return }
                router.subject = subject
                router.push(subject.captureCount == 0 ? .subjectEmpty : .subjectLessons)
            }
        }
    }

    @ViewBuilder
    private var screen: some View {
        switch router.current {
        case .onboarding: OnboardingView { router.reset(to: .login) }
        case .login: LoginScreen()
        case .timetableUpload: TimetableUploadScreen()
        case .timetableConfirm: TimetableConfirmScreen()
        case .homeFirst: HomeScreen(isFirst: true)
        case .home: HomeScreen()
        case .capture: CaptureScreen()
        case .processing: ProcessingScreen()
        case .captureError: CaptureErrorScreen()
        case .result, .copied: ResultScreen()
        case .cardDetail: CardDetailScreen()
        case .subjectLessons: SubjectLessonsScreen()
        case .subjectCards: SubjectCardsScreen()
        case .subjectEmpty: SubjectEmptyScreen()
        case .unsorted: UnsortedScreen()
        case .unsortedMove: UnsortedScreen(startsMoving: true)
        case .allSemesters: AllSemestersScreen()
        case .pastSemester: PastSemesterScreen()
        case .account: AccountScreen()
        case .pending: PendingScreen()
        }
    }
}

#Preview {
    ContentView()
}
