import Foundation

/// Who may even ask for secrets from a vault (Svault's allow_agent mode).
/// Every allowed request still runs the full gate.
enum AgentMode: String, Codable, CaseIterable, Identifiable {
    case none, list, all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "No agents"
        case .list: "Named only"
        case .all: "Any agent"
        }
    }

    var help: String {
        switch self {
        case .none: "No agent may request secrets from this vault — human-only access."
        case .list: "Only the callers you name may ask. Anything else is denied before any other check runs."
        case .all: "Any caller may ask — every request still passes the full gate (scope, tier, rate limit, guardian)."
        }
    }
}

/// Vault metadata + policy settings. The encrypted secret store itself ships
/// with the crypto core; these settings bind to it then. Kelid's change vs
/// Svault: the rate limit here is the DEFAULT PER-SECRET limit for new
/// secrets — enforcement is per secret, not per vault.
struct Vault: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var vaultDescription: String = ""
    var agentMode: AgentMode = .none
    var allowedCallers: [String] = []
    var defaultSecretRateLimit: String = "10/hour"
    var defaultTier: Tier = .medium
    var guardianEnabled: Bool = true
    var assignedGuardianID: UUID? // nil = default guardian
    var autoLock: Bool = true
    var autoLockTimer: String = "30m"
    var loginMethod: LoginMethod = .passphrase
    var createdAt: Date = .now

    enum LoginMethod: String, Codable, CaseIterable, Identifiable {
        case passphrase, yubikey
        var id: String { rawValue }
        var title: String {
            switch self {
            case .passphrase: "Passphrase"
            case .yubikey: "YubiKey"
            }
        }
    }
}
