import SwiftUI

struct YubiKeyStep: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.radiowaves.forward")
                .font(.system(size: 40))
                .foregroundStyle(LinearGradient.kelidAccent)

            Text("Add YubiKey")
                .font(.title.bold())
            Text("Unlock with a hardware security key over FIDO2.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                Button {
                    // Enabled once FIDO2 hmac-secret enrollment lands.
                } label: {
                    Label("Enroll YubiKey", systemImage: "plus.circle")
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .disabled(true)

                Text("Coming soon")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(.thinMaterial, in: .capsule)
                    .foregroundStyle(.secondary)
            }

            Text("Hardware key enrollment (FIDO2 hmac-secret, as in Svault) arrives in a later milestone. You can finish setup without it.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Spacer().frame(height: 4)

            Button("Finish Setup") {
                store.onboardingComplete = true
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            Spacer().frame(height: 8)
        }
        .padding(.horizontal, 30)
    }
}
