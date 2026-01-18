//
//  TranscriptionProcess.swift
//  MeetingRecorder
//
//  Composable transcription process.
//  Orchestrates preprocessing, transcription, and postprocessing steps.
//

import Foundation

// MARK: - Process Result

/// Quality validation result
struct TranscriptionQualityResult {
    let isValid: Bool
    let hasRubbish: Bool
    let rubbishDescription: String?
    let confidence: Double  // 0-1
    let costCents: Int
}

/// Result from a transcription process
struct TranscriptionProcessResult {
    let text: String
    let duration: TimeInterval
    let costCents: Int
    let segments: [TranscriptSegment]?
    let speakerCount: Int?
    let language: String?
    let title: String?

    /// Provider used for transcription
    let provider: TranscriptionProvider
    let modelId: String

    /// Processing metadata
    let processingTime: TimeInterval
    let wasCompressed: Bool
    let wasSilenceCropped: Bool

    /// Quality validation (nil if validation was skipped)
    let qualityValidation: TranscriptionQualityResult?

    /// AI-inferred speaker names (nil if speaker ID was skipped or failed)
    let inferredSpeakers: [InferredSpeaker]?
}

/// A segment of transcribed speech
struct TranscriptSegment {
    let speaker: String?
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}

// MARK: - Process Errors

enum TranscriptionProcessError: LocalizedError {
    case noProviderConfigured
    case noAPIKey(TranscriptionProvider)
    case invalidAPIKey(TranscriptionProvider)
    case fileNotFound(String)
    case fileTooLarge(sizeMB: Int, provider: TranscriptionProvider)
    case compressionFailed(String)
    case networkError(Error)
    case serverError(Int, String)
    case transcriptionFailed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .noProviderConfigured:
            return "No transcription provider configured. Add an API key in Settings."
        case .noAPIKey(let provider):
            return "\(provider.displayName) API key not found. Add your key in Settings."
        case .invalidAPIKey(let provider):
            return "Invalid \(provider.displayName) API key. Check your key in Settings."
        case .fileNotFound(let path):
            return "Audio file not found: \(path)"
        case .fileTooLarge(let sizeMB, let provider):
            return "File too large (\(sizeMB)MB) for \(provider.displayName). Max: \(provider.maxFileSizeFormatted)"
        case .compressionFailed(let reason):
            return "Audio compression failed: \(reason)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        case .timeout:
            return "Request timed out. Try again or use a different provider."
        }
    }
}

// MARK: - Process Options

/// Configuration options for the transcription process
struct TranscriptionProcessOptions {
    /// Which provider to use (nil = auto-select best available)
    var provider: TranscriptionProvider?

    /// Model ID override (nil = use provider default)
    var modelId: String?

    /// Language hint (nil = auto-detect)
    var language: String?

    /// Enable speaker diarization
    var enableDiarization: Bool = true

    /// Auto-compress if file too large
    var autoCompress: Bool = true

    /// Crop long silences before transcribing
    var cropSilences: Bool = false
    var silenceCropThreshold: TimeInterval = 3.0

    /// Generate a smart title from the transcript
    var generateTitle: Bool = true

    /// Validate transcription quality with cheap LLM check
    var validateQuality: Bool = true

    /// Identify speakers by name using AI (requires Gemini API key)
    var identifySpeakers: Bool = true

    /// Meeting title for speaker identification context
    var meetingTitle: String?

    /// Known participants for speaker identification
    var knownParticipants: [MeetingParticipant]?

    static let `default` = TranscriptionProcessOptions()
}

// MARK: - Transcription Process

