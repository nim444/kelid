import SwiftUI

/// Settings detail: a searchable two-pane layout — items on the left, the
/// selected pane on the right. Self-contained so it can sit inside the main
/// NavigationSplitView detail without nesting another split view.
struct SettingsView: View {
    @State private var selection: SettingsItem = .passphrase
    @State private var query = ""

    private var filtered: [SettingsItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return SettingsItem.allCases }
        return SettingsItem.allCases.filter { $0.matches(q) }
    }

    var body: some View {
        HStack(spacing: 0) {
            itemList
                .frame(width: 240)
            Divider()
            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Searchable item list

    private var itemList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                TextField("Search settings", text: $query)
                    .textFieldStyle(.plain)
                    .font(.kelid(13, .regular))
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 10)

            if filtered.isEmpty {
                Spacer()
                Text("No settings match \u{201C}\(query)\u{201D}")
                    .font(.kelid(12, .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                Spacer()
            } else {
                List(selection: $selection) {
                    ForEach(filtered) { item in
                        Label {
                            Text(item.title).font(.kelid(13, .medium))
                        } icon: {
                            Image(systemName: item.icon)
                        }
                        .tag(item)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch selection {
                case .passphrase: ChangePassphrasePane()
                case .recovery: RecoveryCodePane()
                case .touchID: TouchIDPane()
                case .yubiKey: YubiKeyPane()
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(28)
        }
    }
}

// MARK: - Items

enum SettingsItem: String, CaseIterable, Identifiable, Hashable {
    case passphrase, recovery, touchID, yubiKey

    var id: String { rawValue }

    var title: String {
        switch self {
        case .passphrase: "Change Passphrase"
        case .recovery: "Recovery Code"
        case .touchID: "Touch ID"
        case .yubiKey: "YubiKey"
        }
    }

    var icon: String {
        switch self {
        case .passphrase: "lock.rotation"
        case .recovery: "key.viewfinder"
        case .touchID: "touchid"
        case .yubiKey: "key.radiowaves.forward"
        }
    }

    private var keywords: [String] {
        switch self {
        case .passphrase: ["password", "master", "change", "passphrase", "security"]
        case .recovery: ["recovery", "code", "backup", "reset", "reveal"]
        case .touchID: ["touch", "biometric", "fingerprint", "face"]
        case .yubiKey: ["yubikey", "hardware", "fido", "security key", "usb"]
        }
    }

    func matches(_ query: String) -> Bool {
        if title.lowercased().contains(query) { return true }
        return keywords.contains { $0.contains(query) }
    }
}
