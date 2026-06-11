import Foundation
import Observation

/// Tracks which AI providers are configured. Secrets (API keys) live in the
/// Keychain via KeychainStore; only non-secret config (enabled flag, base URL)
/// is persisted to UserDefaults.
@Observable
final class ProvidersStore {
    struct Config: Codable {
        var enabled: Bool = false
        var baseURL: String = ""
    }

    private static let defaultsKey = "ai_provider_configs"

    private(set) var configs: [String: Config]

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([String: Config].self, from: data) {
            configs = decoded
        } else {
            configs = [:]
        }
    }

    func config(for provider: AIProvider) -> Config {
        configs[provider.id] ?? Config(enabled: false, baseURL: provider.defaultBaseURL)
    }

    /// A provider is "ready" when a cloud key is stored, or a local endpoint
    /// has a base URL.
    func isConfigured(_ provider: AIProvider) -> Bool {
        switch provider.auth {
        case .apiKey:
            return KeychainStore.has(account: provider.keychainAccount)
        case .localEndpoint:
            return !config(for: provider).baseURL.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    func hasKey(_ provider: AIProvider) -> Bool {
        KeychainStore.has(account: provider.keychainAccount)
    }

    func apiKey(for provider: AIProvider) -> String? {
        KeychainStore.get(account: provider.keychainAccount)
    }

    func setAPIKey(_ key: String, for provider: AIProvider) {
        KeychainStore.set(key, account: provider.keychainAccount)
        touch(provider)
    }

    func removeKey(for provider: AIProvider) {
        KeychainStore.delete(account: provider.keychainAccount)
        var c = config(for: provider)
        c.enabled = false
        write(c, for: provider)
    }

    func setEnabled(_ enabled: Bool, for provider: AIProvider) {
        var c = config(for: provider)
        c.enabled = enabled
        write(c, for: provider)
    }

    func setBaseURL(_ url: String, for provider: AIProvider) {
        var c = config(for: provider)
        c.baseURL = url
        write(c, for: provider)
    }

    // MARK: - Persistence

    private func touch(_ provider: AIProvider) {
        if configs[provider.id] == nil {
            write(Config(enabled: true, baseURL: provider.defaultBaseURL), for: provider)
        }
    }

    private func write(_ config: Config, for provider: AIProvider) {
        configs[provider.id] = config
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
