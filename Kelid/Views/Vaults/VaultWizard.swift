import SwiftUI

/// Vault create/edit wizard — Svault's 4-step GUI flow:
/// 1. Basics (name, description), 2. Agent access (who may ask + default
/// per-secret rate limit), 3. Protection (default tier + guardian choice),
/// 4. Locking (auto-lock, unlock method).
struct VaultWizard: View {
    let existing: Vault?

    @Environment(\.dismiss) private var dismiss
    @Environment(VaultsStore.self) private var vaults
    @Environment(GuardianStore.self) private var guardians
    @Environment(ProvidersStore.self) private var providers

    @State private var step = 0
    @State private var name = ""
    @State private var vaultDescription = ""
    @State private var agentMode: AgentMode = .none
    @State private var callersText = ""
    @State private var rateCount = 10
    @State private var rateUnit = "hour"
    @State private var defaultTier: Tier = .medium
    @State private var guardianEnabled = true
    @State private var assignedGuardianID: UUID?
    @State private var autoLock = true
    @State private var autoLockTimer = "30m"
    @State private var loginMethod: Vault.LoginMethod = .passphrase

    private let steps = ["Basics", "Agent access", "Protection", "Locking"]

    private var guardianActive: Bool {
        guardians.isOperational(providers: providers)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                Group {
                    switch step {
                    case 0: basicsStep
                    case 1: agentStep
                    case 2: protectionStep
                    default: lockingStep
                    }
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 8)
            }

