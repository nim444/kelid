import SwiftUI

extension LinearGradient {
    /// Brand gradient: accent blue into teal.
    static let kelidAccent = LinearGradient(
        colors: [
            Color(red: 0.078, green: 0.612, blue: 0.922),
            Color(red: 0.0, green: 0.69, blue: 0.6),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// Frosted window background with a soft brand gradient wash.
struct KelidWindowBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.containerBackground(for: .window) {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient.kelidAccent.opacity(0.07)
            }
            .ignoresSafeArea()
        }
    }
}

extension View {
    func kelidWindowBackground() -> some View {
        modifier(KelidWindowBackground())
    }
}

/// Configures the hosting NSWindow: hidden title bar, drag-anywhere moving,
/// optional hiding of the system traffic-light buttons.
struct WindowConfigurator: NSViewRepresentable {
    var hideSystemButtons = false

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(nsView.window)
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        for buttonType in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(buttonType)?.isHidden = hideSystemButtons
        }
    }
}
