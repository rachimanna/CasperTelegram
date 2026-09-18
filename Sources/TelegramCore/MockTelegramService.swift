import Foundation

/// Демо-режим. Нужен для двух вещей:
/// 1. CI собирает и тестирует приложение без TDLib;
/// 2. можно работать над интерфейсом, не входя в настоящий аккаунт.
///
/// Никаких сетевых запросов не делает. Все данные придуманы и живут в памяти.
final class MockTelegramService: TelegramService {
    var onEvent: ((TelegramEvent) -> Void)?
    var isDemo: Bool { true }

    /// Код подтверждения в демо-режиме.
    static let demoCode = "12345"

    private var storage: [Int64: [TelegramMessage]] = [:]
    private var chatList: [ChatSummary] = []
    private var rules = ShowStatusRules()
    private var demoTimer: Timer?
    private var nextMessageID: Int64 = 1000

    // MARK: Жизненный цикл

    func start() async {
        buildDemoData()
        emit(.connection(.ready))
        emit(.authState(.waitPhoneNumber))
    }

    // MARK: Авторизация

    func sendPhoneNumber(_ phone: String) async throws {
        try await pause()
        emit(.authState(.waitCode(phoneNumber: phone)))
    }

    func sendAuthCode(_ code: String) async throws {
        try await pause()
        guard code.trimmingCharacters(in: .whitespaces) == Self.demoCode else {
            throw TelegramError.api(code: 400, message: "PHONE_CODE_INVALID (в демо-режиме код \(Self.demoCode))")
        }
        emit(.authState(.ready))
        emit(.chatsChanged(chatList))
        scheduleDeletionDemo()
    }

    func sendPassword(_ password: String) async throws {
        try await pause()
        emit(.authState(.ready))
    }

    func logOut() async throws {
        demoTimer?.invalidate()
        emit(.authState(.waitPhoneNumber))
    }

    // MARK: Данные

    func chats(limit: Int) async throws -> [ChatSummary] {
        Array(chatList.prefix(limit))
    }

    func messages(chatID: Int64, limit: Int) async throws -> [TelegramMessage] {
        Array((storage[chatID] ?? []).suffix(limit))
    }

    func sendText(_ text: String, to chatID: Int64) async throws {
        nextMessageID += 1
        let message = TelegramMessage(id: nextMessageID,
                                      chatID: chatID,
                                      senderName: "Вы",
                                      isOutgoing: true,
                                      text: text,
                                      date: Date(),
                                      kind: .text)
        storage[chatID, default: []].append(message)
        updatePreview(chatID: chatID, text: text)
        emit(.newMessage(message, chatTitle: title(of: chatID), isSecret: false))
    }

    func sendVoiceNote(path: String, duration: Int, waveform: Data?, to chatID: Int64) async throws {
        try await sendMedia(kind: .voice, text: "Голосовое \(duration) с", chatID: chatID)
    }

    func sendAudioFile(path: String, duration: Int, title: String, to chatID: Int64) async throws {
        try await sendMedia(kind: .audio, text: title, chatID: chatID)
    }

    // MARK: Присутствие

    func setOnlineReporting(_ enabled: Bool) async throws {}
    func openChat(_ chatID: Int64) async throws {}
    func closeChat(_ chatID: Int64) async throws {}
    func markMessagesRead(chatID: Int64, messageIDs: [Int64], force: Bool) async throws {
        guard let index = chatList.firstIndex(where: { $0.id == chatID }) else { return }
        chatList[index].unreadCount = 0
        emit(.chatsChanged(chatList))
    }
    func sendTyping(chatID: Int64) async throws {}

    func setShowStatusRules(_ rules: ShowStatusRules) async throws { self.rules = rules }
    func showStatusRules() async throws -> ShowStatusRules { rules }

    // MARK: Внутреннее

    private func sendMedia(kind: MessageKind, text: String, chatID: Int64) async throws {
        nextMessageID += 1
        let message = TelegramMessage(id: nextMessageID,
                                      chatID: chatID,
                                      senderName: "Вы",
                                      isOutgoing: true,
                                      text: text,
                                      date: Date(),
                                      kind: kind)
        storage[chatID, default: []].append(message)
        updatePreview(chatID: chatID, text: text)
        emit(.newMessage(message, chatTitle: title(of: chatID), isSecret: false))
    }

    private func pause() async throws {
        try await Task.sleep(nanoseconds: 400_000_000)
    }

