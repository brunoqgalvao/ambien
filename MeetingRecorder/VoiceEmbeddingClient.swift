//
//  VoiceEmbeddingClient.swift
//  MeetingRecorder
//
//  Client for the voice embedding service - extracts speaker embeddings
//  and compares them to identify speakers across meetings
//

import Foundation

// MARK: - Voice Embedding Client

/// Client for the voice embedding microservice
/// Extracts 256-dim speaker embeddings and compares them
actor VoiceEmbeddingClient {
    static let shared = VoiceEmbeddingClient()

    private var baseURL: URL?
    private var apiKey: String?

    /// Similarity threshold for same-speaker detection
    let sameSpeakerThreshold: Float = 0.75

    private init() {}

    // MARK: - Configuration

    /// Configure the client with server URL and API key
    func configure(baseURL: String, apiKey: String) {
        self.baseURL = URL(string: baseURL)
        self.apiKey = apiKey
        logInfo("[VoiceEmbeddingClient] Configured with base URL: \(baseURL)")
    }

    /// Check if client is configured
    var isConfigured: Bool {
        baseURL != nil && apiKey != nil && !apiKey!.isEmpty
    }

    /// Load configuration from UserDefaults/Keychain
    func loadConfiguration() {
        let url = UserDefaults.standard.string(forKey: "voiceEmbeddingServiceURL") ?? ""
        let key = KeychainHelper.readVoiceEmbeddingKey() ?? ""

        if !url.isEmpty && !key.isEmpty {
            configure(baseURL: url, apiKey: key)
        }
    }

    // MARK: - Health Check

    /// Check if the service is available
    func healthCheck() async -> Bool {
        guard let baseURL = baseURL else { return false }

        do {
            var request = URLRequest(url: baseURL.appendingPathComponent("health"))
            request.httpMethod = "GET"
            request.timeoutInterval = 5

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
            }

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = json["status"] as? String {
                return status == "healthy"
            }
            return false
        } catch {
            logError("[VoiceEmbeddingClient] Health check failed: \(error)")
            return false
        }
    }

    // MARK: - Extract Embedding

    /// Extract a 256-dimensional speaker embedding from audio data
    /// - Parameters:
    ///   - audioData: Raw audio data (WAV preferred, but service handles conversion)
    ///   - format: Audio format hint (e.g., "wav", "m4a")
    /// - Returns: 256-dimensional embedding vector
    func extractEmbedding(audioData: Data, format: String = "wav") async throws -> [Float] {
        guard let baseURL = baseURL, let apiKey = apiKey else {
            throw VoiceEmbeddingError.notConfigured
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("extract-embedding"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = 60 // Embeddings can take time

        let body: [String: Any] = [
            "audio_base64": audioData.base64EncodedString(),
            "format": format
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw VoiceEmbeddingError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw VoiceEmbeddingError.unauthorized
        }

        if httpResponse.statusCode != 200 {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = errorJson["detail"] as? String {
                throw VoiceEmbeddingError.serverError(detail)
            }
            throw VoiceEmbeddingError.serverError("HTTP \(httpResponse.statusCode)")
        }

        let embeddingResponse = try JSONDecoder().decode(EmbeddingResponse.self, from: data)
        return embeddingResponse.embedding
    }

    /// Extract embedding from an audio file path
    func extractEmbedding(fromFile path: String) async throws -> [Float] {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let format = url.pathExtension.lowercased()
        return try await extractEmbedding(audioData: data, format: format)
    }

    // MARK: - Compare Embeddings

    /// Compare two embeddings and determine if they're the same speaker
    func compareSpeakers(embedding1: [Float], embedding2: [Float]) async throws -> SpeakerComparisonResult {
        guard let baseURL = baseURL, let apiKey = apiKey else {
            throw VoiceEmbeddingError.notConfigured
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("compare-embeddings"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        let body: [String: Any] = [
            "embedding1": embedding1,
            "embedding2": embedding2
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw VoiceEmbeddingError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = errorJson["detail"] as? String {
                throw VoiceEmbeddingError.serverError(detail)
            }
            throw VoiceEmbeddingError.serverError("HTTP \(httpResponse.statusCode)")
        }

        return try JSONDecoder().decode(SpeakerComparisonResult.self, from: data)
    }

    /// Compare embedding against a list of known speaker profiles
    /// Returns the best match if above threshold, nil otherwise
    func findMatchingSpeaker(
        embedding: [Float],
        knownProfiles: [SpeakerProfile]
    ) async throws -> (profile: SpeakerProfile, similarity: Float)? {
        var bestMatch: (profile: SpeakerProfile, similarity: Float)?

        for profile in knownProfiles {
            let result = try await compareSpeakers(embedding1: embedding, embedding2: profile.embedding)

            if result.similarity >= sameSpeakerThreshold {
                if bestMatch == nil || result.similarity > bestMatch!.similarity {
                    bestMatch = (profile, result.similarity)
                }
            }
        }

        return bestMatch
    }

    // MARK: - Local Comparison (No Network)

    /// Compute cosine similarity locally (no network call)
    func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }

        return dotProduct / denominator
    }

    /// Find best matching speaker profile locally (no network)
    func findMatchingSpeakerLocally(
        embedding: [Float],
        knownProfiles: [SpeakerProfile]
    ) -> (profile: SpeakerProfile, similarity: Float)? {
        var bestMatch: (profile: SpeakerProfile, similarity: Float)?

        for profile in knownProfiles {
            let similarity = cosineSimilarity(embedding, profile.embedding)

            if similarity >= sameSpeakerThreshold {
                if bestMatch == nil || similarity > bestMatch!.similarity {
                    bestMatch = (profile, similarity)
                }
            }
        }

        return bestMatch
    }
}

// MARK: - Response Types

struct EmbeddingResponse: Codable {
    let embedding: [Float]
    let dimension: Int
}

struct SpeakerComparisonResult: Codable {
    let similarity: Float
    let isSameSpeaker: Bool

    enum CodingKeys: String, CodingKey {
        case similarity
        case isSameSpeaker = "is_same_speaker"
    }
}

// MARK: - Errors

enum VoiceEmbeddingError: LocalizedError {
    case notConfigured
    case invalidResponse
    case unauthorized
    case serverError(String)
    case audioProcessingFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Voice embedding service not configured"
        case .invalidResponse:
            return "Invalid response from voice embedding service"
        case .unauthorized:
            return "Invalid API key for voice embedding service"
        case .serverError(let message):
            return "Voice embedding service error: \(message)"
        case .audioProcessingFailed(let message):
            return "Audio processing failed: \(message)"
        }
    }
}

// MARK: - Keychain Helper Extension

extension KeychainHelper {
    static let voiceEmbeddingKeyName = "voice-embedding-api-key"

    static func readVoiceEmbeddingKey() -> String? {
        read(key: voiceEmbeddingKeyName)
    }

    static func saveVoiceEmbeddingKey(_ key: String) -> Bool {
        save(key: voiceEmbeddingKeyName, value: key)
    }

    static func deleteVoiceEmbeddingKey() -> Bool {
        delete(key: voiceEmbeddingKeyName)
    }
}