            footer
        }
        .frame(width: 540, height: 560)
        .onAppear(perform: loadExisting)
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(spacing: 10) {
            Text(existing == nil ? "Create Vault" : "Edit Vault")
                .font(.kelid(18, .bold))
            HStack(spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, title in
                    HStack(spacing: 5) {
                        Image(systemName: index < step ? "checkmark.circle.fill" : "\(index + 1).circle\(index == step ? ".fill" : "")")
                            .font(.system(size: 12))
                            .foregroundStyle(index < step ? AnyShapeStyle(.green) : index == step ? AnyShapeStyle(LinearGradient.kelidAccent) : AnyShapeStyle(.tertiary))
                        Text(title)
                            .font(.kelid(11, index == step ? .semibold : .regular))
                            .foregroundStyle(index == step ? .primary : .tertiary)
                    }
                    if index < steps.count - 1 {
                        Rectangle().fill(.quaternary).frame(width: 14, height: 1)
                    }
                }
            }
        }
        .padding(.top, 22)
        .padding(.bottom, 16)
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
            Spacer()
            if step > 0 {
                Button("Back") { step -= 1 }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
            }
            Button(step == 3 ? (existing == nil ? "Create Vault" : "Save") : "Next") {
                if step < 3 { step += 1 } else { finish() }
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .keyboardShortcut(.defaultAction)
            .disabled(!canAdvance)
        }
        .controlSize(.large)
        .padding(20)
    }

    private var canAdvance: Bool {
        guard step == 0 else { return true }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && !vaults.nameTaken(trimmed, excluding: existing?.id)
    }

    private func explainer(_ text: String) -> some View {
        Text(text)
            .font(.kelid(11, .regular))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 10))
    }

    private func fieldLabel(_ label: String, hint: String = "") -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.kelid(12, .medium))
                .foregroundStyle(.secondary)
            if !hint.isEmpty {
                Text(hint)
                    .font(.kelid(10, .regular))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Step 1: basics

    private var basicsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            explainer("A vault is one encrypted store for one project's secrets — its own policy, its own audit trail. The encrypted store ships with the crypto core; everything you set here binds to it.")

            fieldLabel("Name", hint: "Unique on this Mac; doubles as the vault's id (e.g. billing-api). Cannot be changed later.")
            TextField("my-project", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.kelid(13, .regular))
                .disabled(existing != nil)
            if vaults.nameTaken(name.trimmingCharacters(in: .whitespaces), excluding: existing?.id) {
                PaneStatus(kind: .error, message: "A vault with this name already exists.")
            }

            fieldLabel("Description", hint: "The vault's stated purpose. The guardian reads it with every request — \u{201C}production billing service\u{201D} makes it rightly suspicious of odd reasons; blank tells it nothing.")
            TextField("e.g. production billing service", text: $vaultDescription)
                .textFieldStyle(.roundedBorder)
                .font(.kelid(13, .regular))
        }
    }

    // MARK: - Step 2: agent access

    private var agentStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            explainer("Agents reach secrets through the gate (MCP). Here you decide who may even ask — every allowed request still runs the full check: scope, tier, rate limit, and the guardian's verdict on the reason.")

            fieldLabel("Who may ask")
            Picker("", selection: $agentMode) {
                ForEach(AgentMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(agentMode.help)
                .font(.kelid(10, .regular))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if agentMode == .list {
                TextField("caller names, comma-separated (e.g. claude-code, opencode)", text: $callersText)
                    .textFieldStyle(.roundedBorder)
                    .font(.kelid(13, .regular))
            }

            fieldLabel("Default rate limit per secret", hint: "Each secret carries its own limit, counted across all callers — a runaway agent hits the ceiling on that secret without locking the rest of the vault. Override per secret later.")
            HStack(spacing: 8) {
                Stepper(value: $rateCount, in: 1...10000, step: 1) {
                    Text("\(rateCount)")
                        .font(.kelid(14, .semibold))
                        .frame(width: 44, alignment: .trailing)
                }
                Text("requests per")
                    .font(.kelid(12, .regular))
                    .foregroundStyle(.secondary)
                Picker("", selection: $rateUnit) {
                    Text("minute").tag("minute")
                    Text("hour").tag("hour")
                    Text("day").tag("day")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 110, alignment: .leading)
            }
        }
    }

    // MARK: - Step 3: protection

    private var protectionStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            explainer("Every secret carries a sensitivity tier (you can override it per secret later). New secrets start at the default you pick here.")

            fieldLabel("Default tier")
            VStack(spacing: 8) {
                tierCard(.low, "Released on request. Non-sensitive values: public URLs, ids, feature flags.")
                tierCard(.medium, "The guardian must accept the caller's reason first. Good default for API keys.")
                tierCard(.high, "Judged strictly; human-only while no guardian is active. Production credentials.")
            }

            fieldLabel("Guardian")
            if guardians.guardians.isEmpty {
                PaneStatus(kind: .error, message: "No guardian available. This vault will be protected by static policies only — medium/high secrets stay human-only. We highly recommend creating a guardian so agents can be reviewed instead of refused.")
            } else {
                VStack(spacing: 8) {
                    choiceCard(
                        selected: guardianEnabled,
                        title: "Guardian reviews requests (recommended)",
                        detail: "Medium/high secrets are released only when the guardian accepts the caller's reason."
                    ) { guardianEnabled = true }

                    if guardianEnabled {
                        Picker("", selection: $assignedGuardianID) {
                            Text("default guardian").tag(UUID?.none)
                            ForEach(guardians.guardians) { guardian in
                                Text(guardian.name).tag(Optional(guardian.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: 260, alignment: .leading)
                        .padding(.leading, 28)
                    }

                    choiceCard(
                        selected: !guardianEnabled,
                        title: "Policies only",
                        detail: "No AI review for this vault — medium/high secrets become human-only."
                    ) { guardianEnabled = false }
                }
            }
        }
    }

    private func tierCard(_ tier: Tier, _ description: String) -> some View {
        let warning = tier != .low && !guardianActive
            ? " No guardian is active yet, so this is human-only for now." : ""
        return choiceCard(
            selected: defaultTier == tier,
            title: tier.title,
            detail: description + warning
        ) { defaultTier = tier }
    }

    private func choiceCard(selected: Bool, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(selected ? AnyShapeStyle(LinearGradient.kelidAccent) : AnyShapeStyle(.tertiary))
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.kelid(13, .semibold))
                    Text(detail)
                        .font(.kelid(11, .regular))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selected ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(.quaternary.opacity(0.2)),
                in: .rect(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 4: locking

    private var lockingStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            explainer("An unlocked vault holds its key in memory. Locking clears it; a human unlocks again with the master passphrase or a YubiKey — agents never can.")

            fieldLabel("Auto-lock", hint: "Re-locks the vault after this long without use; a forgotten unlock doesn't stay open forever.")
            HStack(spacing: 14) {
                Toggle(isOn: $autoLock) {
                    Text("Lock when idle").font(.kelid(12, .medium))
                }
                .toggleStyle(.switch)
                if autoLock {
                    Picker("", selection: $autoLockTimer) {
                        Text("30m").tag("30m")
                        Text("12h").tag("12h")
                        Text("1d").tag("1d")
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 90, alignment: .leading)
                }
            }

            fieldLabel("Unlock with", hint: "How a human opens this vault. YubiKey needs a key enrolled in Settings.")
            Picker("", selection: $loginMethod) {
                ForEach(Vault.LoginMethod.allCases) { method in
                    Text(method.title).tag(method)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 160, alignment: .leading)
            if loginMethod == .yubikey, !YubiKeyService.isEnrolled {
                PaneStatus(kind: .info, message: "No YubiKey is enrolled yet — enroll one in Settings before relying on this.")
            }
        }
    }

    // MARK: - Finish

    private func loadExisting() {
        guard let existing else { return }
        name = existing.name
        vaultDescription = existing.vaultDescription
        agentMode = existing.agentMode
        callersText = existing.allowedCallers.joined(separator: ", ")
        if let parsed = PolicyEngine.rateLimitParse(existing.defaultSecretRateLimit) {
            rateCount = parsed.count
            rateUnit = switch parsed.window {
            case 60: "minute"
            case 86400: "day"
            default: "hour"
            }
        }
        defaultTier = existing.defaultTier
        guardianEnabled = existing.guardianEnabled
        assignedGuardianID = existing.assignedGuardianID
        autoLock = existing.autoLock
        autoLockTimer = existing.autoLockTimer
        loginMethod = existing.loginMethod
    }

    private func finish() {
        let callers = agentMode == .list
            ? callersText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            : []
        let rate = "\(rateCount)/\(rateUnit)"
        let assigned = guardianEnabled ? assignedGuardianID : nil

        if var updated = existing {
            updated.vaultDescription = vaultDescription
            updated.agentMode = agentMode
            updated.allowedCallers = callers
            updated.defaultSecretRateLimit = rate
            updated.defaultTier = defaultTier
            updated.guardianEnabled = guardianEnabled
            updated.assignedGuardianID = assigned
            updated.autoLock = autoLock
            updated.autoLockTimer = autoLockTimer
            updated.loginMethod = loginMethod
            vaults.update(updated)
            AuditLog.shared.record(.system, "Vault updated", detail: updated.name)
        } else {
            let vault = Vault(
                name: name.trimmingCharacters(in: .whitespaces),
                vaultDescription: vaultDescription,
                agentMode: agentMode,
                allowedCallers: callers,
                defaultSecretRateLimit: rate,
                defaultTier: defaultTier,
                guardianEnabled: guardianEnabled,
                assignedGuardianID: assigned,
                autoLock: autoLock,
                autoLockTimer: autoLockTimer,
                loginMethod: loginMethod
            )
            vaults.add(vault)
            AuditLog.shared.record(.system, "Vault created", detail: vault.name)
        }
        dismiss()
    }
}
