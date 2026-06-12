import Foundation
import Network
import Observation

/// Kelid's MCP agent gateway — a local Model Context Protocol server over
/// Streamable HTTP (loopback only). Exposes `kelid_list_vaults` and
/// `kelid_get_secret`; every secret request runs through GateService, the
/// same enforced path everywhere. The server never prompts, never unlocks,
/// and never explains a denial beyond the generic message.
@MainActor
@Observable
final class McpStore {
    private enum Keys {
        static let enabled = "mcp_enabled"
        static let port = "mcp_port"
        static let callers = "mcp_callers"
    }

    var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Keys.enabled)
            if enabled { start() } else { stop() }
        }
    }
    var port: Int {
        didSet { UserDefaults.standard.set(port, forKey: Keys.port) }
    }
    private(set) var running = false
    private(set) var lastError: String?
    private(set) var knownCallers: [String]

    private var gate: GateService?
    private var listener: NWListener?

    init() {
        let defaults = UserDefaults.standard
        enabled = defaults.bool(forKey: Keys.enabled) // off until a human flips it
        port = defaults.object(forKey: Keys.port) as? Int ?? 4141
        knownCallers = defaults.stringArray(forKey: Keys.callers) ?? []
    }

    var endpointURL: String { "http://127.0.0.1:\(port)/mcp" }

    func configure(gate: GateService) {
        self.gate = gate
        if enabled { start() }
    }

    func noteCaller(_ caller: String) {
        guard !knownCallers.contains(caller) else { return }
        knownCallers.append(caller)
        UserDefaults.standard.set(knownCallers, forKey: Keys.callers)
    }

    // MARK: - Listener lifecycle

    func start() {
        guard listener == nil, gate != nil else { return }
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            lastError = "invalid port"
            return
        }
        let params = NWParameters.tcp
        // Loopback only — never reachable from the network.
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: nwPort)
        do {
            let listener = try NWListener(using: params)
            listener.newConnectionHandler = { [weak self] connection in
                McpHttp.serve(connection: connection) { body in
                    await self?.handleBody(body)
                }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.running = true
                        self?.lastError = nil
                    case .failed(let error):
                        self?.running = false
                        self?.lastError = error.localizedDescription
                        self?.listener = nil
                    case .cancelled:
                        self?.running = false
                        self?.listener = nil
                    default:
                        break
                    }
                }
            }
            listener.start(queue: .global(qos: .userInitiated))
            self.listener = listener
            AuditLog.shared.record(.agent, "MCP gateway started", detail: endpointURL)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        running = false
        AuditLog.shared.record(.agent, "MCP gateway stopped", outcome: .info)
    }

    func restart() {
        stop()
        if enabled { start() }
    }

    // MARK: - JSON-RPC dispatch

    private static let instructions = """
    Kelid gates access to secrets for AI agents. To retrieve a secret, call kelid_get_secret with: \
    vault (the vault's name — required), name (the secret's name), scope (its category, e.g. "database"), \
    and reason (a concise, truthful justification for needing it now). Optionally pass caller (your agent \
    identity). Low-sensitivity secrets are returned directly; medium/high ones are evaluated by a policy \
    engine and an AI guardian against your stated reason — a vague, mismatched, or fabricated reason is \
    denied with a generic message and no value. High-sensitivity secrets may be human-only. Some secrets \
    are restricted to certain callers or times, or may be temporarily sealed after repeated denials; you \
    get the same generic denial in every such case and only a human can change it, so do not retry in a \
    loop. If Kelid is locked, a human must unlock it; you cannot. Use kelid_list_vaults to discover vault \
    names and lock state. Every request is audited — never invent a reason to pass the gate.
    """

    /// Bridges raw HTTP bodies (Sendable) into JSON-RPC dispatch on the main
    /// actor. Returns nil for notifications (HTTP 202).
    func handleBody(_ body: Data) async -> Data? {
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return try? JSONSerialization.data(withJSONObject: rpcError(nil, code: -32700, message: "parse error"))
        }
        guard let response = await dispatch(json) else { return nil }
        return try? JSONSerialization.data(withJSONObject: response)
    }

    /// Handles one JSON-RPC message. Returns nil for notifications.
    func dispatch(_ request: [String: Any]) async -> [String: Any]? {
        let method = request["method"] as? String ?? ""
        let id = request["id"]

        switch method {
        case "initialize":
            return ok(id, [
                "protocolVersion": "2024-11-05",
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "kelid", "version": "0.1.0"],
                "instructions": Self.instructions,
            ])
        case "notifications/initialized", "notifications/cancelled":
            return nil
        case "ping":
            return ok(id, [String: Any]())
        case "tools/list":
            return ok(id, ["tools": toolSpecs()])
        case "tools/call":
            return await handleToolsCall(id: id, params: request["params"] as? [String: Any])
        default:
            return rpcError(id, code: -32601, message: "method not found: \(method)")
        }
    }

    private func toolSpecs() -> [[String: Any]] {
        [
            [
                "name": "kelid_list_vaults",
                "description": "List Kelid vaults on this machine and whether each is currently unlocked. Returns a JSON array of { name, unlocked, description }.",
                "inputSchema": [
                    "type": "object",
                    "properties": [String: Any](),
                    "additionalProperties": false,
                ],
            ],
            [
                "name": "kelid_get_secret",
                "description": "Request a secret through Kelid's policy + AI-guardian gate. Returns the secret value if allowed, or an error (denied / not found / locked). Medium/high-sensitivity secrets are judged against your `reason`; provide a truthful, specific justification.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "vault": ["type": "string", "description": "The vault's name. Required — use kelid_list_vaults to discover names."],
                        "name": ["type": "string", "description": "The secret's name."],
                        "scope": ["type": "string", "description": "The secret's category, e.g. \"database\" or \"payments\"."],
                        "reason": ["type": "string", "description": "A concise, truthful justification for needing the secret now."],
                        "caller": ["type": "string", "description": "Your agent identity (defaults to \"default\")."],
                    ],
                    "required": ["vault", "name", "scope", "reason"],
                    "additionalProperties": false,
                ],
            ],
        ]
    }

    private func handleToolsCall(id: Any?, params: [String: Any]?) async -> [String: Any] {
        guard let params, let tool = params["name"] as? String else {
            return rpcError(id, code: -32602, message: "missing params")
        }
        let args = params["arguments"] as? [String: Any] ?? [:]

        switch tool {
        case "kelid_list_vaults":
            guard let gate else { return rpcError(id, code: -32603, message: "gateway not ready") }
            let list = gate.listVaults()
            let data = (try? JSONSerialization.data(withJSONObject: list, options: [.prettyPrinted, .sortedKeys])) ?? Data()
            return ok(id, toolText(String(decoding: data, as: UTF8.self), isError: false))

        case "kelid_get_secret":
            // The human's enable switch is honored before any policy work.
            guard enabled, let gate else {
                return ok(id, toolText("request not available", isError: true))
            }
            guard let vault = stringArg(args, "vault"),
                  let name = stringArg(args, "name"),
                  let scope = stringArg(args, "scope"),
                  let reason = stringArg(args, "reason")
            else {
                return ok(id, toolText("missing required argument — vault, name, scope, and reason are all required", isError: true))
            }
            let caller = stringArg(args, "caller") ?? "default"
            noteCaller(caller)

            switch await gate.getSecret(vaultName: vault, name: name, scope: scope, reason: reason, caller: caller) {
            case .granted(let value):
                return ok(id, toolText(value, isError: false))
            case .denied:
                return ok(id, toolText(GateService.genericDeny, isError: true))
            case .notFound(let message), .locked(let message):
                return ok(id, toolText(message, isError: true))
            }

        default:
            return rpcError(id, code: -32602, message: "unknown tool: \(tool)")
        }
    }

    // MARK: - JSON-RPC plumbing

    private func stringArg(_ args: [String: Any], _ key: String) -> String? {
        guard let value = (args[key] as? String)?.trimmingCharacters(in: .whitespaces), !value.isEmpty else {
            return nil
        }
        return value
    }

    private func toolText(_ text: String, isError: Bool) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": isError]
    }

    private func ok(_ id: Any?, _ result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result]
    }

    private func rpcError(_ id: Any?, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }
}

