import AppKit
import SwiftUI

struct SplashStep: View {
    var onNext: () -> Void

    @State private var appear = false

    var body: some View {
        ZStack {
            AnimatedMeshBackground()

            VStack(spacing: 0) {
                Spacer()

                monoIcon
                    .stagger(appear, delay: 0.0)

                VStack(spacing: 10) {
                    Text("Kelid")
                        .font(.kelid(54, .bold))
                        .foregroundStyle(.primary)
                        .stagger(appear, delay: 0.08)

                    Text("Secret access layer for AI agents")
                        .font(.kelid(16, .medium))
                        .foregroundStyle(.secondary)
                        .stagger(appear, delay: 0.16)
                }
                .padding(.top, 26)

                Spacer()

                Button(action: onNext) {
                    HStack(spacing: 10) {
                        Text("Get Started")
                            .font(.kelid(17, .semibold))
                        Image(systemName: "arrow.right")
                            .font(.body.weight(.semibold))
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 15)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.extraLarge)
                .tint(.accentColor)
                .keyboardShortcut(.defaultAction)
                .shadow(color: Color.accentColor.opacity(0.45), radius: 22, y: 8)
                .stagger(appear, delay: 0.26)

                Spacer().frame(height: 48)
            }
            .padding(.horizontal, 40)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                appear = true
            }
        }
    }

    private var monoIcon: some View {
        Image(systemName: "key.fill")
            .font(.system(size: 58, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 128, height: 128)
            .background {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(.white.opacity(0.06))
                    .background(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    )
            }
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 30, style: .continuous))
            .shadow(color: Color.accentColor.opacity(0.35), radius: 30, y: 12)
    }
}

/// Staggered fade-up: each element rises ~26px while fading in, on a short delay.
private struct StaggerModifier: ViewModifier {
    let active: Bool
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(active ? 1 : 0)
            .offset(y: active ? 0 : 26)
            .animation(.spring(response: 0.7, dampingFraction: 0.78).delay(delay), value: active)
    }
}

private extension View {
    func stagger(_ active: Bool, delay: Double) -> some View {
        modifier(StaggerModifier(active: active, delay: delay))
    }
}
