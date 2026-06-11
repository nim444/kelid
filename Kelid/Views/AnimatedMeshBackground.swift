import SwiftUI

/// A slow, smoothly drifting mesh gradient. Mostly neutral — near-black in dark
/// mode, near-white in light mode — with a single contained blue glow that
/// drifts, so it reads as a calm dark/light field with just a hint of accent.
struct AnimatedMeshBackground: View {
    @Environment(\.colorScheme) private var scheme

    private var neutral: Color {
        scheme == .dark
            ? Color(red: 0.03, green: 0.03, blue: 0.04)
            : Color(red: 0.96, green: 0.97, blue: 0.98)
    }

    private var neutralSoft: Color {
        scheme == .dark
            ? Color(red: 0.05, green: 0.05, blue: 0.07)
            : Color(red: 0.93, green: 0.94, blue: 0.96)
    }

    /// The one blue accent cell — kept low so most of the field stays neutral.
    private var glow: Color {
        scheme == .dark
            ? Color(red: 0.09, green: 0.22, blue: 0.40)
            : Color(red: 0.78, green: 0.86, blue: 0.97)
    }

    private var glowSoft: Color {
        scheme == .dark
            ? Color(red: 0.05, green: 0.10, blue: 0.18)
            : Color(red: 0.88, green: 0.92, blue: 0.98)
    }

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
                    neutral, neutral, neutral,
                    neutralSoft, glow, neutralSoft,
                    neutral, glowSoft, neutral,
                ],
                smoothsColors: true
            )
            .ignoresSafeArea()
        }
        .background(neutral)
        .ignoresSafeArea()
    }

    private func drift(_ t: TimeInterval) -> (row1: Double, row1b: Double, center: Double, center2: Double) {
        (
            row1: 0.5 + 0.16 * sin(t * 0.23),
            row1b: 0.5 + 0.16 * cos(t * 0.19),
            center: 0.5 + 0.14 * sin(t * 0.17 + 1.0),
            center2: 0.62 + 0.14 * cos(t * 0.21 + 0.5)
        )
    }
}
