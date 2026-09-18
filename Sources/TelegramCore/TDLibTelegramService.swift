#if canImport(TDLibFramework)
import Foundation
import UIKit

/// Настоящий Telegram-клиент на официальном TDLib.
///
/// Принципиально: Casper не имеет доступа ни к каким внутренним серверным
/// возможностям Telegram. Всё, что делает этот класс — отправляет обычные
/// запросы TDLib, ровно те же, что доступны любому стороннему клиенту.
final class TDLibTelegramService: TelegramService {
    var onEvent: ((TelegramEvent) -> Void)?
    var isDemo: Bool { false }

    private let client = TDLibJSONClient()
    private var chatCache: [Int64: ChatSummary] = [:]
    private var userNames: [Int64: String] = [:]
    private var didStart = false
    private var chatsEmitScheduled = false

    init() {
        client.onUpdate = { [weak self] update in
            DispatchQueue.main.async { self?.process(update) }
        }
    }

    // MARK: Запуск

    func start() async {
        guard !didStart else { return }
        didStart = true

        _ = TDLibJSONClient.executeSynchronously([
            "@type": "setLogVerbosityLevel",
            "new_verbosity_level": 1
        ])
        client.start()
        // Первый запрос «будит» клиента: после него TDLib начинает присылать
        // updateAuthorizationState.
        client.send(["@type": "getOption", "name": "version"])
    }

    // MARK: Авторизация

    func sendPhoneNumber(_ phone: String) async throws {
        _ = try await client.request([
            "@type": "setAuthenticationPhoneNumber",
            "phone_number": phone
        ])
    }

    func sendAuthCode(_ code: String) async throws {
        _ = try await client.request(["@type": "checkAuthenticationCode", "code": code])
    }

    func sendPassword(_ password: String) async throws {
        _ = try await client.request(["@type": "checkAuthenticationPassword", "password": password])
    }

    func logOut() async throws {
        _ = try await client.request(["@type": "logOut"])
    }

    // MARK: Чаты и сообщения

    func chats(limit: Int) async throws -> [ChatSummary] {
        do {
            _ = try await client.request([
                "@type": "loadChats",
                "chat_list": ["@type": "chatListMain"],
                "limit": limit
            ])
        } catch TelegramError.api(let code, _) where code == 404 {
            // 404 означает «больше чатов нет» — это нормальный ответ.
        }
        return sortedChats()
    }

    func messages(chatID: Int64, limit: Int) async throws -> [TelegramMessage] {
        var result = try await history(chatID: chatID, limit: limit)
        if result.isEmpty {
            // Первый вызов getChatHistory может вернуть пустой список,
            // пока TDLib догружает историю с сервера.
            result = try await history(chatID: chatID, limit: limit)
        }
        return result.sorted { $0.date < $1.date }
    }

    private func history(chatID: Int64, limit: Int) async throws -> [TelegramMessage] {
        let response = try await client.request([
            "@type": "getChatHistory",
            "chat_id": chatID,
            "from_message_id": 0,
            "offset": 0,
            "limit": limit,
            "only_local": false
        ])
        return response.tdArray("messages").compactMap { message(from: $0) }
    }

    func sendText(_ text: String, to chatID: Int64) async throws {
        _ = try await client.request([
            "@type": "sendMessage",
            "chat_id": chatID,
            "input_message_content": [
                "@type": "inputMessageText",
                "text": ["@type": "formattedText", "text": text, "entities": []]
            ]
        ])
    }

    func sendVoiceNote(path: String, duration: Int, waveform: Data?, to chatID: Int64) async throws {
        var content: [String: Any] = [
            "@type": "inputMessageVoiceNote",
            "voice_note": ["@type": "inputFileLocal", "path": path],
            "duration": duration
        ]
        if let waveform {
            content["waveform"] = waveform.base64EncodedString()
        }
        _ = try await client.request([
            "@type": "sendMessage",
            "chat_id": chatID,
            "input_message_content": content
        ])
    }

    func sendAudioFile(path: String, duration: Int, title: String, to chatID: Int64) async throws {
        _ = try await client.request([
            "@type": "sendMessage",
            "chat_id": chatID,
            "input_message_content": [
                "@type": "inputMessageAudio",
                "audio": ["@type": "inputFileLocal", "path": path],
                "duration": duration,
                "title": title,
                "performer": "Casper"
            ]
        ])
    }

    // MARK: Присутствие

