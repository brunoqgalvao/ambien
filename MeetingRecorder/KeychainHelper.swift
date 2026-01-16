import Foundation
import Security

/// Helper for storing and retrieving API keys from macOS Keychain
enum KeychainHelper {
    private static let service = "com.meetingrecorder.app"

    /// Save a value to the keychain
    /// - Parameters:
    ///   - key: The key identifier
    ///   - value: The value to store
    /// - Returns: true if successful
    static func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Delete any existing item first
        _ = delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Read a value from the keychain
    /// - Parameter key: The key identifier
    /// - Returns: The stored value, or nil if not found
    static func read(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    /// Delete a value from the keychain
    /// - Parameter key: The key identifier
    /// - Returns: true if successful or item didn't exist
    static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Update an existing keychain item
    /// - Parameters:
    ///   - key: The key identifier
    ///   - value: The new value
    /// - Returns: true if successful
    static func update(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        return status == errSecSuccess
    }

    /// Check if a key exists in the keychain
    /// - Parameter key: The key identifier
    /// - Returns: true if the key exists
    static func exists(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: false
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
}

// MARK: - Convenience for API Keys

extension KeychainHelper {
    static let openAIKeyName = "openai-api-key"

    /// Save the OpenAI API key
    static func saveOpenAIKey(_ key: String) -> Bool {
        save(key: openAIKeyName, value: key)
    }

    /// Read the OpenAI API key (Keychain first, then env var fallback)
    static func readOpenAIKey() -> String? {
        // First try Keychain
        if let keychainKey = read(key: openAIKeyName), !keychainKey.isEmpty {
            return keychainKey
        }

        // Fallback to environment variable
        if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !envKey.isEmpty {
            print("[KeychainHelper] Using OPENAI_API_KEY from environment")
            return envKey
        }

        return nil
    }

    /// Delete the OpenAI API key
    static func deleteOpenAIKey() -> Bool {
        delete(key: openAIKeyName)
    }
}
