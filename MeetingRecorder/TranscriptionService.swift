//
//  TranscriptionService.swift
//  MeetingRecorder
//
//  Facade over TranscriptionProcess for backwards compatibility.
//  New code should use TranscriptionProcess.shared directly.
//

import Foundation

// MARK: - Legacy Types (kept for backwards compatibility)

/// Errors that can occur during transcription
enum TranscriptionError: LocalizedError {
    case noAPIKey
    case invalidAPIKey
    case networkError(Error)
    case timeout
    case quotaExceeded
    case fileNotFound(String)
    case invalidResponse
    case serverError(Int, String)
    case fileTooLarge(Int64)
    case fileTooLargeAfterCompression(originalMB: Int, estimatedMinutes: Int, provider: String)
    case compressionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured. Add your key in Settings."
        case .invalidAPIKey:
            return "Invalid API key. Check your key in Settings."
        case .networkError(let error):
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain {
                switch nsError.code {
                case NSURLErrorTimedOut:
                    return "Request timed out. Try again or enable 'Crop silences' in settings."
                case NSURLErrorNotConnectedToInternet:
                    return "No internet connection."
                case NSURLErrorNetworkConnectionLost:
                    return "Network connection lost. Try again."
                default:
                    break
                }
            }
            return "Network error: \(error.localizedDescription)"
        case .timeout:
            return "Request timed out. Try enabling 'Crop silences' in settings."
        case .quotaExceeded:
            return "API quota exceeded. Check your billing."
        case .fileNotFound(let path):
            return "Audio file not found: \(path)"
        case .invalidResponse:
            return "Invalid response from API."
        case .serverError(let code, let message):
            if message.contains("rate_limit") || code == 429 {
                return "Rate limit exceeded. Wait a moment and try again."
            }
            if message.contains("insufficient_quota") {
                return "Account out of credits. Add payment method."
            }
            return "Server error (\(code)): \(message)"
        case .fileTooLarge(let size):
            return "File too large (\(size / 1_000_000)MB)."
        case .fileTooLargeAfterCompression(let originalMB, let estimatedMinutes, let provider):
            return "Recording too long for \(provider) (~\(estimatedMinutes) min, \(originalMB)MB). Try AssemblyAI or Gemini."
        case .compressionFailed(let reason):
            return "Compression failed: \(reason)"
        }
    }
}

/// Model options for transcription (legacy)
enum TranscriptionModel: String, CaseIterable {
    case gpt4oMiniTranscribe = "gpt-4o-mini-transcribe"
    case whisper1 = "whisper-1"

    var displayName: String {
        switch self {
        case .gpt4oMiniTranscribe: return "GPT-4o Mini Transcribe"
        case .whisper1: return "Whisper"
        }
    }

    var costPerMinuteCents: Double {
        switch self {
        case .gpt4oMiniTranscribe: return 0.3
        case .whisper1: return 0.6
        }
    }
}

/// Response from verbose_json format
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
    let title: String?
    /// AI-inferred speaker labels with names and confidence
    let inferredSpeakerLabels: [SpeakerLabel]?

    init(
        text: String,
        duration: TimeInterval,
        costCents: Int,
        model: TranscriptionModel = .whisper1,
        segments: [TranscriptionSegment]? = nil,
        diarizationSegments: [DiarizationSegment]? = nil,
        speakerCount: Int? = nil,
        title: String? = nil,
        inferredSpeakerLabels: [SpeakerLabel]? = nil
    ) {
        self.text = text
        self.duration = duration
        self.costCents = costCents
        self.model = model
        self.segments = segments
        self.diarizationSegments = diarizationSegments
        self.speakerCount = speakerCount
        self.title = title
        self.inferredSpeakerLabels = inferredSpeakerLabels
    }
}

/// Result of a quick dictation transcription
struct DictationResult {
    let text: String
    let latency: TimeInterval
}

// Note: DiarizationSegment is defined in Meeting.swift

// MARK: - Transcription Service (Facade)

