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

    /// The agent-serving window after the last human unlock; nil = no limit.
    var autoLockSeconds: TimeInterval? {
        guard autoLock else { return nil }
        switch autoLockTimer {
        case "30m": return 30 * 60
        case "12h": return 12 * 3600
        case "1d": return 24 * 3600
        default: return 30 * 60
        }
    }
}

extension Vault {
    /// Tolerant decoding: a field added in a later release must never make
    /// stored vaults undecodable — that would silently reset the store and
    /// orphan every secret. Only `name` is required; everything else defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        vaultDescription = (try? c.decode(String.self, forKey: .vaultDescription)) ?? ""
        agentMode = (try? c.decode(AgentMode.self, forKey: .agentMode)) ?? .none
        allowedCallers = (try? c.decode([String].self, forKey: .allowedCallers)) ?? []
        defaultSecretRateLimit = (try? c.decode(String.self, forKey: .defaultSecretRateLimit)) ?? "10/hour"
        defaultTier = (try? c.decode(Tier.self, forKey: .defaultTier)) ?? .medium
        guardianEnabled = (try? c.decode(Bool.self, forKey: .guardianEnabled)) ?? true
        assignedGuardianID = try? c.decode(UUID.self, forKey: .assignedGuardianID)
        autoLock = (try? c.decode(Bool.self, forKey: .autoLock)) ?? true
        autoLockTimer = (try? c.decode(String.self, forKey: .autoLockTimer)) ?? "30m"
        loginMethod = (try? c.decode(LoginMethod.self, forKey: .loginMethod)) ?? .passphrase
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? .now
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, vaultDescription, agentMode, allowedCallers
        case defaultSecretRateLimit, defaultTier, guardianEnabled, assignedGuardianID
        case autoLock, autoLockTimer, loginMethod, createdAt
    }
}
