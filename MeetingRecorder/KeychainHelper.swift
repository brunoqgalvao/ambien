import Foundation
import Security

/// Helper for storing and retrieving API keys from macOS Keychain
enum KeychainHelper {
    private static let service = "com.ambient.app"

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

// MARK: - Transcription Provider Definition

/// Supported transcription API providers
/// Order reflects priority: AssemblyAI (most reliable) > Gemini > OpenAI > Deepgram
enum TranscriptionProvider: String, CaseIterable, Identifiable {
    case assemblyai = "assemblyai"
    case gemini = "gemini"
    case openai = "openai"
    case deepgram = "deepgram"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .gemini: return "Google Gemini"
        case .assemblyai: return "AssemblyAI"
        case .deepgram: return "Deepgram"
        }
    }

    var icon: String {
        switch self {
        case .openai: return "brain.head.profile"
        case .gemini: return "sparkles"
        case .assemblyai: return "waveform"
        case .deepgram: return "mic.badge.plus"
        }
    }

    var apiKeyURL: URL? {
        switch self {
        case .openai: return URL(string: "https://platform.openai.com/api-keys")
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")
        case .assemblyai: return URL(string: "https://www.assemblyai.com/dashboard")
        case .deepgram: return URL(string: "https://console.deepgram.com")
        }
    }

    var description: String {
        switch self {
        case .assemblyai: return "Most reliable. Native diarization. Recommended."
        case .gemini: return "Fast with native diarization. Good for long meetings."
        case .openai: return "Good for short meetings (<25MB). Limited file size."
        case .deepgram: return "Fast and affordable. Good for long recordings."
        }
    }

    var isRecommended: Bool {
        self == .assemblyai  // AssemblyAI is the most reliable
    }

    /// Keychain key for storing the API key
    var keychainKey: String {
        "\(rawValue)-api-key"
    }

    /// Environment variable name fallback
    var envVarName: String {
        switch self {
        case .openai: return "OPENAI_API_KEY"
        case .gemini: return "GEMINI_API_KEY"
        case .assemblyai: return "ASSEMBLYAI_API_KEY"
        case .deepgram: return "DEEPGRAM_API_KEY"
        }
    }

    /// Check if this provider has an API key configured
    var isConfigured: Bool {
        KeychainHelper.hasKey(for: self)
    }

    /// Available models for this provider
    var models: [TranscriptionModelOption] {
        switch self {
        case .openai:
            return [
                TranscriptionModelOption(
                    id: "gpt-4o-mini-transcribe",
                    displayName: "GPT-4o Mini Transcribe",
                    costPerMinute: 0.003,
                    provider: self
                ),
                TranscriptionModelOption(
                    id: "whisper-1",
                    displayName: "Whisper",
                    costPerMinute: 0.006,
                    provider: self
                )
            ]
        case .gemini:
            return [
                TranscriptionModelOption(
                    id: "gemini-2.5-flash",
                    displayName: "Gemini 2.5 Flash",
                    costPerMinute: 0.0003,  // ~based on token pricing
                    provider: self
                )
            ]
        case .assemblyai:
            return [
                TranscriptionModelOption(
                    id: "universal",
                    displayName: "Universal",
                    costPerMinute: 0.0025,
                    provider: self
                ),
                TranscriptionModelOption(
                    id: "slam-1",
                    displayName: "SLAM-1",
                    costPerMinute: 0.0045,
                    provider: self
                )
            ]
        case .deepgram:
            return [
                TranscriptionModelOption(
                    id: "nova-3",
                    displayName: "Nova 3",
                    costPerMinute: 0.0043,
                    provider: self
                )
            ]
        }
    }

    /// Maximum file size in bytes for this provider
    var maxFileSize: Int64 {
        switch self {
        case .openai:
            return 25 * 1024 * 1024  // 25MB
        case .gemini:
            return 2 * 1024 * 1024 * 1024  // 2GB (inline data limit)
        case .assemblyai:
            return 5 * 1024 * 1024 * 1024  // 5GB
        case .deepgram:
            return 2 * 1024 * 1024 * 1024  // 2GB
        }
    }

    /// Maximum duration in seconds for this provider
    var maxDuration: TimeInterval {
        switch self {
        case .openai:
            return 4 * 60 * 60  // ~4 hours (limited by file size)
        case .gemini:
            return 8 * 60 * 60  // 8 hours
        case .assemblyai:
            return 10 * 60 * 60  // 10 hours
        case .deepgram:
            return 2 * 60 * 60  // 2 hours per file
        }
    }

    /// Human-readable file size limit
    var maxFileSizeFormatted: String {
        let mb = maxFileSize / (1024 * 1024)
        if mb >= 1024 {
            return "\(mb / 1024)GB"
        }
        return "\(mb)MB"
    }

    /// Human-readable duration limit
    var maxDurationFormatted: String {
        let hours = Int(maxDuration / 3600)
        if hours == 1 {
            return "1 hour"
        }
        return "\(hours) hours"
    }
}

