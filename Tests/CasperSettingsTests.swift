import XCTest
@testable import CasperTelegram

final class CasperSettingsTests: XCTestCase {

    func testDefaultsAreConservative() {
        let settings = CasperSettings()
        XCTAssertFalse(settings.ghost.isEnabled, "Призрак по умолчанию выключен")
        XCTAssertFalse(settings.archive.isEnabled, "Архив по умолчанию выключен")
        XCTAssertFalse(settings.integration.isEnabled)
        XCTAssertEqual(settings.privacy.showStatus.visibility, .everybody)
        XCTAssertEqual(settings.archive.retentionDays, 7)
    }

    func testCodableRoundTrip() throws {
        var settings = CasperSettings()
        settings.ghost.isEnabled = true
        settings.ghost.scheduleEnabled = true
        settings.archive.retentionDays = 30
        settings.appearance.accent = .mint
        settings.voice.lastEffect = .robot
        settings.privacy.showStatus.visibility = .contacts
        settings.privacy.showStatus.restrictedUserIDs = [42, 7]

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(CasperSettings.self, from: data)
        XCTAssertEqual(decoded, settings)
    }

    func testStorePersistsToDisk() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = CasperSettingsStore(url: url)
        store.settings.ghost.isEnabled = true
        store.settings.appearance.mode = .dark

        let reloaded = CasperSettingsStore(url: url)
        XCTAssertTrue(reloaded.settings.ghost.isEnabled)
        XCTAssertEqual(reloaded.settings.appearance.mode, .dark)
    }

    func testMissingFileFallsBackToDefaults() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(UUID().uuidString).json")
        let store = CasperSettingsStore(url: url)
        XCTAssertEqual(store.settings, CasperSettings())
    }
}
