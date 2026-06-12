import SwiftUI

/// Guardian pane — guardians (AI judges) only, like Svault's Guardian screen:
/// the global switch, the guardian list with its creation wizard, and a test
/// console. Vaults assign a guardian; per-secret policy ships with the vault
/// engine.
struct GuardianView: View {
    @Environment(GuardianStore.self) private var store
    @Environment(ProvidersStore.self) private var providers

    @State private var wizardGuardian: Guardian?
    @State private var showWizard = false
    @State private var toast: Toast?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusCard
                guardiansCard
                GuardianTestConsole(toast: $toast)
            }
            .padding(24)
        }
        .toast($toast)
        .sheet(isPresented: $showWizard) {
            GuardianWizard(existing: wizardGuardian)
        }
    }

    // MARK: - Status

    private var operational: Bool { store.isOperational(providers: providers) }

    private var statusCard: some View {
        @Bindable var store = store
        return HStack(spacing: 14) {
            Image(systemName: operational ? "checkmark.shield.fill" : "shield.slash")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(operational ? AnyShapeStyle(LinearGradient.kelidAccent) : AnyShapeStyle(.secondary))

            VStack(alignment: .leading, spacing: 2) {
                Text(operational ? "Guardian active" : "Guardian off")
                    .font(.kelid(16, .bold))
                Text(statusDetail)
                    .font(.kelid(12, .regular))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: $store.globalEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(store.guardians.isEmpty)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var statusDetail: String {
        if store.guardians.isEmpty {
            return "Create a guardian — without one, medium and high secrets stay human-only."
        }
        if !store.globalEnabled {
            return "Disabled: medium tier allows with a flag, high tier denies."
        }
        if !operational {
            return "The guardian's provider has no credential — configure it in Providers."
        }
        return "Scores every request 0\u{2013}100 on whether the stated reason justifies access. Vaults pick which guardian reviews them."
    }

    // MARK: - Guardians

    private var guardiansCard: some View {
        PaneCard {
            HStack {
                Text("Guardians")
                    .font(.kelid(13, .semibold))
                Spacer()
                Button {
                    wizardGuardian = nil
                    showWizard = true
                } label: {
                    Label("Create Guardian", systemImage: "plus")
                        .font(.kelid(12, .semibold))
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
            }

            if store.guardians.isEmpty {
                PaneStatus(kind: .info, message: "No guardians yet. The wizard picks a provider, a model, and tuning — then you can test it below.")
            } else {
                ForEach(store.guardians) { guardian in
                    guardianRow(guardian)
                }
            }
        }
    }

    private func guardianRow(_ guardian: Guardian) -> some View {
        HStack(spacing: 12) {
            if let provider = guardian.provider {
                ProviderLogo(provider: provider, size: 18)
                    .foregroundStyle(LinearGradient.kelidAccent)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(guardian.name).font(.kelid(13, .semibold))
                    if store.defaultGuardianID == guardian.id {
                        Text("default")
                            .font(.kelid(10, .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(.quaternary.opacity(0.5), in: .capsule)
                    }
                }
                Text("\(guardian.model) \u{2022} allow \u{2265}\(guardian.allowThreshold) \u{2022} high \u{2265}\(guardian.highThreshold)")
                    .font(.kelid(11, .regular))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if store.defaultGuardianID != guardian.id {
                Button("Make default") {
                    store.defaultGuardianID = guardian.id
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .font(.kelid(11, .medium))
            }
            Button {
                wizardGuardian = guardian
                showWizard = true
            } label: {
                Image(systemName: "pencil").font(.system(size: 11))
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            Button(role: .destructive) {
                store.removeGuardian(guardian)
                AuditLog.shared.record(.guardian, "Guardian deleted", detail: guardian.name, outcome: .info)
                toast = .info("\(guardian.name) deleted")
            } label: {
                Image(systemName: "trash").font(.system(size: 11))
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .padding(.vertical, 2)
    }
}
