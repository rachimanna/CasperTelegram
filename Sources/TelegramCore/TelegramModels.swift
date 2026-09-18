import Foundation

// MARK: - Авторизация

enum AuthState: Equatable {
    case unknown
    /// Не заданы api_id / api_hash (см. docs/TELEGRAM-API.md).
    case missingCredentials
    case waitPhoneNumber
    case waitCode(phoneNumber: String)
    case waitPassword(hint: String)
    /// Номер не зарегистрирован в Telegram — регистрацию делаем в официальном приложении.
    case waitRegistration
    case ready
    case loggingOut
    case closed
}

enum ConnectionState: Equatable {
    case waitingForNetwork
    case connectingToProxy
    case connecting
    case updating
    case ready

    var title: String {
        switch self {
        case .waitingForNetwork: return "Ожидание сети"
        case .connectingToProxy: return "Подключение к прокси"
        case .connecting: return "Соединение…"
        case .updating: return "Обновление…"
        case .ready: return "Casper"
        }
    }

    var isBusy: Bool { self != .ready }
}

// MARK: - Чаты и сообщения

struct ChatSummary: Identifiable, Equatable {
    let id: Int64
    var title: String
    var preview: String
    var date: Date
    var unreadCount: Int
    var isSecret: Bool
    var isChannel: Bool
    var isGroup: Bool
    var isMuted: Bool
    var order: Int64

    init(id: Int64,
         title: String,
         preview: String = "",
         date: Date = .distantPast,
         unreadCount: Int = 0,
         isSecret: Bool = false,
         isChannel: Bool = false,
         isGroup: Bool = false,
         isMuted: Bool = false,
         order: Int64 = 0) {
        self.id = id
        self.title = title
        self.preview = preview
        self.date = date
        self.unreadCount = unreadCount
        self.isSecret = isSecret
        self.isChannel = isChannel
        self.isGroup = isGroup
        self.isMuted = isMuted
        self.order = order
    }

    /// Инициалы для аватара-заглушки, пока не загружена фотография.
    var initials: String {
        let words = title.split(separator: " ").prefix(2)
        let letters = words.compactMap { $0.first.map(String.init) }
        return letters.joined().uppercased()
    }

    /// Стабильный индекс цвета аватара (как в Telegram — цвет зависит от id).
    var colorIndex: Int { abs(Int(id % 7)) }
}

enum MessageKind: Equatable {
    case text
    case photo
    case video
    case voice
    case audio
    case document
    case sticker
    case other(String)

    var placeholder: String {
        switch self {
        case .text: return ""
        case .photo: return "Фото"
        case .video: return "Видео"
        case .voice: return "Голосовое сообщение"
        case .audio: return "Аудио"
        case .document: return "Файл"
        case .sticker: return "Стикер"
        case .other: return "Сообщение"
        }
    }

    var symbol: String? {
        switch self {
        case .text: return nil
        case .photo: return "photo"
        case .video: return "video"
        case .voice: return "mic"
        case .audio: return "music.note"
        case .document: return "doc"
        case .sticker: return "face.smiling"
        case .other: return "questionmark.square.dashed"
        }
    }

    var storageKey: String {
        switch self {
        case .text: return "text"
        case .photo: return "photo"
        case .video: return "video"
        case .voice: return "voice"
        case .audio: return "audio"
        case .document: return "document"
        case .sticker: return "sticker"
        case .other(let value): return value
        }
    }

    static func fromStorageKey(_ key: String) -> MessageKind {
        switch key {
        case "text": return .text
        case "photo": return .photo
        case "video": return .video
        case "voice": return .voice
        case "audio": return .audio
        case "document": return .document
        case "sticker": return .sticker
        default: return .other(key)
        }
    }
}

struct TelegramMessage: Identifiable, Equatable {
    let id: Int64
    let chatID: Int64
    var senderName: String
    var isOutgoing: Bool
    var text: String
    var date: Date
    var kind: MessageKind

    var displayText: String { text.isEmpty ? kind.placeholder : text }
}

// MARK: - Приватность

enum ShowStatusVisibility: String, Codable, CaseIterable, Equatable {
    case everybody
    case contacts
    case nobody

    var title: String {
        switch self {
        case .everybody: return "Все"
        case .contacts: return "Мои контакты"
        case .nobody: return "Никто"
        }
    }
}

/// Правила видимости «был(а) в сети». Это серверная настройка Telegram,
/// её меняет метод setUserPrivacySettingRules(userPrivacySettingShowStatus).
struct ShowStatusRules: Codable, Equatable {
    var visibility: ShowStatusVisibility = .everybody
    var allowedUserIDs: [Int64] = []
    var restrictedUserIDs: [Int64] = []
}

// MARK: - События от Telegram

enum TelegramEvent {
    case authState(AuthState)
    case connection(ConnectionState)
    case chatsChanged([ChatSummary])
    case newMessage(TelegramMessage, chatTitle: String, isSecret: Bool)
    case messagesDeleted(chatID: Int64, messageIDs: [Int64], permanent: Bool, fromCache: Bool)
    case failure(String)
}

// MARK: - Ошибки

enum TelegramError: LocalizedError, Equatable {
    case missingCredentials
    case notAvailableInDemoMode(String)
    case api(code: Int, message: String)
    case invalidResponse
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Не заданы api_id и api_hash. См. docs/TELEGRAM-API.md."
        case .notAvailableInDemoMode(let what):
            return "«\(what)» недоступно в демо-режиме: TDLib не подключён к сборке."
        case .api(let code, let message):
            return "Telegram вернул ошибку \(code): \(message)"
        case .invalidResponse:
            return "Непонятный ответ от Telegram."
        case .unsupported(let what):
            return what
        }
    }
}
