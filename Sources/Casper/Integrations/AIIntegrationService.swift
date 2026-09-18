import Foundation

/// Подключение внешнего AI-сервиса с OpenAI-совместимым API.
///
/// Зачем это в Casper: расшифровка и перевод голосовых сообщений.
/// Сам Voice Changer работает локально и никакого ключа не требует.
///
/// Ключ пользователя хранится в Keychain. В репозитории ключей нет и быть
/// не может — см. docs/SECRETS.md.
final class AIIntegrationService: ObservableObject {
    enum Status: Equatable {
        case unknown
        case checking
        case connected(models: Int)
        case failed(String)
    }

    static let keychainKey = "integration.ai.apiKey"

    @Published private(set) var status: Status = .unknown

    var hasKey: Bool { Keychain.string(for: Self.keychainKey)?.isEmpty == false }

    func storeKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            removeKey()
            return
        }
        try Keychain.setString(trimmed, for: Self.keychainKey)
        status = .unknown
    }

    func removeKey() {
        Keychain.remove(Self.keychainKey)
        status = .unknown
    }

    /// Настоящая проверка: запрашиваем список моделей у провайдера.
    @MainActor
    @discardableResult
    func check(baseURL: String) async -> Status {
        guard let key = Keychain.string(for: Self.keychainKey), !key.isEmpty else {
            status = .failed("Сначала введите ключ")
            return status
        }
        let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmedBase + "/models") else {
            status = .failed("Некорректный адрес сервиса")
            return status
        }

        status = .checking

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                status = .failed("Непонятный ответ сервиса")
                return status
            }
            guard (200..<300).contains(http.statusCode) else {
                status = .failed("Сервис ответил \(http.statusCode)")
                return status
            }
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let models = (object?["data"] as? [[String: Any]])?.count ?? 0
            status = .connected(models: models)
        } catch {
            status = .failed(error.localizedDescription)
        }
        return status
    }
}
