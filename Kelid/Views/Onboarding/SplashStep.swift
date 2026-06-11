import AppKit
import SwiftUI

struct SplashStep: View {
    var onNext: () -> Void

    @State private var appear = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 132, height: 132)
                .shadow(color: Color.accentColor.opacity(0.45), radius: 28, y: 10)
                .scaleEffect(appear ? 1 : 0.86)
                .opacity(appear ? 1 : 0)

            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Kelid")
                        .font(.kelid(50, .bold))
                        .foregroundStyle(.primary)
                    Text("کلید")
                        .font(.system(size: 30, weight: .regular))
                        .foregroundStyle(.tertiary)
                        .baselineOffset(2)
                }

                Text("Secret access layer for AI agents")
                    .font(.kelid(16, .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 22)
            .opacity(appear ? 1 : 0)
            .offset(y: appear ? 0 : 10)

            Spacer()

            Button(action: onNext) {
                HStack(spacing: 10) {
                    Text("Get Started")
                        .font(.kelid(17, .semibold))
                    Image(systemName: "arrow.right")
                        .font(.body.weight(.semibold))
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 14)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)
            .tint(.accentColor)
            .keyboardShortcut(.defaultAction)
            .shadow(color: Color.accentColor.opacity(0.4), radius: 20, y: 8)
            .scaleEffect(appear ? 1 : 0.9)
            .opacity(appear ? 1 : 0)

            Spacer().frame(height: 44)
        }
        .padding(.horizontal, 40)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) {
                appear = true
            }
        }
    }
}
