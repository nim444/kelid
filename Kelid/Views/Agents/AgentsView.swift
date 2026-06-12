import AppKit
import SwiftUI

/// Agents pane: the MCP gateway controls and the live feed of agent
/// requests. Agents connect over Streamable HTTP on loopback; the gate
/// (policy + guardian) rules every request.
struct AgentsView: View {
    @Environment(McpStore.self) private var mcp

    @State private var portText = ""
    @State private var copied = false
    @State private var toast: Toast?

    private var agentEvents: [AuditEvent] {
        AuditLog.shared.events.filter { $0.category == .agent }.suffix(30).reversed()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                gatewayCard
                setupCard
                requestsCard
            }
            .padding(24)
        }
        .toast($toast)
        .onAppear { portText = String(mcp.port) }
    }

    // MARK: - Gateway

    private var gatewayCard: some View {
        @Bindable var mcp = mcp
        return PaneCard {
            HStack(spacing: 14) {
                Image(systemName: mcp.running ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(mcp.running ? AnyShapeStyle(LinearGradient.kelidAccent) : AnyShapeStyle(.secondary))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("MCP Gateway")
                            .font(.kelid(16, .bold))
                        Circle()
                            .fill(mcp.running ? .green : .secondary.opacity(0.4))
                            .frame(width: 8, height: 8)
                        Text(mcp.running ? "running" : "stopped")
                            .font(.kelid(11, .medium))
                            .foregroundStyle(.secondary)
                    }
                    Text(statusDetail)
                        .font(.kelid(12, .regular))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Toggle("", isOn: $mcp.enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            if let error = mcp.lastError {
                PaneStatus(kind: .error, message: error)
            }

            Divider().opacity(0.3)

            HStack(spacing: 10) {
                Text("Port")
                    .font(.kelid(12, .medium))
                    .foregroundStyle(.secondary)
                TextField("4141", text: $portText)
                    .textFieldStyle(.roundedBorder)
                    .font(.kelid(13, .regular))
                    .frame(width: 90)
                Button("Apply") {
                    applyPort()
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .disabled(Int(portText) == nil || Int(portText) == mcp.port)

                Spacer()

                Text("Loopback only — never reachable from the network. The app must be running.")
                    .font(.kelid(10, .regular))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var statusDetail: String {
        if !mcp.enabled {
            return "Off. Agents get \u{201C}request not available\u{201D} — indistinguishable from a denial."
        }
        if mcp.running {
            return "Serving kelid_list_vaults and kelid_get_secret at \(mcp.endpointURL). Every request runs the full gate."
        }
        return "Enabled but not listening — check the port."
    }

    // MARK: - Setup

    private var snippet: String {
        "claude mcp add --transport http kelid \(mcp.endpointURL)"
    }

    private var setupCard: some View {
        PaneCard {
            Text("Connect an agent")
                .font(.kelid(13, .semibold))
            Text("Register Kelid as an MCP server in Claude Code (or any MCP-aware agent):")
                .font(.kelid(12, .regular))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(snippet)
                    .font(.kelid(12, .medium))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 9))
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(snippet, forType: .string)
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .frame(width: 18)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }

            Text("Agents can only ask: which vault, which secret, what scope, and why. Kelid is locked? They wait for you. Denied? They get one generic message — the real reason stays in your audit log.")
                .font(.kelid(11, .regular))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if !mcp.knownCallers.isEmpty {
                Divider().opacity(0.3)
                Text("Callers seen")
                    .font(.kelid(12, .medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    ForEach(mcp.knownCallers, id: \.self) { caller in
                        Text(caller)
                            .font(.kelid(11, .semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .glassEffect(.regular, in: .capsule)
                    }
                }
            }
        }
    }

    // MARK: - Requests feed

    private var requestsCard: some View {
        PaneCard {
            Text("Recent agent requests")
                .font(.kelid(13, .semibold))

            if agentEvents.isEmpty {
                PaneStatus(kind: .info, message: "No agent requests yet. Connect an agent and ask it to fetch a secret — every request lands here and in the Audit chain.")
            } else {
                ForEach(agentEvents) { event in
                    HStack(spacing: 10) {
                        Image(systemName: icon(for: event))
                            .font(.system(size: 12))
                            .foregroundStyle(color(for: event))
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event.action).font(.kelid(12, .medium))
                            if !event.detail.isEmpty {
                                Text(event.detail)
                                    .font(.kelid(11, .regular))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(event.at.formatted(.relative(presentation: .named)))
                            .font(.kelid(10, .regular))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func icon(for event: AuditEvent) -> String {
        switch event.outcome {
        case .success: "checkmark.circle.fill"
        case .denied: "xmark.octagon.fill"
        case .failure: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }

    private func color(for event: AuditEvent) -> Color {
        switch event.outcome {
        case .success: .green
        case .denied: .orange
        case .failure: .red
        case .info: .secondary
        }
    }

    // MARK: - Actions

    private func applyPort() {
        guard let newPort = Int(portText), (1024...65535).contains(newPort) else {
            toast = .error("Port must be between 1024 and 65535")
            return
        }
        mcp.port = newPort
        mcp.restart()
        toast = .success("Gateway moved to port \(newPort)")
    }
}
