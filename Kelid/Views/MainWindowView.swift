import SwiftUI

/// Top-level shell after onboarding: a native, collapsible sidebar
/// (NavigationSplitView) with an always-visible toggle so it can be brought
/// back after collapsing. Each section renders its own detail pane.
struct MainWindowView: View {
    @Environment(AppStore.self) private var store

    @State private var selection: MainSection = .dashboard
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 600)
        .background(WindowConfigurator(hideSystemButtons: false))
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                ForEach(MainSection.primary) { section in
                    sidebarRow(section)
                }
            }
            Section("System") {
                ForEach(MainSection.system) { section in
                    sidebarRow(section)
                }
            }
        }
        .listStyle(.sidebar)
        // Clear the traffic-light area without a brand label.
        .safeAreaInset(edge: .top) {
            Color.clear.frame(height: 18)
        }
    }

    private func sidebarRow(_ section: MainSection) -> some View {
        Label {
            Text(section.title).font(.kelid(13, .medium))
        } icon: {
            Image(systemName: section.icon)
        }
        .tag(section)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        ZStack(alignment: .top) {
            paneBackground

            VStack(spacing: 0) {
                paneToolbar
                Group {
                    switch selection {
                    case .dashboard: DashboardPane()
                    case .guardian: GuardianView()
                    case .audit: AuditView()
                    case .providers: ProvidersView()
                    case .settings: SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var paneBackground: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            LinearGradient.kelidAccent.opacity(0.05)
        }
        .ignoresSafeArea()
    }

    private var paneToolbar: some View {
        HStack(spacing: 12) {
            Text(selection.title)
                .font(.kelid(15, .semibold))

            Spacer()

            statusChips
        }
        // Leave room for the native sidebar toggle + traffic lights when collapsed.
        .padding(.leading, columnVisibility == .detailOnly ? 96 : 18)
        .padding(.trailing, 18)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var statusChips: some View {
        HStack(spacing: 6) {
            if store.touchIDEnrolled {
                chip("Touch ID", "touchid")
            }
            if YubiKeyService.isEnrolled {
                chip("YubiKey", "key.radiowaves.forward")
            }
            Button {
                store.lockNow()
            } label: {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular, in: .capsule)
            .keyboardShortcut("l", modifiers: .command)
            .help("Lock now (Cmd+L)")
        }
    }

    private func chip(_ title: String, _ icon: String) -> some View {
        Label {
            Text(title).font(.kelid(11, .medium))
        } icon: {
            Image(systemName: icon)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassEffect(.regular, in: .capsule)
    }
}

// MARK: - Sections

enum MainSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard, guardian, audit, providers, settings

    var id: String { rawValue }

    // Vaults / Agents stay hidden until their engines ship.
    static let primary: [MainSection] = [.dashboard, .guardian, .audit]
    static let system: [MainSection] = [.providers, .settings]

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .guardian: "Guardian"
        case .audit: "Audit"
        case .providers: "Providers"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .guardian: "checkmark.shield"
        case .audit: "list.bullet.rectangle"
        case .providers: "cpu"
        case .settings: "gearshape"
        }
    }
}
