import SwiftUI

@main
struct KelidApp: App {
    @State private var store = AppStore()
    @State private var providers = ProvidersStore()
    @State private var telegram = TelegramStore()
    @State private var guardian = GuardianStore()
    @State private var vaults = VaultsStore()
    @State private var secrets = SecretsStore()
    @State private var mcp = McpStore()

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
                .environment(vaults)
                .environment(secrets)
                .environment(mcp)
                .task {
                    mcp.configure(gate: GateService(
                        app: store, vaults: vaults, secrets: secrets,
                        guardians: guardian, providers: providers, telegram: telegram
                    ))
                }
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
