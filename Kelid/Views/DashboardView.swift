import SwiftUI

/// Dashboard detail pane — stat cards and empty states. The window chrome and
/// sidebar are provided by MainWindowView.
struct DashboardPane: View {
    @Environment(VaultsStore.self) private var vaults
    @Environment(SecretsStore.self) private var secrets
    @Environment(McpStore.self) private var mcp

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                LazyVGrid(columns: columns, spacing: 16) {
                    statCard(
                        icon: "shippingbox",
                        title: "Vaults",
                        value: "\(vaults.vaults.count)",
                        hint: vaults.vaults.isEmpty ? "Create your first vault" : "Encrypted store arrives with the crypto core"
                    )
                    statCard(
                        icon: "key.horizontal",
                        title: "Secrets",
                        value: "\(secrets.totalCount)",
                        hint: secrets.totalCount == 0 ? "Secrets live inside vaults" : "Keychain-held until the crypto core"
                    )
                    statCard(
                        icon: "antenna.radiowaves.left.and.right",
                        title: "Agents",
                        value: "\(mcp.knownCallers.count)",
                        hint: mcp.running ? "Gateway live at 127.0.0.1:\(mcp.port)" : "Enable the MCP gateway in Agents"
                    )
                    statCard(
                        icon: "list.bullet.rectangle",
                        title: "Audit Events",
                        value: "\(AuditLog.shared.events.count)",
                        hint: "Every action is recorded"
                    )
                }

                Text("Milestone 1 — onboarding scaffold. The vault engine is next.")
                    .font(.kelid(11, .regular))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
            .padding(24)
        }
    }

    private func statCard(icon: String, title: String, value: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(LinearGradient.kelidAccent)
                Text(title)
                    .font(.kelid(15, .semibold))
                Spacer()
            }
            Text(value)
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text(hint)
                .font(.kelid(12, .regular))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}

/// Generic empty state for sections whose engine has not shipped yet.
struct ComingSoon: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(LinearGradient.kelidAccent)
            Text(title)
                .font(.kelid(22, .bold))
            Text(message)
                .font(.kelid(13, .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Text("Coming soon")
                .font(.kelid(11, .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .glassEffect(.regular, in: .capsule)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
