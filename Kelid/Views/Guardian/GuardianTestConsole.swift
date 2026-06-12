import SwiftUI

/// Live test console — Kelid's `svault judge test`. Runs a simulated agent
/// request through the REAL pipeline: per-secret rate limit, bursts, seal
/// state, then the guardian model. Repeated denials genuinely seal the
/// secret, so the brute-force response can be exercised end to end.
struct GuardianTestConsole: View {
    @Binding var toast: Toast?

    @Environment(GuardianStore.self) private var store
    @Environment(ProvidersStore.self) private var providers

    @State private var ruleID: UUID?
    @State private var caller = "claude-code"
    @State private var reason = ""
    @State private var running = false
    @State private var result: GuardianStore.Evaluation?

    private var selectedRule: SecretRule? {
        store.rules.first { $0.id == ruleID } ?? store.rules.first
    }

    var body: some View {
        PaneCard {
            Text("Test Console")
                .font(.kelid(13, .semibold))
            Text("Simulate an agent request — same pipeline a real request will take: seal check, rate limit, bursts, then the guardian's verdict.")
                .font(.kelid(11, .regular))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if store.rules.isEmpty {
                PaneStatus(kind: .info, message: "Add a secret rule above to test against.")
            } else {
                form
                if let result {
                    verdictCard(result)
                }
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Secret")
                        .font(.kelid(12, .medium))
                        .foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { selectedRule?.id },
                        set: { ruleID = $0 }
                    )) {
                        ForEach(store.rules) { rule in
                            Text("\(rule.name) (\(rule.tier.rawValue))").tag(Optional(rule.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 200, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Caller")
                        .font(.kelid(12, .medium))
                        .foregroundStyle(.secondary)
                    TextField("claude-code", text: $caller)
                        .textFieldStyle(.roundedBorder)
                        .font(.kelid(13, .regular))
                        .frame(width: 180)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Stated reason")
                    .font(.kelid(12, .medium))
                    .foregroundStyle(.secondary)
                TextField("run the production DB migration for release 2.1", text: $reason)
                    .textFieldStyle(.roundedBorder)
                    .font(.kelid(13, .regular))
                    .onSubmit { run() }
            }

            Button {
                run()
            } label: {
                HStack(spacing: 8) {
                    if running { ProgressView().controlSize(.small) }
                    Label(running ? "Evaluating\u{2026}" : "Run Request", systemImage: "play.fill")
                        .font(.kelid(13, .semibold))
                }
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(running || selectedRule == nil || caller.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func verdictCard(_ evaluation: GuardianStore.Evaluation) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: evaluation.allowed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .font(.system(size: 26))
                .foregroundStyle(evaluation.allowed ? .green : .red)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(evaluation.allowed ? "ALLOWED" : "DENIED")
                        .font(.kelid(15, .bold))
                        .foregroundStyle(evaluation.allowed ? .green : .red)
                    if let score = evaluation.score {
                        Text("score \(score)/100")
                            .font(.kelid(12, .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.quaternary.opacity(0.5), in: .capsule)
                    }
                    if evaluation.sealedNow {
                        Text("SECRET SEALED")
                            .font(.kelid(10, .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.red, in: .capsule)
                    }
                }
                if let score = evaluation.score {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary.opacity(0.5))
                            Capsule()
                                .fill(LinearGradient.kelidAccent)
                                .frame(width: proxy.size.width * Double(score) / 100)
                        }
                    }
                    .frame(height: 5)
                    .frame(maxWidth: 260)
                }
                Text(evaluation.rationale)
                    .font(.kelid(12, .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .background(
            (evaluation.allowed ? Color.green : Color.red).opacity(0.07),
            in: .rect(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke((evaluation.allowed ? Color.green : Color.red).opacity(0.2), lineWidth: 1)
        )
    }

    private func run() {
        guard let rule = selectedRule, !running else { return }
        running = true
        result = nil
        let callerName = caller.trimmingCharacters(in: .whitespaces)
        let statedReason = reason
        Task {
            result = await store.evaluate(
                rule: rule,
                caller: callerName,
                reason: statedReason,
                providers: providers
            )
            if result?.sealedNow == true {
                toast = .error("\(rule.name) is now sealed")
            }
            running = false
        }
    }
}
