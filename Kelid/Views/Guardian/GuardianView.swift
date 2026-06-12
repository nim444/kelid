import SwiftUI

/// Guardian pane: the AI judges that gate secret access, the per-secret
/// policy rules (rate limit lives on the secret — Kelid's change vs Svault),
/// sealed secrets awaiting human approval, and the live test console.
struct GuardianView: View {
    @Environment(GuardianStore.self) private var store
    @Environment(ProvidersStore.self) private var providers

    @State private var wizardGuardian: Guardian?
    @State private var showWizard = false
    @State private var ruleEditor: SecretRule?
    @State private var showRuleEditor = false
    @State private var toast: Toast?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusCard
                guardiansCard
                rulesCard
                if !store.seals.isEmpty {
                    sealsCard
                }
                GuardianTestConsole(toast: $toast)
            }
            .padding(24)
        }
        .toast($toast)
        .sheet(isPresented: $showWizard) {
            GuardianWizard(existing: wizardGuardian)
        }
        .sheet(isPresented: $showRuleEditor) {
            RuleEditorSheet(existing: ruleEditor)
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
        return "Scores every request 0\u{2013}100 on whether the stated reason justifies access."
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

    // MARK: - Rules

    private var rulesCard: some View {
        PaneCard {
            HStack {
                Text("Secret Rules")
                    .font(.kelid(13, .semibold))
                Spacer()
                Button {
                    ruleEditor = nil
                    showRuleEditor = true
                } label: {
                    Label("Add Rule", systemImage: "plus")
                        .font(.kelid(12, .semibold))
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
            }

            Text("Rate limits and brute-force protection are per secret — repeated denials seal the secret itself, and rotating callers doesn't help.")
                .font(.kelid(11, .regular))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if store.rules.isEmpty {
                PaneStatus(kind: .info, message: "No rules yet. Add one to exercise the pipeline in the test console; real secrets attach to these rules when the vault engine ships.")
            } else {
                ForEach(store.rules) { rule in
                    ruleRow(rule)
                }
            }
        }
    }

    private func ruleRow(_ rule: SecretRule) -> some View {
        HStack(spacing: 12) {
            Image(systemName: store.seals[rule.name] != nil ? "lock.fill" : "key.horizontal")
                .font(.system(size: 13))
                .foregroundStyle(store.seals[rule.name] != nil ? AnyShapeStyle(.red) : AnyShapeStyle(LinearGradient.kelidAccent))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(rule.name).font(.kelid(13, .semibold))
                    tierChip(rule.tier)
                    if store.seals[rule.name] != nil {
                        Text("SEALED")
                            .font(.kelid(9, .bold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.red.opacity(0.12), in: .capsule)
                    }
                }
                Text("\(rule.scope) \u{2022} \(rule.rateLimit)\(rule.requireReason ? " \u{2022} reason required" : "")")
                    .font(.kelid(11, .regular))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                ruleEditor = rule
                showRuleEditor = true
            } label: {
                Image(systemName: "pencil").font(.system(size: 11))
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            Button(role: .destructive) {
                store.removeRule(rule)
                toast = .info("Rule \(rule.name) removed")
            } label: {
                Image(systemName: "trash").font(.system(size: 11))
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .padding(.vertical, 2)
    }

    private func tierChip(_ tier: Tier) -> some View {
        let color: Color = switch tier {
        case .low: .green
        case .medium: .orange
        case .high: .red
        }
        return Text(tier.rawValue)
            .font(.kelid(10, .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: .capsule)
    }

    // MARK: - Seals

    private var sealsCard: some View {
        PaneCard {
            Text("Sealed Secrets")
                .font(.kelid(13, .semibold))
            Text("Brute-force response: these secrets deny every request until a human clears them. Unsealing requires Touch ID or your Mac password.")
                .font(.kelid(11, .regular))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(store.seals.sorted(by: { $0.key < $1.key }), id: \.key) { name, seal in
                HStack(spacing: 12) {
                    Image(systemName: "lock.trianglebadge.exclamationmark.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(name).font(.kelid(13, .semibold))
                        Text("\(seal.trigger) \u{2022} last caller \(seal.lastCaller) \u{2022} \(seal.sealedAt.formatted(.relative(presentation: .named)))")
                            .font(.kelid(11, .regular))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button {
                        unseal(name)
                    } label: {
                        Text("Unseal").font(.kelid(12, .semibold))
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func unseal(_ name: String) {
        Task {
            let ok = await TouchIDService.requireUserPresence(reason: "unseal the secret \(name)")
            if ok {
                store.unseal(name)
                toast = .success("\(name) unsealed")
            } else {
                AuditLog.shared.record(.guardian, "Unseal denied", detail: name, outcome: .denied)
                toast = .error("Authentication required to unseal")
            }
        }
    }
}
