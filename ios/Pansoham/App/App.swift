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
