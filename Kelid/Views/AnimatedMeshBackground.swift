import SwiftUI

/// A slow, smoothly drifting mesh gradient in the brand accent range. Sits
/// behind onboarding content to give the dark window subtle motion.
struct AnimatedMeshBackground: View {
    private let base = Color(red: 0.04, green: 0.06, blue: 0.09)
    private let accent = Color(red: 0.078, green: 0.612, blue: 0.922)
    private let deep = Color(red: 0.05, green: 0.10, blue: 0.20)
    private let teal = Color(red: 0.0, green: 0.42, blue: 0.45)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let p = drift(t)

            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    .init(0, 0), .init(0.5, 0), .init(1, 0),
                    [Float(0.0), Float(p.row1)],
                    [Float(p.center), Float(p.center2)],
                    [Float(1.0), Float(p.row1b)],
                    .init(0, 1), .init(0.5, 1), .init(1, 1),
                ],
                colors: [
                    base, deep, base,
                    deep, accent.opacity(0.55), teal.opacity(0.5),
                    base, deep, base,
                ],
                smoothsColors: true
            )
            .ignoresSafeArea()
        }
        .background(base)
        .overlay(.ultraThinMaterial.opacity(0.25))
        .ignoresSafeArea()
    }

    private func drift(_ t: TimeInterval) -> (row1: Double, row1b: Double, center: Double, center2: Double) {
        (
            row1: 0.5 + 0.16 * sin(t * 0.23),
            row1b: 0.5 + 0.16 * cos(t * 0.19),
            center: 0.5 + 0.12 * sin(t * 0.17 + 1.0),
            center2: 0.5 + 0.14 * cos(t * 0.21 + 0.5)
        )
    }
}
