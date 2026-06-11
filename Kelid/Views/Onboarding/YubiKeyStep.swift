import SwiftUI

struct YubiKeyStep: View {
    @Environment(AppStore.self) private var store

    @State private var isEnrolling = false
    @State private var enrolled = YubiKeyService.isEnrolled
    @State private var keyPresent = YubiKeyService.isKeyPresent
    @State private var errorMessage: String?
    @State private var presenceTimer: Timer?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.radiowaves.forward")
                .font(.system(size: 40))
                .foregroundStyle(enrolled ? AnyShapeStyle(.green) : AnyShapeStyle(LinearGradient.kelidAccent))

            Text("Add YubiKey")
                .font(.title.bold())
            Text("Unlock Kelid with a hardware security key over FIDO2.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if enrolled {
                Label("Security key enrolled", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Button("Remove enrollment", role: .destructive) {
                    YubiKeyService.removeEnrollment()
                    enrolled = false
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            } else {
                HStack(spacing: 7) {
                    Circle()
                        .fill(keyPresent ? .green : .secondary.opacity(0.4))
                        .frame(width: 8, height: 8)
                    Text(keyPresent ? "Security key detected" : "No security key detected")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Button {
                    enroll()
                } label: {
                    if isEnrolling {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Touch your key…")
                        }
                    } else {
                        Label("Enroll YubiKey", systemImage: "key.radiowaves.forward")
                    }
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(!keyPresent || isEnrolling)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
            }

            Text("Creates a resident credential with the hmac-secret extension. A later milestone uses it to wrap your master keyslot; for now this proves the key works with Kelid.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)

            Spacer().frame(height: 4)

            HStack(spacing: 12) {
                if !enrolled {
                    Button("Skip for Now") { finish() }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                } else {
                    Button("Finish Setup") { finish() }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)
                        .keyboardShortcut(.defaultAction)
                }
            }

            Spacer().frame(height: 8)
        }
        .padding(.horizontal, 30)
        .onAppear { startPresencePolling() }
        .onDisappear { presenceTimer?.invalidate() }
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
        Task {
            do {
                _ = try await YubiKeyService.enroll()
                enrolled = true
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
