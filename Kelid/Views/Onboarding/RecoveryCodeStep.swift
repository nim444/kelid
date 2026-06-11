import AppKit
import SwiftUI

struct RecoveryCodeStep: View {
    let code: String
    var onNext: () -> Void

    @State private var saved = false
    @State private var copied = false

    private var codeLines: [String] {
        let groups = code.split(separator: "-").map(String.init)
        guard groups.count == 8 else { return [code] }
        return [
            groups[0..<4].joined(separator: "-"),
            groups[4..<8].joined(separator: "-"),
        ]
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.viewfinder")
                .font(.system(size: 36))
                .foregroundStyle(LinearGradient.kelidAccent)

            Text("Recovery Code")
                .font(.title.bold())
            Text("This is the only way back in if you forget your master passphrase.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                ForEach(codeLines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 28)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            } label: {
                Label(copied ? "Copied" : "Copy Code", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.glass)

            Label(
                "Shown only once. Kelid keeps only a hash of this code — write it down or store it in a safe place now.",
                systemImage: "exclamationmark.triangle"
            )
            .font(.callout)
            .foregroundStyle(.orange)
            .frame(maxWidth: 440)

            Toggle("I saved my recovery code", isOn: $saved)
                .toggleStyle(.checkbox)

            Button("Continue", action: onNext)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!saved)

            Spacer().frame(height: 8)
        }
        .padding(.horizontal, 30)
    }
}
