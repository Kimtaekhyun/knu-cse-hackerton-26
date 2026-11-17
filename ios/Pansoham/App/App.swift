import SwiftUI

@main
struct MyApp: App {
    @State private var showsLaunch = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                if showsLaunch {
                    LaunchScreen {
                        withAnimation(.easeInOut(duration: 0.35)) { showsLaunch = false }
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
        }
    }
}
