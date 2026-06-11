import SwiftUI

struct TermsStep: View {
    var onNext: () -> Void
    @State private var agreed = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Terms & Agreement")
                .font(.title.bold())

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section(
                        "License",
                        "Kelid is licensed under the PolyForm Noncommercial License 1.0.0. "
                            + "It is free for personal, academic, and non-profit use. "
                            + "Commercial use by companies is not permitted."
                    )
                    section(
                        "The security boundary, stated honestly",
                        "Kelid is built for cooperative and semi-trusted AI agents. It gates, "
                            + "judges, and audits agent access to your secrets. It is not a sandbox "
                            + "against a hostile process running as your own macOS user — such a "
                            + "process can read an unlocked session directly. If that distinction "
                            + "matters to you, Kelid is exactly for you."
                    )
                    section(
                        "Your data stays local",
                        "Vaults, policies, and audit logs live only on this Mac. Kelid sends no "
                            + "telemetry. The only outbound traffic is the optional AI judge call "
                            + "to the model provider you configure yourself."
                    )
                    section(
                        "No warranty",
                        "Kelid is provided as-is, without warranty of any kind. You are "
                            + "responsible for keeping your passphrase and recovery code safe — "
                            + "without them, your secrets cannot be recovered."
                    )
                }
                .padding(18)
            }
            .frame(maxWidth: 520, maxHeight: 320)
            .background(.thinMaterial, in: .rect(cornerRadius: 14))

            Toggle("I have read and agree to the terms", isOn: $agreed)
                .toggleStyle(.checkbox)

            Button("Agree & Continue", action: onNext)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!agreed)

            Spacer().frame(height: 8)
        }
        .padding(.horizontal, 30)
    }

    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(body).font(.callout).foregroundStyle(.secondary)
        }
    }
}
