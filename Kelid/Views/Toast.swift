import SwiftUI

/// A transient message that auto-dismisses. Identity (`id`) lets repeated
/// toasts re-trigger the fade timer.
struct Toast: Equatable, Identifiable {
    enum Kind { case success, error, info }
    let id = UUID()
    let kind: Kind
    let text: String

    static func success(_ t: String) -> Toast { Toast(kind: .success, text: t) }
    static func error(_ t: String) -> Toast { Toast(kind: .error, text: t) }
    static func info(_ t: String) -> Toast { Toast(kind: .info, text: t) }
}

private struct ToastCapsule: View {
    let toast: Toast

    private var icon: String {
        switch toast.kind {
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }

    private var tint: Color {
        switch toast.kind {
        case .success: .green
        case .error: .red
        case .info: .blue
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(toast.text).font(.kelid(13, .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .glassEffect(.regular, in: .capsule)
        .overlay(Capsule().stroke(tint.opacity(0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }
}

private struct ToastModifier: ViewModifier {
    @Binding var toast: Toast?
    var duration: Double = 1.6

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let toast {
                    ToastCapsule(toast: toast)
                        .padding(.bottom, 28)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task(id: toast.id) {
                            try? await Task.sleep(for: .seconds(duration))
                            withAnimation(.easeInOut(duration: 0.25)) { self.toast = nil }
                        }
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: toast)
    }
}

extension View {
    /// Presents an auto-fading toast anchored to the bottom of this view.
    func toast(_ toast: Binding<Toast?>, duration: Double = 1.6) -> some View {
        modifier(ToastModifier(toast: toast, duration: duration))
    }
}
