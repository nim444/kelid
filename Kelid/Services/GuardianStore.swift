import Foundation
import Observation

/// State and orchestration for the Guardian subsystem: guardians (AI judges),
/// per-secret policy rules, seals, and the recent-activity window that feeds
/// rate/burst/seal counting.
///
/// Persistence: guardians + rules + flags in UserDefaults (no secrets — API
/// keys stay in the provider Keychain entries). Seals + activity in
/// guardian-state.json (0600, sandbox container) so seals survive restarts.
@MainActor
@Observable
final class GuardianStore {
    private enum Keys {
        static let guardians = "guardians"
        static let rules = "guardian_rules"
        static let enabled = "guardian_enabled"
        static let defaultID = "guardian_default"
    }

    private(set) var guardians: [Guardian]
    private(set) var rules: [SecretRule]
    private(set) var seals: [String: Seal]
    var defaultGuardianID: UUID? {
        didSet { UserDefaults.standard.set(defaultGuardianID?.uuidString, forKey: Keys.defaultID) }
    }
    var globalEnabled: Bool {
        didSet { UserDefaults.standard.set(globalEnabled, forKey: Keys.enabled) }
    }

    private var activity: [PolicyEngine.ActivityRecord] = []

    init() {
        let defaults = UserDefaults.standard
        guardians = Self.decode([Guardian].self, defaults.data(forKey: Keys.guardians)) ?? []
        rules = Self.decode([SecretRule].self, defaults.data(forKey: Keys.rules)) ?? []
        globalEnabled = defaults.bool(forKey: Keys.enabled)
        defaultGuardianID = defaults.string(forKey: Keys.defaultID).flatMap(UUID.init)
        let state = Self.loadState()
        seals = state.seals
        activity = state.activity
        pruneActivity()
    }

    var defaultGuardian: Guardian? {
        guardians.first { $0.id == defaultGuardianID } ?? guardians.first
    }

    /// The guardian is operational when globally on and a guardian exists
    /// whose provider has a credential (or is a local runtime).
    func isOperational(providers: ProvidersStore) -> Bool {
        guard globalEnabled, let guardian = defaultGuardian, let provider = guardian.provider else { return false }
        return providers.isConfigured(provider)
    }

    // MARK: - Guardian CRUD

    func add(_ guardian: Guardian) {
        guardians.append(guardian)
        if guardians.count == 1 {
            defaultGuardianID = guardian.id
            globalEnabled = true // first guardian flips the global switch on
        }
        persistGuardians()
    }

    func update(_ guardian: Guardian) {
        if let index = guardians.firstIndex(where: { $0.id == guardian.id }) {
            guardians[index] = guardian
            persistGuardians()
        }
    }

    func removeGuardian(_ guardian: Guardian) {
        guardians.removeAll { $0.id == guardian.id }
        if defaultGuardianID == guardian.id { defaultGuardianID = guardians.first?.id }
        if guardians.isEmpty { globalEnabled = false }
        persistGuardians()
    }

    // MARK: - Rule CRUD

    func addRule(_ rule: SecretRule) {
        rules.append(rule)
        persistRules()
    }

