import SwiftUI

struct ChangePassphrasePane: View {
    @State private var current = ""
    @State private var newPass = ""
    @State private var confirm = ""
    @State private var busy = false
    @State private var status: (PaneStatus.Kind, String)?

    private var canSubmit: Bool {
        !busy && !current.isEmpty && newPass.count >= 8 && newPass == confirm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PaneHeader(
                icon: "lock.rotation",
                title: "Change Passphrase",
                subtitle: "Set a new master passphrase. Kelid verifies your current one, then re-derives the verifier under a fresh salt — it never stores the passphrase itself."
            )

            PaneCard {
                field("Current passphrase", text: $current)
                Divider().opacity(0.4)
                field("New passphrase", text: $newPass)
                field("Confirm new passphrase", text: $confirm)

                if !newPass.isEmpty, newPass.count < 8 {
                    PaneStatus(kind: .info, message: "Use at least 8 characters.")
                } else if !confirm.isEmpty, newPass != confirm {
                    PaneStatus(kind: .error, message: "The new passphrases do not match.")
                }
            }

            if let status {
                PaneStatus(kind: status.0, message: status.1)
            }

            Button {
                submit()
            } label: {
                HStack(spacing: 8) {
                    if busy { ProgressView().controlSize(.small) }
                    Text(busy ? "Updating\u{2026}" : "Update Passphrase")
                        .font(.kelid(14, .semibold))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.5)
        }
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.kelid(12, .medium))
                .foregroundStyle(.secondary)
            SecureField("", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.kelid(14, .regular))
        }
    }

    private func submit() {
        busy = true
        status = nil
        Task {
            do {
                try await MasterKeyStore.changePassphrase(current: current, new: newPass)
                current = ""; newPass = ""; confirm = ""
                status = (.success, "Passphrase updated.")
            } catch {
                status = (.error, error.localizedDescription)
            }
            busy = false
        }
    }
}
