import Foundation
import Observation

/// Guardians (AI judges) — creation, default selection, and the global
/// switch. Mirrors Svault's judge registry: guardians are global, and each
/// vault either assigns one by name or falls back to the default.
///
/// Per-secret policy enforcement (PolicyEngine: rate limits, bursts, seals)
/// attaches to vault secrets when the vault engine ships — it is not part of
/// this store. API keys stay in the provider Keychain entries.
@MainActor
@Observable
final class GuardianStore {
    private enum Keys {
        static let guardians = "guardians"
        static let enabled = "guardian_enabled"
        static let defaultID = "guardian_default"
    }

    private(set) var guardians: [Guardian]
    var defaultGuardianID: UUID? {
        didSet { UserDefaults.standard.set(defaultGuardianID?.uuidString, forKey: Keys.defaultID) }
    }
    var globalEnabled: Bool {
        didSet { UserDefaults.standard.set(globalEnabled, forKey: Keys.enabled) }
    }

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Keys.guardians),
           let decoded = try? JSONDecoder().decode([Guardian].self, from: data) {
            guardians = decoded
        } else {
            guardians = []
        }
        globalEnabled = defaults.bool(forKey: Keys.enabled)
        defaultGuardianID = defaults.string(forKey: Keys.defaultID).flatMap(UUID.init)
    }

    var defaultGuardian: Guardian? {
        guardians.first { $0.id == defaultGuardianID } ?? guardians.first
    }

    func guardian(id: UUID?) -> Guardian? {
        guard let id else { return defaultGuardian }
        return guardians.first { $0.id == id } ?? defaultGuardian
    }

    /// Operational = globally on, and the default guardian's provider has a
    /// credential (or is a local runtime).
    func isOperational(providers: ProvidersStore) -> Bool {
        guard globalEnabled, let guardian = defaultGuardian, let provider = guardian.provider else { return false }
        return providers.isConfigured(provider)
    }

    // MARK: - CRUD

    func add(_ guardian: Guardian) {
        guardians.append(guardian)
        if guardians.count == 1 {
            defaultGuardianID = guardian.id
            globalEnabled = true // first guardian flips the global switch on
        }
        persist()
    }

    func update(_ guardian: Guardian) {
        if let index = guardians.firstIndex(where: { $0.id == guardian.id }) {
            guardians[index] = guardian
            persist()
        }
    }

    func removeGuardian(_ guardian: Guardian) {
        guardians.removeAll { $0.id == guardian.id }
        if defaultGuardianID == guardian.id { defaultGuardianID = guardians.first?.id }
        if guardians.isEmpty { globalEnabled = false }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(guardians) {
            UserDefaults.standard.set(data, forKey: Keys.guardians)
        }
    }
}