/// Minimal HTTP/1.1 handling for the MCP endpoint: POST /mcp with a JSON-RPC
/// body, plain-JSON response (Streamable HTTP without an event stream).
nonisolated enum McpHttp {
    typealias Handler = @Sendable (Data) async -> Data?

    static func serve(connection: NWConnection, handler: @escaping Handler) {
        connection.start(queue: .global(qos: .userInitiated))
        receive(connection: connection, buffer: Data(), handler: handler)
    }

    private static func receive(connection: NWConnection, buffer: Data, handler: @escaping Handler) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { data, _, isComplete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            if error != nil || (isComplete && buffer.isEmpty) {
                connection.cancel()
                return
            }

            if let request = parseRequest(buffer) {
                Task {
                    let responseData = await respond(to: request, handler: handler)
                    connection.send(content: responseData, completion: .contentProcessed { _ in
                        let leftover = buffer.suffix(from: buffer.startIndex.advanced(by: request.totalLength))
                        receive(connection: connection, buffer: Data(leftover), handler: handler)
                    })
                }
            } else if isComplete {
                connection.cancel()
            } else {
                receive(connection: connection, buffer: buffer, handler: handler)
            }
        }
    }

    private struct HttpRequest {
        var method: String
        var path: String
        var body: Data
        var totalLength: Int
    }

    private static func parseRequest(_ data: Data) -> HttpRequest? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data[data.startIndex..<headerEnd.lowerBound]
        let header = String(decoding: headerData, as: UTF8.self)
        let lines = header.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        var contentLength = 0
        for line in lines.dropFirst() {
            let pair = line.split(separator: ":", maxSplits: 1)
            if pair.count == 2, pair[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                contentLength = Int(pair[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }

        let bodyStart = headerEnd.upperBound
        let available = data.distance(from: bodyStart, to: data.endIndex)
        guard available >= contentLength else { return nil } // wait for more bytes

        let body = data[bodyStart..<data.index(bodyStart, offsetBy: contentLength)]
        let total = data.distance(from: data.startIndex, to: bodyStart) + contentLength
        return HttpRequest(method: String(parts[0]), path: String(parts[1]), body: Data(body), totalLength: total)
    }

    private static func respond(to request: HttpRequest, handler: Handler) async -> Data {
        guard request.path == "/mcp" || request.path == "/" else {
            return httpResponse(status: "404 Not Found", body: Data())
        }
        switch request.method {
        case "POST":
            if let body = await handler(request.body) {
                return httpResponse(status: "200 OK", body: body)
            }
            return httpResponse(status: "202 Accepted", body: Data()) // notification
        case "GET":
            return httpResponse(status: "405 Method Not Allowed", body: Data()) // no event stream
        case "DELETE":
            return httpResponse(status: "200 OK", body: Data()) // stateless: nothing to end
        default:
            return httpResponse(status: "405 Method Not Allowed", body: Data())
        }
    }

    private static func httpResponse(status: String, body: Data) -> Data {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: keep-alive\r\n"
        head += "\r\n"
        return Data(head.utf8) + body
    }
}
