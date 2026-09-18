import Foundation
import SwiftUI

// MARK: - Архив сообщений

struct ArchiveSettings: Codable, Equatable {
    /// По умолчанию выключено: функция чувствительная, включать её должен
    /// сам пользователь осознанно.
    var isEnabled = false
    /// Через сколько дней запись удаляется без возможности восстановления.
    var retentionDays = 7
    var notifyOnDeletion = true
    var includeOutgoing = false
}

// MARK: - Voice Changer

struct VoiceSettings: Codable, Equatable {
    var lastEffect: VoiceEffect = .none
    /// Пока нет Opus-кодирования, отправлять обработанный звук как аудиофайл.
    var sendAsAudioFile = true
}

// MARK: - Внешний вид

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Как в системе"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum CasperAccent: String, Codable, CaseIterable, Identifiable {
    case casper, telegram, mint, amber, rose, graphite
    var id: String { rawValue }

    var title: String {
        switch self {
        case .casper: return "Casper"
        case .telegram: return "Синий"
        case .mint: return "Мята"
        case .amber: return "Янтарь"
        case .rose: return "Роза"
        case .graphite: return "Графит"
        }
    }

    var color: Color {
        switch self {
        case .casper: return Color(red: 0.40, green: 0.62, blue: 0.95)
        case .telegram: return Color(red: 0.20, green: 0.55, blue: 0.94)
        case .mint: return Color(red: 0.21, green: 0.76, blue: 0.62)
        case .amber: return Color(red: 0.96, green: 0.68, blue: 0.24)
        case .rose: return Color(red: 0.93, green: 0.42, blue: 0.56)
        case .graphite: return Color(red: 0.45, green: 0.48, blue: 0.54)
        }
    }
}

struct AppearanceSettings: Codable, Equatable {
    var mode: AppearanceMode = .system
    var accent: CasperAccent = .casper
    var bubbleCornerRadius: Double = 18
    var compactChatList = false
    var showCasperBadge = true
}

// MARK: - Приватность

struct CasperPrivacySettings: Codable, Equatable {
    var showStatus = ShowStatusRules()
    var lockCasperSection = false
}

// MARK: - Интеграции

struct AIIntegrationSettings: Codable, Equatable {
    var isEnabled = false
    var baseURL = "https://api.openai.com/v1"
    var model = ""
}

// MARK: - Всё вместе

struct CasperSettings: Codable, Equatable {
    var ghost = GhostSettings()
    var archive = ArchiveSettings()
    var voice = VoiceSettings()
    var appearance = AppearanceSettings()
    var privacy = CasperPrivacySettings()
    var integration = AIIntegrationSettings()
}

/// Настройки Casper в одном файле JSON. Секретов тут нет — они в Keychain.
final class CasperSettingsStore: ObservableObject {
    @Published var settings: CasperSettings {
        didSet { if settings != oldValue { save() } }
    }

    private let url: URL

    init(url: URL = AppPaths.settingsURL) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(CasperSettings.self, from: data) {
            settings = decoded
        } else {
            settings = CasperSettings()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func reset() {
        settings = CasperSettings()
    }
}
