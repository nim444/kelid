import SwiftUI

/// Shared building blocks for Settings panes: a title header and a glass card.
struct PaneHeader: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(LinearGradient.kelidAccent)
                Text(title)
                    .font(.kelid(22, .bold))
            }
            Text(subtitle)
                .font(.kelid(13, .regular))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PaneCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

/// Inline status line — green check on success, red warning on error.
struct PaneStatus: View {
    enum Kind { case success, error, info }
    let kind: Kind
    let message: String

    private var icon: String {
        switch kind {
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }

    private var color: Color {
        switch kind {
        case .success: .green
        case .error: .red
        case .info: .secondary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            Text(message)
                .font(.kelid(12, .regular))
                .foregroundStyle(kind == .info ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
