import XCTest
@testable import CasperTelegram

final class MessageArchiveTests: XCTestCase {
    private var archive: MessageArchive!
    private var path: String!

    override func setUpWithError() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        path = directory.appendingPathComponent("archive.sqlite").path
        archive = try MessageArchive(path: path)
    }

    override func tearDownWithError() throws {
        archive = nil
        if let path { try? FileManager.default.removeItem(atPath: path) }
    }

    private func message(id: Int64, chatID: Int64 = 7, date: Date = Date(), outgoing: Bool = false) -> TelegramMessage {
        TelegramMessage(id: id,
                        chatID: chatID,
                        senderName: "Марина",
                        isOutgoing: outgoing,
                        text: "сообщение \(id)",
                        date: date,
                        kind: .text)
    }

    func testStoreAndCount() {
        archive.store(message(id: 1), chatTitle: "Марина")
        archive.store(message(id: 2), chatTitle: "Марина")
        XCTAssertEqual(archive.stats().stored, 2)
        XCTAssertEqual(archive.stats().deleted, 0)
    }

    func testStoringSameMessageTwiceDoesNotDuplicate() {
        archive.store(message(id: 1), chatTitle: "Марина")
        archive.store(message(id: 1), chatTitle: "Марина")
        XCTAssertEqual(archive.stats().stored, 1)
    }

    func testMarkDeletedReturnsOnlyKnownMessages() {
        archive.store(message(id: 1), chatTitle: "Марина")
        // id 99 приложение никогда не получало — его в результате быть не должно.
        let affected = archive.markDeleted(chatID: 7, messageIDs: [1, 99])
        XCTAssertEqual(affected.count, 1)
        XCTAssertEqual(affected.first?.messageID, 1)
        XCTAssertNotNil(affected.first?.deletedAt)
        XCTAssertEqual(archive.stats().deleted, 1)
    }

    func testMarkDeletedIsIdempotent() {
        archive.store(message(id: 1), chatTitle: "Марина")
        XCTAssertEqual(archive.markDeleted(chatID: 7, messageIDs: [1]).count, 1)
        XCTAssertEqual(archive.markDeleted(chatID: 7, messageIDs: [1]).count, 0)
    }

    func testDeletedRecordsAreReturnedNewestFirst() {
        archive.store(message(id: 1), chatTitle: "Марина")
        archive.store(message(id: 2), chatTitle: "Марина")
        _ = archive.markDeleted(chatID: 7, messageIDs: [1], at: Date(timeIntervalSince1970: 1_000))
        _ = archive.markDeleted(chatID: 7, messageIDs: [2], at: Date(timeIntervalSince1970: 2_000))

        let records = archive.deletedRecords()
        XCTAssertEqual(records.map(\.messageID), [2, 1])
        XCTAssertEqual(records.first?.text, "сообщение 2")
    }

    func testPurgeRemovesOldRecords() {
        let old = Date().addingTimeInterval(-10 * 86_400)
        archive.store(message(id: 1, date: old), chatTitle: "Марина")
        archive.store(message(id: 2), chatTitle: "Марина")

        let removed = archive.purge(olderThanDays: 7)
        XCTAssertEqual(removed, 1)
        XCTAssertEqual(archive.stats().stored, 1)
    }

    func testClearRemovesEverything() {
        archive.store(message(id: 1), chatTitle: "Марина")
        archive.clear()
        XCTAssertEqual(archive.stats().stored, 0)
    }

    func testRecordKeepsMessageKind() {
        let voice = TelegramMessage(id: 5, chatID: 7, senderName: "Антон", isOutgoing: false,
                                    text: "", date: Date(), kind: .voice)
        archive.store(voice, chatTitle: "Casper Dev")
        let affected = archive.markDeleted(chatID: 7, messageIDs: [5])
        XCTAssertEqual(affected.first?.kind, .voice)
    }
}
