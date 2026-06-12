import Foundation

/// The enforced agent path: every MCP `get_secret` runs through here.
/// Svault's gate semantics — serves only unlocked state, generic denials to
/// the caller (the real reason goes only to the audit log), per-secret rate
/// limits and bursts, auto-seal on repeated denials, guardian verdicts via
/// the vault's assigned guardian (medium fails open flagged, high fails
/// closed). A Telegram alert fires when a secret seals.
@MainActor
final class GateService {
    /// What an agent is told. Denials are deliberately generic.
    static let genericDeny = "denied: request not authorized for this secret"

    enum Outcome {
        case granted(String)
        case denied
        case notFound(String)   // message, isError
        case locked(String)
    }

    private let app: AppStore
    private let vaults: VaultsStore
    private let secrets: SecretsStore
    private let guardians: GuardianStore
    private let providers: ProvidersStore
    private let telegram: TelegramStore

    private var activity: [PolicyEngine.ActivityRecord]

    init(
        app: AppStore, vaults: VaultsStore, secrets: SecretsStore,
        guardians: GuardianStore, providers: ProvidersStore, telegram: TelegramStore
    ) {
        self.app = app
        self.vaults = vaults
        self.secrets = secrets
        self.guardians = guardians
        self.providers = providers
        self.telegram = telegram
        self.activity = Self.loadActivity()
    }

    // MARK: - Tools

    func listVaults() -> [[String: Any]] {
        let unlocked = !app.isLocked
        return vaults.vaults.map { vault in
            [
                "name": vault.name,
                "unlocked": unlocked,
                "description": vault.vaultDescription,
            ]
        }
    }

    func getSecret(vaultName: String, name: String, scope: String, reason: String, caller: String) async -> Outcome {
        // Serve only from unlocked state — an agent can never unlock.
        guard !app.isLocked else {
            return .locked("Kelid is locked — a human must unlock it before secrets can be served")
        }

        guard let vault = vaults.vaults.first(where: { $0.name == vaultName }) else {
            return .notFound("no vault named '\(vaultName)' — use kelid_list_vaults to discover vault names")
        }

        // Vault-level door: who may even ask.
        switch vault.agentMode {
        case .none:
            return deny(vault: vault, secretName: name, caller: caller, why: "vault is human-only (no agents)", secret: nil)
        case .list:
            if !vault.allowedCallers.contains(caller) {
                return deny(vault: vault, secretName: name, caller: caller, why: "caller '\(caller)' not in the vault's allowlist", secret: nil)
            }
        case .all:
            break
        }

        guard let secret = secrets.secrets(for: vault.id).first(where: { $0.name == name }) else {
            return .notFound("secret '\(name)' not found")
        }

        // Stated scope must match the secret's scope.
        if scope.trimmingCharacters(in: .whitespaces).lowercased() != secret.scope.lowercased() {
            return deny(vault: vault, secretName: name, caller: caller, why: "scope mismatch (stated '\(scope)', secret is '\(secret.scope)')", secret: secret)
        }

        // Time windows (after caller checks, before rate — svault order).
        if !withinWindows(secret.timeWindows) {
            return deny(vault: vault, secretName: name, caller: caller, why: "outside the allowed time window", secret: secret)
        }

        // Deterministic gates: seal → reason → callers → rate → bursts → tier.
        let key = activityKey(vault.id, secret.name)
        let rule = SecretRule(
            name: secret.name,
            scope: secret.scope,
            tier: secret.tier,
            requireReason: secret.requireReason,
            ruleDescription: secret.secretDescription,
            rateLimit: secret.rateLimit,
            requiredCallers: secret.requiredCallers
        )
        let gate = PolicyEngine.gate(
            secret: key,
            caller: caller,
            reason: reason,
            rule: rule,
            seal: secrets.seal(for: secret, in: vault.id),
            recent: activity
        )

        switch gate {
        case .deny(let why):
            return deny(vault: vault, secretName: name, caller: caller, why: why, secret: secret)
        case .allow(let note):
            return grant(vault: vault, secret: secret, caller: caller, score: nil, note: note ?? "low tier — auto-allowed")
        case .needsJudge:
            break
        }

        // Guardian path with svault failure semantics.
        guard guardians.globalEnabled,
              vault.guardianEnabled,
              let guardian = guardians.guardian(id: vault.assignedGuardianID),
              let provider = guardian.provider
        else {
            return judgeOff(vault: vault, secret: secret, caller: caller, why: "no guardian active")
        }

        let apiKey = providers.apiKey(for: provider)
        if provider.auth == .apiKey, apiKey == nil {
            return judgeOff(vault: vault, secret: secret, caller: caller, why: "\(provider.name) has no key")
        }

        let verdict = await JudgeClient.evaluate(
            guardian: guardian,
            request: JudgeClient.JudgeRequest(
                caller: caller,
                secret: secret.name,
                scope: secret.scope,
                tier: secret.tier,
                secretPurpose: secret.secretDescription.isEmpty
                    ? vault.vaultDescription
                    : secret.secretDescription,
                reason: reason,
                recentSummary: recentSummary(key: key)
            ),
            apiKey: apiKey,
            baseURL: JudgeClient.normalizedOpenAIBase(provider: provider, baseURL: providers.config(for: provider).baseURL)
        )

        let threshold = secret.tier == .high ? guardian.highThreshold : guardian.allowThreshold
        switch verdict {
        case .allow(let score, let rationale):
            if score >= threshold {
                return grant(vault: vault, secret: secret, caller: caller, score: score, note: rationale)
            }
            return deny(vault: vault, secretName: secret.name, caller: caller, why: "guardian score \(score) below threshold \(threshold)", secret: secret)
        case .deny(let score, let rationale):
            return deny(vault: vault, secretName: secret.name, caller: caller, why: "guardian denied (\(score)): \(rationale)", secret: secret)
        case .unavailable(let why):
            return judgeOff(vault: vault, secret: secret, caller: caller, why: "guardian unavailable: \(why)")
        }
    }