/// Facade over TranscriptionProcess for backwards compatibility
actor TranscriptionService {
    static let shared = TranscriptionService()

    /// Default model (legacy)
    var defaultModel: TranscriptionModel = .whisper1

    /// Whether to perform speaker diarization
    var enableDiarization: Bool = true

    // MARK: - Main Transcription (delegates to TranscriptionProcess)

    /// Transcribe an audio file
    func transcribe(
        audioPath: String,
        model: TranscriptionModel? = nil,
        performDiarization: Bool? = nil
    ) async throws -> TranscriptionResult {
        // Read user preferences
        let cropLongSilences = UserDefaults.standard.bool(forKey: "cropLongSilences")
        let silenceCropThreshold = UserDefaults.standard.double(forKey: "silenceCropThreshold")

        // Build options
        var options = TranscriptionProcessOptions()
        options.enableDiarization = performDiarization ?? enableDiarization
        options.cropSilences = cropLongSilences
        options.silenceCropThreshold = silenceCropThreshold
        options.generateTitle = true

        // Map legacy model to provider preference
        if let model = model {
            options.provider = .openai
            options.modelId = model.rawValue
        }

        do {
            let result = try await TranscriptionProcess.shared.transcribe(
                audioPath: audioPath,
                options: options
            )

            // Convert InferredSpeaker to SpeakerLabel
            let speakerLabels: [SpeakerLabel]? = result.inferredSpeakers?.map { inferred in
                SpeakerLabel(
                    speakerId: inferred.speakerId,
                    name: inferred.inferredName,
                    confidence: inferred.confidence,
                    evidence: inferred.evidence,
                    role: inferred.role,
                    isUserAssigned: false
                )
            }

            // Convert to legacy format
            return TranscriptionResult(
                text: result.text,
                duration: result.duration,
                costCents: result.costCents,
                model: model ?? defaultModel,
                segments: result.segments?.enumerated().map { idx, seg in
                    TranscriptionSegment(id: idx, start: seg.start, end: seg.end, text: seg.text)
                },
                diarizationSegments: result.segments?.compactMap { seg -> DiarizationSegment? in
                    guard let speaker = seg.speaker else { return nil }
                    return DiarizationSegment(
                        speakerId: speaker,
                        start: seg.start,
                        end: seg.end,
                        text: seg.text
                    )
                },
                speakerCount: result.speakerCount,
                title: result.title,
                inferredSpeakerLabels: speakerLabels
            )

        } catch let error as TranscriptionProcessError {
            // Map to legacy error type
            throw mapProcessError(error)
        }
    }

    // MARK: - Dictation (fast path, stays with OpenAI)

    /// Quick transcription for dictation (optimized for latency)
    func transcribeDictation(audioPath: String) async throws -> DictationResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        guard let apiKey = KeychainHelper.readOpenAIKey() else {
            throw TranscriptionError.noAPIKey
        }

        guard FileManager.default.fileExists(atPath: audioPath) else {
            throw TranscriptionError.fileNotFound(audioPath)
        }

        let fileURL = URL(fileURLWithPath: audioPath)
        let audioData = try Data(contentsOf: fileURL)

        // Build request (whisper-1 for low latency)
        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        var body = Data()
        let ext = fileURL.pathExtension.lowercased()
        let mimeType = ext == "wav" ? "audio/wav" : ext == "mp3" ? "audio/mpeg" : "audio/m4a"

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.\(ext)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\nwhisper-1\r\n".data(using: .utf8)!)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\ntext\r\n".data(using: .utf8)!)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\nen\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let latency = CFAbsoluteTimeGetCurrent() - startTime
            let durationMs = Int(latency * 1000)

            guard let httpResponse = response as? HTTPURLResponse else {
                await APICallLogManager.shared.logFailure(
                    type: .dictation,
                    provider: "OpenAI",
                    model: "whisper-1",
                    endpoint: "/v1/audio/transcriptions",
                    durationMs: durationMs,
                    error: "Invalid response"
                )
                throw TranscriptionError.invalidResponse
            }

            if httpResponse.statusCode == 401 {
                await APICallLogManager.shared.logFailure(
                    type: .dictation,
                    provider: "OpenAI",
                    model: "whisper-1",
                    endpoint: "/v1/audio/transcriptions",
                    durationMs: durationMs,
                    error: "Invalid API key"
                )
                throw TranscriptionError.invalidAPIKey
            }

            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown"
                await APICallLogManager.shared.logFailure(
                    type: .dictation,
                    provider: "OpenAI",
                    model: "whisper-1",
                    endpoint: "/v1/audio/transcriptions",
                    durationMs: durationMs,
                    error: "HTTP \(httpResponse.statusCode): \(errorMessage)"
                )
                throw TranscriptionError.serverError(httpResponse.statusCode, errorMessage)
            }

            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            // Dictation is usually very short, minimal cost
            await APICallLogManager.shared.logSuccess(
                type: .dictation,
                provider: "OpenAI",
                model: "whisper-1",
                endpoint: "/v1/audio/transcriptions",
                inputSizeBytes: audioData.count,
                durationMs: durationMs,
                costCents: 0  // Dictation is typically < 30 seconds, negligible cost
            )

            logDebug("[TranscriptionService] Dictation transcribed in \(String(format: "%.2f", latency))s")

            return DictationResult(text: text, latency: latency)
        } catch let error as TranscriptionError {
            throw error
        } catch {
            let durationMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            await APICallLogManager.shared.logFailure(
                type: .dictation,
                provider: "OpenAI",
                model: "whisper-1",
                endpoint: "/v1/audio/transcriptions",
                durationMs: durationMs,
                error: error.localizedDescription
            )
            throw TranscriptionError.networkError(error)
        }
    }

    // MARK: - Title Generation (delegates to process, but exposed for legacy callers)

    /// Generate a meeting title from transcript
    func generateMeetingTitle(from transcript: String) async -> String? {
        // The new process does this internally, but some callers still use this directly
        guard let apiKey = KeychainHelper.readOpenAIKey() else { return nil }

        let truncated = String(transcript.prefix(2000))
        let prompt = """
        Based on this meeting transcript, generate a short, descriptive title (max 6 words).
        Return ONLY the title, no quotes.

        Transcript:
        \(truncated)
        """

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": "Generate concise meeting titles."],
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 20,
            "temperature": 0.3
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                return nil
            }
            let title = content.trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : title
        } catch {
            return nil
        }
    }

    // MARK: - Cost Estimation

    /// Estimate transcription cost for an audio file
    func estimateCost(audioPath: String) async throws -> Int {
        let duration = await AudioCompressor.shared.getAudioDuration(filePath: audioPath) ?? 0
        // Use default OpenAI whisper-1 rate: $0.006/min = 0.6 cents/min
        return Int(ceil((duration / 60.0) * 0.6))
    }

    // MARK: - API Key Validation

    func validateAPIKey() async -> Bool {
        guard let apiKey = KeychainHelper.readOpenAIKey() else { return false }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Error Mapping

    private func mapProcessError(_ error: TranscriptionProcessError) -> TranscriptionError {
        switch error {
        case .noProviderConfigured, .noAPIKey:
            return .noAPIKey
        case .invalidAPIKey:
            return .invalidAPIKey
        case .fileNotFound(let path):
            return .fileNotFound(path)
        case .fileTooLarge(let sizeMB, let provider):
            return .fileTooLargeAfterCompression(
                originalMB: sizeMB,
                estimatedMinutes: sizeMB * 8 / 60,  // rough estimate
                provider: provider.displayName
            )
        case .compressionFailed(let reason):
            return .compressionFailed(reason)
        case .networkError(let err):
            return .networkError(err)
        case .serverError(let code, let msg):
            return .serverError(code, msg)
        case .transcriptionFailed(let reason):
            return .serverError(500, reason)
        case .timeout:
            return .timeout
        }
    }
}
