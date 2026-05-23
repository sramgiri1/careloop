import Foundation
import Security

enum KeychainStore {
    private static let service = "com.careloop.ios"

    static func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query = baseQuery(for: key)

        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return value
    }

    static func remove(_ key: String) {
        SecItemDelete(baseQuery(for: key) as CFDictionary)
    }

    private static func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
