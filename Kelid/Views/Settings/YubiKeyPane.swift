import SwiftUI

struct YubiKeyPane: View {
    @State private var enrolled = YubiKeyService.isEnrolled
    @State private var keyPresent = YubiKeyService.isKeyPresent
    @State private var pin = ""
    @State private var noPin = false
    @State private var isEnrolling = false
    @State private var status: (PaneStatus.Kind, String)?
    @State private var presenceTimer: Timer?

    private var canEnroll: Bool {
        keyPresent && !isEnrolling && (noPin || !pin.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PaneHeader(
                icon: "key.radiowaves.forward",
                title: "YubiKey",
                subtitle: "Enroll a hardware security key over FIDO2. Kelid creates a resident credential with the hmac-secret extension; a later milestone uses it to wrap your master keyslot."
            )

            PaneCard {
                if enrolled {
                    PaneStatus(kind: .success, message: "A security key is enrolled.")
                    if let e = YubiKeyService.enrollment {
                        Text("AAGUID \(e.aaguidHex.prefix(8))\u{2026} \u{2022} enrolled \(e.enrolledAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.kelid(11, .regular))
                            .foregroundStyle(.tertiary)
                    }
                    Button("Remove YubiKey", role: .destructive) {
                        YubiKeyService.removeEnrollment()
                        enrolled = false
                        AuditLog.shared.record(.yubiKey, "YubiKey enrollment removed", outcome: .info)
                        status = (.info, "YubiKey enrollment removed.")
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                } else {
                    presenceRow

                    SecureField("Security key PIN", text: $pin)
                        .textFieldStyle(.roundedBorder)
                        .font(.kelid(14, .regular))
                        .disabled(noPin)
                        .opacity(noPin ? 0.4 : 1)
                        .frame(maxWidth: 280)

                    Toggle(isOn: $noPin) {
                        Text("My key has no PIN").font(.kelid(12, .medium))
                    }
                    .toggleStyle(.checkbox)
                    .onChange(of: noPin) { _, on in if on { pin = "" } }

                    Button {
                        enroll()
                    } label: {
                        HStack(spacing: 8) {
                            if isEnrolling {
                                ProgressView().controlSize(.small)
                                Text("Touch your key\u{2026}").font(.kelid(14, .medium))
                            } else {
                                Label("Enroll YubiKey", systemImage: "key.radiowaves.forward")
                                    .font(.kelid(14, .semibold))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
                    .disabled(!canEnroll)
                    .opacity(canEnroll ? 1 : 0.5)
                }
            }

            if let status {
                PaneStatus(kind: status.0, message: status.1)
            }
        }
        .onAppear(perform: startPolling)
        .onDisappear { presenceTimer?.invalidate() }
    }

    private var presenceRow: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(keyPresent ? .green : .secondary.opacity(0.4))
                .frame(width: 8, height: 8)
            Text(keyPresent ? "Security key detected" : "No security key detected")
                .font(.kelid(13, .regular))
                .foregroundStyle(.secondary)
        }
    }

    private func startPolling() {
        presenceTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            Task { @MainActor in
                if !isEnrolling { keyPresent = YubiKeyService.isKeyPresent }
            }
        }
    }

    private func enroll() {
        isEnrolling = true
        status = nil
        let pinValue = noPin ? nil : pin
        Task {
            do {
                _ = try await YubiKeyService.enroll(pin: pinValue)
                enrolled = true
                pin = "" // drop the PIN from memory once it has served its purpose
                AuditLog.shared.record(.yubiKey, "YubiKey enrolled")
                status = (.success, "Security key enrolled.")
            } catch {
                AuditLog.shared.record(.yubiKey, "YubiKey enrollment failed", detail: error.localizedDescription, outcome: .failure)
                status = (.error, error.localizedDescription)
            }
            isEnrolling = false
        }
    }
}
