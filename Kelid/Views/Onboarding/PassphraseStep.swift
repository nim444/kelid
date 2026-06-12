import SwiftUI

struct PassphraseStep: View {
    var onCreated: (String) -> Void

    @State private var passphrase = ""
    @State private var confirmation = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    private let minimumLength = 10

    private var longEnough: Bool { passphrase.count >= minimumLength }
    private var matches: Bool { !confirmation.isEmpty && passphrase == confirmation }
    private var canCreate: Bool { longEnough && matches && !isWorking }

    private var strength: (label: String, fraction: Double, color: Color) {
        let length = passphrase.count
        var score = min(Double(length) / 24.0, 1.0)
        let hasDigit = passphrase.contains { $0.isNumber }
        let hasSymbol = passphrase.contains { !$0.isLetter && !$0.isNumber }
        if hasDigit { score = min(score + 0.1, 1.0) }
        if hasSymbol { score = min(score + 0.15, 1.0) }
        switch score {
        case ..<0.4: return ("Weak", score, .red)
        case ..<0.7: return ("Okay", score, .orange)
        default: return ("Strong", score, .green)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 36))
                .foregroundStyle(LinearGradient.kelidAccent)

            Text("Set Master Passphrase")
                .font(.title.bold())
            Text("One passphrase unlocks everything. It never leaves this Mac\nand cannot be reset without your recovery code.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                SecureField("Master passphrase", text: $passphrase)
                    .textFieldStyle(.roundedBorder)
                SecureField("Confirm passphrase", text: $confirmation)
                    .textFieldStyle(.roundedBorder)

                if !passphrase.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.secondary.opacity(0.2))
                                Capsule()
                                    .fill(strength.color)
                                    .frame(width: proxy.size.width * strength.fraction)
                            }
                        }
                        .frame(height: 5)
                        HStack {
                            Text(strength.label)
                                .font(.caption)
                                .foregroundStyle(strength.color)
                            Spacer()
                            if !longEnough {
                                Text("At least \(minimumLength) characters")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if !confirmation.isEmpty, !matches {
                                Text("Passphrases do not match")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 380)

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Button {
                create()
            } label: {
                if isWorking {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Create Passphrase")
                }
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!canCreate)

            Spacer().frame(height: 8)
        }
        .padding(.horizontal, 30)
    }

    private func create() {
        guard canCreate else { return }
        isWorking = true
        errorMessage = nil
        Task {
            do {
                let code = try await MasterKeyStore.create(passphrase: passphrase)
                AuditLog.shared.record(.master, "Master passphrase created")
                isWorking = false
                onCreated(code)
            } catch {
                isWorking = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
