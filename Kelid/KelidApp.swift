import SwiftUI

@main
struct KelidApp: App {
    @State private var store = AppStore()
    @State private var providers = ProvidersStore()

    init() {
        KelidFont.registerIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(providers)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        if store.onboardingComplete {
            MainWindowView()
        } else {
            OnboardingView()
        }
    }
}
