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
        .task { await auth.refresh() }
        // 로그아웃되거나 토큰이 만료되면 로그인 화면으로
        .onChange(of: auth.isLoggedIn) { _, loggedIn in
            if !loggedIn, ![.login, .onboarding].contains(router.current) {
                router.reset(to: .login, direction: .fade)
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
        case .splitView: SplitViewScreen()
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