/// Orchestrates the full transcription pipeline
actor TranscriptionProcess {

    static let shared = TranscriptionProcess()

    // MARK: - Main Entry Point

    /// Transcribe an audio file
    func transcribe(
        audioPath: String,
        options: TranscriptionProcessOptions = .default
    ) async throws -> TranscriptionProcessResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Validate file exists
        guard FileManager.default.fileExists(atPath: audioPath) else {
            throw TranscriptionProcessError.fileNotFound(audioPath)
        }

        // Select provider
        let provider = try selectProvider(preferred: options.provider)
        logInfo("[TranscriptionProcess] Using provider: \(provider.displayName)")

        // Preprocess
        logInfo("[TranscriptionProcess] Original audio path: \(audioPath)")
        let preprocessResult = try await preprocess(
            audioPath: audioPath,
            provider: provider,
            options: options
        )
        logInfo("[TranscriptionProcess] After preprocess: \(preprocessResult.processedPath)")
        logInfo("[TranscriptionProcess] Compressed: \(preprocessResult.wasCompressed), Silence cropped: \(preprocessResult.wasSilenceCropped)")

        // Transcribe
        let transcriptionResult = try await performTranscription(
            audioPath: preprocessResult.processedPath,
            provider: provider,
            options: options
        )

        // Postprocess
        let title = options.generateTitle
            ? await generateTitle(from: transcriptionResult.text)
            : nil

        // Quality validation
        var qualityValidation: TranscriptionQualityResult? = nil
        var totalCostCents = transcriptionResult.costCents

        if options.validateQuality && !transcriptionResult.text.isEmpty {
            qualityValidation = await validateTranscriptionQuality(transcript: transcriptionResult.text)
            if let validation = qualityValidation {
                totalCostCents += validation.costCents
                if validation.hasRubbish {
                    logWarning("[TranscriptionProcess] Quality check detected rubbish: \(validation.rubbishDescription ?? "unknown issue")")
                }
            }
        }

        // Speaker identification (Pass 2)
        var inferredSpeakers: [InferredSpeaker]? = nil

        if options.identifySpeakers && options.enableDiarization {
            // Convert TranscriptSegments to DiarizationSegments for the service
            let diarizationSegments = transcriptionResult.segments?.compactMap { segment -> DiarizationSegment? in
                guard let speaker = segment.speaker else { return nil }
                return DiarizationSegment(
                    speakerId: speaker,
                    start: segment.start,
                    end: segment.end,
                    text: segment.text
                )
            }

            // Only attempt identification if we have multiple speakers
            let uniqueSpeakers = Set(diarizationSegments?.map { $0.speakerId } ?? [])
            if uniqueSpeakers.count > 1 {
                logInfo("[TranscriptionProcess] Identifying \(uniqueSpeakers.count) speakers...")

                if let result = await SpeakerIdentificationService.shared.identifySpeakers(
                    transcript: transcriptionResult.text,
                    segments: diarizationSegments,
                    meetingTitle: options.meetingTitle ?? title,
                    participants: options.knownParticipants
                ) {
                    inferredSpeakers = result.speakers
                    totalCostCents += result.costCents
                    logInfo("[TranscriptionProcess] Speaker identification complete: \(result.speakers.count) speakers identified")
                }
            }
        }

        let processingTime = CFAbsoluteTimeGetCurrent() - startTime

        logInfo("[TranscriptionProcess] Complete in \(String(format: "%.1f", processingTime))s")

        return TranscriptionProcessResult(
            text: transcriptionResult.text,
            duration: transcriptionResult.duration,
            costCents: totalCostCents,
            segments: transcriptionResult.segments,
            speakerCount: transcriptionResult.speakerCount,
            language: transcriptionResult.language,
            title: title,
            provider: provider,
            modelId: transcriptionResult.modelId,
            processingTime: processingTime,
            wasCompressed: preprocessResult.wasCompressed,
            wasSilenceCropped: preprocessResult.wasSilenceCropped,
            qualityValidation: qualityValidation,
            inferredSpeakers: inferredSpeakers
        )
    }

    // MARK: - Provider Selection

    private func selectProvider(preferred: TranscriptionProvider?) throws -> TranscriptionProvider {
        // If preferred and configured, use it
        if let preferred, preferred.isConfigured {
            return preferred
        }

        // Auto-select: AssemblyAI > Gemini > OpenAI > Deepgram
        // AssemblyAI is most reliable; Gemini can produce garbage on some audio formats
        let priority: [TranscriptionProvider] = [.assemblyai, .gemini, .openai, .deepgram]

        for provider in priority {
            if provider.isConfigured {
                return provider
            }
        }

        throw TranscriptionProcessError.noProviderConfigured
    }

    // MARK: - Preprocessing

    private struct PreprocessResult {
        let processedPath: String
        let wasCompressed: Bool
        let wasSilenceCropped: Bool
    }

    private func preprocess(
        audioPath: String,
        provider: TranscriptionProvider,
        options: TranscriptionProcessOptions
    ) async throws -> PreprocessResult {
        var currentPath = audioPath
        var wasCompressed = false
        var wasSilenceCropped = false

        // Step 1: Crop silences if enabled
        if options.cropSilences && options.silenceCropThreshold > 0 {
            do {
                let result = try await SilenceProcessor.shared.cropLongSilences(
                    audioPath: currentPath,
                    minSilenceDuration: options.silenceCropThreshold,
                    keepDuration: 1.0
                )
                if result.silencesCropped > 0 {
                    currentPath = result.outputPath
                    wasSilenceCropped = true
                    logInfo("[TranscriptionProcess] Cropped \(result.silencesCropped) silences")
                }
            } catch {
                logWarning("[TranscriptionProcess] Silence cropping failed: \(error.localizedDescription)")
            }
        }

        // Step 2: Check file size and compress if needed
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: currentPath)
        let fileSize = fileAttributes[.size] as? Int64 ?? 0

        if fileSize > provider.maxFileSize {
            if options.autoCompress {
                logInfo("[TranscriptionProcess] File \(fileSize / 1_000_000)MB exceeds limit, compressing...")

                do {
                    currentPath = try await AudioCompressor.shared.compress(
                        inputPath: currentPath,
                        targetSizeBytes: Int64(provider.maxFileSize - 1_000_000), // Leave buffer
                        maxLevel: .extreme
                    )
                    wasCompressed = true

                    // Verify compressed size
                    let newAttributes = try FileManager.default.attributesOfItem(atPath: currentPath)
                    let newSize = newAttributes[.size] as? Int64 ?? 0
                    logInfo("[TranscriptionProcess] Compressed to \(newSize / 1_000_000)MB")

                    if newSize > provider.maxFileSize {
                        throw TranscriptionProcessError.fileTooLarge(
                            sizeMB: Int(newSize / 1_000_000),
                            provider: provider
                        )
                    }
                } catch let error as AudioCompressionError {
                    throw TranscriptionProcessError.compressionFailed(error.localizedDescription)
                }
            } else {
                throw TranscriptionProcessError.fileTooLarge(
                    sizeMB: Int(fileSize / 1_000_000),
                    provider: provider
                )
            }
        }

        return PreprocessResult(
            processedPath: currentPath,
            wasCompressed: wasCompressed,
            wasSilenceCropped: wasSilenceCropped
        )
    }

    // MARK: - Transcription (Provider Dispatch)

    private struct InternalResult {
        let text: String
        let duration: TimeInterval
        let costCents: Int
        let modelId: String
        let segments: [TranscriptSegment]?
        let speakerCount: Int?
        let language: String?
    }

    private func performTranscription(
        audioPath: String,
        provider: TranscriptionProvider,
        options: TranscriptionProcessOptions
    ) async throws -> InternalResult {
        switch provider {
        case .openai:
            return try await transcribeWithOpenAI(audioPath: audioPath, options: options)
        case .assemblyai:
            return try await transcribeWithAssemblyAI(audioPath: audioPath, options: options)
        case .gemini:
            return try await transcribeWithGemini(audioPath: audioPath, options: options)
        case .deepgram:
            return try await transcribeWithDeepgram(audioPath: audioPath, options: options)
        }
    }

    // MARK: - OpenAI Transcription

    private func transcribeWithOpenAI(
        audioPath: String,
        options: TranscriptionProcessOptions
    ) async throws -> InternalResult {
        let callStartTime = CFAbsoluteTimeGetCurrent()

        guard let apiKey = KeychainHelper.readOpenAIKey() else {
            throw TranscriptionProcessError.noAPIKey(.openai)
        }

        let fileURL = URL(fileURLWithPath: audioPath)
        let audioData = try Data(contentsOf: fileURL)
        let model = options.modelId ?? "whisper-1"

        logInfo("[TranscriptionProcess] OpenAI transcription starting...")

        // Build multipart request
        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // File
        let ext = fileURL.pathExtension.lowercased()
        let mimeType = ext == "wav" ? "audio/wav" : ext == "mp3" ? "audio/mpeg" : "audio/m4a"
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.\(ext)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // Model
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n\(model)\r\n".data(using: .utf8)!)

        // Response format
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\nverbose_json\r\n".data(using: .utf8)!)

        // Language
        if let lang = options.language {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n\(lang)\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        // Timeout based on size
        let sizeMB = Double(audioData.count) / 1_000_000.0
        request.timeoutInterval = max(180, min(120 + sizeMB * 30, 900))

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let durationMs = Int((CFAbsoluteTimeGetCurrent() - callStartTime) * 1000)

            guard let httpResponse = response as? HTTPURLResponse else {
                await APICallLogManager.shared.logFailure(
                    type: .transcription,
                    provider: "OpenAI",
                    model: model,
                    endpoint: "/v1/audio/transcriptions",
                    durationMs: durationMs,
                    error: "Invalid response"
                )
                throw TranscriptionProcessError.networkError(NSError(domain: "OpenAI", code: -1))
            }

            if httpResponse.statusCode == 401 {
                await APICallLogManager.shared.logFailure(
                    type: .transcription,
                    provider: "OpenAI",
                    model: model,
                    endpoint: "/v1/audio/transcriptions",
                    durationMs: durationMs,
                    error: "Invalid API key"
                )
                throw TranscriptionProcessError.invalidAPIKey(.openai)
            }

            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown"
                await APICallLogManager.shared.logFailure(
                    type: .transcription,
                    provider: "OpenAI",
                    model: model,
                    endpoint: "/v1/audio/transcriptions",
                    durationMs: durationMs,
                    error: "HTTP \(httpResponse.statusCode): \(errorMessage)"
                )
                throw TranscriptionProcessError.serverError(httpResponse.statusCode, errorMessage)
            }

            // Parse
            struct OpenAIResponse: Codable {
                let text: String
                let duration: Double?
                let language: String?
                let segments: [Segment]?
                struct Segment: Codable {
                    let start: Double
                    let end: Double
                    let text: String
                }
            }

            let resp = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            let duration = resp.duration ?? Double(audioData.count) / 8000.0

            // Cost
            let costPerMinute = model == "gpt-4o-mini-transcribe" ? 0.3 : 0.6
            var costCents = Int(ceil((duration / 60.0) * costPerMinute))

            // Log successful transcription
            await APICallLogManager.shared.logSuccess(
                type: .transcription,
                provider: "OpenAI",
                model: model,
                endpoint: "/v1/audio/transcriptions",
                inputSizeBytes: audioData.count,
                durationMs: durationMs,
                costCents: costCents
            )

            // Diarization via LLM if requested (OpenAI doesn't have native diarization)
            var segments: [TranscriptSegment]? = resp.segments?.map {
                TranscriptSegment(speaker: nil, start: $0.start, end: $0.end, text: $0.text)
            }
            var speakerCount: Int? = nil

            if options.enableDiarization && !resp.text.isEmpty {
                let diarizationResult = await performLLMDiarization(transcript: resp.text)
                if !diarizationResult.segments.isEmpty {
                    segments = diarizationResult.segments
                    speakerCount = diarizationResult.speakerCount
                    costCents += diarizationResult.costCents
                }
            }

            logInfo("[TranscriptionProcess] OpenAI complete, duration: \(String(format: "%.1f", duration))s")

            return InternalResult(
                text: resp.text,
                duration: duration,
                costCents: costCents,
                modelId: model,
                segments: segments,
                speakerCount: speakerCount,
                language: resp.language
            )
        } catch let error as TranscriptionProcessError {
            throw error
        } catch {
            let durationMs = Int((CFAbsoluteTimeGetCurrent() - callStartTime) * 1000)
            await APICallLogManager.shared.logFailure(
                type: .transcription,
                provider: "OpenAI",
                model: model,
                endpoint: "/v1/audio/transcriptions",
                durationMs: durationMs,
                error: error.localizedDescription
            )
            throw TranscriptionProcessError.networkError(error)
        }
    }

    // MARK: - AssemblyAI Transcription

    private func transcribeWithAssemblyAI(
        audioPath: String,
        options: TranscriptionProcessOptions
    ) async throws -> InternalResult {
        let callStartTime = CFAbsoluteTimeGetCurrent()

        guard let apiKey = KeychainHelper.readAssemblyAIKey() else {
            throw TranscriptionProcessError.noAPIKey(.assemblyai)
        }

        let fileURL = URL(fileURLWithPath: audioPath)
        let inputSizeBytes = fileSizeBytes(for: fileURL)
        logInfo("[TranscriptionProcess] AssemblyAI transcription starting...")

        do {
            // Step 1: Upload
            let uploadedURL = try await assemblyAIUpload(fileURL: fileURL, apiKey: apiKey)

            // Step 2: Create transcript
            let transcriptId = try await assemblyAICreateTranscript(
                audioURL: uploadedURL,
                apiKey: apiKey,
                language: options.language,
                enableDiarization: options.enableDiarization
            )

            // Step 3: Poll for completion
            let result = try await assemblyAIPoll(transcriptId: transcriptId, apiKey: apiKey)

            let durationMs = Int((CFAbsoluteTimeGetCurrent() - callStartTime) * 1000)

            // Log successful transcription
            await APICallLogManager.shared.logSuccess(
                type: .transcription,
                provider: "AssemblyAI",
                model: "universal",
                endpoint: "/v2/transcript",
                inputSizeBytes: inputSizeBytes > 0 ? Int(inputSizeBytes) : nil,
                durationMs: durationMs,
                costCents: result.costCents
            )

            return result
        } catch {
            let durationMs = Int((CFAbsoluteTimeGetCurrent() - callStartTime) * 1000)
            await APICallLogManager.shared.logFailure(
                type: .transcription,
                provider: "AssemblyAI",
                model: "universal",
                endpoint: "/v2/transcript",
                durationMs: durationMs,
                error: error.localizedDescription
            )
            throw error
        }
    }

    private func assemblyAIUpload(fileURL: URL, apiKey: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.assemblyai.com/v2/upload")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "authorization")
        request.setValue(assemblyAIContentType(for: fileURL), forHTTPHeaderField: "Content-Type")

        let sizeMB = Double(fileSizeBytes(for: fileURL)) / 1_000_000.0
        request.timeoutInterval = max(60, 30 + sizeMB)

        let (data, response) = try await URLSession.shared.upload(for: request, fromFile: fileURL)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TranscriptionProcessError.networkError(NSError(domain: "AssemblyAI", code: -1))
        }

        if httpResponse.statusCode == 401 {
            throw TranscriptionProcessError.invalidAPIKey(.assemblyai)
        }

        guard httpResponse.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let uploadURL = json["upload_url"] as? String else {
            throw TranscriptionProcessError.transcriptionFailed("Upload failed")
        }

        return uploadURL
    }

    private func assemblyAIContentType(for fileURL: URL) -> String {
        let ext = fileURL.pathExtension.lowercased()
        switch ext {
        case "m4a":
            return "audio/mp4"
        case "mp3":
            return "audio/mpeg"
        case "wav":
            return "audio/wav"
        case "webm":
            return "audio/webm"
        default:
            return "application/octet-stream"
        }
    }

    private func fileSizeBytes(for fileURL: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        return attributes?[.size] as? Int64 ?? 0
    }

    private func assemblyAICreateTranscript(
        audioURL: String,
        apiKey: String,
        language: String?,
        enableDiarization: Bool
    ) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.assemblyai.com/v2/transcript")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "audio_url": audioURL,
            "speaker_labels": enableDiarization
        ]
        if let lang = language {
            body["language_code"] = lang
        } else {
            // MUST enable language_detection when no language is specified!
            // Without this, AssemblyAI defaults to English and produces garbage
            // for non-English audio. Example: Portuguese "Fazendo um teste" becomes
            // "Fazen killed Tofazen" when language_detection is NOT set.
            // Verified via direct API testing - Python with language_detection=true works,
            // Swift without it produces garbage.
            body["language_detection"] = true
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String else {
            throw TranscriptionProcessError.transcriptionFailed("Failed to create transcript")
        }

        return id
    }

    private func assemblyAIPoll(transcriptId: String, apiKey: String) async throws -> InternalResult {
        let pollURL = URL(string: "https://api.assemblyai.com/v2/transcript/\(transcriptId)")!
        var request = URLRequest(url: pollURL)
        request.setValue(apiKey, forHTTPHeaderField: "authorization")

        var pollInterval: TimeInterval = 2.0
        let maxPollTime: TimeInterval = 600
        let startTime = CFAbsoluteTimeGetCurrent()

        while CFAbsoluteTimeGetCurrent() - startTime < maxPollTime {
            let (data, _) = try await URLSession.shared.data(for: request)

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String else {
                throw TranscriptionProcessError.transcriptionFailed("Invalid poll response")
            }

            switch status {
            case "completed":
                return try parseAssemblyAIResult(json)
            case "error":
                let errorMsg = json["error"] as? String ?? "Unknown"
                throw TranscriptionProcessError.transcriptionFailed(errorMsg)
            case "queued", "processing":
                try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
                pollInterval = min(pollInterval * 1.5, 10)
            default:
                throw TranscriptionProcessError.transcriptionFailed("Unknown status: \(status)")
            }
        }

        throw TranscriptionProcessError.timeout
    }

    private func parseAssemblyAIResult(_ json: [String: Any]) throws -> InternalResult {
        guard let text = json["text"] as? String else {
            throw TranscriptionProcessError.transcriptionFailed("No text in response")
        }

        let duration = json["audio_duration"] as? Double ?? 0
        let language = json["language_code"] as? String

        var segments: [TranscriptSegment] = []
        var speakerSet = Set<String>()

        if let utterances = json["utterances"] as? [[String: Any]] {
            for utt in utterances {
                guard let uttText = utt["text"] as? String,
                      let start = utt["start"] as? Int,
                      let end = utt["end"] as? Int else { continue }

                let speaker = utt["speaker"] as? String
                if let s = speaker { speakerSet.insert(s) }

                segments.append(TranscriptSegment(
                    speaker: speaker.map { "Speaker \($0)" },
                    start: Double(start) / 1000.0,
                    end: Double(end) / 1000.0,
                    text: uttText
                ))
            }
        }

        // $0.00283/minute
        let costCents = Int(ceil((duration / 60.0) * 0.283))

        logInfo("[TranscriptionProcess] AssemblyAI complete, duration: \(String(format: "%.1f", duration))s, speakers: \(speakerSet.count)")

        return InternalResult(
            text: text,
            duration: duration,
            costCents: costCents,
            modelId: "universal",
            segments: segments.isEmpty ? nil : segments,
            speakerCount: speakerSet.isEmpty ? nil : speakerSet.count,
            language: language
        )
    }

    // MARK: - Gemini Transcription

    private func transcribeWithGemini(
        audioPath: String,
        options: TranscriptionProcessOptions
    ) async throws -> InternalResult {
        let callStartTime = CFAbsoluteTimeGetCurrent()

        guard let apiKey = KeychainHelper.readGeminiKey() else {
            throw TranscriptionProcessError.noAPIKey(.gemini)
        }

        let fileURL = URL(fileURLWithPath: audioPath)
        let audioData = try Data(contentsOf: fileURL)
        let model = options.modelId ?? "gemini-2.5-flash"

        logInfo("[TranscriptionProcess] Gemini transcription starting with \(model)...")
        logInfo("[TranscriptionProcess] Audio path: \(audioPath)")
        logInfo("[TranscriptionProcess] Audio size: \(audioData.count) bytes (\(audioData.count / 1_000_000)MB)")

        let base64Audio = audioData.base64EncodedString()
        let ext = fileURL.pathExtension.lowercased()
        let mimeType = ext == "m4a" ? "audio/mp4" : ext == "mp3" ? "audio/mpeg" : ext == "wav" ? "audio/wav" : "audio/mp4"

        // Estimate duration for max tokens calculation
        let estimatedDuration = await AudioCompressor.shared.getAudioDuration(filePath: audioPath) ?? Double(audioData.count) / 8000.0

        let langStr = options.language ?? "the spoken language"
        var prompt: String
        if options.enableDiarization {
            prompt = """
            Transcribe this audio in \(langStr) with speaker diarization and timestamps.

            RULES:
            1. Label speakers as Speaker A, Speaker B, etc. based on voice.
            2. Group consecutive speech from the same speaker into ONE segment.
            3. Only start a new segment when the speaker CHANGES.
            4. Include timestamp (MM:SS) at the start of each segment.

            FORMAT:
            [Speaker A, 0:00] Complete speech until next speaker.
            [Speaker B, 1:15] Next speaker's complete response.

            Transcribe the entire audio now:
            """
        } else {
            prompt = "Transcribe this audio in \(langStr). Return only the transcript text."
        }

        // Use maximum output tokens for transcription - Gemini Flash supports up to 65k
        // A 46-min meeting produces ~10k tokens of transcription
        let maxTokens = 65536

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600  // 10 minutes for long audio

        let payload: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": prompt],
                    ["inline_data": ["mime_type": mimeType, "data": base64Audio]]
                ]
            ]],
            "generationConfig": ["temperature": 0.1, "maxOutputTokens": maxTokens]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let durationMs = Int((CFAbsoluteTimeGetCurrent() - callStartTime) * 1000)

            guard let httpResponse = response as? HTTPURLResponse else {
                await APICallLogManager.shared.logFailure(
                    type: .transcription,
                    provider: "Gemini",
                    model: model,
                    endpoint: "/v1beta/models/\(model):generateContent",
                    durationMs: durationMs,
                    error: "Invalid response"
                )
                throw TranscriptionProcessError.networkError(NSError(domain: "Gemini", code: -1))
            }

            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown"
                await APICallLogManager.shared.logFailure(
                    type: .transcription,
                    provider: "Gemini",
                    model: model,
                    endpoint: "/v1beta/models/\(model):generateContent",
                    durationMs: durationMs,
                    error: "HTTP \(httpResponse.statusCode): \(errorMessage)"
                )
                throw TranscriptionProcessError.serverError(httpResponse.statusCode, errorMessage)
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else {
                await APICallLogManager.shared.logFailure(
                    type: .transcription,
                    provider: "Gemini",
                    model: model,
                    endpoint: "/v1beta/models/\(model):generateContent",
                    durationMs: durationMs,
                    error: "Invalid response format"
                )
                throw TranscriptionProcessError.transcriptionFailed("Invalid response")
            }

            let text = parts.compactMap { $0["text"] as? String }.joined(separator: " ")
            // Cost based on Gemini pricing (~$0.0003/min for audio)
            let costCents = Int(ceil((estimatedDuration / 60.0) * 0.03))

            // Log successful transcription
            await APICallLogManager.shared.logSuccess(
                type: .transcription,
                provider: "Gemini",
                model: model,
                endpoint: "/v1beta/models/\(model):generateContent",
                inputSizeBytes: audioData.count,
                durationMs: durationMs,
                costCents: costCents
            )

            // Parse diarization from output
            let segments = options.enableDiarization ? parseGeminiDiarization(text) : nil

            logInfo("[TranscriptionProcess] Gemini complete")

            return InternalResult(
                text: text,
                duration: estimatedDuration,
                costCents: costCents,
                modelId: model,
                segments: segments,
                speakerCount: segments.map { Set($0.compactMap { $0.speaker }).count },
                language: options.language
            )
        } catch let error as TranscriptionProcessError {
            throw error
        } catch {
            let durationMs = Int((CFAbsoluteTimeGetCurrent() - callStartTime) * 1000)
            await APICallLogManager.shared.logFailure(
                type: .transcription,
                provider: "Gemini",
                model: model,
                endpoint: "/v1beta/models/\(model):generateContent",
                durationMs: durationMs,
                error: error.localizedDescription
            )
            throw TranscriptionProcessError.networkError(error)
        }
    }

    private func parseGeminiDiarization(_ text: String) -> [TranscriptSegment]? {
        let pattern = #"\[Speaker\s+([A-Z]),?\s*(\d{1,2}:\d{2}(?::\d{2})?)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        var segments: [TranscriptSegment] = []

        for line in text.components(separatedBy: .newlines) {
            let range = NSRange(line.startIndex..., in: line)
            if let match = regex.firstMatch(in: line, options: [], range: range),
               let speakerRange = Range(match.range(at: 1), in: line),
               let timeRange = Range(match.range(at: 2), in: line) {

                let speaker = "Speaker \(line[speakerRange])"
                let timeStr = String(line[timeRange])
                let startTime = parseTimestamp(timeStr)

                let afterBracket = line.replacingOccurrences(
                    of: #"\[Speaker\s+[A-Z],?\s*\d{1,2}:\d{2}(?::\d{2})?\]\s*"#,
                    with: "",
                    options: .regularExpression
                ).trimmingCharacters(in: .whitespaces)

                if !afterBracket.isEmpty {
                    segments.append(TranscriptSegment(
                        speaker: speaker,
                        start: startTime,
                        end: startTime + 10,
                        text: afterBracket
                    ))
                }
            }
        }

        return segments.isEmpty ? nil : segments
    }

    private func parseTimestamp(_ ts: String) -> TimeInterval {
        let parts = ts.split(separator: ":").compactMap { Int($0) }
        if parts.count == 2 {
            return TimeInterval(parts[0] * 60 + parts[1])
        } else if parts.count == 3 {
            return TimeInterval(parts[0] * 3600 + parts[1] * 60 + parts[2])
        }
        return 0
    }

    // MARK: - Deepgram Transcription

    private func transcribeWithDeepgram(
        audioPath: String,
        options: TranscriptionProcessOptions
    ) async throws -> InternalResult {
        let callStartTime = CFAbsoluteTimeGetCurrent()

        guard let apiKey = KeychainHelper.readDeepgramKey() else {
            throw TranscriptionProcessError.noAPIKey(.deepgram)
        }

        let fileURL = URL(fileURLWithPath: audioPath)
        let audioData = try Data(contentsOf: fileURL)
        let model = options.modelId ?? "nova-2"

        logInfo("[TranscriptionProcess] Deepgram transcription starting...")

        var urlComponents = URLComponents(string: "https://api.deepgram.com/v1/listen")!
        var queryItems = [
            URLQueryItem(name: "model", value: model),
            URLQueryItem(name: "smart_format", value: "true")
        ]

        if options.enableDiarization {
            queryItems.append(URLQueryItem(name: "diarize", value: "true"))
        }
        if let lang = options.language {
            queryItems.append(URLQueryItem(name: "language", value: lang))
        }

        urlComponents.queryItems = queryItems

        var request = URLRequest(url: urlComponents.url!)
        request.httpMethod = "POST"
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")

        let ext = fileURL.pathExtension.lowercased()
        let contentType = ext == "wav" ? "audio/wav" : ext == "mp3" ? "audio/mpeg" : "audio/mp4"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = audioData
        request.timeoutInterval = 300

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let durationMs = Int((CFAbsoluteTimeGetCurrent() - callStartTime) * 1000)

            guard let httpResponse = response as? HTTPURLResponse else {
                await APICallLogManager.shared.logFailure(
                    type: .transcription,
                    provider: "Deepgram",
                    model: model,
                    endpoint: "/v1/listen",
                    durationMs: durationMs,
                    error: "Invalid response"
                )
                throw TranscriptionProcessError.networkError(NSError(domain: "Deepgram", code: -1))
            }

            if httpResponse.statusCode == 401 {
                await APICallLogManager.shared.logFailure(
                    type: .transcription,
                    provider: "Deepgram",
                    model: model,
                    endpoint: "/v1/listen",
                    durationMs: durationMs,
                    error: "Invalid API key"
                )
                throw TranscriptionProcessError.invalidAPIKey(.deepgram)
            }

            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown"
                await APICallLogManager.shared.logFailure(
                    type: .transcription,
                    provider: "Deepgram",
                    model: model,
                    endpoint: "/v1/listen",
                    durationMs: durationMs,
                    error: "HTTP \(httpResponse.statusCode): \(errorMessage)"
                )
                throw TranscriptionProcessError.serverError(httpResponse.statusCode, errorMessage)
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [String: Any],
                  let channels = results["channels"] as? [[String: Any]],
                  let alternatives = channels.first?["alternatives"] as? [[String: Any]],
                  let transcript = alternatives.first?["transcript"] as? String else {
                await APICallLogManager.shared.logFailure(
                    type: .transcription,
                    provider: "Deepgram",
                    model: model,
                    endpoint: "/v1/listen",
                    durationMs: durationMs,
                    error: "Invalid response format"
                )
                throw TranscriptionProcessError.transcriptionFailed("Invalid response")
            }

            let duration = (json["metadata"] as? [String: Any])?["duration"] as? Double ?? Double(audioData.count) / 8000.0

            // Parse words with speakers
            var segments: [TranscriptSegment] = []
            var speakerSet = Set<Int>()

            if let words = alternatives.first?["words"] as? [[String: Any]] {
                var currentSpeaker: Int? = nil
                var currentStart: Double = 0
                var currentText = ""

                for word in words {
                    guard let wordText = word["word"] as? String,
                          let start = word["start"] as? Double,
                          let _ = word["end"] as? Double else { continue }

                    let speaker = word["speaker"] as? Int
                    if let s = speaker { speakerSet.insert(s) }

                    if speaker != currentSpeaker && !currentText.isEmpty {
                        segments.append(TranscriptSegment(
                            speaker: currentSpeaker.map { "Speaker \($0)" },
                            start: currentStart,
                            end: start,
                            text: currentText.trimmingCharacters(in: .whitespaces)
                        ))
                        currentText = ""
                        currentStart = start
                    }

                    currentSpeaker = speaker
                    if currentText.isEmpty { currentStart = start }
                    currentText += wordText + " "
                }

                if !currentText.isEmpty {
                    segments.append(TranscriptSegment(
                        speaker: currentSpeaker.map { "Speaker \($0)" },
                        start: currentStart,
                        end: duration,
                        text: currentText.trimmingCharacters(in: .whitespaces)
                    ))
                }
            }

            // $0.0043/minute for nova-2
            let costCents = Int(ceil((duration / 60.0) * 0.43))

            // Log successful transcription
            await APICallLogManager.shared.logSuccess(
                type: .transcription,
                provider: "Deepgram",
                model: model,
                endpoint: "/v1/listen",
                inputSizeBytes: audioData.count,
                durationMs: durationMs,
                costCents: costCents
            )

            logInfo("[TranscriptionProcess] Deepgram complete, duration: \(String(format: "%.1f", duration))s")

            return InternalResult(
                text: transcript,
                duration: duration,
                costCents: costCents,
                modelId: model,
                segments: segments.isEmpty ? nil : segments,
                speakerCount: speakerSet.isEmpty ? nil : speakerSet.count,
                language: options.language
            )
        } catch let error as TranscriptionProcessError {
            throw error
        } catch {
            let durationMs = Int((CFAbsoluteTimeGetCurrent() - callStartTime) * 1000)
            await APICallLogManager.shared.logFailure(
                type: .transcription,
                provider: "Deepgram",
                model: model,
                endpoint: "/v1/listen",
                durationMs: durationMs,
                error: error.localizedDescription
            )
            throw TranscriptionProcessError.networkError(error)
        }
    }

    // MARK: - LLM Diarization (for OpenAI which lacks native diarization)

    private struct LLMDiarizationResult {
        let segments: [TranscriptSegment]
        let speakerCount: Int
        let costCents: Int
    }

    private func performLLMDiarization(transcript: String) async -> LLMDiarizationResult {
        let callStartTime = CFAbsoluteTimeGetCurrent()

        guard let apiKey = KeychainHelper.readOpenAIKey() else {
            return LLMDiarizationResult(segments: [], speakerCount: 0, costCents: 0)
        }

        let truncated = String(transcript.prefix(8000))

        let prompt = """
        Analyze this meeting transcript and identify different speakers.
        Return a JSON array where each element has:
        - "speakerId": string like "speaker_0", "speaker_1"
        - "text": the text spoken by this speaker

        Return ONLY the JSON array.

        Transcript:
        \(truncated)
        """

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": "You are an expert at speaker diarization. Respond with valid JSON only."],
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 4000,
            "temperature": 0.3,
            "response_format": ["type": "json_object"]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let durationMs = Int((CFAbsoluteTimeGetCurrent() - callStartTime) * 1000)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                await APICallLogManager.shared.logFailure(
                    type: .diarization,
                    provider: "OpenAI",
                    model: "gpt-4o-mini",
                    endpoint: "/v1/chat/completions",
                    durationMs: durationMs,
                    error: "Invalid response"
                )
                return LLMDiarizationResult(segments: [], speakerCount: 0, costCents: 0)
            }

            let segments = parseLLMDiarizationResponse(content)
            let speakers = Set(segments.compactMap { $0.speaker })

            // Estimate cost
            let inputTokens = truncated.count / 4
            let outputTokens = 1000
            let costCents = Int(ceil(Double(inputTokens) * 0.00015 + Double(outputTokens) * 0.0006))

            // Log successful diarization
            await APICallLogManager.shared.logSuccess(
                type: .diarization,
                provider: "OpenAI",
                model: "gpt-4o-mini",
                endpoint: "/v1/chat/completions",
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                durationMs: durationMs,
                costCents: costCents
            )

            return LLMDiarizationResult(
                segments: segments,
                speakerCount: speakers.count,
                costCents: costCents
            )
        } catch {
            let durationMs = Int((CFAbsoluteTimeGetCurrent() - callStartTime) * 1000)
            await APICallLogManager.shared.logFailure(
                type: .diarization,
                provider: "OpenAI",
                model: "gpt-4o-mini",
                endpoint: "/v1/chat/completions",
                durationMs: durationMs,
                error: error.localizedDescription
            )
            logWarning("[TranscriptionProcess] LLM diarization failed: \(error)")
            return LLMDiarizationResult(segments: [], speakerCount: 0, costCents: 0)
        }
    }

    private func parseLLMDiarizationResponse(_ content: String) -> [TranscriptSegment] {
        guard let data = content.data(using: .utf8) else { return [] }

        do {
            var array: [[String: Any]] = []

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let segments = json["segments"] as? [[String: Any]] {
                    array = segments
                } else if let speakers = json["speakers"] as? [[String: Any]] {
                    array = speakers
                }
            } else if let directArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                array = directArray
            }

            var segments: [TranscriptSegment] = []
            var currentTime: TimeInterval = 0

            for item in array {
                guard let speakerId = item["speakerId"] as? String ?? item["speaker_id"] as? String ?? item["speaker"] as? String,
                      let text = item["text"] as? String else { continue }

                let wordCount = Double(text.split(separator: " ").count)
                let duration = max(1.0, wordCount / 2.5)

                segments.append(TranscriptSegment(
                    speaker: speakerId,
                    start: currentTime,
                    end: currentTime + duration,
                    text: text
                ))
                currentTime += duration
            }

            return segments
        } catch {
            return []
        }
    }

    // MARK: - Title Generation

    private func generateTitle(from transcript: String) async -> String? {
        let callStartTime = CFAbsoluteTimeGetCurrent()

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
            let durationMs = Int((CFAbsoluteTimeGetCurrent() - callStartTime) * 1000)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                await APICallLogManager.shared.logFailure(
                    type: .titleGeneration,
                    provider: "OpenAI",
                    model: "gpt-4o-mini",
                    endpoint: "/v1/chat/completions",
                    durationMs: durationMs,
                    error: "Invalid response"
                )
                return nil
            }

            let title = content.trimmingCharacters(in: .whitespacesAndNewlines)

            // Log successful title generation
            // GPT-4o-mini: $0.15/1M input, $0.60/1M output
            let inputTokens = truncated.count / 4 + 50  // prompt overhead
            let outputTokens = 20
            let costCents = max(1, Int(ceil(Double(inputTokens) * 0.00015 + Double(outputTokens) * 0.0006)))
            await APICallLogManager.shared.logSuccess(
                type: .titleGeneration,
                provider: "OpenAI",
                model: "gpt-4o-mini",
                endpoint: "/v1/chat/completions",
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                durationMs: durationMs,
                costCents: costCents
            )

            return title.isEmpty ? nil : title
        } catch {
            let durationMs = Int((CFAbsoluteTimeGetCurrent() - callStartTime) * 1000)
            await APICallLogManager.shared.logFailure(
                type: .titleGeneration,
                provider: "OpenAI",
                model: "gpt-4o-mini",
                endpoint: "/v1/chat/completions",
                durationMs: durationMs,
                error: error.localizedDescription
            )
            return nil
        }
    }

    // MARK: - Quality Validation

    /// Validate transcription quality using a cheap LLM call
    /// Detects rubbish, garbage, repetitive text, or nonsensical content
    private func validateTranscriptionQuality(transcript: String) async -> TranscriptionQualityResult {
        let callStartTime = CFAbsoluteTimeGetCurrent()

        // Quick heuristic checks first (free)
        let heuristicIssues = detectHeuristicIssues(transcript)
        if !heuristicIssues.isEmpty {
            logWarning("[TranscriptionProcess] Heuristic quality issues: \(heuristicIssues)")
            return TranscriptionQualityResult(
                isValid: false,
                hasRubbish: true,
                rubbishDescription: heuristicIssues,
                confidence: 0.9,
                costCents: 0
            )
        }

        // LLM check for subtle issues
        guard let apiKey = KeychainHelper.readOpenAIKey() else {
            // No API key, skip LLM validation
            return TranscriptionQualityResult(
                isValid: true,
                hasRubbish: false,
                rubbishDescription: nil,
                confidence: 0.5,
                costCents: 0
            )
        }

        // Sample the transcript - check beginning, middle, and end
        let sample = sampleTranscript(transcript, maxLength: 1500)

        let prompt = """
        Analyze this transcription for quality issues. Look for:
        1. Repetitive/looping text (same phrase repeated many times)
        2. Nonsensical word salad or garbage characters
        3. Hallucinated content (made-up names, numbers that don't fit)
        4. Encoding issues (mojibake, wrong characters)
        5. Music/sound descriptions instead of speech ("[music playing]" for entire transcript)

        Respond with JSON only:
        {"valid": true/false, "rubbish": true/false, "issue": "description if rubbish", "confidence": 0.0-1.0}

        Transcript sample:
        \(sample)
        """

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": "You are a transcription quality checker. Respond with valid JSON only."],
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 100,
            "temperature": 0.1,
            "response_format": ["type": "json_object"]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let durationMs = Int((CFAbsoluteTimeGetCurrent() - callStartTime) * 1000)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                await APICallLogManager.shared.logFailure(
                    type: .qualityValidation,
                    provider: "OpenAI",
                    model: "gpt-4o-mini",
                    endpoint: "/v1/chat/completions",
                    durationMs: durationMs,
                    error: "Invalid response"
                )
                // On failure, assume valid to not block transcription
                return TranscriptionQualityResult(
                    isValid: true,
                    hasRubbish: false,
                    rubbishDescription: nil,
                    confidence: 0.3,
                    costCents: 0
                )
            }

            // Parse response
            let result = parseQualityResponse(content)

            // Cost estimate: ~400 input tokens + 50 output tokens
            let inputTokens = sample.count / 4 + 100  // prompt overhead
            let outputTokens = 50
            let costCents = 1  // Roughly 0.1 cents, round up

            // Log the validation
            if result.hasRubbish {
                await APICallLogManager.shared.logSuccess(
                    type: .qualityValidation,
                    provider: "OpenAI",
                    model: "gpt-4o-mini",
                    endpoint: "/v1/chat/completions",
                    inputTokens: inputTokens,
                    outputTokens: outputTokens,
                    durationMs: durationMs,
                    costCents: costCents
                )
                logWarning("[TranscriptionProcess] LLM detected rubbish: \(result.rubbishDescription ?? "unknown")")
            } else {
                await APICallLogManager.shared.logSuccess(
                    type: .qualityValidation,
                    provider: "OpenAI",
                    model: "gpt-4o-mini",
                    endpoint: "/v1/chat/completions",
                    inputTokens: inputTokens,
                    outputTokens: outputTokens,
                    durationMs: durationMs,
                    costCents: costCents
                )
                logInfo("[TranscriptionProcess] Quality validation passed")
            }

            return TranscriptionQualityResult(
                isValid: result.isValid,
                hasRubbish: result.hasRubbish,
                rubbishDescription: result.rubbishDescription,
                confidence: result.confidence,
                costCents: costCents
            )

        } catch {
            let durationMs = Int((CFAbsoluteTimeGetCurrent() - callStartTime) * 1000)
            await APICallLogManager.shared.logFailure(
                type: .qualityValidation,
                provider: "OpenAI",
                model: "gpt-4o-mini",
                endpoint: "/v1/chat/completions",
                durationMs: durationMs,
                error: error.localizedDescription
            )
            // On network error, assume valid to not block
            return TranscriptionQualityResult(
                isValid: true,
                hasRubbish: false,
                rubbishDescription: nil,
                confidence: 0.3,
                costCents: 0
            )
        }
    }

    /// Quick heuristic checks for obvious issues (free, no API call)
    private func detectHeuristicIssues(_ transcript: String) -> String {
        var issues: [String] = []

        // Check for excessive repetition
        let words = transcript.lowercased().split(separator: " ")
        if words.count > 20 {
            // Check for 3+ word phrase repeated more than 5 times
            var phraseCount: [String: Int] = [:]
            for i in 0..<(words.count - 2) {
                let phrase = "\(words[i]) \(words[i+1]) \(words[i+2])"
                phraseCount[phrase, default: 0] += 1
            }
            if let maxRepeat = phraseCount.values.max(), maxRepeat > 5 {
                let repeatedPhrase = phraseCount.first { $0.value == maxRepeat }?.key ?? ""
                issues.append("Excessive repetition detected: '\(repeatedPhrase)' repeated \(maxRepeat)x")
            }
        }

        // Check for very short transcripts relative to expected content
        let charCount = transcript.count
        if charCount < 50 && words.count < 10 {
            // Very short, could be placeholder or error
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == "." || trimmed.lowercased().contains("inaudible") {
                issues.append("Transcript appears empty or inaudible")
            }
        }

        // Check for garbage characters (high proportion of non-alphanumeric)
        let alphanumericCount = transcript.filter { $0.isLetter || $0.isNumber || $0.isWhitespace }.count
        if charCount > 100 && Double(alphanumericCount) / Double(charCount) < 0.7 {
            issues.append("High proportion of non-standard characters")
        }

        // Check for [music] or similar taking up most of transcript
        let musicPattern = #"\[.*?(music|sound|noise|silence).*?\]"#
        if let regex = try? NSRegularExpression(pattern: musicPattern, options: .caseInsensitive) {
            let range = NSRange(transcript.startIndex..., in: transcript)
            let matches = regex.matches(in: transcript, range: range)
            let matchedLength = matches.reduce(0) { $0 + $1.range.length }
            if Double(matchedLength) > Double(charCount) * 0.5 {
                issues.append("Transcript is mostly sound/music descriptions")
            }
        }

        return issues.joined(separator: "; ")
    }

    /// Sample transcript for validation (beginning, middle, end)
    private func sampleTranscript(_ transcript: String, maxLength: Int) -> String {
        let length = transcript.count
        if length <= maxLength {
            return transcript
        }

        let sectionLength = maxLength / 3
        let beginning = String(transcript.prefix(sectionLength))

        let middleStart = transcript.index(transcript.startIndex, offsetBy: (length - sectionLength) / 2)
        let middleEnd = transcript.index(middleStart, offsetBy: sectionLength)
        let middle = String(transcript[middleStart..<middleEnd])

        let ending = String(transcript.suffix(sectionLength))

        return """
        [BEGINNING]:
        \(beginning)

        [MIDDLE]:
        \(middle)

        [END]:
        \(ending)
        """
    }

    /// Parse the LLM quality check response
    private func parseQualityResponse(_ content: String) -> TranscriptionQualityResult {
        guard let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return TranscriptionQualityResult(
                isValid: true,
                hasRubbish: false,
                rubbishDescription: nil,
                confidence: 0.3,
                costCents: 0
            )
        }

        let isValid = json["valid"] as? Bool ?? true
        let hasRubbish = json["rubbish"] as? Bool ?? false
        let issue = json["issue"] as? String
        let confidence = json["confidence"] as? Double ?? 0.5

        return TranscriptionQualityResult(
            isValid: isValid,
            hasRubbish: hasRubbish,
            rubbishDescription: hasRubbish ? issue : nil,
            confidence: confidence,
            costCents: 0
        )
    }
}
