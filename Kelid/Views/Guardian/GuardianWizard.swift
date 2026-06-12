import SwiftUI

/// Guardian creation wizard — Svault's 3-step flow:
/// 1. Provider (a configured AI provider), 2. Model (live list + recommended,
/// free-text fallback), 3. Tuning (name, thresholds, criteria).
struct GuardianWizard: View {
    let existing: Guardian?

    @Environment(\.dismiss) private var dismiss
    @Environment(GuardianStore.self) private var store
    @Environment(ProvidersStore.self) private var providers

    @State private var step = 0
    @State private var provider: AIProvider?
    @State private var models: [String] = []
    @State private var modelsLoading = false
    @State private var modelsFailed = false
    @State private var model = ""
    @State private var name = ""
    @State private var allowThreshold = 60
    @State private var highThreshold = 80
    @State private var criteria = ""

    private var configuredProviders: [AIProvider] {
        AIProvider.allCases.filter { providers.isConfigured($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Group {
                switch step {
                case 0: providerStep
                case 1: modelStep
                default: tuningStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 26)

            footer
        }
        .frame(width: 520, height: 480)
        .onAppear(perform: loadExisting)
    }

    // MARK: - Chrome

    private var header: some View {
        VStack(spacing: 10) {
            Text(existing == nil ? "Create Guardian" : "Edit Guardian")
                .font(.kelid(18, .bold))
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? AnyShapeStyle(LinearGradient.kelidAccent) : AnyShapeStyle(.quaternary))
                        .frame(width: 36, height: 4)
                }
            }
        }
        .padding(.top, 22)
        .padding(.bottom, 18)
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
            Button(step == 2 ? (existing == nil ? "Create" : "Save") : "Next") {
                advance()
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
        switch step {
        case 0: provider != nil
        case 1: !model.trimmingCharacters(in: .whitespaces).isEmpty
        default: !name.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func advance() {
        if step < 2 {
            step += 1
            if step == 1, models.isEmpty { fetchModels() }
            return
        }
        finish()
    }

    // MARK: - Step 1: provider

    private var providerStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Which provider should the guardian reason with?")
                .font(.kelid(13, .regular))
                .foregroundStyle(.secondary)

            if configuredProviders.isEmpty {
                PaneStatus(kind: .error, message: "No configured AI providers. Without a provider the guardian has no model to reason with — medium and high secrets stay human-only. Configure one under Providers first.")
            } else {
                ForEach(configuredProviders) { candidate in
                    Button {
                        if provider != candidate { model = ""; models = [] }
                        provider = candidate
                    } label: {
                        HStack(spacing: 12) {
                            ProviderLogo(provider: candidate, size: 18)
                                .foregroundStyle(LinearGradient.kelidAccent)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(candidate.name).font(.kelid(13, .semibold))
                                Text(candidate.summary)
                                    .font(.kelid(11, .regular))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if provider == candidate {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            provider == candidate ? AnyShapeStyle(.quaternary.opacity(0.6)) : AnyShapeStyle(.quaternary.opacity(0.2)),
                            in: .rect(cornerRadius: 12)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Step 2: model

    private var modelStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pick the model that scores access requests.")
                .font(.kelid(13, .regular))
                .foregroundStyle(.secondary)

            if modelsLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading models\u{2026}").font(.kelid(12, .regular)).foregroundStyle(.secondary)
                }
            } else if modelsFailed || models.isEmpty {
                PaneStatus(kind: .info, message: "Could not load the model list — type a model ID below.")
            } else {
                Picker("", selection: $model) {
                    ForEach(models, id: \.self) { id in
                        Text(displayName(id)).font(.kelid(12, .regular)).tag(id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 360, alignment: .leading)
            }

            Text("Model ID")
                .font(.kelid(12, .medium))
                .foregroundStyle(.secondary)
            TextField(recommendedPlaceholder, text: $model)
                .textFieldStyle(.roundedBorder)
                .font(.kelid(13, .regular))

            if let provider, let recommended = JudgeClient.recommendedModel(for: provider) {
                Button {
                    model = recommended
                } label: {
                    Label("Use recommended: \(recommended)", systemImage: "sparkles")
                        .font(.kelid(12, .medium))
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
            }
        }
    }

    private var recommendedPlaceholder: String {
        provider.flatMap(JudgeClient.recommendedModel(for:)) ?? "model id"
    }

    private func displayName(_ id: String) -> String {
        if let provider, id == JudgeClient.recommendedModel(for: provider) {
            return "\(id) (recommended)"
        }
        return id
    }

    private func fetchModels() {
        guard let provider else { return }
        modelsLoading = true
        modelsFailed = false
        Task {
            do {
                let list = try await JudgeClient.listModels(
                    provider: provider,
                    apiKey: providers.apiKey(for: provider),
                    baseURL: providers.config(for: provider).baseURL
                )
                models = list
                if model.isEmpty {
                    if let recommended = JudgeClient.recommendedModel(for: provider), list.contains(recommended) {
                        model = recommended
                    } else {
                        model = list.first ?? ""
                    }
                }
            } catch {
                modelsFailed = true
            }
            modelsLoading = false
        }
    }

    // MARK: - Step 3: tuning

    private var tuningStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Name")
                .font(.kelid(12, .medium))
                .foregroundStyle(.secondary)
            TextField("default", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.kelid(13, .regular))
                .disabled(existing != nil)

            HStack(spacing: 16) {
                thresholdField("Allow score", value: $allowThreshold, hint: "medium releases at \u{2265}")
                thresholdField("High score", value: $highThreshold, hint: "high releases at \u{2265}")
            }

            Text("Criteria (optional)")
                .font(.kelid(12, .medium))
                .foregroundStyle(.secondary)
            TextEditor(text: $criteria)
                .font(.kelid(12, .regular))
                .frame(height: 70)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 10))

            PaneStatus(kind: .info, message: "The guardian scores every request 0\u{2013}100 on how plausibly the stated reason justifies access. Criteria example: \u{201C}deny anything mentioning production deploys outside business hours\u{201D}.")
        }
    }

    private func thresholdField(_ label: String, value: Binding<Int>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.kelid(12, .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Stepper(value: value, in: 0...100, step: 5) {
                    Text("\(value.wrappedValue)")
                        .font(.kelid(15, .semibold))
                        .frame(width: 36, alignment: .trailing)
                }
            }
            Text("\(hint) this")
                .font(.kelid(10, .regular))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Finish

    private func loadExisting() {
        guard let existing else { return }
        provider = existing.provider
        model = existing.model
        name = existing.name
        allowThreshold = existing.allowThreshold
        highThreshold = existing.highThreshold
        criteria = existing.criteria
    }

    private func finish() {
        guard let provider else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedModel = model.trimmingCharacters(in: .whitespaces)

        if var updated = existing {
            updated.providerID = provider.rawValue
            updated.model = trimmedModel
            updated.allowThreshold = allowThreshold
            updated.highThreshold = highThreshold
            updated.criteria = criteria
            store.update(updated)
            AuditLog.shared.record(.guardian, "Guardian updated", detail: updated.name)
        } else {
            let guardian = Guardian(
                name: trimmedName,
                providerID: provider.rawValue,
                model: trimmedModel,
                allowThreshold: allowThreshold,
                highThreshold: highThreshold,
                criteria: criteria
            )
            store.add(guardian)
            AuditLog.shared.record(.guardian, "Guardian created", detail: "\(trimmedName) — \(trimmedModel)")
        }
        dismiss()
    }
}
