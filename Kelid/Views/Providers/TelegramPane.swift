import SwiftUI

struct TelegramPane: View {
    @Environment(TelegramStore.self) private var store

    @State private var tokenField = ""
    @State private var revealToken = false
    @State private var testing = false
    @State private var finding = false
    @State private var sendingTo: Int64?
    @State private var manualID = ""
    @State private var manualLabel = ""
    @State private var toast: Toast?

    private var trimmedToken: String { tokenField.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image("TelegramLogo")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .foregroundStyle(LinearGradient.kelidAccent)
                    Text("Telegram")
                        .font(.kelid(22, .bold))
                }
                Text("Audit alerts and approvals through a bot you control. Kelid only ever messages whitelisted chats — everything else is refused.")
                    .font(.kelid(13, .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            tokenCard
            whitelistCard
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .toast($toast)
    }

    // MARK: - Bot token

    private var tokenCard: some View {
        PaneCard {
            HStack(spacing: 7) {
                Circle()
                    .fill(store.isConfigured ? .green : .secondary.opacity(0.4))
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.kelid(12, .medium))
                    .foregroundStyle(.secondary)
            }

            Text("Bot token")
                .font(.kelid(12, .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Group {
                    if revealToken {
                        TextField(tokenPrompt, text: $tokenField)
                    } else {
                        SecureField(tokenPrompt, text: $tokenField)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.kelid(13, .regular))

                Button {
                    toggleReveal()
                } label: {
                    Image(systemName: revealToken ? "eye.slash" : "eye")
                        .frame(width: 18)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .help(revealToken ? "Hide" : "Reveal stored token (requires Touch ID)")
            }

            Text("From @BotFather. Stored in the macOS Keychain — never written to disk in plaintext. Revealing requires Touch ID or your Mac password.")
                .font(.kelid(11, .regular))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    store.setToken(trimmedToken)
                    tokenField = ""
                    revealToken = false
                    AuditLog.shared.record(.telegram, "Bot token saved")
                    toast = .success("Bot token saved")
                } label: {
                    Text(store.hasToken ? "Update Token" : "Save Token").font(.kelid(13, .semibold))
                }
                .buttonStyle(.glassProminent)
                .disabled(trimmedToken.isEmpty)

                Button {
                    runTest()
                } label: {
                    HStack(spacing: 6) {
                        if testing { ProgressView().controlSize(.small) }
                        Text(testing ? "Testing\u{2026}" : "Test").font(.kelid(13, .semibold))
                    }
                }
                .buttonStyle(.glass)
                .disabled(testing || (trimmedToken.isEmpty && !store.hasToken))

                if store.hasToken {
                    Button(role: .destructive) {
                        store.removeToken()
                        tokenField = ""
                        AuditLog.shared.record(.telegram, "Bot token removed", outcome: .info)
                        toast = .info("Bot token removed")
                    } label: {
                        Text("Remove").font(.kelid(13, .semibold))
                    }
                    .buttonStyle(.glass)
                }
            }
            .controlSize(.large)
            .buttonBorderShape(.capsule)
        }
    }

    private var statusText: String {
        if store.isConfigured { return "Configured" }
        if store.hasToken { return "Token saved — whitelist at least one chat" }
        return "Not configured"
    }

    private var tokenPrompt: String {
        if tokenField.isEmpty && store.hasToken {
            return "Saved — type to replace, or reveal"
        }
        return "123456789:ABC\u{2026}"
    }

    // MARK: - Whitelist

    private var whitelistCard: some View {
        PaneCard {
            Text("Whitelisted chats")
                .font(.kelid(12, .medium))
                .foregroundStyle(.secondary)

            if store.whitelist.isEmpty {
                PaneStatus(kind: .info, message: "No chats approved yet. Kelid refuses to message anyone until you whitelist a person or group.")
            } else {
                ForEach(store.whitelist) { chat in
                    chatRow(chat)
                }
            }

            Divider().opacity(0.4)

            // Pairing-style discovery: message the bot, then approve here.
            Text("Find chats")
                .font(.kelid(12, .medium))
                .foregroundStyle(.secondary)
            Text("Send any message to your bot in Telegram (or add it to a group), then look for it here. Nothing is approved automatically.")
                .font(.kelid(11, .regular))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                findChats()
            } label: {
                HStack(spacing: 6) {
                    if finding { ProgressView().controlSize(.small) }
                    Label(finding ? "Looking\u{2026}" : "Find New Chats", systemImage: "magnifyingglass")
                        .font(.kelid(13, .semibold))
                }
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .disabled(finding || !store.hasToken)

            ForEach(store.pending) { chat in
                pendingRow(chat)
            }

            Divider().opacity(0.4)

            Text("Or add a chat ID manually")
                .font(.kelid(12, .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("Chat ID (negative for groups)", text: $manualID)
                    .textFieldStyle(.roundedBorder)
                    .font(.kelid(13, .regular))
                    .frame(maxWidth: 220)
                TextField("Label (optional)", text: $manualLabel)
                    .textFieldStyle(.roundedBorder)
                    .font(.kelid(13, .regular))
                Button {
                    addManual()
                } label: {
                    Text("Add").font(.kelid(13, .semibold))
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .buttonBorderShape(.capsule)
                .disabled(Int64(manualID.trimmingCharacters(in: .whitespaces)) == nil)
            }
        }
    }

    private func chatRow(_ chat: TelegramService.Chat) -> some View {
        HStack(spacing: 10) {
            Image(systemName: chat.isGroup ? "person.3" : "person")
                .font(.system(size: 13))
                .foregroundStyle(LinearGradient.kelidAccent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(chat.title).font(.kelid(13, .medium))
                Text(String(chat.id)).font(.kelid(11, .regular)).foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                sendTest(to: chat)
            } label: {
                if sendingTo == chat.id {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "paperplane")
                        .font(.system(size: 12))
                }
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .help("Send a test message")
            .disabled(sendingTo != nil)

            Button(role: .destructive) {
                store.remove(chat)
                AuditLog.shared.record(.telegram, "Chat removed from whitelist", detail: "\(chat.title) (\(chat.id))", outcome: .info)
                toast = .info("\(chat.title) removed from whitelist")
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .help("Remove from whitelist")
        }
        .padding(.vertical, 2)
    }

    private func pendingRow(_ chat: TelegramService.Chat) -> some View {
        HStack(spacing: 10) {
            Image(systemName: chat.isGroup ? "person.3" : "person")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(chat.title).font(.kelid(13, .medium))
                Text("\(chat.id) \u{2022} pending").font(.kelid(11, .regular)).foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                store.approve(chat)
                AuditLog.shared.record(.telegram, "Chat whitelisted", detail: "\(chat.title) (\(chat.id))")
                toast = .success("\(chat.title) whitelisted")
            } label: {
                Text("Approve").font(.kelid(12, .semibold))
            }
            .buttonStyle(.glassProminent)
            .controlSize(.small)
            .buttonBorderShape(.capsule)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Actions

    private func toggleReveal() {
        if revealToken {
            revealToken = false
            if tokenField == store.token { tokenField = "" }
            return
        }
        if tokenField.isEmpty, store.hasToken {
            Task {
                let ok = await TouchIDService.requireUserPresence(reason: "reveal the Telegram bot token")
                if ok {
                    tokenField = store.token ?? ""
                    revealToken = true
                    AuditLog.shared.record(.telegram, "Bot token revealed", outcome: .info)
                } else {
                    AuditLog.shared.record(.telegram, "Bot token reveal denied", outcome: .denied)
                    toast = .error("Authentication required to reveal the token")
                }
            }
        } else {
            revealToken = true
        }
    }

    private func activeToken() -> String? {
        if !trimmedToken.isEmpty { return trimmedToken }
        return store.token
    }

    private func runTest() {
        guard let token = activeToken() else { return }
        testing = true
        Task {
            do {
                let bot = try await TelegramService.getMe(token: token)
                AuditLog.shared.record(.telegram, "Bot verified", detail: "@\(bot.username)")
                toast = .success("Connected as @\(bot.username)")
            } catch {
                AuditLog.shared.record(.telegram, "Bot verification failed", detail: error.localizedDescription, outcome: .failure)
                toast = .error(error.localizedDescription)
            }
            testing = false
        }
    }

    private func findChats() {
        guard let token = activeToken() else { return }
        finding = true
        Task {
            do {
                try await store.refreshPending(token: token)
                if store.pending.isEmpty {
                    toast = .info("No new chats — message the bot first, then retry")
                }
            } catch {
                toast = .error(error.localizedDescription)
            }
            finding = false
        }
    }

    private func addManual() {
        guard let id = Int64(manualID.trimmingCharacters(in: .whitespaces)) else { return }
        store.addManual(id: id, label: manualLabel)
        AuditLog.shared.record(.telegram, "Chat whitelisted", detail: "manual entry (\(id))")
        manualID = ""
        manualLabel = ""
        toast = .success("Chat whitelisted")
    }

    private func sendTest(to chat: TelegramService.Chat) {
        guard let token = activeToken() else { return }
        sendingTo = chat.id
        Task {
            do {
                try await TelegramService.send(
                    token: token,
                    text: "Kelid test message — your alert channel works.",
                    to: chat.id,
                    whitelist: store.whitelist
                )
                AuditLog.shared.record(.telegram, "Test message sent", detail: chat.title)
                toast = .success("Test message sent to \(chat.title)")
            } catch {
                AuditLog.shared.record(.telegram, "Message send failed", detail: "\(chat.title): \(error.localizedDescription)", outcome: .failure)
                toast = .error(error.localizedDescription)
            }
            sendingTo = nil
        }
    }
}
