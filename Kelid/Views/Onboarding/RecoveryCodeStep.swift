import AppKit
import SwiftUI

struct RecoveryCodeStep: View {
    let code: String
    var onNext: () -> Void

    @State private var saved = false
    @State private var copied = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "key.viewfinder")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.tint)

            VStack(spacing: 6) {
                Text("Recovery Code")
                    .font(.kelid(28, .bold))
                Text("The only way back in if you forget your master passphrase.")
                    .font(.kelid(13, .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // The full code on a single row, in one box.
            Text(code)
                .font(.kelid(16, .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .padding(.horizontal, 20)
                .background(.regularMaterial, in: .rect(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.primary.opacity(0.08), lineWidth: 1)
                )
                .frame(maxWidth: 520)

            Button {
                copy()
            } label: {
                Label(copied ? "Copied" : "Copy Code", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.kelid(13, .medium))
            }
            .buttonStyle(.glass)
            .controlSize(.regular)

            // Warning as a contained callout, not raw orange text.
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Shown only once. Kelid stores just a hash of this code — write it down or save it somewhere safe now.")
                    .font(.kelid(12, .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: 440, alignment: .leading)
            .background(.orange.opacity(0.08), in: .rect(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.orange.opacity(0.25), lineWidth: 1)
            )

            Toggle(isOn: $saved) {
                Text("I saved my recovery code")
                    .font(.kelid(13, .medium))
            }
            .toggleStyle(.checkbox)

            Button(action: onNext) {
                Text("Continue")
                    .font(.kelid(15, .semibold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!saved)
            .opacity(saved ? 1 : 0.5)

            Spacer().frame(height: 4)
        }
        .padding(.horizontal, 30)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        // Concealed marker: clipboard managers must not archive this value.
        NSPasteboard.general.setString("", forType: .init("org.nspasteboard.ConcealedType"))
        NSPasteboard.general.setString(code, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}