    // MARK: - Outcomes

    private func grant(vault: Vault, secret: VaultSecret, caller: String, score: Int?, note: String) -> Outcome {
        guard let value = secrets.revealValue(of: secret, in: vault.id) else {
            return .notFound("secret '\(secret.name)' has no stored value")
        }
        record(vault: vault, secret: secret, caller: caller, allowed: true)
        let scoreText = score.map { " (score \($0))" } ?? ""
        AuditLog.shared.record(.agent, "Request allowed", detail: "\(vault.name)/\(secret.name) — \(caller)\(scoreText) [mcp]")
        return .granted(value)
    }

    private func deny(vault: Vault, secretName: String, caller: String, why: String, secret: VaultSecret?) -> Outcome {
        if let secret {
            record(vault: vault, secret: secret, caller: caller, allowed: false)
        }
        AuditLog.shared.record(.agent, "Request denied", detail: "\(vault.name)/\(secretName) — \(caller): \(why) [mcp]", outcome: .denied)

        // Brute-force response: repeated denials seal the secret itself.
        if let secret,
           secrets.seal(for: secret, in: vault.id) == nil,
           PolicyEngine.shouldSeal(secret: activityKey(vault.id, secret.name), tier: secret.tier, recent: activity) {
            secrets.autoSeal(secret, in: vault.id, lastCaller: caller)
            AuditLog.shared.record(.secret, "Secret sealed", detail: "\(vault.name)/\(secret.name) — 5 denials in 300s, last caller \(caller)", outcome: .failure)
            alertSeal(vault: vault, secret: secret, caller: caller)
        }
        return .denied
    }

    /// Svault semantics when no guardian can rule: medium fails open
    /// (flagged), high fails closed.
    private func judgeOff(vault: Vault, secret: VaultSecret, caller: String, why: String) -> Outcome {
        switch secret.tier {
        case .high:
            return deny(vault: vault, secretName: secret.name, caller: caller, why: "\(why) — high tier fails closed", secret: secret)
        default:
            return grant(vault: vault, secret: secret, caller: caller, score: nil, note: "\(why) — allowed with flag")
        }
    }

