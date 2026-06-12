import Foundation

/// A secret's metadata + classification. The VALUE is never here — it lives
/// in the macOS Keychain (OS-encrypted), keyed per vault + secret, until the
/// crypto core migrates it into the vault's own encrypted store.
/// Rate limiting and sealing are per-secret by design.
struct VaultSecret: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String                  // how callers ask for it (DATABASE_URL)
    var scope: String = "misc"        // request must state the matching scope
    var tier: Tier = .medium
    var requireReason: Bool = false   // force the guardian even at low tier
    var secretDescription: String = "" // weighed by the guardian against each reason
    var requiredCallers: [String] = [] // empty = any caller the vault allows
    var timeWindows: [String] = []    // e.g. "mon-fri 09:00-18:00"; empty = any time
    var rateLimit: String = "10/hour" // per-secret, counted across all callers
    var createdAt: Date = .now
    var lastReadAt: Date?
}

extension VaultSecret {
    /// Tolerant decoding: new fields in later releases must never make stored
    /// metadata undecodable (that would reset the store and orphan the
    /// Keychain values). Only `name` is required.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        scope = (try? c.decode(String.self, forKey: .scope)) ?? "misc"
        tier = (try? c.decode(Tier.self, forKey: .tier)) ?? .medium
        requireReason = (try? c.decode(Bool.self, forKey: .requireReason)) ?? false
        secretDescription = (try? c.decode(String.self, forKey: .secretDescription)) ?? ""
        requiredCallers = (try? c.decode([String].self, forKey: .requiredCallers)) ?? []
        timeWindows = (try? c.decode([String].self, forKey: .timeWindows)) ?? []
        rateLimit = (try? c.decode(String.self, forKey: .rateLimit)) ?? "10/hour"
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? .now
        lastReadAt = try? c.decode(Date.self, forKey: .lastReadAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, scope, tier, requireReason, secretDescription
        case requiredCallers, timeWindows, rateLimit, createdAt, lastReadAt
    }
}
