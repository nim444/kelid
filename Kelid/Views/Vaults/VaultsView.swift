import SwiftUI

/// Vaults pane: the vault registry. Each vault carries its policy settings
/// and an assigned guardian; the encrypted secret store ships with the
/// crypto core and binds to these entries.
struct VaultsView: View {
    @Environment(VaultsStore.self) private var store
    @Environment(GuardianStore.self) private var guardians

    @State private var wizardVault: Vault?
    @State private var showWizard = false
    @State private var toast: Toast?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerRow

                if store.vaults.isEmpty {
                    emptyState
                } else {
                    ForEach(store.vaults) { vault in
                        vaultCard(vault)
                    }
                    Text("The encrypted secret store ships with the crypto core — these vaults and their policies bind to it then.")
                        .font(.kelid(11, .regular))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                }
            }
            .padding(24)
        }
        .toast($toast)
        .sheet(isPresented: $showWizard) {
            VaultWizard(existing: wizardVault)
        }
    }

    private var headerRow: some View {
        HStack {
            Text("\(store.vaults.count) vault\(store.vaults.count == 1 ? "" : "s")")
                .font(.kelid(13, .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                wizardVault = nil
                showWizard = true
            } label: {
                Label("Create Vault", systemImage: "plus")
                    .font(.kelid(12, .semibold))
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "shippingbox")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(LinearGradient.kelidAccent)
            Text("No vaults yet")
                .font(.kelid(20, .bold))
            Text("A vault is one encrypted store for one project's secrets — its own policy, audit trail, and guardian. Create your first one.")
                .font(.kelid(13, .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func vaultCard(_ vault: Vault) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(LinearGradient.kelidAccent)
                .frame(width: 40, height: 40)
                .glassEffect(.regular, in: .rect(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 5) {
                Text(vault.name)
                    .font(.kelid(15, .bold))
                if !vault.vaultDescription.isEmpty {
                    Text(vault.vaultDescription)
                        .font(.kelid(12, .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    chip("tier \(vault.defaultTier.rawValue)", tierColor(vault.defaultTier))
                    chip(guardianLabel(vault), vault.guardianEnabled && !guardians.guardians.isEmpty ? .green : .orange)
                    chip(vault.agentMode.title, .secondary)
                    chip("\(vault.defaultSecretRateLimit)/secret", .secondary)
                    if vault.loginMethod == .yubikey {
                        chip("YubiKey unlock", .secondary)
                    }
                }
            }

            Spacer()

            HStack(spacing: 6) {
                Button {
                    wizardVault = vault
                    showWizard = true
                } label: {
                    Image(systemName: "pencil").font(.system(size: 11))
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help("Edit vault settings")

                Button(role: .destructive) {
                    store.remove(vault)
                    AuditLog.shared.record(.system, "Vault deleted", detail: vault.name, outcome: .info)
                    toast = .info("\(vault.name) deleted")
                } label: {
                    Image(systemName: "trash").font(.system(size: 11))
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .help("Delete vault")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func guardianLabel(_ vault: Vault) -> String {
        guard vault.guardianEnabled else { return "policies only" }
        if let assigned = vault.assignedGuardianID,
           let guardian = guardians.guardians.first(where: { $0.id == assigned }) {
            return "guardian: \(guardian.name)"
        }
        if let fallback = guardians.defaultGuardian {
            return "guardian: \(fallback.name) (default)"
        }
        return "no guardian yet"
    }

    private func tierColor(_ tier: Tier) -> Color {
        switch tier {
        case .low: .green
        case .medium: .orange
        case .high: .red
        }
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.kelid(10, .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: .capsule)
    }
}