    private func emit(_ event: TelegramEvent) {
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(event)
        }
    }

    private func title(of chatID: Int64) -> String {
        chatList.first(where: { $0.id == chatID })?.title ?? "Чат"
    }

    private func updatePreview(chatID: Int64, text: String) {
        guard let index = chatList.firstIndex(where: { $0.id == chatID }) else { return }
        chatList[index].preview = text
        chatList[index].date = Date()
        chatList.sort { $0.date > $1.date }
        emit(.chatsChanged(chatList))
    }

    /// Демонстрация работы архива: через 10 секунд приходит сообщение,
    /// а через 8 секунд «собеседник» его удаляет. Это тот же самый путь
    /// событий, что и в настоящем TDLib, поэтому раздел
    /// «Удалённые сообщения» можно проверить без входа в аккаунт.
    private func scheduleDeletionDemo() {
        demoTimer?.invalidate()
        demoTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.nextMessageID += 1
            let message = TelegramMessage(id: self.nextMessageID,
                                          chatID: 2,
                                          senderName: "Марина",
                                          isOutgoing: false,
                                          text: "Ой, это я не тебе. Сейчас удалю 🙈",
                                          date: Date(),
                                          kind: .text)
            self.storage[2, default: []].append(message)
            self.emit(.newMessage(message, chatTitle: self.title(of: 2), isSecret: false))

            let deletedID = message.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                guard let self else { return }
                self.storage[2]?.removeAll { $0.id == deletedID }
                self.emit(.messagesDeleted(chatID: 2,
                                           messageIDs: [deletedID],
                                           permanent: true,
                                           fromCache: false))
            }
        }
    }

    private func buildDemoData() {
        let now = Date()
        chatList = [
            ChatSummary(id: 1, title: "Saved Messages", preview: "Ссылка на статью про Opus",
                        date: now.addingTimeInterval(-120), unreadCount: 0, order: 100),
            ChatSummary(id: 2, title: "Марина", preview: "Договорились, до вечера!",
                        date: now.addingTimeInterval(-900), unreadCount: 2, order: 99),
            ChatSummary(id: 3, title: "Casper Dev", preview: "Ghost-режим наконец работает",
                        date: now.addingTimeInterval(-3600), unreadCount: 12, isGroup: true, order: 98),
            ChatSummary(id: 4, title: "Swift Weekly", preview: "Выпуск 512: манёвры с AVAudioEngine",
                        date: now.addingTimeInterval(-7200), unreadCount: 0, isChannel: true, isMuted: true, order: 97),
            ChatSummary(id: 5, title: "Мама", preview: "Позвони, как сможешь",
                        date: now.addingTimeInterval(-86_400), unreadCount: 1, order: 96)
        ]

        storage = [
            1: [
                TelegramMessage(id: 1, chatID: 1, senderName: "Вы", isOutgoing: true,
                                text: "Голосовое сообщение в Telegram — это Opus в контейнере OGG, моно.",
                                date: now.addingTimeInterval(-300), kind: .text)
            ],
            2: [
                TelegramMessage(id: 10, chatID: 2, senderName: "Марина", isOutgoing: false,
                                text: "Привет! Ты успеешь к семи?", date: now.addingTimeInterval(-1500), kind: .text),
                TelegramMessage(id: 11, chatID: 2, senderName: "Вы", isOutgoing: true,
                                text: "Да, выхожу", date: now.addingTimeInterval(-1200), kind: .text),
                TelegramMessage(id: 12, chatID: 2, senderName: "Марина", isOutgoing: false,
                                text: "Договорились, до вечера!", date: now.addingTimeInterval(-900), kind: .text)
            ],
            3: [
                TelegramMessage(id: 20, chatID: 3, senderName: "Антон", isOutgoing: false,
                                text: "Ghost-режим наконец работает", date: now.addingTimeInterval(-3600), kind: .text),
                TelegramMessage(id: 21, chatID: 3, senderName: "Антон", isOutgoing: false,
                                text: "", date: now.addingTimeInterval(-3500), kind: .voice)
            ],
            4: [
                TelegramMessage(id: 30, chatID: 4, senderName: "Swift Weekly", isOutgoing: false,
                                text: "Выпуск 512: манёвры с AVAudioEngine", date: now.addingTimeInterval(-7200), kind: .text)
            ],
            5: [
                TelegramMessage(id: 40, chatID: 5, senderName: "Мама", isOutgoing: false,
                                text: "Позвони, как сможешь", date: now.addingTimeInterval(-86_400), kind: .text)
            ]
        ]
    }
}
