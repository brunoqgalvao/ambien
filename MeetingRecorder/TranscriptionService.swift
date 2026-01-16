//
//  TranscriptionService.swift
//  MeetingRecorder
//
//  OpenAI API integration for audio transcription
//  Supports gpt-4o-mini-transcribe (default) and whisper-1 (fallback)
//

import Foundation

/// Errors that can occur during transcription
enum TranscriptionError: LocalizedError {
    case noAPIKey
    case invalidAPIKey
    case networkError(Error)
    case quotaExceeded
    case fileNotFound(String)
    case invalidResponse
    case serverError(Int, String)
    case fileTooLarge(Int64)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "OpenAI API key not found. Please add your API key in Settings."
        case .invalidAPIKey:
            return "Invalid API key. Please check your OpenAI API key."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .quotaExceeded:
            return "API quota exceeded. Please check your OpenAI billing."
        case .fileNotFound(let path):
            return "Audio file not found: \(path)"
        case .invalidResponse:
            return "Invalid response from OpenAI API"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .fileTooLarge(let size):
            return "File too large (\(size / 1_000_000)MB). Maximum is 25MB."
        }
    }
}

/// Model options for transcription
enum TranscriptionModel: String, CaseIterable {
    case gpt4oMiniTranscribe = "gpt-4o-mini-transcribe"
    case whisper1 = "whisper-1"

    var displayName: String {
        switch self {
        case .gpt4oMiniTranscribe: return "GPT-4o Mini Transcribe"
        case .whisper1: return "Whisper"
        }
    }

    /// Cost per minute in cents
    var costPerMinuteCents: Double {
        switch self {
        case .gpt4oMiniTranscribe: return 0.3  // $0.003/min
        case .whisper1: return 0.6  // $0.006/min
        }
    }
}

/// Response from verbose_json format including duration
struct TranscriptionResponse: Codable {
    let text: String
    let duration: Double?
    let language: String?
    let segments: [TranscriptionSegment]?
}

struct TranscriptionSegment: Codable {
    let id: Int
    let start: Double
    let end: Double
    let text: String
}

/// Result of a transcription including cost estimate
struct TranscriptionResult {
    let text: String
    let duration: TimeInterval
    let costCents: Int
    let model: TranscriptionModel
    let segments: [TranscriptionSegment]?
}

/// Result of a quick dictation transcription (optimized for latency)
struct DictationResult {
    let text: String
    let latency: TimeInterval
}

