import SwiftUI

struct TouchIDStep: View {
    var onNext: () -> Void

    @Environment(AppStore.self) private var store
    @State private var failed = false

    private var available: Bool { TouchIDService.isAvailable }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "touchid")
                .font(.system(size: 44))
                .foregroundStyle(store.touchIDEnrolled ? AnyShapeStyle(.green) : AnyShapeStyle(LinearGradient.kelidAccent))

            Text("Add Touch ID")
                .font(.title.bold())

            if available {
                Text("Unlock Kelid with your fingerprint instead of typing\nthe master passphrase every time.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Touch ID is not available on this Mac.\nYou can enable it later in Settings on a supported machine.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if store.touchIDEnrolled {
                Label("Touch ID enabled", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
            } else if available {
                Button {
                    enroll()
                } label: {
                    Label("Enable Touch ID", systemImage: "touchid")
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)

                if failed {
                    Text("Touch ID check did not complete — you can try again or skip.")
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }

            Text("Milestone note: this records your choice after a successful fingerprint check. Binding Touch ID to the master keyslot ships with the crypto core.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Spacer().frame(height: 4)

            HStack(spacing: 12) {
                if !store.touchIDEnrolled {
                    Button("Skip for Now", action: onNext)
                        .buttonStyle(.glass)
                        .controlSize(.large)
                }
                if store.touchIDEnrolled {
                    Button("Continue", action: onNext)
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                }
            }

            Spacer().frame(height: 8)
        }
        .padding(.horizontal, 30)
    }

    private func enroll() {
        failed = false
        Task {
            let ok = await TouchIDService.authenticate(reason: "enable Touch ID unlock for Kelid")
            if ok {
                store.touchIDEnrolled = true
                AuditLog.shared.record(.touchID, "Touch ID enabled")
            } else {
                AuditLog.shared.record(.touchID, "Touch ID enrollment failed", outcome: .failure)
                failed = true
            }
        }
    }
}
