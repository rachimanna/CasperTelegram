import XCTest
@testable import CasperTelegram

/// Логика «Призрака» — чистая, поэтому её можно проверить без Telegram.
final class GhostSettingsTests: XCTestCase {

    func testDisabledGhostKeepsNormalPolicy() {
        let settings = GhostSettings()
        XCTAssertFalse(settings.isActive())
        XCTAssertEqual(settings.policy(), .normal)
    }

    func testEnabledGhostHidesEverythingByDefault() {
        var settings = GhostSettings()
        settings.isEnabled = true
        XCTAssertTrue(settings.isActive())
        XCTAssertEqual(settings.policy(), .fullGhost)
    }

    func testPartialGhostOnlyHidesSelectedSignals() {
        var settings = GhostSettings()
        settings.isEnabled = true
        settings.hideOnlineStatus = true
        settings.hideReadReceipts = false
        settings.hideTypingIndicator = false

        let policy = settings.policy()
        XCTAssertFalse(policy.reportsOnline)
        XCTAssertTrue(policy.sendsReadReceipts)
        XCTAssertTrue(policy.sendsTypingIndicator)
    }

    func testWindowInsideSameDay() {
        XCTAssertTrue(GhostSettings.isInsideWindow(minutes: 10 * 60, start: 9 * 60, end: 18 * 60))
        XCTAssertFalse(GhostSettings.isInsideWindow(minutes: 8 * 60, start: 9 * 60, end: 18 * 60))
        XCTAssertFalse(GhostSettings.isInsideWindow(minutes: 18 * 60, start: 9 * 60, end: 18 * 60))
    }

    func testWindowAcrossMidnight() {
        // Окно 22:00 → 08:00
        XCTAssertTrue(GhostSettings.isInsideWindow(minutes: 23 * 60, start: 22 * 60, end: 8 * 60))
        XCTAssertTrue(GhostSettings.isInsideWindow(minutes: 2 * 60, start: 22 * 60, end: 8 * 60))
        XCTAssertFalse(GhostSettings.isInsideWindow(minutes: 12 * 60, start: 22 * 60, end: 8 * 60))
    }

    func testEqualBoundsMeanAlwaysActive() {
        XCTAssertTrue(GhostSettings.isInsideWindow(minutes: 3 * 60, start: 60, end: 60))
    }

    func testScheduleControlsActivation() throws {
        var settings = GhostSettings()
        settings.isEnabled = true
        settings.scheduleEnabled = true
        settings.scheduleStartMinutes = 22 * 60
        settings.scheduleEndMinutes = 8 * 60

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))

        let night = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 23)))
        let noon = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 12)))

        XCTAssertTrue(settings.isActive(at: night, calendar: calendar))
        XCTAssertFalse(settings.isActive(at: noon, calendar: calendar))
        XCTAssertEqual(settings.policy(at: noon, calendar: calendar), .normal)
    }

    func testTimeTextFormatting() {
        XCTAssertEqual(GhostSettings.timeText(minutes: 22 * 60), "22:00")
        XCTAssertEqual(GhostSettings.timeText(minutes: 8 * 60 + 5), "08:05")
    }
}
