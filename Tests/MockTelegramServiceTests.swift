import XCTest
@testable import CasperTelegram

/// Проверяем сам поток событий: те же события приходят и от TDLib,
/// поэтому такой тест ловит ошибки в связке «событие → состояние».
final class MockTelegramServiceTests: XCTestCase {

    func testAuthorizationFlowReachesReady() async throws {
        let service = MockTelegramService()
        var states: [AuthState] = []

        let expectation = expectation(description: "ready")
        service.onEvent = { event in
            if case .authState(let state) = event {
                states.append(state)
                if state == .ready { expectation.fulfill() }
            }
        }

        await service.start()
        try await service.sendPhoneNumber("+70000000000")
        try await service.sendAuthCode(MockTelegramService.demoCode)

        await fulfillment(of: [expectation], timeout: 5)
        XCTAssertTrue(states.contains(.waitPhoneNumber))
        XCTAssertTrue(states.contains(.ready))
    }

    func testWrongCodeIsRejected() async throws {
        let service = MockTelegramService()
        await service.start()
        try await service.sendPhoneNumber("+70000000000")

        do {
            try await service.sendAuthCode("00000")
            XCTFail("Неверный код должен приводить к ошибке")
        } catch {
            XCTAssertTrue(error is TelegramError)
        }
    }

    func testChatsAndMessagesAreAvailable() async throws {
        let service = MockTelegramService()
        await service.start()
        let chats = try await service.chats(limit: 10)
        XCTAssertFalse(chats.isEmpty)

        let first = try XCTUnwrap(chats.first)
        let messages = try await service.messages(chatID: first.id, limit: 10)
        XCTAssertFalse(messages.isEmpty)
        XCTAssertTrue(messages.allSatisfy { $0.chatID == first.id })
    }

    func testSendingTextAppearsInHistory() async throws {
        let service = MockTelegramService()
        await service.start()
        try await service.sendText("привет из теста", to: 2)
        let messages = try await service.messages(chatID: 2, limit: 50)
        XCTAssertEqual(messages.last?.text, "привет из теста")
        XCTAssertEqual(messages.last?.isOutgoing, true)
    }

    func testChatInitialsAndColorIndex() {
        let chat = ChatSummary(id: 12, title: "Анна Рахим")
        XCTAssertEqual(chat.initials, "АР")
        XCTAssertTrue((0..<7).contains(chat.colorIndex))
    }
}
