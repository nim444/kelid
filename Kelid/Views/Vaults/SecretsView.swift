import AppKit
import SwiftUI

/// Secrets of one vault — Svault's Secrets screen: cards with classification
/// badges, audited reveal, edit, delete, plus Kelid's per-secret seal
/// controls. Values come from the Keychain only after a user-presence check.
struct SecretsView: View {
    let vault: Vault
    var onBack: () -> Void

    @Environment(SecretsStore.self) private var store
    @Environment(GuardianStore.self) private var guardians
    @Environment(ProvidersStore.self) private var providers

    @State private var wizardSecret: VaultSecret?
    @State private var showWizard = false
    @State private var toDelete: VaultSecret?
    @State private var revealed: (name: String, value: String)?
    @State private var showReveal = false
    @State private var copied = false
    @State private var toast: Toast?

    private var secrets: [VaultSecret] { store.secrets(for: vault.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerRow

                if secrets.isEmpty {
                    emptyState
                } else {
                    ForEach(secrets) { secret in
                        secretCard(secret)
                    }
                    Text("Values live in the macOS Keychain (OS-encrypted) until the crypto core moves them into the vault's own encrypted store. Released to agents only through the gate.")
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
            SecretWizard(vault: vault, existing: wizardSecret)
        }
        .sheet(isPresented: $showReveal, onDismiss: { revealed = nil }) {
            revealSheet
        }
        .alert(
            "Delete secret \u{201C}\(toDelete?.name ?? "")\u{201D}?",
            isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } })
        ) {
            Button("Delete Secret", role: .destructive) {
                if let secret = toDelete {
                    store.remove(secret, from: vault.id)
                    AuditLog.shared.record(.secret, "Secret deleted", detail: "\(vault.name)/\(secret.name)", outcome: .info)
                    toast = .info("\(secret.name) deleted")
                }
                toDelete = nil
            }
            Button("Cancel", role: .cancel) { toDelete = nil }
        } message: {
            Text("The value and its classification are destroyed. This cannot be undone.")
        }
    }

    // MARK: - Header / empty

    private var headerRow: some View {
        HStack(spacing: 12) {
            Button {
                onBack()
            } label: {
                Label("Vaults", systemImage: "chevron.left")
                    .font(.kelid(12, .medium))
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
            .controlSize(.small)

            VStack(alignment: .leading, spacing: 0) {
                Text(vault.name)
                    .font(.kelid(15, .bold))
                Text("\(secrets.count) secret\(secrets.count == 1 ? "" : "s")")
                    .font(.kelid(11, .regular))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button {
                wizardSecret = nil
                showWizard = true
            } label: {
                Label("Add Secret", systemImage: "plus")
                    .font(.kelid(12, .semibold))
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.horizontal")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(LinearGradient.kelidAccent)
            Text("No secrets yet")
                .font(.kelid(18, .bold))
            Text("Add the first one — the value is stored OS-encrypted and released only through the gate.")
                .font(.kelid(12, .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }

    // MARK: - Secret card

    private func secretCard(_ secret: VaultSecret) -> some View {
        let seal = store.seal(for: secret, in: vault.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(secret.name)
                    .font(.kelid(14, .bold))
                badge(secret.scope.isEmpty ? "misc" : secret.scope, .secondary)
                badge(secret.tier.rawValue, tierColor(secret.tier))
                if seal != nil {
                    badge("sealed", .red)
                }
                if secret.requireReason {
                    badge("always judged", .purple)
                }
                Spacer()
            }

            if !secret.secretDescription.isEmpty {
                Text(secret.secretDescription)
                    .font(.kelid(12, .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 6) {
                Text("rate \(secret.rateLimit)")
                Text("\u{2022}")
                Text("callers: \(secret.requiredCallers.isEmpty ? "any" : secret.requiredCallers.joined(separator: ", "))")
                Text("\u{2022}")
                Text("window: \(secret.timeWindows.isEmpty ? "any" : secret.timeWindows.joined(separator: "; "))")
                Spacer()
                if let lastRead = secret.lastReadAt {
                    Text("read \(lastRead.formatted(.relative(presentation: .named)))")
                }
            }
            .font(.kelid(10, .regular))
            .foregroundStyle(.tertiary)

            if let seal {
                PaneStatus(kind: .error, message: "Sealed \(seal.sealedAt.formatted(.relative(presentation: .named))) — \(seal.trigger). Every request is denied until a human unseals it.")
            }

            Divider().opacity(0.3)

            HStack(spacing: 8) {
                Button {
                    reveal(secret)
                } label: {
                    Label("Reveal", systemImage: "eye")
                        .font(.kelid(11, .medium))
                }
                .buttonStyle(.glass)
                .controlSize(.small)

                Button {
                    wizardSecret = secret
                    showWizard = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .font(.kelid(11, .medium))
                }
                .buttonStyle(.glass)
                .controlSize(.small)

                if seal == nil {
                    Button {
                        store.sealManually(secret, in: vault.id)
                        AuditLog.shared.record(.secret, "Secret sealed", detail: "\(vault.name)/\(secret.name) — manually", outcome: .info)
                        toast = .info("\(secret.name) sealed — all requests deny until unsealed")
                    } label: {
                        Label("Seal", systemImage: "lock.fill")
                            .font(.kelid(11, .medium))
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .help("Deny every request for this secret until a human unseals it")
                } else {
                    Button {
                        unseal(secret)
                    } label: {
                        Label("Unseal", systemImage: "lock.open")
                            .font(.kelid(11, .semibold))
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.small)
                }

                Spacer()

                Button(role: .destructive) {
                    toDelete = secret
                } label: {
                    Image(systemName: "trash").font(.system(size: 11))
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.kelid(10, .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: .capsule)
    }

    private func tierColor(_ tier: Tier) -> Color {
        switch tier {
        case .low: .green
        case .medium: .orange
        case .high: .red
        }
    }

    // MARK: - Reveal

    private var revealSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Value \u{2022} \(revealed?.name ?? "")")
                .font(.kelid(15, .bold))

            Text(revealed?.value ?? "")
                .font(.kelid(13, .medium))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 10))

            Text("This read is recorded in the audit log.")
                .font(.kelid(11, .regular))
                .foregroundStyle(.tertiary)

            HStack {
                Button {
                    guard let value = revealed?.value else { return }
                    NSPasteboard.general.clearContents()
                    // Concealed marker: clipboard managers must not archive this value.
                    NSPasteboard.general.setString("", forType: .init("org.nspasteboard.ConcealedType"))
                    NSPasteboard.general.setString(value, forType: .string)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.kelid(12, .medium))
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)

                Spacer()

                Button("Close") { showReveal = false }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(22)
        .frame(width: 460)
    }

    private func reveal(_ secret: VaultSecret) {
        Task {
            let ok = await TouchIDService.requireUserPresence(reason: "reveal the secret \(secret.name)")
            guard ok else {
                AuditLog.shared.record(.secret, "Reveal denied", detail: "\(vault.name)/\(secret.name)", outcome: .denied)
                toast = .error("Authentication required to reveal")
                return
            }
            guard let value = store.revealValue(of: secret, in: vault.id) else {
                toast = .error("No value found in the Keychain for \(secret.name)")
                return
            }
            AuditLog.shared.record(.secret, "Value revealed", detail: "\(vault.name)/\(secret.name)", outcome: .info)
            revealed = (secret.name, value)
            showReveal = true
        }
    }

    private func unseal(_ secret: VaultSecret) {
        Task {
            let ok = await TouchIDService.requireUserPresence(reason: "unseal the secret \(secret.name)")
            if ok {
                store.unseal(secret, in: vault.id)
                AuditLog.shared.record(.secret, "Seal cleared", detail: "\(vault.name)/\(secret.name)")
                toast = .success("\(secret.name) unsealed")
            } else {
                AuditLog.shared.record(.secret, "Unseal denied", detail: "\(vault.name)/\(secret.name)", outcome: .denied)
                toast = .error("Authentication required to unseal")
            }
        }
    }
}
