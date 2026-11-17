import SwiftUI

@main
struct MyApp: App {
    @State private var showsLaunch = true

    init() {
        AppFonts.register()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                // 런치 화면이 사라질 때 앱 화면을 만들어야 첫 화면의 등장 애니메이션이 보여요.
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
        }
    }
}
