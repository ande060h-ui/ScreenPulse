// API key storage. The key lives in the macOS Keychain, never in a plain-text preferences file.

import Foundation
import Security

enum KeyStore {
    private static let service = AppInfo.bundleID
    private static let account = "GEMINI_API_KEY"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    /// The key saved by the user in Settings (Keychain).
    static func loadStored() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty {
            return key
        }
        return nil
    }

    /// Key used for requests: Keychain → environment → .env (development builds).
    static func load() -> String? {
        if let k = loadStored() { return k }
        if let k = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !k.isEmpty { return k }
        return projectEnvValue("GEMINI_API_KEY")
    }

    /// Saves the key to the Keychain. An empty string removes it.
    @discardableResult
    static func save(_ key: String) -> Bool {
        SecItemDelete(baseQuery as CFDictionary)
        guard !key.isEmpty else { return true }
        var attrs = baseQuery
        attrs[kSecValueData as String] = Data(key.utf8)
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }
}
