import SwiftUI

@main
struct KelidApp: App {
    @State private var store = AppStore()
    @State private var providers = ProvidersStore()
    @State private var telegram = TelegramStore()
    @State private var guardian = GuardianStore()

    init() {
        KelidFont.registerIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(providers)
                .environment(telegram)
                .environment(guardian)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}

struct RootView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            if store.onboardingComplete {
                if store.isLocked {
                    LockScreenView()
                } else {
                    MainWindowView()
                }
            } else {
                OnboardingView()
            }
        }
        .task { store.startAutoLock() }
    }
}
