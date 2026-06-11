import SwiftUI

/// Providers detail: a category switch (AI Providers / Communications) over a
/// two-pane layout. AI Providers is functional now; Communications is a
/// placeholder for outbound notification channels (Telegram, Resend, etc).
struct ProvidersView: View {
    enum Category: String, CaseIterable, Identifiable {
        case ai = "AI Providers"
        case comms = "Communications"
        var id: String { rawValue }
    }

    @State private var category: Category = .ai
    @State private var selected: AIProvider = .openRouter

    var body: some View {
        HStack(spacing: 0) {
            leftColumn
                .frame(width: 240)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var leftColumn: some View {
        VStack(spacing: 0) {
            Picker("", selection: $category) {
                ForEach(Category.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 10)

            switch category {
            case .ai:
                List(selection: $selected) {
                    ForEach(AIProvider.allCases) { provider in
                        Label {
                            Text(provider.name).font(.kelid(13, .medium))
                        } icon: {
                            ProviderLogo(provider: provider, size: 16)
                        }
                        .tag(provider)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            case .comms:
                Spacer()
                Text("Channels appear here")
                    .font(.kelid(12, .regular))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch category {
                case .ai:
                    AIProviderPane(provider: selected)
                        .id(selected)
                case .comms:
                    ComingSoon(
                        icon: "paperplane",
                        title: "Communications",
                        message: "Connect outbound channels like Telegram or Resend to send Kelid notifications — access alerts, approvals, and audit summaries. Coming soon."
                    )
                    .frame(maxWidth: .infinity, minHeight: 360)
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(28)
        }
    }
}
