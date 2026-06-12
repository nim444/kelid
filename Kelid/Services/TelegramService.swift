import Foundation

/// Telegram Bot API client for Kelid's alert/audit channel.
///
/// Design (adapted from OpenClaw's channel security model):
/// - **Default-deny**: messages can only be sent to whitelisted chat IDs —
///   enforced here at the service level, not just in the UI.
/// - **Pairing-style discovery**: `discoverChats` long-polls `getUpdates` and
///   returns chats that contacted the bot; nothing is auto-approved.
/// - Long polling only — a desktop app exposes no public webhook endpoint.
/// - The bot token is a secret: Keychain-stored, never logged, ephemeral
///   URLSession so no request ever touches the disk cache.
nonisolated enum TelegramService {
    struct BotInfo: Sendable {
        var id: Int64
        var username: String
        var name: String
    }

    struct Chat: Codable, Identifiable, Hashable, Sendable {
        var id: Int64
        var title: String
        var kind: String // "private", "group", "supergroup", "channel"

        var isGroup: Bool { kind != "private" }
    }

    enum TelegramError: LocalizedError {
        case badToken
        case notWhitelisted
        case api(String)

        var errorDescription: String? {
            switch self {
            case .badToken: "Telegram rejected the bot token."
            case .notWhitelisted: "Refused: that chat is not on the whitelist."
            case .api(let why): "Telegram API error: \(why)"
            }
        }
    }

    private static let session = URLSession(configuration: .ephemeral)

    // MARK: - API calls

    /// Validates the token and returns the bot identity.
    static func getMe(token: String) async throws -> BotInfo {
        let data = try await call(token: token, method: "getMe")
        struct Me: Codable { var id: Int64; var username: String?; var first_name: String }
        let me = try decodeResult(Me.self, from: data)
        return BotInfo(id: me.id, username: me.username ?? "", name: me.first_name)
    }

    /// Polls `getUpdates` and returns the distinct chats that have messaged
    /// the bot. Discovery only — approval stays an explicit user action.
    static func discoverChats(token: String) async throws -> [Chat] {
        let data = try await call(token: token, method: "getUpdates", query: ["timeout": "0", "limit": "100"])
        struct Update: Codable {
            struct Message: Codable {
                struct RawChat: Codable {
                    var id: Int64
                    var type: String
                    var title: String?
                    var username: String?
                    var first_name: String?
                    var last_name: String?
                }
                var chat: RawChat
            }
            var message: Message?
            var my_chat_member: Message?
        }
        let updates = try decodeResult([Update].self, from: data)

        var seen = Set<Int64>()
        var chats: [Chat] = []
        for update in updates {
            guard let raw = update.message?.chat ?? update.my_chat_member?.chat else { continue }
            guard !seen.contains(raw.id) else { continue }
            seen.insert(raw.id)
            let title = raw.title
                ?? [raw.first_name, raw.last_name].compactMap(\.self).joined(separator: " ").nilIfEmpty
                ?? raw.username.map { "@\($0)" }
                ?? String(raw.id)
            chats.append(Chat(id: raw.id, title: title, kind: raw.type))
        }
        return chats
    }

    /// Sends a message — only to a whitelisted chat. The whitelist check is
    /// here on purpose: no caller can bypass it.
    static func send(token: String, text: String, to chatID: Int64, whitelist: [Chat]) async throws {
        guard whitelist.contains(where: { $0.id == chatID }) else {
            throw TelegramError.notWhitelisted
        }
        _ = try await call(token: token, method: "sendMessage", query: [
            "chat_id": String(chatID),
            "text": text,
        ])
    }

    // MARK: - Plumbing

    private static func call(token: String, method: String, query: [String: String] = [:]) async throws -> Data {
        var components = URLComponents(string: "https://api.telegram.org/bot\(token)/\(method)")!
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            throw TelegramError.badToken
        }
        return data
    }

    private struct Envelope<R: Codable>: Codable {
        var ok: Bool
        var result: R?
        var description: String?
    }

    private static func decodeResult<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        let envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
        guard envelope.ok, let result = envelope.result else {
            let why = envelope.description ?? "unknown error"
            if why.lowercased().contains("unauthorized") { throw TelegramError.badToken }
            throw TelegramError.api(why)
        }
        return result
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
