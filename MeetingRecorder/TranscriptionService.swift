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
    let diarizationSegments: [DiarizationSegment]?
    let speakerCount: Int?
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

    /// Whether to perform speaker diarization on transcripts
    var enableDiarization: Bool = true

    /// Transcribe an audio file
    /// - Parameters:
    ///   - audioPath: Path to the .m4a audio file
    ///   - model: Model to use (defaults to gpt-4o-mini-transcribe)
    ///   - performDiarization: Whether to perform speaker diarization (default: true if enabled globally)
    /// - Returns: TranscriptionResult with text and cost
    func transcribe(audioPath: String, model: TranscriptionModel? = nil, performDiarization: Bool? = nil) async throws -> TranscriptionResult {
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
        var costCents = Int(ceil(durationMinutes * selectedModel.costPerMinuteCents))

        print("[TranscriptionService] Transcribed \(String(format: "%.1f", duration))s using \(selectedModel.displayName)")
        print("[TranscriptionService] Cost: \(costCents) cents (\(String(format: "%.2f", durationMinutes)) minutes)")

        // Perform speaker diarization if enabled
        let shouldDiarize = performDiarization ?? enableDiarization
        var diarizationSegments: [DiarizationSegment]? = nil
        var speakerCount: Int? = nil

        if shouldDiarize && !transcriptionResponse.text.isEmpty {
            print("[TranscriptionService] Performing speaker diarization...")
            let diarizationResult = await performSpeakerDiarization(
                transcript: transcriptionResponse.text,
                segments: transcriptionResponse.segments
            )
            diarizationSegments = diarizationResult.segments
            speakerCount = diarizationResult.speakerCount
            costCents += diarizationResult.costCents
            print("[TranscriptionService] Diarization complete: \(speakerCount ?? 0) speakers detected")
        }

        return TranscriptionResult(
            text: transcriptionResponse.text,
            duration: duration,
            costCents: costCents,
            model: selectedModel,
            segments: transcriptionResponse.segments,
            diarizationSegments: diarizationSegments,
            speakerCount: speakerCount
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

    // MARK: - Smart Meeting Title Generation

    /// Generate a smart, relevant title from transcript using GPT-4o-mini
    /// - Parameter transcript: The meeting transcript
    /// - Returns: A concise, descriptive title or nil if generation fails
    func generateMeetingTitle(from transcript: String) async -> String? {
        guard let apiKey = KeychainHelper.readOpenAIKey() else {
            return nil
        }

        // Take first ~2000 chars to avoid token limits
        let truncatedTranscript = String(transcript.prefix(2000))

        let prompt = """
        Based on this meeting transcript, generate a short, descriptive title (max 6 words).
        The title should capture the main topic or purpose of the meeting.
        Return ONLY the title, no quotes or extra text.

        Transcript:
        \(truncatedTranscript)
        """

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": "You are a helpful assistant that generates concise meeting titles."],
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 20,
            "temperature": 0.3
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            // Parse response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                let title = content.trimmingCharacters(in: .whitespacesAndNewlines)
                print("[TranscriptionService] Generated title: \(title)")
                return title.isEmpty ? nil : title
            }
        } catch {
            print("[TranscriptionService] Title generation failed: \(error)")
        }

        return nil
    }

    // MARK: - Speaker Diarization

    /// Result of speaker diarization
    struct DiarizationResult {
        let segments: [DiarizationSegment]
        let speakerCount: Int
        let costCents: Int
    }

    /// Perform speaker diarization using GPT-4o-mini
    /// - Parameters:
    ///   - transcript: The full transcript text
    ///   - segments: Optional time-aligned segments from transcription
    /// - Returns: DiarizationResult with speaker-labeled segments
    private func performSpeakerDiarization(
        transcript: String,
        segments: [TranscriptionSegment]?
    ) async -> DiarizationResult {
        guard let apiKey = KeychainHelper.readOpenAIKey() else {
            return DiarizationResult(segments: [], speakerCount: 0, costCents: 0)
        }

        // Truncate transcript if too long (keep ~8000 chars for context)
        let maxLength = 8000
        let truncatedTranscript = transcript.count > maxLength
            ? String(transcript.prefix(maxLength)) + "..."
            : transcript

        let prompt = """
        Analyze this meeting transcript and identify different speakers. For each segment of speech, assign a speaker ID (speaker_0, speaker_1, etc.).

        Return a JSON array where each element has:
        - "speakerId": string like "speaker_0", "speaker_1"
        - "text": the text spoken by this speaker

        Try to detect speaker changes based on:
        - Topic shifts
        - Questions and answers
        - Different speaking styles
        - Context clues like "thanks John" or "as I mentioned"

        Return ONLY the JSON array, no explanation.

        Transcript:
        \(truncatedTranscript)
        """

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": "You are an expert at speaker diarization. Analyze transcripts and identify different speakers. Always respond with valid JSON only."],
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 4000,
            "temperature": 0.3,
            "response_format": ["type": "json_object"]
        ]

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 60  // Diarization can take time

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("[TranscriptionService] Diarization API error")
                return DiarizationResult(segments: [], speakerCount: 0, costCents: 0)
            }

            // Estimate cost (~500 input tokens + ~1000 output tokens for gpt-4o-mini)
            // gpt-4o-mini: $0.15/1M input, $0.60/1M output
            let estimatedInputTokens = truncatedTranscript.count / 4
            let estimatedOutputTokens = 1000
            let costCents = Int(ceil(Double(estimatedInputTokens) * 0.00015 + Double(estimatedOutputTokens) * 0.0006))

            // Parse response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {

                // Parse the JSON response
                let segments = parseDiarizationResponse(content)
                let uniqueSpeakers = Set(segments.map { $0.speakerId })

                return DiarizationResult(
                    segments: segments,
                    speakerCount: uniqueSpeakers.count,
                    costCents: costCents
                )
            }
        } catch {
            print("[TranscriptionService] Diarization failed: \(error)")
        }

        return DiarizationResult(segments: [], speakerCount: 0, costCents: 0)
    }

    /// Parse the JSON response from diarization
    private func parseDiarizationResponse(_ content: String) -> [DiarizationSegment] {
        guard let data = content.data(using: .utf8) else { return [] }

        do {
            // Try to parse as a root object with "segments" key or as an array
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Handle {"segments": [...]} format
                if let segmentsArray = json["segments"] as? [[String: Any]] {
                    return parseSegmentsArray(segmentsArray)
                }
                // Handle {"speakers": [...]} format
                if let speakersArray = json["speakers"] as? [[String: Any]] {
                    return parseSegmentsArray(speakersArray)
                }
            }

            // Try to parse as direct array
            if let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return parseSegmentsArray(array)
            }
        } catch {
            print("[TranscriptionService] Failed to parse diarization JSON: \(error)")
        }

        return []
    }

    /// Parse an array of segment dictionaries
    private func parseSegmentsArray(_ array: [[String: Any]]) -> [DiarizationSegment] {
        var segments: [DiarizationSegment] = []
        var currentTime: TimeInterval = 0

        for item in array {
            guard let speakerId = item["speakerId"] as? String ?? item["speaker_id"] as? String ?? item["speaker"] as? String,
                  let text = item["text"] as? String else {
                continue
            }

            // Estimate timing (rough: ~150 words per minute, ~5 chars per word)
            let wordCount = Double(text.split(separator: " ").count)
            let estimatedDuration = max(1.0, wordCount / 2.5)  // ~150 wpm

            let segment = DiarizationSegment(
                speakerId: speakerId,
                start: currentTime,
                end: currentTime + estimatedDuration,
                text: text
            )
            segments.append(segment)
            currentTime += estimatedDuration
        }

        return segments
    }
}

// MARK: - Singleton for Easy Access

extension TranscriptionService {
    static let shared = TranscriptionService()
}