    /// TDLib-опция `online`. Пока она false, клиент вообще не сообщает серверу,
    /// что вы в сети — именно на этом и построен режим «Призрак».
    func setOnlineReporting(_ enabled: Bool) async throws {
        _ = try await client.request([
            "@type": "setOption",
            "name": "online",
            "value": ["@type": "optionValueBoolean", "value": enabled]
        ])
    }

    func openChat(_ chatID: Int64) async throws {
        _ = try await client.request(["@type": "openChat", "chat_id": chatID])
    }

    func closeChat(_ chatID: Int64) async throws {
        _ = try await client.request(["@type": "closeChat", "chat_id": chatID])
    }

    func markMessagesRead(chatID: Int64, messageIDs: [Int64], force: Bool) async throws {
        guard !messageIDs.isEmpty else { return }
        _ = try await client.request([
            "@type": "viewMessages",
            "chat_id": chatID,
            "message_ids": messageIDs,
            "source": ["@type": "messageSourceChatHistory"],
            "force_read": force
        ])
    }

    func sendTyping(chatID: Int64) async throws {
        _ = try await client.request([
            "@type": "sendChatAction",
            "chat_id": chatID,
            "message_thread_id": 0,
            "action": ["@type": "chatActionTyping"]
        ])
    }

    // MARK: Приватность «был(а) в сети»

    func setShowStatusRules(_ rules: ShowStatusRules) async throws {
        _ = try await client.request([
            "@type": "setUserPrivacySettingRules",
            "setting": ["@type": "userPrivacySettingShowStatus"],
            "rules": ["@type": "userPrivacySettingRules", "rules": ruleObjects(from: rules)]
        ])
    }

    func showStatusRules() async throws -> ShowStatusRules {
        let response = try await client.request([
            "@type": "getUserPrivacySettingRules",
            "setting": ["@type": "userPrivacySettingShowStatus"]
        ])
        return Self.rules(from: response.tdArray("rules"))
    }

    private func ruleObjects(from rules: ShowStatusRules) -> [[String: Any]] {
        var objects: [[String: Any]] = []
        if !rules.restrictedUserIDs.isEmpty {
            objects.append([
                "@type": "userPrivacySettingRuleRestrictUsers",
                "user_ids": rules.restrictedUserIDs
            ])
        }
        if !rules.allowedUserIDs.isEmpty {
            objects.append([
                "@type": "userPrivacySettingRuleAllowUsers",
                "user_ids": rules.allowedUserIDs
            ])
        }
        switch rules.visibility {
        case .everybody:
            objects.append(["@type": "userPrivacySettingRuleAllowAll"])
        case .contacts:
            objects.append(["@type": "userPrivacySettingRuleAllowContacts"])
            objects.append(["@type": "userPrivacySettingRuleRestrictAll"])
        case .nobody:
            objects.append(["@type": "userPrivacySettingRuleRestrictAll"])
        }
        return objects
    }

    private static func rules(from objects: [[String: Any]]) -> ShowStatusRules {
        var result = ShowStatusRules()
        var visibility: ShowStatusVisibility?
        for object in objects {
            switch object.tdType {
            case "userPrivacySettingRuleRestrictUsers":
                result.restrictedUserIDs = (object["user_ids"] as? [NSNumber])?.map { $0.int64Value } ?? []
            case "userPrivacySettingRuleAllowUsers":
                result.allowedUserIDs = (object["user_ids"] as? [NSNumber])?.map { $0.int64Value } ?? []
            case "userPrivacySettingRuleAllowAll":
                if visibility == nil { visibility = .everybody }
            case "userPrivacySettingRuleAllowContacts":
                if visibility == nil { visibility = .contacts }
            case "userPrivacySettingRuleRestrictAll":
                if visibility == nil { visibility = .nobody }
            default:
                break
            }
        }
        result.visibility = visibility ?? .everybody
        return result
    }

    // MARK: Обработка обновлений

