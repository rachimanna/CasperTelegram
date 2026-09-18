import Foundation

/// Что именно Casper сообщает серверу Telegram о вашей активности.
///
/// Важно понимать механику: сервер Telegram узнаёт о вашей активности
/// ТОЛЬКО из исходящих запросов клиента:
/// * «я в сети»  — TDLib-опция `online`;
/// * «прочитано» — метод `viewMessages`;
/// * «печатает»  — метод `sendChatAction`.
///
/// Поэтому «Призрак» — это не обман сервера, а просто отказ клиента
/// отправлять эти сигналы. Ровно то, что сторонний клиент вправе не делать.
struct PresencePolicy: Equatable {
    var reportsOnline = true
    var sendsReadReceipts = true
    var sendsTypingIndicator = true

    static let normal = PresencePolicy()
    static let fullGhost = PresencePolicy(reportsOnline: false,
                                          sendsReadReceipts: false,
                                          sendsTypingIndicator: false)
}

struct GhostSettings: Codable, Equatable {
    var isEnabled = false
    var hideOnlineStatus = true
    var hideReadReceipts = true
    var hideTypingIndicator = true
    var enableOnLaunch = false
    var scheduleEnabled = false
    /// Минуты от полуночи.
    var scheduleStartMinutes = 22 * 60
    var scheduleEndMinutes = 8 * 60

    /// Действует ли режим прямо сейчас (с учётом расписания).
    func isActive(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard isEnabled else { return false }
        guard scheduleEnabled else { return true }
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        return GhostSettings.isInsideWindow(minutes: minutes,
                                            start: scheduleStartMinutes,
                                            end: scheduleEndMinutes)
    }

    /// Итоговая политика присутствия.
    func policy(at date: Date = Date(), calendar: Calendar = .current) -> PresencePolicy {
        guard isActive(at: date, calendar: calendar) else { return .normal }
        return PresencePolicy(reportsOnline: !hideOnlineStatus,
                              sendsReadReceipts: !hideReadReceipts,
                              sendsTypingIndicator: !hideTypingIndicator)
    }

    /// Окно может проходить через полночь: 22:00 → 08:00.
    static func isInsideWindow(minutes: Int, start: Int, end: Int) -> Bool {
        if start == end { return true }
        if start < end { return minutes >= start && minutes < end }
        return minutes >= start || minutes < end
    }

    static func timeText(minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60 % 24, minutes % 60)
    }
}