/// A transcription model option with pricing and provider info
struct TranscriptionModelOption: Identifiable, Hashable {
    let id: String
    let displayName: String
    let costPerMinute: Double  // in dollars
    let provider: TranscriptionProvider

    /// Cost formatted as string (e.g., "$0.003/min")
    var formattedCost: String {
        if costPerMinute < 0.001 {
            return String(format: "$%.4f/min", costPerMinute)
        } else {
            return String(format: "$%.3f/min", costPerMinute)
        }
    }

    /// Unique identifier combining provider and model
    var fullId: String {
        "\(provider.rawValue):\(id)"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(provider)
    }

    static func == (lhs: TranscriptionModelOption, rhs: TranscriptionModelOption) -> Bool {
        lhs.id == rhs.id && lhs.provider == rhs.provider
    }

    /// Find a model by its full ID (provider:model)
    static func find(byFullId fullId: String) -> TranscriptionModelOption? {
        let parts = fullId.split(separator: ":")
        guard parts.count == 2,
              let provider = TranscriptionProvider.allCases.first(where: { $0.rawValue == String(parts[0]) }) else {
            return nil
        }
        return provider.models.first { $0.id == String(parts[1]) }
    }

    /// Get all available models across all providers
    static var allModels: [TranscriptionModelOption] {
        TranscriptionProvider.allCases.flatMap { $0.models }
    }

    /// Get all models from configured providers
    static var configuredModels: [TranscriptionModelOption] {
        TranscriptionProvider.allCases
            .filter { $0.isConfigured }
            .flatMap { $0.models }
    }

    /// Default model (AssemblyAI if available, else Gemini, else OpenAI, else first configured)
    static var defaultModel: TranscriptionModelOption? {
        // Prefer AssemblyAI if configured (most reliable + native diarization)
        if TranscriptionProvider.assemblyai.isConfigured {
            return TranscriptionProvider.assemblyai.models.first
        }
        // Fall back to Gemini if configured (fast with native diarization)
        if TranscriptionProvider.gemini.isConfigured {
            return TranscriptionProvider.gemini.models.first
        }
        // Fall back to OpenAI if configured
        if TranscriptionProvider.openai.isConfigured {
            return TranscriptionProvider.openai.models.first
        }
        // Otherwise first configured provider's first model
        return configuredModels.first
    }
}

// MARK: - Convenience for API Keys

extension KeychainHelper {
    static let openAIKeyName = "openai-api-key"
    static let geminiKeyName = "gemini-api-key"
    static let assemblyAIKeyName = "assemblyai-api-key"
    static let deepgramKeyName = "deepgram-api-key"
    static let anthropicKeyName = "anthropic-api-key"

    // MARK: - OpenAI

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

    // MARK: - Gemini

    /// Save the Gemini API key
    static func saveGeminiKey(_ key: String) -> Bool {
        save(key: geminiKeyName, value: key)
    }

    /// Read the Gemini API key (Keychain first, then env var fallback)
    static func readGeminiKey() -> String? {
        if let keychainKey = read(key: geminiKeyName), !keychainKey.isEmpty {
            return keychainKey
        }
        if let envKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !envKey.isEmpty {
            print("[KeychainHelper] Using GEMINI_API_KEY from environment")
            return envKey
        }
        return nil
    }

    /// Delete the Gemini API key
    static func deleteGeminiKey() -> Bool {
        delete(key: geminiKeyName)
    }

    // MARK: - AssemblyAI

    /// Save the AssemblyAI API key
    static func saveAssemblyAIKey(_ key: String) -> Bool {
        save(key: assemblyAIKeyName, value: key)
    }

