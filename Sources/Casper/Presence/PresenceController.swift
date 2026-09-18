import Foundation

/// Применяет `PresencePolicy` к Telegram и помнит, что уже применено,
/// чтобы не дёргать сервер одинаковыми запросами.
final class PresenceController {
    private let service: TelegramService
    private var applied: PresencePolicy?

    /// Текущая политика — её спрашивают экраны чатов перед отправкой
    /// отметок о прочтении и «печатает…».
    private(set) var current: PresencePolicy = .normal

    init(service: TelegramService) {
        self.service = service
    }

    func apply(_ policy: PresencePolicy) async throws {
        current = policy
        guard applied?.reportsOnline != policy.reportsOnline else { return }
        try await service.setOnlineReporting(policy.reportsOnline)
        applied = policy
    }

    /// Открыть чат, не выдавая присутствие: openChat нужен, чтобы TDLib
    /// подгружал историю, а вот viewMessages мы посылаем только если можно.
    func openChat(_ chatID: Int64) async throws {
        try await service.openChat(chatID)
    }

    func closeChat(_ chatID: Int64) async throws {
        try await service.closeChat(chatID)
    }

    func markReadIfAllowed(chatID: Int64, messageIDs: [Int64]) async throws {
        guard current.sendsReadReceipts else { return }
        try await service.markMessagesRead(chatID: chatID, messageIDs: messageIDs, force: false)
    }

    /// Ручное «прочитать всё равно» — кнопка в чате, когда включён Призрак.
    func forceMarkRead(chatID: Int64, messageIDs: [Int64]) async throws {
        try await service.markMessagesRead(chatID: chatID, messageIDs: messageIDs, force: true)
    }

    func sendTypingIfAllowed(chatID: Int64) async throws {
        guard current.sendsTypingIndicator else { return }
        try await service.sendTyping(chatID: chatID)
    }
}
