import Foundation

/// Где Casper хранит свои данные на устройстве.
enum AppPaths {
    private static func directory(_ url: URL, excludeFromBackup: Bool = true) -> URL {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        if excludeFromBackup {
            var mutable = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? mutable.setResourceValues(values)
        }
        return url
    }

    static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return directory(base.appendingPathComponent("Casper", isDirectory: true))
    }

    /// Локальная база TDLib (там лежит и кэш сообщений самого Telegram).
    static var telegramDatabaseDirectory: URL {
        directory(applicationSupport.appendingPathComponent("tdlib", isDirectory: true))
    }

    /// Архив Casper: только те сообщения, которые приложение уже получило.
    static var archiveDatabaseURL: URL {
        applicationSupport.appendingPathComponent("casper-archive.sqlite")
    }

    static var settingsURL: URL {
        applicationSupport.appendingPathComponent("casper-settings.json")
    }

    /// Временные записи Voice Changer.
    static var voiceDirectory: URL {
        directory(applicationSupport.appendingPathComponent("voice", isDirectory: true))
    }
}

enum AppInfo {
    static var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil
    }
}