    func updateRule(_ rule: SecretRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
            persistRules()
        }
    }

    func removeRule(_ rule: SecretRule) {
        rules.removeAll { $0.id == rule.id }
        seals.removeValue(forKey: rule.name)
        persistRules()
        persistState()
    }

    // MARK: - The request pipeline

    struct Evaluation {
        var allowed: Bool
        var score: Int?
        var rationale: String
        var note: String
        var sealedNow: Bool
    }

    /// Full Svault-order pipeline against a rule: deterministic gates first,
    /// then the AI guardian for medium/high (or low + requireReason). Every
    /// outcome is recorded for rate/seal counting and audited.
    func evaluate(
        rule: SecretRule,
        caller: String,
        reason: String,
        providers: ProvidersStore
    ) async -> Evaluation {
        let gate = PolicyEngine.gate(
            secret: rule.name,
            caller: caller,
            reason: reason,
            rule: rule,
            seal: seals[rule.name],
            recent: activity
        )

        switch gate {
        case .deny(let why):
            return finishDenied(rule: rule, caller: caller, why: why, score: nil)

        case .allow(let note):
            return finishAllowed(rule: rule, caller: caller, score: nil, note: note ?? "low tier — auto-allowed")

        case .needsJudge:
            break
        }

        // Guardian path.
        guard globalEnabled, let guardian = defaultGuardian, let provider = guardian.provider else {
            return judgeUnavailable(rule: rule, caller: caller, why: "no guardian configured")
        }

        let apiKey = providers.apiKey(for: provider)
        if provider.auth == .apiKey, apiKey == nil {
            return judgeUnavailable(rule: rule, caller: caller, why: "\(provider.name) has no key")
        }

        let baseURL = JudgeClient.normalizedOpenAIBase(
            provider: provider,
            baseURL: providers.config(for: provider).baseURL
        )
        let verdict = await JudgeClient.evaluate(
            guardian: guardian,
            request: JudgeClient.JudgeRequest(
                caller: caller,
                secret: rule.name,
                scope: rule.scope,
                tier: rule.tier,
                secretPurpose: rule.ruleDescription,
                reason: reason,
                recentSummary: recentSummary(secret: rule.name)
            ),
            apiKey: apiKey,
            baseURL: baseURL
        )

        let threshold = rule.tier == .high ? guardian.highThreshold : guardian.allowThreshold
        switch verdict {
        case .allow(let score, let rationale):
            if score >= threshold {
                return finishAllowed(rule: rule, caller: caller, score: score, note: rationale)
            }
            return finishDenied(rule: rule, caller: caller, why: "guardian score \(score) below threshold \(threshold)", score: score, rationale: rationale)
        case .deny(let score, let rationale):
            return finishDenied(rule: rule, caller: caller, why: "guardian denied (\(score))", score: score, rationale: rationale)
        case .unavailable(let why):
            return judgeUnavailable(rule: rule, caller: caller, why: why)
        }
    }

    /// Human-only unseal. Caller must have passed a fresh user-presence check.
    func unseal(_ secretName: String) {
        seals.removeValue(forKey: secretName)
        // Clear the denial window too, or the next denial instantly re-seals.
        activity.removeAll { $0.secret == secretName && !$0.allowed }
        persistState()
        AuditLog.shared.record(.guardian, "Seal cleared", detail: secretName)
    }

    // MARK: - Outcomes

    private func finishAllowed(rule: SecretRule, caller: String, score: Int?, note: String) -> Evaluation {
        recordActivity(secret: rule.name, caller: caller, allowed: true)
        let detail = score.map { "\(rule.name) — \(caller) (score \($0))" } ?? "\(rule.name) — \(caller)"
        AuditLog.shared.record(.guardian, "Request allowed", detail: detail)
        return Evaluation(allowed: true, score: score, rationale: note, note: note, sealedNow: false)
    }

    private func finishDenied(rule: SecretRule, caller: String, why: String, score: Int?, rationale: String = "") -> Evaluation {
        recordActivity(secret: rule.name, caller: caller, allowed: false)
        AuditLog.shared.record(.guardian, "Request denied", detail: "\(rule.name) — \(caller): \(why)", outcome: .denied)

        var sealedNow = false
        if seals[rule.name] == nil,
           PolicyEngine.shouldSeal(secret: rule.name, tier: rule.tier, recent: activity) {
            seals[rule.name] = Seal(
                sealedAt: .now,
                trigger: "\(PolicyEngine.sealDenyThreshold) denials in \(Int(PolicyEngine.sealWindowSecs))s",
                lastCaller: caller,
                denials: PolicyEngine.sealDenyThreshold
            )
            sealedNow = true
            persistState()
            AuditLog.shared.record(.guardian, "Secret sealed", detail: "\(rule.name) — \(seals[rule.name]!.trigger)", outcome: .failure)
        }
        return Evaluation(allowed: false, score: score, rationale: rationale.isEmpty ? why : rationale, note: why, sealedNow: sealedNow)
    }

    private func judgeUnavailable(rule: SecretRule, caller: String, why: String) -> Evaluation {
        // Svault semantics: medium fails open (flagged), high fails closed.
        switch rule.tier {
        case .high:
            return finishDenied(rule: rule, caller: caller, why: "guardian unavailable (\(why)) — high tier fails closed", score: nil)
        default:
            return finishAllowed(rule: rule, caller: caller, score: nil, note: "guardian unavailable (\(why)) — allowed with flag")
        }
    }

    private func recentSummary(secret: String) -> String {
        let now = Date.now
        let window = activity.filter { $0.secret == secret && now.timeIntervalSince($0.at) < 600 }
        guard !window.isEmpty else { return "" }
        let denials = window.count { !$0.allowed }
        return "\(window.count) requests for this secret in the last 10 min, \(denials) denied"
    }

    // MARK: - Activity + persistence

    private func recordActivity(secret: String, caller: String, allowed: Bool) {
        activity.append(.init(secret: secret, caller: caller, allowed: allowed, at: .now))
        pruneActivity()
        persistState()
    }

    private func pruneActivity() {
        let cutoff = Date.now.addingTimeInterval(-86400)
        activity.removeAll { $0.at < cutoff }
    }

    private struct PersistedState: Codable {
        var seals: [String: Seal] = [:]
        var activity: [PolicyEngine.ActivityRecord] = []
    }

    private static var stateURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kelid", isDirectory: true)
            .appendingPathComponent("guardian-state.json")
    }

    private static func loadState() -> (seals: [String: Seal], activity: [PolicyEngine.ActivityRecord]) {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data)
        else { return ([:], []) }
        return (state.seals, state.activity)
    }

    private func persistState() {
        let state = PersistedState(seals: seals, activity: activity)
        guard let data = try? JSONEncoder().encode(state) else { return }
        let dir = Self.stateURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        try? data.write(to: Self.stateURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.stateURL.path)
    }

    private func persistGuardians() {
        if let data = try? JSONEncoder().encode(guardians) {
            UserDefaults.standard.set(data, forKey: Keys.guardians)
        }
    }

    private func persistRules() {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: Keys.rules)
        }
    }

    private static func decode<T: Codable>(_ type: T.Type, _ data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
