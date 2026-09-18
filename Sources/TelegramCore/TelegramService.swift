import Foundation

/// Единая точка входа в Telegram для всего приложения.
///
/// Две реализации:
/// * `TDLibTelegramService` — настоящий клиент на официальном TDLib;
/// * `MockTelegramService`  — демо-режим, чтобы интерфейс собирался и запускался
///   без TDLib (нужно для CI и для быстрой работы над UI).
///
/// Вся Casper-логика работает только через этот протокол и не знает,
/// какая реализация под ней. Это и есть граница между Telegram Core и Casper.
protocol TelegramService: AnyObject {
    var onEvent: ((TelegramEvent) -> Void)? { get set }
    /// true — если это демо-режим без настоящего Telegram.
    var isDemo: Bool { get }

    func start() async

    // Авторизация
    func sendPhoneNumber(_ phone: String) async throws
    func sendAuthCode(_ code: String) async throws
    func sendPassword(_ password: String) async throws
    func logOut() async throws

    // Данные
    func chats(limit: Int) async throws -> [ChatSummary]
    func messages(chatID: Int64, limit: Int) async throws -> [TelegramMessage]
    func sendText(_ text: String, to chatID: Int64) async throws
    /// path — путь к файлу. Настоящее голосовое сообщение Telegram — это
    /// Opus в контейнере OGG, моно (см. docs/LIMITATIONS.md, раздел Voice Changer).
    func sendVoiceNote(path: String, duration: Int, waveform: Data?, to chatID: Int64) async throws
    func sendAudioFile(path: String, duration: Int, title: String, to chatID: Int64) async throws

    // Присутствие — всё, что клиент сам сообщает серверу о своей активности
    func setOnlineReporting(_ enabled: Bool) async throws
    func openChat(_ chatID: Int64) async throws
    func closeChat(_ chatID: Int64) async throws
    func markMessagesRead(chatID: Int64, messageIDs: [Int64], force: Bool) async throws
    func sendTyping(chatID: Int64) async throws

    // Серверные настройки приватности
    func setShowStatusRules(_ rules: ShowStatusRules) async throws
    func showStatusRules() async throws -> ShowStatusRules
}

/// Фабрика: если TDLib вкомпилирован — берём его, иначе демо-режим.
enum TelegramServiceFactory {
    static func make() -> TelegramService {
        #if canImport(TDLibFramework)
        return TDLibTelegramService()
        #else
        return MockTelegramService()
        #endif
    }
}
