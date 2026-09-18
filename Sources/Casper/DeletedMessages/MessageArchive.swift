import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Локальный архив Casper.
///
/// Что делает: складывает в свою базу на устройстве те сообщения, которые
/// приложение и так получило обычным путём, и помечает их, когда Telegram
/// присылает `updateDeleteMessages`.
///
/// Чего НЕ делает и не может делать:
/// * не запрашивает у сервера сообщения, которых не получал;
/// * не восстанавливает удалённое, пока приложение было выключено;
/// * никогда не трогает секретные чаты (они и не включены в TDLib-параметрах).
final class MessageArchive {
    struct Record: Identifiable, Equatable {
        var chatID: Int64
        var messageID: Int64
        var chatTitle: String
        var sender: String
        var text: String
        var kind: MessageKind
        var date: Date
        var isOutgoing: Bool
        var deletedAt: Date?

        var id: String { "\(chatID):\(messageID)" }
    }

    struct Stats: Equatable {
        var stored = 0
        var deleted = 0
    }

    enum Failure: LocalizedError {
        case sqlite(String)

        var errorDescription: String? {
            switch self {
            case .sqlite(let message): return "Локальный архив: \(message)"
            }
        }
    }

    private static let schema = """
    CREATE TABLE IF NOT EXISTS messages (
        chat_id     INTEGER NOT NULL,
        message_id  INTEGER NOT NULL,
        chat_title  TEXT    NOT NULL DEFAULT '',
        sender      TEXT    NOT NULL DEFAULT '',
        text        TEXT    NOT NULL DEFAULT '',
        kind        TEXT    NOT NULL DEFAULT 'text',
        date        INTEGER NOT NULL,
        is_outgoing INTEGER NOT NULL DEFAULT 0,
        deleted_at  INTEGER,
        PRIMARY KEY (chat_id, message_id)
    );
    CREATE INDEX IF NOT EXISTS idx_messages_deleted ON messages(deleted_at DESC);
    CREATE INDEX IF NOT EXISTS idx_messages_date ON messages(date DESC);
    """

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "app.casper.archive")

    init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK, let opened = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "не удалось открыть базу"
            sqlite3_close_v2(handle)
            throw Failure.sqlite(message)
        }
        db = opened
        try run("PRAGMA journal_mode=WAL;")
        try run(Self.schema)

        // Файл базы читается только после первой разблокировки устройства.
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUnlessOpen],
            ofItemAtPath: path
        )
    }

    deinit {
        sqlite3_close_v2(db)
    }

    // MARK: Запись

    func store(_ message: TelegramMessage, chatTitle: String) {
        queue.sync {
            let sql = """
            INSERT INTO messages (chat_id, message_id, chat_title, sender, text, kind, date, is_outgoing, deleted_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL)
            ON CONFLICT(chat_id, message_id) DO UPDATE SET
                text = excluded.text,
                kind = excluded.kind,
                sender = excluded.sender,
                chat_title = excluded.chat_title;
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_int64(statement, 1, message.chatID)
            sqlite3_bind_int64(statement, 2, message.id)
            bindText(statement, 3, chatTitle)
            bindText(statement, 4, message.senderName)
            bindText(statement, 5, message.text)
            bindText(statement, 6, message.kind.storageKey)
            sqlite3_bind_int64(statement, 7, Int64(message.date.timeIntervalSince1970))
            sqlite3_bind_int(statement, 8, message.isOutgoing ? 1 : 0)
            sqlite3_step(statement)
        }
    }

    /// Помечает сообщения удалёнными. Возвращает только те записи,
    /// которые действительно были у нас — остальное Casper не видел.
    func markDeleted(chatID: Int64, messageIDs: [Int64], at date: Date = Date()) -> [Record] {
        queue.sync {
            var result: [Record] = []
            for messageID in messageIDs {
                guard var record = fetch(chatID: chatID, messageID: messageID), record.deletedAt == nil else { continue }

                var statement: OpaquePointer?
                let sql = "UPDATE messages SET deleted_at = ? WHERE chat_id = ? AND message_id = ?;"
                if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                    sqlite3_bind_int64(statement, 1, Int64(date.timeIntervalSince1970))
                    sqlite3_bind_int64(statement, 2, chatID)
                    sqlite3_bind_int64(statement, 3, messageID)
                    sqlite3_step(statement)
                }
                sqlite3_finalize(statement)

                record.deletedAt = date
                result.append(record)
            }
            return result
        }
    }

    // MARK: Чтение

    func deletedRecords(limit: Int = 200) -> [Record] {
        queue.sync {
            select("SELECT * FROM messages WHERE deleted_at IS NOT NULL ORDER BY deleted_at DESC LIMIT \(max(1, limit));")
        }
    }

    func stats() -> Stats {
        queue.sync {
            Stats(stored: count(where: nil), deleted: count(where: "deleted_at IS NOT NULL"))
        }
    }

    // MARK: Очистка

    /// Удаляет всё старше указанного числа дней. Возвращает число удалённых строк.
    @discardableResult
    func purge(olderThanDays days: Int, now: Date = Date()) -> Int {
        guard days > 0 else { return 0 }
        return queue.sync {
            let cutoff = Int64(now.addingTimeInterval(-Double(days) * 86_400).timeIntervalSince1970)
            var statement: OpaquePointer?
            let sql = "DELETE FROM messages WHERE date < ?;"
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, cutoff)
            sqlite3_step(statement)
            return Int(sqlite3_changes(db))
        }
    }

    func clear() {
        queue.sync {
            try? run("DELETE FROM messages;")
        }
    }

    func removeRecord(chatID: Int64, messageID: Int64) {
        queue.sync {
            var statement: OpaquePointer?
            let sql = "DELETE FROM messages WHERE chat_id = ? AND message_id = ?;"
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, chatID)
            sqlite3_bind_int64(statement, 2, messageID)
            sqlite3_step(statement)
        }
    }

    // MARK: Низкий уровень

    private func run(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? "неизвестная ошибка"
            sqlite3_free(errorPointer)
            throw Failure.sqlite(message)
        }
    }

    private func bindText(_ statement: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(statement, index, (value as NSString).utf8String, -1, SQLITE_TRANSIENT)
    }

    private func fetch(chatID: Int64, messageID: Int64) -> Record? {
        var statement: OpaquePointer?
        let sql = "SELECT * FROM messages WHERE chat_id = ? AND message_id = ? LIMIT 1;"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, chatID)
        sqlite3_bind_int64(statement, 2, messageID)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return record(from: statement)
    }

    private func select(_ sql: String) -> [Record] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var result: [Record] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let item = record(from: statement) { result.append(item) }
        }
        return result
    }

    private func count(where condition: String?) -> Int {
        let sql = "SELECT COUNT(*) FROM messages" + (condition.map { " WHERE \($0)" } ?? "") + ";"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    /// Порядок колонок соответствует схеме таблицы.
    private func record(from statement: OpaquePointer?) -> Record? {
        func text(_ index: Int32) -> String {
            guard let pointer = sqlite3_column_text(statement, index) else { return "" }
            return String(cString: pointer)
        }

        let deletedAtRaw = sqlite3_column_type(statement, 8) == SQLITE_NULL
            ? nil
            : Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 8)))

        return Record(chatID: sqlite3_column_int64(statement, 0),
                      messageID: sqlite3_column_int64(statement, 1),
                      chatTitle: text(2),
                      sender: text(3),
                      text: text(4),
                      kind: MessageKind.fromStorageKey(text(5)),
                      date: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 6))),
                      isOutgoing: sqlite3_column_int(statement, 7) == 1,
                      deletedAt: deletedAtRaw)
    }
}