    private func process(_ update: [String: Any]) {
        switch update.tdType {
        case "updateAuthorizationState":
            handleAuthorizationState(update.tdObject("authorization_state") ?? [:])

        case "updateConnectionState":
            emit(.connection(Self.connectionState(from: update.tdObject("state")?.tdType ?? "")))

        case "updateUser", "user":
            cacheUser(update.tdObject("user") ?? update)

        case "updateNewChat":
            if let chat = update.tdObject("chat"), let summary = chatSummary(from: chat) {
                chatCache[summary.id] = summary
                scheduleChatsEmit()
            }

        case "updateChatLastMessage":
            guard let chatID = update.tdInt64("chat_id") else { return }
            if let last = update.tdObject("last_message"), let parsed = message(from: last) {
                chatCache[chatID]?.preview = parsed.displayText
                chatCache[chatID]?.date = parsed.date
            }
            if let order = Self.order(fromPositions: update.tdArray("positions")) {
                chatCache[chatID]?.order = order
            }
            scheduleChatsEmit()

        case "updateChatPosition":
            guard let chatID = update.tdInt64("chat_id"),
                  let position = update.tdObject("position"),
                  let order = position.tdInt64("order") else { return }
            chatCache[chatID]?.order = order
            scheduleChatsEmit()

        case "updateChatTitle":
            guard let chatID = update.tdInt64("chat_id") else { return }
            chatCache[chatID]?.title = update.tdString("title") ?? ""
            scheduleChatsEmit()

        case "updateChatReadInbox":
            guard let chatID = update.tdInt64("chat_id") else { return }
            chatCache[chatID]?.unreadCount = update.tdInt("unread_count") ?? 0
            scheduleChatsEmit()

        case "updateNewMessage":
            guard let raw = update.tdObject("message"), let parsed = message(from: raw) else { return }
            let chat = chatCache[parsed.chatID]
            emit(.newMessage(parsed,
                             chatTitle: chat?.title ?? "Чат",
                             isSecret: chat?.isSecret ?? false))

        case "updateDeleteMessages":
            guard let chatID = update.tdInt64("chat_id") else { return }
            let ids = (update["message_ids"] as? [NSNumber])?.map { $0.int64Value } ?? []
            guard !ids.isEmpty else { return }
            emit(.messagesDeleted(chatID: chatID,
                                  messageIDs: ids,
                                  permanent: update.tdBool("is_permanent"),
                                  fromCache: update.tdBool("from_cache")))

        case "error":
            let message = update.tdString("message") ?? "unknown"
            emit(.failure("Telegram: \(message)"))

        default:
            break
        }
    }

    private func handleAuthorizationState(_ state: [String: Any]) {
        switch state.tdType {
        case "authorizationStateWaitTdlibParameters":
            sendTdlibParameters()

        case "authorizationStateWaitEncryptionKey":
            // Осталось от старых версий TDLib; на 1.8.6+ не вызывается.
            client.send([
                "@type": "checkDatabaseEncryptionKey",
                "encryption_key": DatabaseKey.base64Key()
            ])

        case "authorizationStateWaitPhoneNumber":
            emit(.authState(.waitPhoneNumber))

        case "authorizationStateWaitCode":
            let phone = state.tdObject("code_info")?.tdString("phone_number") ?? ""
            emit(.authState(.waitCode(phoneNumber: phone)))

        case "authorizationStateWaitPassword":
            emit(.authState(.waitPassword(hint: state.tdString("password_hint") ?? "")))

        case "authorizationStateWaitRegistration":
            emit(.authState(.waitRegistration))

        case "authorizationStateReady":
            emit(.authState(.ready))

        case "authorizationStateLoggingOut":
            emit(.authState(.loggingOut))

        case "authorizationStateClosing":
            break

        case "authorizationStateClosed":
            chatCache.removeAll()
            emit(.authState(.closed))

        default:
            break
        }
    }

    private func sendTdlibParameters() {
        guard TelegramCredentials.isConfigured else {
            emit(.authState(.missingCredentials))
            return
        }

        let base = AppPaths.telegramDatabaseDirectory
        client.send([
            "@type": "setTdlibParameters",
            "use_test_dc": false,
            "database_directory": base.path,
            "files_directory": base.appendingPathComponent("files", isDirectory: true).path,
            "database_encryption_key": DatabaseKey.base64Key(),
            "use_file_database": true,
            "use_chat_info_database": true,
            "use_message_database": true,
            // Секретные чаты Casper не обрабатывает принципиально:
            // локальный архив не должен их касаться.
            "use_secret_chats": false,
            "api_id": Int(TelegramCredentials.apiID),
            "api_hash": TelegramCredentials.apiHash,
            "system_language_code": Locale.preferredLanguages.first ?? "en",
            "device_model": UIDevice.current.model,
            "system_version": UIDevice.current.systemVersion,
            "application_version": AppInfo.version
        ])
    }

    // MARK: Разбор объектов

    private func cacheUser(_ user: [String: Any]) {
        guard user.tdType == "user", let id = user.tdInt64("id") else { return }
        let first = user.tdString("first_name") ?? ""
        let last = user.tdString("last_name") ?? ""
        let name = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        let username = user.tdObject("usernames")?.tdString("editable_username")
        userNames[id] = name.isEmpty ? (username.map { "@\($0)" } ?? "Без имени") : name
    }

