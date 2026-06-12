import Foundation
import Observation

/// Secrets per vault. Values live in the macOS Keychain (account
/// `vault.<vaultID>.<name>`, OS-encrypted, ThisDeviceOnly) — never in this
/// store's persistence. Metadata in UserDefaults; seals in
/// secrets-state.json (0600) so they survive restarts.
@MainActor
@Observable
final class SecretsStore {
    private static let metaKey = "vault_secrets"

    /// vault id (uuidString) → its secrets.
    private(set) var secretsByVault: [String: [VaultSecret]]
    /// "vaultID/secretName" → seal.
    private(set) var seals: [String: Seal]

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.metaKey),
           let decoded = try? JSONDecoder().decode([String: [VaultSecret]].self, from: data) {
            secretsByVault = decoded
        } else {
            secretsByVault = [:]
        }
        seals = Self.loadSeals()
    }

    // MARK: - Queries

    func secrets(for vaultID: UUID) -> [VaultSecret] {
        secretsByVault[vaultID.uuidString] ?? []
    }

    var totalCount: Int {
        secretsByVault.values.reduce(0) { $0 + $1.count }
    }

    func nameTaken(_ name: String, in vaultID: UUID, excluding id: UUID? = nil) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespaces)
        return secrets(for: vaultID).contains { $0.name == normalized && $0.id != id }
    }

    func seal(for secret: VaultSecret, in vaultID: UUID) -> Seal? {
        seals[sealKey(vaultID, secret.name)]
    }

    // MARK: - CRUD

    /// False when the Keychain refused the value — no metadata is written
    /// then, so a secret can never exist without its value.
    @discardableResult
    func add(_ secret: VaultSecret, value: String, to vaultID: UUID) -> Bool {
        guard KeychainStore.set(value, account: keychainAccount(vaultID, secret.name)) else {
            return false
        }
        var list = secrets(for: vaultID)
        list.append(secret)
        secretsByVault[vaultID.uuidString] = list
        persistMeta()
        return true
    }

    /// Updates classification; replaces the value only when one is supplied.
    /// The name is the Keychain/seal key and must never change here — the UI
    /// disables it on edit; a programmatic rename would orphan the value.
    @discardableResult
    func update(_ secret: VaultSecret, newValue: String?, in vaultID: UUID) -> Bool {
        var list = secrets(for: vaultID)
        guard let index = list.firstIndex(where: { $0.id == secret.id }) else { return false }
        guard list[index].name == secret.name else {
            assertionFailure("secret rename is not supported — Keychain and seal keys are name-based")
            return false
        }
        if let newValue, !newValue.isEmpty {
            guard KeychainStore.set(newValue, account: keychainAccount(vaultID, secret.name)) else {
                return false
            }
        }
        list[index] = secret
        secretsByVault[vaultID.uuidString] = list
        persistMeta()
        return true
    }

    func remove(_ secret: VaultSecret, from vaultID: UUID) {
        var list = secrets(for: vaultID)
        list.removeAll { $0.id == secret.id }
        secretsByVault[vaultID.uuidString] = list
        KeychainStore.delete(account: keychainAccount(vaultID, secret.name))
        seals.removeValue(forKey: sealKey(vaultID, secret.name))
        persistMeta()
        persistSeals()
    }

    /// Removes every secret (values included) of a deleted vault.
    func removeAll(for vaultID: UUID) {
        for secret in secrets(for: vaultID) {
            KeychainStore.delete(account: keychainAccount(vaultID, secret.name))
            seals.removeValue(forKey: sealKey(vaultID, secret.name))
        }
        secretsByVault.removeValue(forKey: vaultID.uuidString)
        persistMeta()
        persistSeals()
    }

    // MARK: - Value access

    /// Fetches the value from the Keychain and stamps the read. The caller is
    /// responsible for the user-presence gate before invoking this.
    func revealValue(of secret: VaultSecret, in vaultID: UUID) -> String? {
        guard let value = KeychainStore.get(account: keychainAccount(vaultID, secret.name)) else {
            return nil
        }
        var stamped = secret
        stamped.lastReadAt = .now
        update(stamped, newValue: nil, in: vaultID)
        return value
    }

    // MARK: - Seals

    func sealManually(_ secret: VaultSecret, in vaultID: UUID) {
        seals[sealKey(vaultID, secret.name)] = Seal(
            sealedAt: .now,
            trigger: "sealed manually",
            lastCaller: "human",
            denials: 0
        )
        persistSeals()
    }

    /// Brute-force response from the gate: repeated denials sealed the secret.
    func autoSeal(_ secret: VaultSecret, in vaultID: UUID, lastCaller: String) {
        seals[sealKey(vaultID, secret.name)] = Seal(
            sealedAt: .now,
            trigger: "\(PolicyEngine.sealDenyThreshold) denials in \(Int(PolicyEngine.sealWindowSecs))s",
            lastCaller: lastCaller,
            denials: PolicyEngine.sealDenyThreshold
        )
        persistSeals()
    }

    /// Human-only; caller must have passed a fresh user-presence check.
    func unseal(_ secret: VaultSecret, in vaultID: UUID) {
        seals.removeValue(forKey: sealKey(vaultID, secret.name))
        persistSeals()
    }

    // MARK: - Keys + persistence

    private func keychainAccount(_ vaultID: UUID, _ name: String) -> String {
        "vault.\(vaultID.uuidString).\(name)"
    }

    private func sealKey(_ vaultID: UUID, _ name: String) -> String {
        "\(vaultID.uuidString)/\(name)"
    }

    private func persistMeta() {
        if let data = try? JSONEncoder().encode(secretsByVault) {
            UserDefaults.standard.set(data, forKey: Self.metaKey)
        }
    }

    private static var sealsURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Kelid", isDirectory: true)
            .appendingPathComponent("secrets-state.json")
    }

    private static func loadSeals() -> [String: Seal] {
        guard let data = try? Data(contentsOf: sealsURL),
              let decoded = try? JSONDecoder().decode([String: Seal].self, from: data)
        else { return [:] }
        return decoded
    }

    private func persistSeals() {
        guard let data = try? JSONEncoder().encode(seals) else { return }
        let dir = Self.sealsURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        try? data.write(to: Self.sealsURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.sealsURL.path)
    }
}
