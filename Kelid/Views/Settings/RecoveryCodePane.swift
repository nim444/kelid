import AppKit
import SwiftUI

struct RecoveryCodePane: View {
    @State private var passphrase = ""
    @State private var busy = false
    @State private var newCode: String?
    @State private var copied = false
    @State private var status: (PaneStatus.Kind, String)?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PaneHeader(
                icon: "key.viewfinder",
                title: "Recovery Code",
                subtitle: "Your recovery code was shown only once. Kelid stores just a hash of it, so the original can\u{2019}t be revealed. Confirm your passphrase to generate a new one — the old code stops working immediately."
            )

            if let newCode {
                generatedCard(newCode)
            } else {
                regenerateCard
            }

            if let status {
                PaneStatus(kind: status.0, message: status.1)
            }
        }
    }

    private var regenerateCard: some View {
        PaneCard {
            Text("Master passphrase")
                .font(.kelid(12, .medium))
                .foregroundStyle(.secondary)
            SecureField("", text: $passphrase)
                .textFieldStyle(.roundedBorder)
                .font(.kelid(14, .regular))

            Button {
                regenerate()
            } label: {
                HStack(spacing: 8) {
                    if busy { ProgressView().controlSize(.small) }
                    Text(busy ? "Generating\u{2026}" : "Generate New Code")
                        .font(.kelid(14, .semibold))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .disabled(busy || passphrase.isEmpty)
            .opacity(busy || passphrase.isEmpty ? 0.5 : 1)
        }
    }

    private func generatedCard(_ code: String) -> some View {
        PaneCard {
            Text("New recovery code")
                .font(.kelid(12, .medium))
                .foregroundStyle(.secondary)

            Text(code)
                .font(.kelid(15, .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, 18)
                .background(.regularMaterial, in: .rect(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.primary.opacity(0.08), lineWidth: 1)
                )

            HStack(spacing: 10) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.kelid(13, .medium))
                }
                .buttonStyle(.glass)

                Button {
                    newCode = nil
                    passphrase = ""
                    status = nil
                } label: {
                    Text("Done").font(.kelid(13, .medium))
                }
                .buttonStyle(.glass)
            }

            PaneStatus(kind: .info, message: "Write this down now. It will not be shown again, and the previous code no longer works.")
        }
    }

    private func regenerate() {
        busy = true
        status = nil
        Task {
            do {
                let code = try await MasterKeyStore.regenerateRecoveryCode(currentPassphrase: passphrase)
                newCode = code
            } catch {
                status = (.error, error.localizedDescription)
            }
            busy = false
        }
    }
}
