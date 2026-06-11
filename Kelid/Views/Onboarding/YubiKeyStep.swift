import SwiftUI

struct YubiKeyStep: View {
    @Environment(AppStore.self) private var store

    @State private var isEnrolling = false
    @State private var enrolled = YubiKeyService.isEnrolled
    @State private var keyPresent = YubiKeyService.isKeyPresent
    @State private var pin = ""
    @State private var noPin = false
    @State private var errorMessage: String?
    @State private var presenceTimer: Timer?

    /// Enroll is enabled only once the user has either entered a PIN or
    /// explicitly declared the key has none.
    private var canEnroll: Bool {
        keyPresent && !isEnrolling && (noPin || !pin.isEmpty)
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.radiowaves.forward")
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(enrolled ? AnyShapeStyle(.green) : AnyShapeStyle(.tint))

            VStack(spacing: 6) {
                Text("Add YubiKey")
                    .font(.kelid(28, .bold))
                Text("Unlock Kelid with a hardware security key over FIDO2.")
                    .font(.kelid(13, .regular))
                    .foregroundStyle(.secondary)
            }

            if enrolled {
                Label("Security key enrolled", systemImage: "checkmark.circle.fill")
                    .font(.kelid(15, .semibold))
                    .foregroundStyle(.green)
                Button("Remove enrollment", role: .destructive) {
                    YubiKeyService.removeEnrollment()
                    enrolled = false
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            } else {
                presenceRow

                // PIN entry + "no PIN" escape hatch.
                VStack(spacing: 10) {
                    SecureField("Security key PIN", text: $pin)
                        .textFieldStyle(.roundedBorder)
                        .font(.kelid(14, .regular))
                        .disabled(noPin)
                        .opacity(noPin ? 0.4 : 1)
                        .frame(maxWidth: 280)

                    Toggle(isOn: $noPin) {
                        Text("My key has no PIN")
                            .font(.kelid(12, .medium))
                    }
                    .toggleStyle(.checkbox)
                    .onChange(of: noPin) { _, on in if on { pin = "" } }
                }
                .frame(maxWidth: 280)

                Button {
                    enroll()
                } label: {
                    if isEnrolling {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Touch your key…").font(.kelid(14, .medium))
                        }
                    } else {
                        Label("Enroll YubiKey", systemImage: "key.radiowaves.forward")
                            .font(.kelid(14, .semibold))
                    }
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .disabled(!canEnroll)
                .opacity(canEnroll ? 1 : 0.5)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.kelid(12, .regular))
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
            }

            Text("Creates a resident credential with the hmac-secret extension. A later milestone uses it to wrap your master keyslot; for now this proves the key works with Kelid.")
                .font(.kelid(11, .regular))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)

            Spacer().frame(height: 4)

            HStack(spacing: 12) {
                if enrolled {
                    Button("Finish Setup") { finish() }
                        .buttonStyle(.glassProminent)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Skip for Now") { finish() }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .controlSize(.large)
                }
            }

            Spacer().frame(height: 8)
        }
        .padding(.horizontal, 30)
        .onAppear { startPresencePolling() }
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

    private func startPresencePolling() {
        presenceTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            Task { @MainActor in
                if !isEnrolling { keyPresent = YubiKeyService.isKeyPresent }
            }
        }
    }

    private func enroll() {
        isEnrolling = true
        errorMessage = nil
        let pinValue = noPin ? nil : pin
        Task {
            do {
                _ = try await YubiKeyService.enroll(pin: pinValue)
                enrolled = true
                pin = "" // drop the PIN from memory once it has served its purpose
            } catch {
                errorMessage = error.localizedDescription
            }
            isEnrolling = false
        }
    }

    private func finish() {
        presenceTimer?.invalidate()
        store.onboardingComplete = true
    }
}
