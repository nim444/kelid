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
