import SwiftUI

@main
struct KelidApp: App {
    @State private var store = AppStore()

    init() {
        KelidFont.registerIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if store.onboardingComplete {
            DashboardView()
        } else {
            OnboardingView()
        }
    }
}
