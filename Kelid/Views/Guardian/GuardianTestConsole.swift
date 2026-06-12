import SwiftUI

/// `svault judge test` as a GUI: send a fabricated request straight to a
/// guardian and see its verdict. No secret value involved, no policy state
/// touched — this only tests how the model reasons.
struct GuardianTestConsole: View {
    @Binding var toast: Toast?

    @Environment(GuardianStore.self) private var store
    @Environment(ProvidersStore.self) private var providers

    @State private var guardianID: UUID?
    @State private var caller = "claude-code"
    @State private var secret = "DB_URL"
    @State private var scope = "database"
    @State private var tier: Tier = .medium
    @State private var purpose = ""
    @State private var reason = ""
    @State private var running = false
    @State private var result: TestResult?

    private struct TestResult {
        var allowed: Bool
        var score: Int?
        var rationale: String
        var thresholdNote: String
    }

    private var selectedGuardian: Guardian? {
        store.guardians.first { $0.id == guardianID } ?? store.defaultGuardian
    }

    private var canRun: Bool {
        selectedGuardian != nil && !running
            && !caller.trimmingCharacters(in: .whitespaces).isEmpty
            && !secret.trimmingCharacters(in: .whitespaces).isEmpty
            && !reason.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        PaneCard {
            Text("Test Console")
                .font(.kelid(13, .semibold))
            Text("Send a fabricated request to the guardian and see how it scores the reason. Nothing is stored and no secret value is involved.")
                .font(.kelid(11, .regular))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if store.guardians.isEmpty {
                PaneStatus(kind: .info, message: "Create a guardian first.")
            } else {
                form
                if let result {
                    verdictCard(result)
                }
            }
        }
    }

    // MARK: - Form

    private var form: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                labeled("Guardian", width: 180) {
                    Picker("", selection: Binding(
                        get: { selectedGuardian?.id },
                        set: { guardianID = $0 }
                    )) {
                        ForEach(store.guardians) { guardian in
                            Text(guardian.name).tag(Optional(guardian.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                labeled("Caller", width: 160) {
                    TextField("claude-code", text: $caller)
                        .textFieldStyle(.roundedBorder)
                        .font(.kelid(13, .regular))
                }
                labeled("Tier", width: 200) {
                    Picker("", selection: $tier) {
                        ForEach(Tier.allCases) { tier in
                            Text(tier.title).tag(tier)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            HStack(spacing: 12) {
                labeled("Secret name", width: 180) {
                    TextField("DB_URL", text: $secret)
                        .textFieldStyle(.roundedBorder)
                        .font(.kelid(13, .regular))
                }
                labeled("Scope", width: 160) {
                    TextField("database", text: $scope)
                        .textFieldStyle(.roundedBorder)
                        .font(.kelid(13, .regular))
                }
            }

            labeled("Secret purpose (optional — the guardian checks the reason against it)", width: nil) {
                TextField("production Postgres connection string", text: $purpose)
                    .textFieldStyle(.roundedBorder)
                    .font(.kelid(13, .regular))
            }

            labeled("Stated reason", width: nil) {
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
                    Label(running ? "Asking the guardian\u{2026}" : "Run Test", systemImage: "play.fill")
                        .font(.kelid(13, .semibold))
                }
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(!canRun)
        }
    }

    private func labeled(_ label: String, width: CGFloat?, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.kelid(12, .medium))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(width: width, alignment: .leading)
    }

    // MARK: - Verdict

    private func verdictCard(_ result: TestResult) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: result.allowed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .font(.system(size: 26))
                .foregroundStyle(result.allowed ? .green : .red)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(result.allowed ? "ALLOWED" : "DENIED")
                        .font(.kelid(15, .bold))
                        .foregroundStyle(result.allowed ? .green : .red)
                    if let score = result.score {
                        Text("score \(score)/100")
                            .font(.kelid(12, .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.quaternary.opacity(0.5), in: .capsule)
                    }
                }
                if let score = result.score {
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
                Text(result.rationale)
                    .font(.kelid(12, .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(result.thresholdNote)
                    .font(.kelid(11, .regular))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(14)
        .background(
            (result.allowed ? Color.green : Color.red).opacity(0.07),
            in: .rect(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke((result.allowed ? Color.green : Color.red).opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Run

    private func run() {
        guard canRun, let guardian = selectedGuardian, let provider = guardian.provider else { return }
        running = true
        result = nil

        let request = JudgeClient.JudgeRequest(
            caller: caller.trimmingCharacters(in: .whitespaces),
            secret: secret.trimmingCharacters(in: .whitespaces),
            scope: scope.trimmingCharacters(in: .whitespaces),
            tier: tier,
            secretPurpose: purpose,
            reason: reason,
            recentSummary: ""
        )
        let apiKey = providers.apiKey(for: provider)
        let baseURL = JudgeClient.normalizedOpenAIBase(
            provider: provider,
            baseURL: providers.config(for: provider).baseURL
        )

        Task {
            let verdict = await JudgeClient.evaluate(
                guardian: guardian, request: request, apiKey: apiKey, baseURL: baseURL
            )
            let threshold = tier == .high ? guardian.highThreshold : guardian.allowThreshold

            switch verdict {
            case .allow(let score, let rationale):
                let allowed = score >= threshold
                result = TestResult(
                    allowed: allowed,
                    score: score,
                    rationale: rationale,
                    thresholdNote: "\(tier.rawValue) tier releases at score \u{2265}\(threshold)\(allowed ? "" : " — model said allow, but the score is below the threshold")"
                )
            case .deny(let score, let rationale):
                result = TestResult(
                    allowed: false,
                    score: score,
                    rationale: rationale,
                    thresholdNote: "\(tier.rawValue) tier releases at score \u{2265}\(threshold)"
                )
            case .unavailable(let why):
                result = TestResult(
                    allowed: false,
                    score: nil,
                    rationale: "Guardian unavailable: \(why)",
                    thresholdNote: "medium tier fails open in the real gate; high tier fails closed"
                )
                toast = .error("Guardian unavailable")
            }

            if let result {
                AuditLog.shared.record(
                    .guardian, "Guardian test",
                    detail: "\(request.secret) — \(request.caller)\(result.score.map { " (score \($0))" } ?? "")",
                    outcome: result.allowed ? .success : .denied
                )
            }
            running = false
        }
    }
}