    /// Sealing is exactly what the alert channel exists for.
    private func alertSeal(vault: Vault, secret: VaultSecret, caller: String) {
        guard let token = telegram.token, !telegram.whitelist.isEmpty else { return }
        let chats = telegram.whitelist
        let text = "Kelid alert: secret \(secret.name) in vault \(vault.name) was sealed after repeated denials (last caller: \(caller)). Every request is now denied until you unseal it in Kelid."
        Task {
            for chat in chats {
                try? await TelegramService.send(token: token, text: text, to: chat.id, whitelist: chats)
            }
        }
    }

    // MARK: - Activity window

    private func activityKey(_ vaultID: UUID, _ name: String) -> String {
        "\(vaultID.uuidString)/\(name)"
    }

    private func record(vault: Vault, secret: VaultSecret, caller: String, allowed: Bool) {
        activity.append(.init(secret: activityKey(vault.id, secret.name), caller: caller, allowed: allowed, at: .now))
        let cutoff = Date.now.addingTimeInterval(-86400)
        activity.removeAll { $0.at < cutoff }
        persistActivity()
    }

    private func recentSummary(key: String) -> String {
        let now = Date.now
        let window = activity.filter { $0.secret == key && now.timeIntervalSince($0.at) < 600 }
        guard !window.isEmpty else { return "" }
        let denials = window.count { !$0.allowed }
        return "\(window.count) requests for this secret in the last 10 min, \(denials) denied"
    }

    // MARK: - Time windows ("mon-fri 09:00-18:00", "fri 10:00-12:00", "09:00-17:00")

    func withinWindows(_ windows: [String], now: Date = .now) -> Bool {
        guard !windows.isEmpty else { return true }
        return windows.contains { matches(window: $0, now: now) }
    }

    private func matches(window: String, now: Date) -> Bool {
        let parts = window.lowercased().split(separator: " ").map(String.init)
        let dayPart: String?
        let timePart: String
        switch parts.count {
        case 1: dayPart = nil; timePart = parts[0]
        case 2: dayPart = parts[0]; timePart = parts[1]
        default: return false
        }

        let calendar = Calendar.current
        if let dayPart, !dayMatches(dayPart, weekday: calendar.component(.weekday, from: now)) {
            return false
        }

        let range = timePart.split(separator: "-").map(String.init)
        guard range.count == 2,
              let start = minutes(range[0]), let end = minutes(range[1])
        else { return false }
        let nowMinutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        return nowMinutes >= start && nowMinutes < end // start inclusive, end exclusive
    }

    private func dayMatches(_ spec: String, weekday: Int) -> Bool {
        // Calendar weekday: 1=sun ... 7=sat. Map to mon=0 ... sun=6.
        let today = (weekday + 5) % 7
        let names = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
        for token in spec.split(separator: ",").map(String.init) {
            if token.contains("-") {
                let bounds = token.split(separator: "-").map(String.init)
                guard bounds.count == 2,
                      let lo = names.firstIndex(of: bounds[0]),
                      let hi = names.firstIndex(of: bounds[1])
                else { continue }
                if lo <= hi ? (today >= lo && today <= hi) : (today >= lo || today <= hi) {
                    return true
                }
            } else if names.firstIndex(of: token) == today {
                return true
            }
        }
        return false
    }

    private func minutes(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":").map(String.init)
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m)
        else { return nil }
        return h * 60 + m
    }

    // MARK: - Persistence

    private static var stateURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kelid", isDirectory: true)
            .appendingPathComponent("gate-state.json")
    }

    private static func loadActivity() -> [PolicyEngine.ActivityRecord] {
        guard let data = try? Data(contentsOf: stateURL),
              let decoded = try? JSONDecoder().decode([PolicyEngine.ActivityRecord].self, from: data)
        else { return [] }
        return decoded
    }

    private func persistActivity() {
        guard let data = try? JSONEncoder().encode(activity) else { return }
        let dir = Self.stateURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        try? data.write(to: Self.stateURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.stateURL.path)
    }
}
