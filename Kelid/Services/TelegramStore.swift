import Foundation
import Observation

/// State for the Telegram alert channel. The bot token lives in the Keychain;
/// the whitelist (chat IDs + display names — not secrets) persists in
/// UserDefaults. Discovered-but-unapproved chats stay in memory only.
@Observable
final class TelegramStore {
    private static let tokenAccount = "comms.telegram.bot_token"
    private static let whitelistKey = "telegram_whitelist"

    /// Approved chats — the only destinations Kelid will ever message.
    private(set) var whitelist: [TelegramService.Chat]

    /// Chats discovered via getUpdates, awaiting explicit approval.
    var pending: [TelegramService.Chat] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.whitelistKey),
           let decoded = try? JSONDecoder().decode([TelegramService.Chat].self, from: data) {
            whitelist = decoded
        } else {
            whitelist = []
        }
    }

    // MARK: - Token (Keychain)

    var hasToken: Bool { KeychainStore.has(account: Self.tokenAccount) }

    var token: String? { KeychainStore.get(account: Self.tokenAccount) }

    func setToken(_ token: String) {
        KeychainStore.set(token, account: Self.tokenAccount)
    }

    func removeToken() {
        KeychainStore.delete(account: Self.tokenAccount)
        pending = []
    }

    var isConfigured: Bool { hasToken && !whitelist.isEmpty }

    // MARK: - Whitelist

    func approve(_ chat: TelegramService.Chat) {
        guard !whitelist.contains(where: { $0.id == chat.id }) else { return }
        whitelist.append(chat)
        pending.removeAll { $0.id == chat.id }
        persist()
    }

    func addManual(id: Int64, label: String) {
        let title = label.trimmingCharacters(in: .whitespaces)
        let chat = TelegramService.Chat(
            id: id,
            title: title.isEmpty ? String(id) : title,
            kind: id < 0 ? "group" : "private"
        )
        approve(chat)
    }

    func remove(_ chat: TelegramService.Chat) {
        whitelist.removeAll { $0.id == chat.id }
        persist()
    }

    /// Refreshes the pending list from getUpdates, excluding already-approved chats.
    func refreshPending(token: String) async throws {
        let discovered = try await TelegramService.discoverChats(token: token)
        let known = Set(whitelist.map(\.id))
        pending = discovered.filter { !known.contains($0.id) }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(whitelist) {
            UserDefaults.standard.set(data, forKey: Self.whitelistKey)
        }
    }
}
