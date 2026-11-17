import SwiftUI

/// 지금 보여 줄 화면을 고르는 곳. 화면 이동은 Router 가 맡아요.
struct ContentView: View {
    @State private var router = Router()

    var body: some View {
        screen
            .id(router.current)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: router.current)
            .environment(router)
            .preferredColorScheme(.light)
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
        }
    }
}

#Preview {
    ContentView()
}