/// Service for transcribing audio via OpenAI API
actor TranscriptionService {
    private let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    private let maxFileSize: Int64 = 25 * 1024 * 1024  // 25MB limit

    /// Default model to use (whisper-1 is more reliable)
    var defaultModel: TranscriptionModel = .whisper1

    /// Transcribe an audio file
    /// - Parameters:
    ///   - audioPath: Path to the .m4a audio file
    ///   - model: Model to use (defaults to gpt-4o-mini-transcribe)
    /// - Returns: TranscriptionResult with text and cost
    func transcribe(audioPath: String, model: TranscriptionModel? = nil) async throws -> TranscriptionResult {
        // Get API key from Keychain
        guard let apiKey = KeychainHelper.readOpenAIKey() else {
            throw TranscriptionError.noAPIKey
        }

        // Verify file exists
        let fileURL = URL(fileURLWithPath: audioPath)
        guard FileManager.default.fileExists(atPath: audioPath) else {
            throw TranscriptionError.fileNotFound(audioPath)
        }

        // Check file size
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: audioPath)
        let fileSize = fileAttributes[.size] as? Int64 ?? 0
        guard fileSize <= maxFileSize else {
            throw TranscriptionError.fileTooLarge(fileSize)
        }

        // Read audio data
        let audioData = try Data(contentsOf: fileURL)

        let selectedModel = model ?? defaultModel

        // Build multipart form request
        let boundary = UUID().uuidString
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Build request body
        var body = Data()

        // Determine file extension and MIME type
        let fileExtension = fileURL.pathExtension.lowercased()
        let mimeType: String
        let filename: String
        switch fileExtension {
        case "wav":
            mimeType = "audio/wav"
            filename = "audio.wav"
        case "mp3":
            mimeType = "audio/mpeg"
            filename = "audio.mp3"
        case "m4a":
            mimeType = "audio/m4a"
            filename = "audio.m4a"
        default:
            mimeType = "audio/mpeg"
            filename = "audio.\(fileExtension)"
        }

        // File field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // Model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(selectedModel.rawValue)\r\n".data(using: .utf8)!)

        // Response format field (verbose_json for duration)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("verbose_json\r\n".data(using: .utf8)!)

        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        // Make request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        // Handle HTTP errors
        if httpResponse.statusCode != 200 {
            try handleHTTPError(statusCode: httpResponse.statusCode, data: data)
        }

        // Parse response
        let decoder = JSONDecoder()
        let transcriptionResponse = try decoder.decode(TranscriptionResponse.self, from: data)

        // Calculate cost based on duration
        let duration = transcriptionResponse.duration ?? estimateDuration(fileSize: fileSize)
        let durationMinutes = duration / 60.0
        let costCents = Int(ceil(durationMinutes * selectedModel.costPerMinuteCents))

        print("[TranscriptionService] Transcribed \(String(format: "%.1f", duration))s using \(selectedModel.displayName)")
        print("[TranscriptionService] Cost: \(costCents) cents (\(String(format: "%.2f", durationMinutes)) minutes)")

        return TranscriptionResult(
            text: transcriptionResponse.text,
            duration: duration,
            costCents: costCents,
            model: selectedModel,
            segments: transcriptionResponse.segments
        )
    }

    /// Estimate cost before transcription
    /// - Parameters:
    ///   - audioPath: Path to audio file
    ///   - model: Model to use
    /// - Returns: Estimated cost in cents
    func estimateCost(audioPath: String, model: TranscriptionModel? = nil) throws -> Int {
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: audioPath)
        let fileSize = fileAttributes[.size] as? Int64 ?? 0

        let duration = estimateDuration(fileSize: fileSize)
        let durationMinutes = duration / 60.0
        let selectedModel = model ?? defaultModel

        return Int(ceil(durationMinutes * selectedModel.costPerMinuteCents))
    }

    /// Validate that the API key works
    /// - Returns: true if the key is valid
    func validateAPIKey() async -> Bool {
        guard let apiKey = KeychainHelper.readOpenAIKey() else {
            return false
        }

        // Make a simple models request to validate the key
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            return httpResponse.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Quick Dictation Transcription

    /// Transcribe audio quickly for dictation (optimized for low latency)
    /// Uses whisper-1 which tends to have lower latency for short clips
    /// - Parameter audioPath: Path to the audio file
    /// - Returns: DictationResult with transcribed text and latency
    func transcribeDictation(audioPath: String) async throws -> DictationResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Get API key from Keychain
        guard let apiKey = KeychainHelper.readOpenAIKey() else {
            throw TranscriptionError.noAPIKey
        }

        // Verify file exists
        let fileURL = URL(fileURLWithPath: audioPath)
        guard FileManager.default.fileExists(atPath: audioPath) else {
            throw TranscriptionError.fileNotFound(audioPath)
        }

        // Read audio data
        let audioData = try Data(contentsOf: fileURL)

        // Use whisper-1 for dictation (lower latency)
        let model = TranscriptionModel.whisper1

        // Build multipart form request
        let boundary = UUID().uuidString
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30  // 30 second timeout for dictation

        // Build request body
        var body = Data()

        // Determine file extension and MIME type
        let fileExtension = fileURL.pathExtension.lowercased()
        let mimeType: String
        let filename: String
        switch fileExtension {
        case "wav":
            mimeType = "audio/wav"
            filename = "audio.wav"
        case "mp3":
            mimeType = "audio/mpeg"
            filename = "audio.mp3"
        case "m4a":
            mimeType = "audio/m4a"
            filename = "audio.m4a"
        default:
            mimeType = "audio/wav"
            filename = "audio.wav"
        }

        // File field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // Model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(model.rawValue)\r\n".data(using: .utf8)!)

        // Response format field (text for fastest response)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("text\r\n".data(using: .utf8)!)

        // Language hint (optional, can speed up transcription)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("en\r\n".data(using: .utf8)!)

        // End boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        // Make request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        // Handle HTTP errors
        if httpResponse.statusCode != 200 {
            try handleHTTPError(statusCode: httpResponse.statusCode, data: data)
        }

        // Parse response (plain text format)
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let latency = CFAbsoluteTimeGetCurrent() - startTime

        print("[TranscriptionService] Dictation transcribed in \(String(format: "%.2f", latency))s")

        return DictationResult(text: text, latency: latency)
    }

    // MARK: - Private Helpers

    private func handleHTTPError(statusCode: Int, data: Data) throws -> Never {
        let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"

        // Log the full error for debugging
        print("[TranscriptionService] HTTP Error \(statusCode):")
        print("[TranscriptionService] Response: \(errorMessage)")

        switch statusCode {
        case 401:
            throw TranscriptionError.invalidAPIKey
        case 429:
            throw TranscriptionError.quotaExceeded
        default:
            throw TranscriptionError.serverError(statusCode, errorMessage)
        }
    }

    /// Estimate duration from file size (rough approximation)
    /// AAC at 64kbps mono = ~8KB per second
    private func estimateDuration(fileSize: Int64) -> TimeInterval {
        let bytesPerSecond: Double = 8000  // 64kbps / 8
        return Double(fileSize) / bytesPerSecond
    }
}

// MARK: - Singleton for Easy Access

extension TranscriptionService {
    static let shared = TranscriptionService()
}
