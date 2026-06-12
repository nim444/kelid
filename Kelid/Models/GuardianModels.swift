import Foundation

/// Sensitivity tier of a secret — drives how the Guardian gates access.
enum Tier: String, Codable, CaseIterable, Identifiable {
    case low, medium, high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    var summary: String {
        switch self {
        case .low: "Auto-allowed unless the rule requires a reason."
        case .medium: "Guardian-gated. Fails open (flagged) if the guardian is unavailable."
        case .high: "Guardian-gated, stricter threshold. Fails closed if unavailable."
        }
    }
}

/// A Guardian: an AI judge that scores whether a stated reason justifies
/// handing a secret to a caller. Mirrors Svault's JudgeDef; the API key is
/// NOT here — it comes from the provider's Keychain entry.
struct Guardian: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var providerID: String // AIProvider.rawValue
    var model: String
    var allowThreshold: Int = 60 // medium tier releases at >= this score
    var highThreshold: Int = 80  // high tier releases at >= this score
    var criteria: String = ""    // free-text rules appended to the system prompt

    var provider: AIProvider? { AIProvider(rawValue: providerID) }
}

extension Guardian {
    /// Tolerant decoding: new fields in later releases must never make stored
    /// guardians undecodable — that would silently reset the list.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        providerID = (try? c.decode(String.self, forKey: .providerID)) ?? ""
        model = (try? c.decode(String.self, forKey: .model)) ?? ""
        allowThreshold = (try? c.decode(Int.self, forKey: .allowThreshold)) ?? 60
        highThreshold = (try? c.decode(Int.self, forKey: .highThreshold)) ?? 80
        criteria = (try? c.decode(String.self, forKey: .criteria)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, providerID, model, allowThreshold, highThreshold, criteria
    }
}

/// Per-secret policy. Kelid's deliberate change vs Svault: the rate limit
/// lives HERE, on the secret — not in per-vault caller rules — so protection
/// and sealing are properties of the secret itself.
struct SecretRule: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String              // secret name, e.g. "DB_URL"
    var scope: String             // e.g. "database"
    var tier: Tier = .medium
    var requireReason: Bool = false // force the guardian even for low tier
    var ruleDescription: String = "" // what the secret is for — given to the guardian
    var rateLimit: String = "5/hour" // count/unit (s|m|h|d), caller-agnostic, per secret
    var requiredCallers: [String] = [] // empty = any caller
}

/// A sealed secret: brute-force response. Once sealed, every request is
/// denied before any other check until a human clears it.
struct Seal: Codable, Hashable {
    var sealedAt: Date
    var trigger: String     // e.g. "5 denials in 300s"
    var lastCaller: String
    var denials: Int
}

extension Seal {
    /// Tolerant decoding — a seal must never silently disappear because a
    /// later release added a field.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sealedAt = (try? c.decode(Date.self, forKey: .sealedAt)) ?? .now
        trigger = (try? c.decode(String.self, forKey: .trigger)) ?? "sealed"
        lastCaller = (try? c.decode(String.self, forKey: .lastCaller)) ?? "unknown"
        denials = (try? c.decode(Int.self, forKey: .denials)) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case sealedAt, trigger, lastCaller, denials
    }
}
