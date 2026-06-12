import CryptoKit
import Foundation
import Observation

/// One audited action. Events form a tamper-evident hash chain: every entry
/// carries the previous entry's hash inside its own, so editing or deleting
/// any line on disk breaks verification for everything after it.
/// Details never contain secret values — names and outcomes only.
struct AuditEvent: Codable, Identifiable, Hashable {
    enum Category: String, Codable, CaseIterable, Identifiable {
        case session, master, touchID, yubiKey, provider, telegram, guardian, secret, agent, system

        var id: String { rawValue }

        var title: String {
            switch self {
            case .session: "Session"
            case .master: "Master"
            case .touchID: "Touch ID"
            case .yubiKey: "YubiKey"
            case .provider: "AI Providers"
            case .telegram: "Telegram"
            case .guardian: "Guardian"
            case .secret: "Secrets"
            case .agent: "Agents"
            case .system: "System"
            }
        }

        var icon: String {
            switch self {
            case .session: "lock.open"
            case .master: "key.horizontal"
            case .touchID: "touchid"
            case .yubiKey: "key.radiowaves.forward"
            case .provider: "cpu"
            case .telegram: "paperplane"
            case .guardian: "checkmark.shield"
            case .secret: "key.horizontal.fill"
            case .agent: "antenna.radiowaves.left.and.right"
            case .system: "gearshape"
            }
        }
    }

    enum Outcome: String, Codable {
        case success, failure, denied, info
    }

    let id: UUID
    let at: Date
    let category: Category
    let action: String
    let detail: String
    let outcome: Outcome
    let prevHash: String
    let hash: String
}

/// Append-only audit log: JSONL on disk (0600, inside the sandbox container),
/// hash-chain verified on every load. The chain alone cannot detect a
/// truncated tail (a clean prefix still verifies), so the latest head hash +
/// count are anchored in the Keychain and compared on load.
@MainActor
@Observable
final class AuditLog {
    static let shared = AuditLog()

    private static let anchorAccount = "audit.head"

    private(set) var events: [AuditEvent] = []
    /// False if the on-disk log failed hash-chain or head-anchor verification.
    private(set) var chainValid = true

    private var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kelid", isDirectory: true)
            .appendingPathComponent("audit.jsonl")
    }

    private init() {
        load()
    }

    func record(
        _ category: AuditEvent.Category,
        _ action: String,
        detail: String = "",
        outcome: AuditEvent.Outcome = .success
    ) {
        let prev = events.last?.hash ?? "genesis"
        let id = UUID()
        let at = Date()
        let hash = Self.entryHash(
            prev: prev, id: id, at: at,
            category: category, action: action, detail: detail, outcome: outcome
        )
        let event = AuditEvent(
            id: id, at: at, category: category, action: action,
            detail: detail, outcome: outcome, prevHash: prev, hash: hash
        )
        events.append(event)
        append(event)
        KeychainStore.set("\(events.count)|\(event.hash)", account: Self.anchorAccount)
    }

    // MARK: - Persistence

    private func append(_ event: AuditEvent) {
        // Auditing must never crash the app; failures here are silent by design.
        do {
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)

            var line = try JSONEncoder().encode(event)
            line.append(0x0A)

            if FileManager.default.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try line.write(to: fileURL, options: [.atomic])
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            }
        } catch {}
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return }
        let decoder = JSONDecoder()
        var loaded: [AuditEvent] = []
        for line in data.split(separator: 0x0A) {
            if let event = try? decoder.decode(AuditEvent.self, from: line) {
                loaded.append(event)
            }
        }
        events = loaded
        chainValid = verifyChain(loaded) && headMatchesAnchor(loaded)
    }

    /// Detects tail truncation: the anchored head must be this chain's last
    /// entry (or an earlier entry only when the app died between appending a
    /// line and updating the anchor — then newer events follow it). An empty
    /// file is a legitimate fresh start (wiped container); a non-empty chain
    /// that doesn't contain the anchored head was replaced wholesale.
    private func headMatchesAnchor(_ events: [AuditEvent]) -> Bool {
        guard let anchor = KeychainStore.get(account: Self.anchorAccount) else { return true }
        let parts = anchor.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let anchorCount = Int(parts[0]) else { return true }
        if events.isEmpty { return true }
        guard let index = events.firstIndex(where: { $0.hash == parts[1] }) else { return false }
        return index == anchorCount - 1
    }

    private func verifyChain(_ events: [AuditEvent]) -> Bool {
        var prev = "genesis"
        for event in events {
            let expected = Self.entryHash(
                prev: prev, id: event.id, at: event.at,
                category: event.category, action: event.action,
                detail: event.detail, outcome: event.outcome
            )
            guard event.prevHash == prev, event.hash == expected else { return false }
            prev = event.hash
        }
        return true
    }

    private nonisolated static func entryHash(
        prev: String, id: UUID, at: Date,
        category: AuditEvent.Category, action: String, detail: String, outcome: AuditEvent.Outcome
    ) -> String {
        let stamp = String(format: "%.6f", at.timeIntervalSince1970)
        let material = [prev, id.uuidString, stamp, category.rawValue, action, detail, outcome.rawValue]
            .joined(separator: "|")
        return SHA256.hash(data: Data(material.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
