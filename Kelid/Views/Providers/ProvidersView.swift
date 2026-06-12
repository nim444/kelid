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

    enum CommsProvider: String, CaseIterable, Identifiable {
        case telegram, resend
        var id: String { rawValue }

        var name: String {
            switch self {
            case .telegram: "Telegram"
            case .resend: "Resend"
            }
        }
    }

    @State private var category: Category = .ai
    @State private var selected: AIProvider = .openRouter
    @State private var selectedComms: CommsProvider = .telegram

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
                List(selection: $selectedComms) {
                    ForEach(CommsProvider.allCases) { provider in
                        Label {
                            Text(provider.name).font(.kelid(13, .medium))
                        } icon: {
                            switch provider {
                            case .telegram:
                                Image("TelegramLogo")
                                    .renderingMode(.template)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 16, height: 16)
                            case .resend:
                                Image(systemName: "envelope")
                            }
                        }
                        .tag(provider)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
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
                    switch selectedComms {
                    case .telegram:
                        TelegramPane()
                            .id(selectedComms)
                    case .resend:
                        ComingSoon(
                            icon: "envelope",
                            title: "Resend",
                            message: "Email alerts through the Resend API — access notices, approvals, and audit summaries. Coming soon."
                        )
                        .frame(maxWidth: .infinity, minHeight: 360)
                    }
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(28)
        }
    }
}
