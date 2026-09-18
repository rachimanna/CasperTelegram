#if canImport(TDLibFramework)
import Foundation
import TDLibFramework

/// Тонкая обёртка над C-API tdjson (интерфейс с client_id):
///
///     int  td_create_client_id();
///     void td_send(int client_id, const char *request);
///     const char *td_receive(double timeout);
///     const char *td_execute(const char *request);
///
/// Ответы на запросы находим по полю `@extra`, всё остальное считаем
/// обновлением и отдаём в `onUpdate`.
final class TDLibJSONClient {
    typealias JSONObject = [String: Any]

    private var clientID: Int32 = 0
    private let receiveQueue = DispatchQueue(label: "app.casper.tdlib.receive", qos: .utility)
    private let lock = NSLock()
    private var handlers: [String: (Result<JSONObject, Error>) -> Void] = [:]
    private var counter: UInt64 = 0
    private var isRunning = false

    /// Вызывается на очереди receiveQueue — переводите в main сами.
    var onUpdate: ((JSONObject) -> Void)?

    init() {
        clientID = td_create_client_id()
    }

    deinit { isRunning = false }

    // MARK: Цикл получения

    func start() {
        lock.lock()
        let alreadyRunning = isRunning
        isRunning = true
        lock.unlock()
        guard !alreadyRunning else { return }

        receiveQueue.async { [weak self] in
            while true {
                guard let self else { return }
                self.lock.lock()
                let running = self.isRunning
                self.lock.unlock()
                guard running else { return }

                guard let pointer = td_receive(1.0) else { continue }
                let raw = String(cString: pointer)
                self.handle(raw: raw)
            }
        }
    }

    func stop() {
        lock.lock()
        isRunning = false
        lock.unlock()
    }

    // MARK: Отправка

    /// Запрос без ожидания ответа.
    func send(_ request: JSONObject) {
        guard let json = Self.string(from: request) else { return }
        json.withCString { td_send(clientID, $0) }
    }

    /// Запрос с ожиданием ответа.
    func request(_ request: JSONObject) async throws -> JSONObject {
        let extra = nextExtra()
        var payload = request
        payload["@extra"] = extra

        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            handlers[extra] = { result in continuation.resume(with: result) }
            lock.unlock()
            send(payload)
        }
    }

    /// Синхронные методы TDLib (setLogVerbosityLevel, getTextEntities и т. п.).
    static func executeSynchronously(_ request: JSONObject) -> JSONObject? {
        guard let json = string(from: request) else { return nil }
        let result: UnsafePointer<CChar>? = json.withCString { td_execute($0) }
        guard let result else { return nil }
        return object(from: String(cString: result))
    }

    // MARK: Разбор входящего

    private func handle(raw: String) {
        guard let object = Self.object(from: raw) else { return }

        if let extra = object["@extra"] as? String {
            lock.lock()
            let handler = handlers.removeValue(forKey: extra)
            lock.unlock()

            if let handler {
                if (object["@type"] as? String) == "error" {
                    let code = (object["code"] as? NSNumber)?.intValue ?? 0
                    let message = (object["message"] as? String) ?? "unknown"
                    handler(.failure(TelegramError.api(code: code, message: message)))
                } else {
                    handler(.success(object))
                }
                return
            }
        }

        onUpdate?(object)
    }

    private func nextExtra() -> String {
        lock.lock()
        counter += 1
        let value = counter
        lock.unlock()
        return "casper-\(value)"
    }

    private static func string(from object: JSONObject) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: []) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func object(from string: String) -> JSONObject? {
        guard let data = string.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data, options: []) as? JSONObject
        else { return nil }
        return parsed
    }
}

// MARK: - Удобный разбор JSON от TDLib

/// TDLib передаёт `int53` числом, а `int64` — строкой, поэтому читаем оба варианта.
extension Dictionary where Key == String, Value == Any {
    var tdType: String { (self["@type"] as? String) ?? "" }

    func tdString(_ key: String) -> String? { self[key] as? String }

    func tdInt(_ key: String) -> Int? { (self[key] as? NSNumber)?.intValue }

    func tdInt64(_ key: String) -> Int64? {
        if let number = self[key] as? NSNumber { return number.int64Value }
        if let text = self[key] as? String { return Int64(text) }
        return nil
    }

    func tdBool(_ key: String) -> Bool { (self[key] as? NSNumber)?.boolValue ?? false }

    func tdObject(_ key: String) -> [String: Any]? { self[key] as? [String: Any] }

    func tdArray(_ key: String) -> [[String: Any]] { (self[key] as? [[String: Any]]) ?? [] }

    func tdDate(_ key: String) -> Date? {
        guard let seconds = tdInt(key), seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }
}
#endif
