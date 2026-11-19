import SwiftUI

@main
struct MyApp: App {
    @State private var showsLaunch = true

    init() {
        AppFonts.register()
        KakaoLogin.configure()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showsLaunch {
                    LaunchScreen {
                        withAnimation(.easeInOut(duration: 0.35)) { showsLaunch = false }
                    }
                    .transition(.opacity)
                    .zIndex(1)
                } else {
                    ContentView()
                        .transition(.opacity)
                }
            }
            // 카카오톡 앱에서 로그인하고 돌아올 때
            .onOpenURL { KakaoLogin.handle($0) }
        }
    }
}
