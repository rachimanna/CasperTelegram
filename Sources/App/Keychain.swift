import Foundation
import Security

/// Все пользовательские секреты (ключи внешних сервисов, ключ шифрования
/// локальной базы) лежат в Keychain, а не в UserDefaults и не в файлах.
enum Keychain {
    private static let service = "app.casper.telegram"

    enum Failure: LocalizedError {
        case status(OSStatus)

        var errorDescription: String? {
            switch self {
            case .status(let code):
                let message = SecCopyErrorMessageString(code, nil) as String? ?? "код \(code)"
                return "Keychain: \(message)"
            }
        }
    }

    static func setData(_ data: Data, for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure.status(status) }
    }

    static func data(for key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    static func setString(_ value: String, for key: String) throws {
        guard let data = value.data(using: .utf8) else { return }
        try setData(data, for: key)
    }

    static func string(for key: String) -> String? {
        guard let data = data(for: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Ключ шифрования локальной базы TDLib. Генерируется один раз на устройстве
/// и хранится в Keychain, поэтому база бесполезна без самого устройства.
enum DatabaseKey {
    private static let keychainKey = "tdlib.database.key"

    static func base64Key() -> String {
        if let existing = Keychain.data(for: keychainKey) {
            return existing.base64EncodedString()
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let data = status == errSecSuccess ? Data(bytes) : Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        try? Keychain.setData(data, for: keychainKey)
        return data.base64EncodedString()
    }
}
