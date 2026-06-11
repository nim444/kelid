import SwiftUI

struct AIProviderPane: View {
    let provider: AIProvider
    @Environment(ProvidersStore.self) private var store

    @State private var key = ""
    @State private var baseURL = ""
    @State private var revealKey = false
    @State private var testing = false
    @State private var toast: Toast?

    private var isConfigured: Bool { store.isConfigured(provider) }
    private var trimmedKey: String { key.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            switch provider.auth {
            case .apiKey: apiKeyCard
            case .localEndpoint: localEndpointCard
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .toast($toast)
        .onAppear(perform: load)
        .onChange(of: provider) { _, _ in load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ProviderLogo(provider: provider, size: 24)
                    .foregroundStyle(LinearGradient.kelidAccent)
                Text(provider.name)
                    .font(.kelid(22, .bold))
            }
            Text(provider.summary)
                .font(.kelid(13, .regular))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Cloud (API key)

    private var apiKeyCard: some View {
        PaneCard {
            statusBadge

            Text("API key")
                .font(.kelid(12, .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Group {
                    if revealKey {
                        TextField(keyFieldPrompt, text: $key)
                    } else {
                        SecureField(keyFieldPrompt, text: $key)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.kelid(13, .regular))

                Button {
                    toggleReveal()
                } label: {
                    Image(systemName: revealKey ? "eye.slash" : "eye")
                        .frame(width: 18)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .help(revealKey ? "Hide" : "Reveal stored key (requires Touch ID)")
            }

            Text("Stored in the macOS Keychain — never written to disk in plaintext. Revealing a saved key requires Touch ID or your Mac password.")
                .font(.kelid(11, .regular))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            buttonRow
        }
    }

    // MARK: - Local (endpoint)

    private var localEndpointCard: some View {
        PaneCard {
            statusBadge

            Text("Base URL")
                .font(.kelid(12, .medium))
                .foregroundStyle(.secondary)
            TextField(provider.defaultBaseURL, text: $baseURL)
                .textFieldStyle(.roundedBorder)
                .font(.kelid(13, .regular))

            Text("Runs locally on this Mac — no API key needed.")
                .font(.kelid(11, .regular))
                .foregroundStyle(.tertiary)

            buttonRow
        }
    }

    // MARK: - Buttons (uniform sizing)

    private var buttonRow: some View {
        HStack(spacing: 10) {
            Button(action: save) {
                Text(saveTitle).font(.kelid(13, .semibold))
            }
            .buttonStyle(.glassProminent)
            .disabled(!canSave)

            Button(action: runTest) {
                HStack(spacing: 6) {
                    if testing { ProgressView().controlSize(.small) }
                    Text(testing ? "Testing\u{2026}" : "Test").font(.kelid(13, .semibold))
                }
            }
            .buttonStyle(.glass)
            .disabled(!canTest)

            if canRemove {
                Button(role: .destructive, action: remove) {
                    Text("Remove").font(.kelid(13, .semibold))
                }
                .buttonStyle(.glass)
            }
        }
        .controlSize(.large)
        .buttonBorderShape(.capsule)
    }

    private var saveTitle: String {
        switch provider.auth {
        case .apiKey: isConfigured ? "Update Key" : "Save Key"
        case .localEndpoint: "Save Endpoint"
        }
    }

    private var canSave: Bool {
        switch provider.auth {
        case .apiKey: !trimmedKey.isEmpty
        case .localEndpoint: !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private var canTest: Bool {
        guard !testing else { return false }
        switch provider.auth {
        case .apiKey: return !trimmedKey.isEmpty || store.hasKey(provider)
        case .localEndpoint: return !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private var canRemove: Bool {
        provider.auth == .apiKey && store.hasKey(provider)
    }

    private var statusBadge: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(isConfigured ? .green : .secondary.opacity(0.4))
                .frame(width: 8, height: 8)
            Text(isConfigured ? "Configured" : "Not configured")
                .font(.kelid(12, .medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    /// The stored key is never auto-loaded into memory — the field stays empty
    /// until the user types a new key or authenticates to reveal the saved one.
    private func load() {
        key = ""
        let cfg = store.config(for: provider)
        baseURL = cfg.baseURL.isEmpty ? provider.defaultBaseURL : cfg.baseURL
        revealKey = false
    }

    private var keyFieldPrompt: String {
        if key.isEmpty && store.hasKey(provider) {
            return "Saved — type to replace, or reveal"
        }
        return provider.keyHint
    }

    private func toggleReveal() {
        if revealKey {
            // Hiding again: if the field holds the stored key (not a fresh
            // entry), drop it from memory too.
            revealKey = false
            if key == store.apiKey(for: provider) { key = "" }
            return
        }
        // Revealing the stored key requires user presence.
        if key.isEmpty, store.hasKey(provider) {
            Task {
                let ok = await TouchIDService.requireUserPresence(
                    reason: "reveal the \(provider.name) API key"
                )
                if ok {
                    key = store.apiKey(for: provider) ?? ""
                    revealKey = true
                } else {
                    toast = .error("Authentication required to reveal the key")
                }
            }
        } else {
            revealKey = true
        }
    }

    private func save() {
        switch provider.auth {
        case .apiKey:
            store.setAPIKey(trimmedKey, for: provider)
            key = ""
            revealKey = false
            toast = .success("\(provider.name) key saved")
        case .localEndpoint:
            store.setBaseURL(baseURL.trimmingCharacters(in: .whitespaces), for: provider)
            toast = .success("Endpoint saved")
        }
    }

    private func remove() {
        store.removeKey(for: provider)
        key = ""
        toast = .info("\(provider.name) key removed")
    }

    private func runTest() {
        testing = true
        // Field empty but a key is saved: use the stored key transiently,
        // without ever displaying it.
        let testKey = trimmedKey.isEmpty ? (store.apiKey(for: provider) ?? "") : trimmedKey
        let testURL = baseURL.trimmingCharacters(in: .whitespaces)
        Task {
            let result = await AIProviderClient.test(provider, key: testKey, baseURL: testURL)
            switch result {
            case .ok(let msg): toast = .success(msg)
            case .failed(let msg): toast = .error(msg)
            case .unsupported(let msg): toast = .info(msg)
            }
            testing = false
        }
    }
}
