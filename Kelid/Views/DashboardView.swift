import SwiftUI

/// Main panel after onboarding. Milestone-1: layout and empty states only —
/// the vault engine, agents, and audit log arrive in the next milestones.
struct DashboardView: View {
    @Environment(AppStore.self) private var store

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        VStack(spacing: 18) {
            header

            LazyVGrid(columns: columns, spacing: 16) {
                statCard(
                    icon: "shippingbox",
                    title: "Vaults",
                    value: "0",
                    hint: "Create your first vault — next milestone"
                )
                statCard(
                    icon: "key.horizontal",
                    title: "Secrets",
                    value: "0",
                    hint: "Secrets live inside vaults"
                )
                statCard(
                    icon: "cpu",
                    title: "Agents",
                    value: "0",
                    hint: "Agents connect over MCP"
                )
                statCard(
                    icon: "list.bullet.rectangle",
                    title: "Audit Events",
                    value: "0",
                    hint: "Every request is recorded"
                )
            }

            Spacer()

            Text("Milestone 1 — onboarding scaffold. The vault engine is next.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)
        }
        .padding(20)
        .padding(.top, 6)
        .frame(minWidth: 760, maxWidth: .infinity, minHeight: 560, maxHeight: .infinity)
        .kelidWindowBackground()
        .background(WindowConfigurator(hideSystemButtons: false))
    }

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(LinearGradient.kelidAccent)
                Text("Kelid")
                    .font(.headline)
                HStack(spacing: 5) {
                    Circle().fill(.green).frame(width: 7, height: 7)
                    Text("Set up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)

            Spacer()

            HStack(spacing: 6) {
                if store.touchIDEnrolled {
                    Label("Touch ID", systemImage: "touchid")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Touch ID unlock is enabled")
                }
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .help("Settings arrive with the vault engine")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
        }
        .padding(.leading, 66) // keep clear of the traffic lights
    }

    private func statCard(icon: String, title: String, value: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(LinearGradient.kelidAccent)
                Text(title)
                    .font(.headline)
                Spacer()
            }
            Text(value)
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}
