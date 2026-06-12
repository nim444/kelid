import Foundation
import Observation

/// Vault registry. Holds metadata + policy settings; the encrypted secret
/// stores arrive with the crypto core and bind to these entries. Nothing in
/// here is secret material.
@MainActor
@Observable
final class VaultsStore {
    private static let key = "vaults"

    private(set) var vaults: [Vault]

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([Vault].self, from: data) {
            vaults = decoded
        } else {
            vaults = []
        }
    }

    func nameTaken(_ name: String, excluding id: UUID? = nil) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespaces).lowercased()
        return vaults.contains { $0.name.lowercased() == normalized && $0.id != id }
    }

    func add(_ vault: Vault) {
        vaults.append(vault)
        persist()
    }

    func update(_ vault: Vault) {
        if let index = vaults.firstIndex(where: { $0.id == vault.id }) {
            vaults[index] = vault
            persist()
        }
    }

    func remove(_ vault: Vault) {
        vaults.removeAll { $0.id == vault.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(vaults) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
