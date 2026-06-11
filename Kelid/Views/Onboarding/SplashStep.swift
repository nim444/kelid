import AppKit
import SwiftUI

struct SplashStep: View {
    var onNext: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 118, height: 118)
                .shadow(color: Color.accentColor.opacity(0.35), radius: 18, y: 8)
                .padding(.bottom, 6)

            Text("Kelid")
                .font(.system(size: 40, weight: .bold))
            Text("کلید")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("The key your AI agents have to ask for.")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("Native successor of Svault — structured requests, policy, AI judge, audit.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)

            Spacer()

            Button("Get Started", action: onNext)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

            Spacer().frame(height: 20)
        }
    }
}