    /// Read the AssemblyAI API key (Keychain first, then env var fallback)
    static func readAssemblyAIKey() -> String? {
        if let keychainKey = read(key: assemblyAIKeyName), !keychainKey.isEmpty {
            return keychainKey
        }
        if let envKey = ProcessInfo.processInfo.environment["ASSEMBLYAI_API_KEY"], !envKey.isEmpty {
            print("[KeychainHelper] Using ASSEMBLYAI_API_KEY from environment")
            return envKey
        }
        return nil
    }

    /// Delete the AssemblyAI API key
    static func deleteAssemblyAIKey() -> Bool {
        delete(key: assemblyAIKeyName)
    }

    // MARK: - Deepgram

    /// Save the Deepgram API key
    static func saveDeepgramKey(_ key: String) -> Bool {
        save(key: deepgramKeyName, value: key)
    }

    /// Read the Deepgram API key (Keychain first, then env var fallback)
    static func readDeepgramKey() -> String? {
        if let keychainKey = read(key: deepgramKeyName), !keychainKey.isEmpty {
            return keychainKey
        }
        if let envKey = ProcessInfo.processInfo.environment["DEEPGRAM_API_KEY"], !envKey.isEmpty {
            print("[KeychainHelper] Using DEEPGRAM_API_KEY from environment")
            return envKey
        }
        return nil
    }

    /// Delete the Deepgram API key
    static func deleteDeepgramKey() -> Bool {
        delete(key: deepgramKeyName)
    }

    // MARK: - Anthropic (for chat)

    /// Save the Anthropic API key
    static func saveAnthropicKey(_ key: String) -> Bool {
        save(key: anthropicKeyName, value: key)
    }

    /// Read the Anthropic API key
    static func readAnthropicKey() -> String? {
        if let keychainKey = read(key: anthropicKeyName), !keychainKey.isEmpty {
            return keychainKey
        }
        if let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !envKey.isEmpty {
            print("[KeychainHelper] Using ANTHROPIC_API_KEY from environment")
            return envKey
        }
        return nil
    }

    /// Delete the Anthropic API key
    static func deleteAnthropicKey() -> Bool {
        delete(key: anthropicKeyName)
    }

    // MARK: - Generic Provider Methods

    /// Save API key for a given provider
    static func saveKey(for provider: TranscriptionProvider, key: String) -> Bool {
        switch provider {
        case .openai: return saveOpenAIKey(key)
        case .gemini: return saveGeminiKey(key)
        case .assemblyai: return saveAssemblyAIKey(key)
        case .deepgram: return saveDeepgramKey(key)
        }
    }

    /// Read API key for a given provider
    static func readKey(for provider: TranscriptionProvider) -> String? {
        switch provider {
        case .openai: return readOpenAIKey()
        case .gemini: return readGeminiKey()
        case .assemblyai: return readAssemblyAIKey()
        case .deepgram: return readDeepgramKey()
        }
    }

    /// Delete API key for a given provider
    static func deleteKey(for provider: TranscriptionProvider) -> Bool {
        switch provider {
        case .openai: return deleteOpenAIKey()
        case .gemini: return deleteGeminiKey()
        case .assemblyai: return deleteAssemblyAIKey()
        case .deepgram: return deleteDeepgramKey()
        }
    }

    /// Check if a provider has a configured API key
    static func hasKey(for provider: TranscriptionProvider) -> Bool {
        readKey(for: provider) != nil
    }

    /// Get all providers that have configured API keys
    static func getAllConfiguredProviders() -> [TranscriptionProvider] {
        TranscriptionProvider.allCases.filter { hasKey(for: $0) }
    }

    /// Get the first available provider (AssemblyAI preferred, then Gemini, then OpenAI)
    static func getPreferredProvider() -> TranscriptionProvider? {
        // Prefer AssemblyAI if available (most reliable + native diarization)
        if hasKey(for: .assemblyai) { return .assemblyai }
        // Fall back to Gemini (fast with native diarization)
        if hasKey(for: .gemini) { return .gemini }
        // Fall back to OpenAI
        if hasKey(for: .openai) { return .openai }
        // Otherwise return first configured
        return getAllConfiguredProviders().first
    }
}
