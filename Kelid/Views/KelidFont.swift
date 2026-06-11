import CoreText
import SwiftUI

/// IBM Plex Mono, bundled and registered at launch. Kelid's type identity —
/// a monospaced technical face for a security tool.
enum KelidFont {
    enum Weight: String, CaseIterable {
        case regular = "IBMPlexMono-Regular"
        case medium = "IBMPlexMono-Medium"
        case semibold = "IBMPlexMono-SemiBold"
        case bold = "IBMPlexMono-Bold"

        var swiftUIWeight: Font.Weight {
            switch self {
            case .regular: .regular
            case .medium: .medium
            case .semibold: .semibold
            case .bold: .bold
            }
        }
    }

    /// PostScript family name once registered.
    static let family = "IBM Plex Mono"

    private static var didRegister = false

    /// Registers every bundled weight with CoreText. Idempotent; call once at launch.
    static func registerIfNeeded() {
        guard !didRegister else { return }
        didRegister = true
        for weight in Weight.allCases {
            guard let url = Bundle.main.url(forResource: weight.rawValue, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    static func font(size: CGFloat, weight: Weight = .regular) -> Font {
        .custom(family, size: size).weight(weight.swiftUIWeight)
    }
}

extension Font {
    /// IBM Plex Mono at an explicit point size.
    static func kelid(_ size: CGFloat, _ weight: KelidFont.Weight = .regular) -> Font {
        KelidFont.font(size: size, weight: weight)
    }

    /// IBM Plex Mono mapped onto a Dynamic Type text style (scales with the
    /// system size while keeping the bundled face).
    static func kelid(relativeTo style: Font.TextStyle, size: CGFloat, weight: KelidFont.Weight = .regular) -> Font {
        .custom(KelidFont.family, size: size, relativeTo: style).weight(weight.swiftUIWeight)
    }
}
