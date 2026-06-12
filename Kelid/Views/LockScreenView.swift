import SwiftUI

/// Full-window lock screen. Replaces the entire UI while locked — nothing is
/// rendered underneath. The preferred unlock method is offered first; the
/// others stay available as fallbacks.
struct LockScreenView: View {
    @Environment(AppStore.self) private var store

    @State private var passphrase = ""
    @State private var checking = false
    @State private var errorMessage: String?
    @State private var usePassphrase = false

    private var touchAvailable: Bool {
        store.touchIDEnrolled && TouchIDService.isAvailable
    }

    /// Touch ID leads only when available and preferred; passphrase otherwise.
    private var touchLeads: Bool {
        touchAvailable && store.preferredUnlock == .touchID && !usePassphrase
    }

    var body: some View {
        ZStack {
            AnimatedMeshBackground()

            VStack(spacing: 18) {
                Image("KeyGlyph")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .foregroundStyle(LinearGradient.kelidAccent)
                    .padding(18)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))

                VStack(spacing: 6) {
                    Text("Kelid is locked")
                        .font(.kelid(24, .bold))
                    Text("Authenticate to continue.")
                        .font(.kelid(13, .regular))
                        .foregroundStyle(.secondary)
                }

                if touchLeads {
                    touchIDPrimary
                } else {
                    passphrasePrimary
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.kelid(12, .regular))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
            }
            .padding(36)
            .frame(maxWidth: 440)
        }
        .frame(minWidth: 680, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
        .background(WindowConfigurator(hideSystemButtons: false))
    }

    // MARK: - Touch ID first

    private var touchIDPrimary: some View {
        VStack(spacing: 14) {
            Button {
                Task { await unlockWithTouchID() }
            } label: {
                HStack(spacing: 8) {
                    if checking { ProgressView().controlSize(.small) }
                    Label("Unlock with Touch ID", systemImage: "touchid")
                        .font(.kelid(14, .semibold))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .disabled(checking)
            .keyboardShortcut(.defaultAction)

            Button("Use passphrase instead") {
                usePassphrase = true
                errorMessage = nil
            }
            .buttonStyle(.borderless)
            .font(.kelid(12, .medium))
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Passphrase first

    private var passphrasePrimary: some View {
        VStack(spacing: 14) {
            SecureField("Master passphrase", text: $passphrase)
                .textFieldStyle(.roundedBorder)
                .font(.kelid(14, .regular))
                .frame(maxWidth: 300)
                .onSubmit { unlockWithPassphrase() }
                .disabled(checking)

            Button {
                unlockWithPassphrase()
            } label: {
                HStack(spacing: 8) {
                    if checking { ProgressView().controlSize(.small) }
                    Text(checking ? "Checking\u{2026}" : "Unlock")
                        .font(.kelid(14, .semibold))
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 9)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(checking || passphrase.isEmpty)
            .opacity(checking || passphrase.isEmpty ? 0.5 : 1)

            if touchAvailable {
                Button {
                    usePassphrase = false
                    errorMessage = nil
                    Task { await unlockWithTouchID() }
                } label: {
                    Label("Use Touch ID", systemImage: "touchid")
                        .font(.kelid(12, .medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func unlockWithTouchID() async {
        checking = true
        errorMessage = nil
        let ok = await TouchIDService.authenticate(reason: "unlock Kelid")
        checking = false
        if ok {
            AuditLog.shared.record(.session, "Unlocked", detail: "Touch ID")
            store.unlock()
        } else {
            AuditLog.shared.record(.session, "Unlock failed", detail: "Touch ID", outcome: .failure)
            errorMessage = "Touch ID was not confirmed."
        }
    }

    private func unlockWithPassphrase() {
        guard !passphrase.isEmpty, !checking else { return }
        checking = true
        errorMessage = nil
        Task {
            let ok = await MasterKeyStore.verify(passphrase: passphrase)
            passphrase = "" // drop from memory regardless of outcome
            checking = false
            if ok {
                AuditLog.shared.record(.session, "Unlocked", detail: "Passphrase")
                store.unlock()
            } else {
                AuditLog.shared.record(.session, "Unlock failed", detail: "Wrong passphrase", outcome: .failure)
                errorMessage = "Wrong passphrase."
            }
        }
    }
}