    private func chatSummary(from chat: [String: Any]) -> ChatSummary? {
        guard let id = chat.tdInt64("id") else { return nil }
        let type = chat.tdObject("type")
        let typeName = type?.tdType ?? ""
        let isChannel = typeName == "chatTypeSupergroup" && (type?.tdBool("is_channel") ?? false)
        let isGroup = typeName == "chatTypeBasicGroup" || (typeName == "chatTypeSupergroup" && !isChannel)
        let muteFor = chat.tdObject("notification_settings")?.tdInt("mute_for") ?? 0

        var summary = ChatSummary(id: id,
                                  title: chat.tdString("title") ?? "Без названия",
                                  unreadCount: chat.tdInt("unread_count") ?? 0,
                                  isSecret: typeName == "chatTypeSecret",
                                  isChannel: isChannel,
                                  isGroup: isGroup,
                                  isMuted: muteFor > 0,
                                  order: Self.order(fromPositions: chat.tdArray("positions")) ?? 0)

        if let last = chat.tdObject("last_message"), let parsed = message(from: last) {
            summary.preview = parsed.displayText
            summary.date = parsed.date
        }
        return summary
    }

    private func message(from raw: [String: Any]) -> TelegramMessage? {
        guard let id = raw.tdInt64("id"), let chatID = raw.tdInt64("chat_id") else { return nil }
        let (kind, text) = Self.content(from: raw.tdObject("content") ?? [:])
        return TelegramMessage(id: id,
                               chatID: chatID,
                               senderName: senderName(from: raw.tdObject("sender_id")),
                               isOutgoing: raw.tdBool("is_outgoing"),
                               text: text,
                               date: raw.tdDate("date") ?? Date(),
                               kind: kind)
    }

    private func senderName(from sender: [String: Any]?) -> String {
        guard let sender else { return "" }
        switch sender.tdType {
        case "messageSenderUser":
            guard let userID = sender.tdInt64("user_id") else { return "" }
            if let name = userNames[userID] { return name }
            // Имя подтянется из ответа `user`, который обработает process(_:).
            client.send(["@type": "getUser", "user_id": userID])
            return ""
        case "messageSenderChat":
            guard let chatID = sender.tdInt64("chat_id") else { return "" }
            return chatCache[chatID]?.title ?? ""
        default:
            return ""
        }
    }

    private static func content(from content: [String: Any]) -> (MessageKind, String) {
        func caption() -> String {
            content.tdObject("caption")?.tdString("text") ?? ""
        }
        switch content.tdType {
        case "messageText":
            return (.text, content.tdObject("text")?.tdString("text") ?? "")
        case "messagePhoto":
            return (.photo, caption())
        case "messageVideo":
            return (.video, caption())
        case "messageVoiceNote":
            return (.voice, caption())
        case "messageAudio":
            return (.audio, content.tdObject("audio")?.tdString("title") ?? caption())
        case "messageDocument":
            return (.document, content.tdObject("document")?.tdString("file_name") ?? caption())
        case "messageSticker":
            return (.sticker, content.tdObject("sticker")?.tdString("emoji") ?? "")
        default:
            return (.other(content.tdType), "")
        }
    }

    private static func order(fromPositions positions: [[String: Any]]) -> Int64? {
        for position in positions where position.tdObject("list")?.tdType == "chatListMain" {
            return position.tdInt64("order")
        }
        return positions.first?.tdInt64("order")
    }

    private static func connectionState(from type: String) -> ConnectionState {
        switch type {
        case "connectionStateWaitingForNetwork": return .waitingForNetwork
        case "connectionStateConnectingToProxy": return .connectingToProxy
        case "connectionStateConnecting": return .connecting
        case "connectionStateUpdating": return .updating
        default: return .ready
        }
    }

    private func sortedChats() -> [ChatSummary] {
        chatCache.values
            .filter { $0.order != 0 || $0.date != .distantPast }
            .sorted { left, right in
                if left.order != right.order { return left.order > right.order }
                return left.date > right.date
            }
    }

    private func scheduleChatsEmit() {
        guard !chatsEmitScheduled else { return }
        chatsEmitScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            self.chatsEmitScheduled = false
            self.emit(.chatsChanged(self.sortedChats()))
        }
    }

    private func emit(_ event: TelegramEvent) {
        if Thread.isMainThread {
            onEvent?(event)
        } else {
            DispatchQueue.main.async { [weak self] in self?.onEvent?(event) }
        }
    }
}
#endif
