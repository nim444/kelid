import SwiftUI

/// Add/edit secret — Svault's 2-step wizard: the secret itself, then who
/// gets it and when. Kelid adds the per-secret rate limit (defaulted from
/// the vault) on the access step.
struct SecretWizard: View {
    let vault: Vault
    let existing: VaultSecret?

    @Environment(\.dismiss) private var dismiss
    @Environment(SecretsStore.self) private var store
    @Environment(GuardianStore.self) private var guardians
    @Environment(ProvidersStore.self) private var providers

    @State private var step = 0
    @State private var name = ""
    @State private var value = ""
    @State private var revealValue = false
    @State private var scope = "misc"
    @State private var tier: Tier = .medium
    @State private var requireReason = false
    @State private var secretDescription = ""
    @State private var callersText = ""
    @State private var windowsText = ""
    @State private var rateCount = 10
    @State private var rateUnit = "hour"
    @State private var saveError: String?

    private var guardianActive: Bool {
        guardians.isOperational(providers: providers)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                Group {
                    if step == 0 { secretStep } else { accessStep }
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 8)
            }

            footer
        }
        .frame(width: 520, height: 540)
        .onAppear(perform: loadExisting)
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(spacing: 10) {
            Text(existing == nil ? "Add Secret" : "Edit Secret \u{2022} \(existing?.name ?? "")")
                .font(.kelid(17, .bold))
            HStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? AnyShapeStyle(LinearGradient.kelidAccent) : AnyShapeStyle(.quaternary))
                        .frame(width: 44, height: 4)
                }
            }
        }
        .padding(.top, 22)
        .padding(.bottom, 16)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            if let saveError {
                PaneStatus(kind: .error, message: saveError)
                    .padding(.horizontal, 20)
            }
            footerButtons
        }
    }

    private var footerButtons: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
            Spacer()
            if step == 1 {
                Button("Back") { step = 0 }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
            }
            Button(step == 0 ? "Next" : (existing == nil ? "Add Secret" : "Save Changes")) {
                if step == 0 { step = 1 } else { save() }
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .keyboardShortcut(.defaultAction)
            .disabled(!canAdvance)
        }
        .controlSize(.large)
        .padding(20)
    }

    private var parsedWindows: [String] {
        windowsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var invalidWindow: String? {
        parsedWindows.first { !GateService.windowValid($0) }
    }

    private var canAdvance: Bool {
        guard step == 0 else {
            return PolicyEngine.rateLimitParse("\(rateCount)/\(rateUnit)") != nil && invalidWindow == nil
        }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        if existing == nil {
            return !value.isEmpty && !store.nameTaken(trimmed, in: vault.id)
        }
        return true
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

    // MARK: - Step 1: the secret

    private var secretStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            fieldLabel(
                "Name",
                hint: existing == nil
                    ? "How callers ask for it — usually the env-var name (e.g. DATABASE_URL)."
                    : "The name identifies the secret — it can\u{2019}t be changed."
            )
            TextField("DATABASE_URL", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.kelid(13, .regular))
                .disabled(existing != nil)
            if existing == nil, store.nameTaken(name.trimmingCharacters(in: .whitespaces), in: vault.id) {
                PaneStatus(kind: .error, message: "A secret with this name already exists in this vault.")
            }

            fieldLabel("Value", hint: "Stored in the macOS Keychain (OS-encrypted); never logged, shown only on explicit reveal. The crypto core moves it into the vault\u{2019}s own encrypted store.")
            HStack(spacing: 8) {
                Group {
                    if revealValue {
                        TextField(existing == nil ? "" : "unchanged", text: $value)
                    } else {
                        SecureField(existing == nil ? "" : "unchanged", text: $value)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.kelid(13, .regular))

                Button {
                    revealValue.toggle()
                } label: {
                    Image(systemName: revealValue ? "eye.slash" : "eye")
                        .frame(width: 18)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }

            fieldLabel("Scope", hint: "The secret\u{2019}s category. A request must state the matching scope — an agent asking for \u{201C}database\u{201D} never sees \u{201C}payments\u{201D}.")
            TextField("e.g. database, api, payments", text: $scope)
                .textFieldStyle(.roundedBorder)
                .font(.kelid(13, .regular))
        }
    }

    // MARK: - Step 2: access rules

    private var accessStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            fieldLabel("Sensitivity tier")
            VStack(spacing: 8) {
                tierCard(.low, "Released on request. Non-sensitive values: public URLs, ids, feature flags.")
                tierCard(.medium, "The guardian must accept the caller\u{2019}s reason first. Good default for API keys.")
                tierCard(.high, "Judged strictly; human-only while no guardian is active. Production credentials.")
            }

            if guardianActive {
                Toggle(isOn: $requireReason) {
                    Text("Always ask the guardian — even at low tier")
                        .font(.kelid(12, .medium))
                }
                .toggleStyle(.checkbox)
            }

            fieldLabel("Description", hint: "What this secret is for. The guardian weighs it against each request\u{2019}s reason — \u{201C}production Postgres connection string\u{201D} beats silence.")
            TextField("e.g. production Postgres connection string", text: $secretDescription)
                .textFieldStyle(.roundedBorder)
                .font(.kelid(13, .regular))

            fieldLabel("Rate limit", hint: "Per secret, counted across all callers — rotating caller names doesn\u{2019}t evade it. 5 denials in 5 minutes seal the secret (medium/high).")
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

            fieldLabel("Allowed callers", hint: "Restrict to specific agent identities, comma-separated (e.g. claude-code, ci-bot). Blank = any caller the vault allows.")
            TextField("blank = any", text: $callersText)
                .textFieldStyle(.roundedBorder)
                .font(.kelid(13, .regular))

            fieldLabel("Time window", hint: "Only release during these times, comma-separated — e.g. mon-fri 09:00-18:00 or 22:00-06:00 (overnight). Blank = any time.")
            TextField("blank = any time", text: $windowsText)
                .textFieldStyle(.roundedBorder)
                .font(.kelid(13, .regular))
            if let invalidWindow {
                PaneStatus(kind: .error, message: "\u{201C}\(invalidWindow)\u{201D} is not a valid window — use day names and 24h times, e.g. mon-fri 09:00-18:00.")
            }
        }
    }

    private func tierCard(_ candidate: Tier, _ description: String) -> some View {
        let warning = candidate != .low && !guardianActive
            ? " No guardian is active yet, so this is human-only for now." : ""
        return Button {
            tier = candidate
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: tier == candidate ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(tier == candidate ? AnyShapeStyle(LinearGradient.kelidAccent) : AnyShapeStyle(.tertiary))
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.title).font(.kelid(13, .semibold))
                    Text(description + warning)
                        .font(.kelid(11, .regular))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                tier == candidate ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(.quaternary.opacity(0.2)),
                in: .rect(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Load / save

    private func loadExisting() {
        if let existing {
            name = existing.name
            scope = existing.scope
            tier = existing.tier
            requireReason = existing.requireReason
            secretDescription = existing.secretDescription
            callersText = existing.requiredCallers.joined(separator: ", ")
            windowsText = existing.timeWindows.joined(separator: ", ")
            if let parsed = PolicyEngine.rateLimitParse(existing.rateLimit) {
                rateCount = parsed.count
                rateUnit = switch parsed.window {
                case 60: "minute"
                case 86400: "day"
                default: "hour"
                }
            }
        } else {
            tier = vault.defaultTier
            if let parsed = PolicyEngine.rateLimitParse(vault.defaultSecretRateLimit) {
                rateCount = parsed.count
                rateUnit = switch parsed.window {
                case 60: "minute"
                case 86400: "day"
                default: "hour"
                }
            }
        }
    }

    private func save() {
        let callers = callersText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let windows = parsedWindows
        let rate = "\(rateCount)/\(rateUnit)"
        saveError = nil

        if var updated = existing {
            updated.scope = scope.trimmingCharacters(in: .whitespaces).isEmpty ? "misc" : scope.trimmingCharacters(in: .whitespaces)
            updated.tier = tier
            updated.requireReason = requireReason
            updated.secretDescription = secretDescription
            updated.requiredCallers = callers
            updated.timeWindows = windows
            updated.rateLimit = rate
            guard store.update(updated, newValue: value.isEmpty ? nil : value, in: vault.id) else {
                saveError = "The Keychain refused the new value — nothing was changed. Try again."
                AuditLog.shared.record(.secret, "Secret update failed", detail: "\(vault.name)/\(updated.name) — Keychain write failed", outcome: .failure)
                return
            }
            AuditLog.shared.record(.secret, "Secret updated", detail: "\(vault.name)/\(updated.name)\(value.isEmpty ? "" : " (value replaced)")")
        } else {
            let secret = VaultSecret(
                name: name.trimmingCharacters(in: .whitespaces),
                scope: scope.trimmingCharacters(in: .whitespaces).isEmpty ? "misc" : scope.trimmingCharacters(in: .whitespaces),
                tier: tier,
                requireReason: requireReason,
                secretDescription: secretDescription,
                requiredCallers: callers,
                timeWindows: windows,
                rateLimit: rate
            )
            guard store.add(secret, value: value, to: vault.id) else {
                saveError = "The Keychain refused the value — the secret was not created. Try again."
                AuditLog.shared.record(.secret, "Secret add failed", detail: "\(vault.name)/\(secret.name) — Keychain write failed", outcome: .failure)
                return
            }
            AuditLog.shared.record(.secret, "Secret added", detail: "\(vault.name)/\(secret.name) (\(secret.tier.rawValue), \(secret.scope))")
        }
        value = ""
        dismiss()
    }
}
