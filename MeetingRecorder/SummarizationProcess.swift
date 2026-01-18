//
//  SummarizationProcess.swift
//  MeetingRecorder
//
//  Composable summarization process.
//  Generates meeting summaries, action items, key points from transcripts.
//

import Foundation

// MARK: - Process Result

/// Result from a summarization process
struct SummarizationProcessResult {
    let summary: String
    let keyPoints: [String]?
    let actionItems: [LegacyActionItem]?
    let decisions: [String]?
    let topics: [String]?

    /// Cost and performance metadata
    let costCents: Int
    let processingTime: TimeInterval
    let model: String
    let provider: SummarizationProvider
}

/// Legacy action item from old summarization (kept for backwards compat)
struct LegacyActionItem: Codable {
    let task: String
    let assignee: String?
    let dueDate: String?
}

/// Result from meeting intelligence extraction
struct MeetingIntelligenceResult {
    let brief: MeetingBrief
    let actionItems: [ActionItem]
    let costCents: Int
    let processingTime: TimeInterval
    let model: String
    let provider: SummarizationProvider
}

// MARK: - Provider

/// Providers for summarization
enum SummarizationProvider: String, CaseIterable {
    case openai
    case anthropic
    case gemini

    var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Claude"
        case .gemini: return "Gemini"
        }
    }

    var isConfigured: Bool {
        switch self {
        case .openai: return KeychainHelper.readOpenAIKey() != nil
        case .anthropic: return KeychainHelper.readAnthropicKey() != nil
        case .gemini: return KeychainHelper.readGeminiKey() != nil
        }
    }
}

// MARK: - Process Errors

enum SummarizationProcessError: LocalizedError {
    case noProviderConfigured
    case noAPIKey(SummarizationProvider)
    case emptyTranscript
    case networkError(Error)
    case serverError(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .noProviderConfigured:
            return "No summarization provider configured. Add an API key in Settings."
        case .noAPIKey(let provider):
            return "\(provider.displayName) API key not found."
        case .emptyTranscript:
            return "Cannot summarize an empty transcript."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .invalidResponse:
            return "Invalid response from summarization API."
        }
    }
}

// MARK: - Process Options

/// Configuration options for summarization
struct SummarizationProcessOptions {
    /// Which provider to use (nil = auto-select)
    var provider: SummarizationProvider?

    /// Model ID override
    var modelId: String?

    /// Include key points extraction
    var extractKeyPoints: Bool = true

    /// Include action items extraction
    var extractActionItems: Bool = true

    /// Include decisions extraction
    var extractDecisions: Bool = true

    /// Include topic detection
    var extractTopics: Bool = false

    /// Max length for summary (words)
    var maxSummaryLength: Int = 300

    /// Language for output
    var language: String?

    static let `default` = SummarizationProcessOptions()

    /// Quick summary only (no extraction)
    static let quick = SummarizationProcessOptions(
        extractKeyPoints: false,
        extractActionItems: false,
        extractDecisions: false,
        extractTopics: false,
        maxSummaryLength: 150
    )
}

// MARK: - Summarization Process

/// Orchestrates the summarization pipeline
actor SummarizationProcess {

    static let shared = SummarizationProcess()

    // MARK: - Main Entry Point

    /// Summarize a transcript
    func summarize(
        transcript: String,
        speakerSegments: [TranscriptSegment]? = nil,
        options: SummarizationProcessOptions = .default
    ) async throws -> SummarizationProcessResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SummarizationProcessError.emptyTranscript
        }

        // Select provider
        let provider = try selectProvider(preferred: options.provider)
        logInfo("[SummarizationProcess] Using provider: \(provider.displayName)")

        // Preprocess transcript
        let processedTranscript = preprocessTranscript(
            transcript: transcript,
            speakerSegments: speakerSegments
        )

        // Generate summary
        let result = try await performSummarization(
            transcript: processedTranscript,
            provider: provider,
            options: options
        )

        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        logInfo("[SummarizationProcess] Complete in \(String(format: "%.1f", processingTime))s")

        return SummarizationProcessResult(
            summary: result.summary,
            keyPoints: result.keyPoints,
            actionItems: result.actionItems,
            decisions: result.decisions,
            topics: result.topics,
            costCents: result.costCents,
            processingTime: processingTime,
            model: result.model,
            provider: provider
        )
    }

    // MARK: - Meeting Intelligence (NEW)

    /// Generate meeting intelligence: brief + action items using Gemini Flash 3
    func generateMeetingIntelligence(
        transcript: String,
        meetingId: UUID,
        meetingDate: Date,
        speakerSegments: [TranscriptSegment]? = nil,
        preferredProvider: SummarizationProvider? = nil
    ) async throws -> MeetingIntelligenceResult {
        let startTime = CFAbsoluteTimeGetCurrent()

        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SummarizationProcessError.emptyTranscript
        }

        // Default to Gemini for meeting intelligence (fast + cheap + good at structured output)
        let provider = try selectProviderForIntelligence(preferred: preferredProvider)
        logInfo("[SummarizationProcess] Generating meeting intelligence with: \(provider.displayName)")

        // Preprocess transcript
        let processedTranscript = preprocessTranscript(
            transcript: transcript,
            speakerSegments: speakerSegments
        )

        // Generate intelligence
        let result = try await performIntelligenceExtraction(
            transcript: processedTranscript,
            provider: provider,
            meetingId: meetingId,
            meetingDate: meetingDate
        )

        let processingTime = CFAbsoluteTimeGetCurrent() - startTime
        logInfo("[SummarizationProcess] Intelligence complete in \(String(format: "%.1f", processingTime))s - extracted \(result.actionItems.count) action items")

        return MeetingIntelligenceResult(
            brief: result.brief,
            actionItems: result.actionItems,
            costCents: result.costCents,
            processingTime: processingTime,
            model: result.model,
            provider: provider
        )
    }

    private func selectProviderForIntelligence(preferred: SummarizationProvider?) throws -> SummarizationProvider {
        if let preferred, preferred.isConfigured {
            return preferred
        }

        // Priority for intelligence: Gemini > OpenAI > Claude (Gemini is fast + cheap for structured output)
        let priority: [SummarizationProvider] = [.gemini, .openai, .anthropic]
        for provider in priority {
            if provider.isConfigured {
                return provider
            }
        }

        throw SummarizationProcessError.noProviderConfigured
    }

    private struct IntelligenceResult {
        let brief: MeetingBrief
        let actionItems: [ActionItem]
        let costCents: Int
        let model: String
    }

    private func performIntelligenceExtraction(
        transcript: String,
        provider: SummarizationProvider,
        meetingId: UUID,
        meetingDate: Date
    ) async throws -> IntelligenceResult {
        switch provider {
        case .gemini:
            return try await extractIntelligenceWithGemini(
                transcript: transcript,
                meetingId: meetingId,
                meetingDate: meetingDate
            )
        case .openai:
            return try await extractIntelligenceWithOpenAI(
                transcript: transcript,
                meetingId: meetingId,
                meetingDate: meetingDate
            )
        case .anthropic:
            return try await extractIntelligenceWithClaude(
                transcript: transcript,
                meetingId: meetingId,
                meetingDate: meetingDate
            )
        }
    }

    // MARK: - Gemini Intelligence Extraction

    private func extractIntelligenceWithGemini(
        transcript: String,
        meetingId: UUID,
        meetingDate: Date
    ) async throws -> IntelligenceResult {
        let callStartTime = CFAbsoluteTimeGetCurrent()

        guard let apiKey = KeychainHelper.readGeminiKey() else {
            throw SummarizationProcessError.noAPIKey(.gemini)
        }

        let model = "gemini-2.0-flash-exp"
        let prompt = buildIntelligencePrompt(transcript: transcript)

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let payload: [String: Any] = [
            "contents": [[
                "parts": [["text": prompt]]
            ]],
            "generationConfig": [
                "temperature": 0.2,
                "maxOutputTokens": 4000,
                "responseMimeType": "application/json"
            ],
            "systemInstruction": [
                "parts": [["text": "You are an expert meeting analyst. Extract actionable intelligence from meeting transcripts. Be precise about action items - only include explicitly mentioned commitments."]]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        let durationMs = Int((CFAbsoluteTimeGetCurrent() - callStartTime) * 1000)

        guard let httpResponse = response as? HTTPURLResponse else {
            await APICallLogManager.shared.logFailure(
                type: .summarization,
                provider: "Gemini",
                model: model,
                endpoint: "/v1beta/models/\(model):generateContent",
                durationMs: durationMs,
                error: "Invalid response"
            )
            throw SummarizationProcessError.networkError(NSError(domain: "Gemini", code: -1))
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown"
            await APICallLogManager.shared.logFailure(
                type: .summarization,
                provider: "Gemini",
                model: model,
                endpoint: "/v1beta/models/\(model):generateContent",
                durationMs: durationMs,
                error: "HTTP \(httpResponse.statusCode): \(errorMessage)"
            )
            throw SummarizationProcessError.serverError(httpResponse.statusCode, errorMessage)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            await APICallLogManager.shared.logFailure(
                type: .summarization,
                provider: "Gemini",
                model: model,
                endpoint: "/v1beta/models/\(model):generateContent",
                durationMs: durationMs,
                error: "Invalid response format"
            )
            throw SummarizationProcessError.invalidResponse
        }

        // Estimate cost (Gemini Flash is very cheap)
        let inputTokens = transcript.count / 4
        let outputTokens = text.count / 4
        let costCents = max(1, Int(ceil((Double(inputTokens) + Double(outputTokens)) * 0.0001)))

        // Log success
        await APICallLogManager.shared.logSuccess(
            type: .summarization,
            provider: "Gemini",
            model: model,
            endpoint: "/v1beta/models/\(model):generateContent",
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            durationMs: durationMs,
            costCents: costCents
        )

        return try parseIntelligenceResponse(text, model: model, costCents: costCents, meetingId: meetingId, meetingDate: meetingDate)
    }

    // MARK: - OpenAI Intelligence Extraction

    private func extractIntelligenceWithOpenAI(
        transcript: String,
        meetingId: UUID,
        meetingDate: Date
    ) async throws -> IntelligenceResult {
        let callStartTime = CFAbsoluteTimeGetCurrent()

        guard let apiKey = KeychainHelper.readOpenAIKey() else {
            throw SummarizationProcessError.noAPIKey(.openai)
        }

        let model = "gpt-4o-mini"
        let prompt = buildIntelligencePrompt(transcript: transcript)

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "You are an expert meeting analyst. Extract actionable intelligence from meeting transcripts. Be precise about action items - only include explicitly mentioned commitments."],
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 4000,
            "temperature": 0.2,
            "response_format": ["type": "json_object"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let durationMs = Int((CFAbsoluteTimeGetCurrent() - callStartTime) * 1000)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown"
            throw SummarizationProcessError.serverError((response as? HTTPURLResponse)?.statusCode ?? -1, errorMessage)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw SummarizationProcessError.invalidResponse
        }

        let inputTokens = transcript.count / 4
        let outputTokens = text.count / 4
        let costCents = Int(ceil(Double(inputTokens) * 0.00015 + Double(outputTokens) * 0.0006))

        await APICallLogManager.shared.logSuccess(
            type: .summarization,
            provider: "OpenAI",
            model: model,
            endpoint: "/v1/chat/completions",
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            durationMs: durationMs,
            costCents: costCents
        )

        return try parseIntelligenceResponse(text, model: model, costCents: costCents, meetingId: meetingId, meetingDate: meetingDate)
    }

    // MARK: - Claude Intelligence Extraction

    private func extractIntelligenceWithClaude(
        transcript: String,
        meetingId: UUID,
        meetingDate: Date
    ) async throws -> IntelligenceResult {
        let callStartTime = CFAbsoluteTimeGetCurrent()

        guard let apiKey = KeychainHelper.readAnthropicKey() else {
            throw SummarizationProcessError.noAPIKey(.anthropic)
        }

        let model = "claude-3-5-haiku-20241022"
        let prompt = buildIntelligencePrompt(transcript: transcript)

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4000,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "system": "You are an expert meeting analyst. Extract actionable intelligence from meeting transcripts. Be precise about action items - only include explicitly mentioned commitments. Always respond with valid JSON."
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let durationMs = Int((CFAbsoluteTimeGetCurrent() - callStartTime) * 1000)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown"
            throw SummarizationProcessError.serverError((response as? HTTPURLResponse)?.statusCode ?? -1, errorMessage)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            throw SummarizationProcessError.invalidResponse
        }

        let inputTokens = transcript.count / 4
        let outputTokens = text.count / 4
        let costCents = Int(ceil(Double(inputTokens) * 0.000025 + Double(outputTokens) * 0.000125))

        await APICallLogManager.shared.logSuccess(
            type: .summarization,
            provider: "Anthropic",
            model: model,
            endpoint: "/v1/messages",
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            durationMs: durationMs,
            costCents: costCents
        )

        return try parseIntelligenceResponse(text, model: model, costCents: costCents, meetingId: meetingId, meetingDate: meetingDate)
    }

    // MARK: - Intelligence Prompt

    private func buildIntelligencePrompt(transcript: String) -> String {
        // Truncate if too long
        let maxTranscriptLength = 50000
        let truncatedTranscript = transcript.count > maxTranscriptLength
            ? String(transcript.prefix(maxTranscriptLength)) + "\n\n[... transcript truncated ...]"
            : transcript

        return """
        Analyze this meeting transcript and extract actionable intelligence.

        Respond with JSON in this exact format:
        {
            "brief": {
                "purpose": "One clear sentence describing the meeting's purpose",
                "participants": ["Name1", "Name2"],
                "discussion_points": ["Key topic 1", "Key topic 2", ...],
                "decisions_made": ["Decision 1", ...],
                "decisions_pending": ["Pending decision 1", ...],
                "blockers": ["Blocker 1", ...] or null if none
            },
            "action_items": [
                {
                    "task": "Clear, actionable task description",
                    "assignee": "Person name" or null if unclear,
                    "due_suggestion": "by Friday" or "next week" or "ASAP" or null,
                    "priority": "high" | "medium" | "low",
                    "context": "Brief context from meeting" or null
                }
            ]
        }

        Guidelines:
        - Extract ONLY explicitly mentioned action items (things someone committed to DO)
        - Infer priority from urgency language ("ASAP", "critical", "when you get a chance")
        - Use exact names mentioned in transcript for assignees
        - If no clear assignee, leave null (don't guess)
        - Due suggestions should use relative terms from the meeting context
        - Keep discussion points to 3-7 most important topics
        - Decisions must be explicit agreements, not assumptions
        - For participants, extract names mentioned as attendees/speakers

        TRANSCRIPT:
        \(truncatedTranscript)
        """
    }

    // MARK: - Intelligence Response Parsing

    private func parseIntelligenceResponse(
        _ content: String,
        model: String,
        costCents: Int,
        meetingId: UUID,
        meetingDate: Date
    ) throws -> IntelligenceResult {
        // Clean up response
        var jsonString = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle markdown code blocks
        if jsonString.hasPrefix("```json") {
            jsonString = String(jsonString.dropFirst(7))
        } else if jsonString.hasPrefix("```") {
            jsonString = String(jsonString.dropFirst(3))
        }
        if jsonString.hasSuffix("```") {
            jsonString = String(jsonString.dropLast(3))
        }
        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SummarizationProcessError.invalidResponse
        }

        // Parse brief
        guard let briefJson = json["brief"] as? [String: Any] else {
            throw SummarizationProcessError.invalidResponse
        }

        let brief = MeetingBrief(
            purpose: briefJson["purpose"] as? String ?? "Meeting summary",
            participants: briefJson["participants"] as? [String] ?? [],
            discussionPoints: briefJson["discussion_points"] as? [String] ?? [],
            decisionsMade: briefJson["decisions_made"] as? [String] ?? [],
            decisionsPending: briefJson["decisions_pending"] as? [String] ?? [],
            blockers: briefJson["blockers"] as? [String],
            generatedAt: Date(),
            model: model,
            provider: model.contains("gemini") ? "Gemini" : (model.contains("gpt") ? "OpenAI" : "Anthropic")
        )

        // Parse action items
        var actionItems: [ActionItem] = []
        if let itemsJson = json["action_items"] as? [[String: Any]] {
            for itemJson in itemsJson {
                guard let task = itemJson["task"] as? String, !task.isEmpty else { continue }

                let dueSuggestion = itemJson["due_suggestion"] as? String
                let dueDate = parseDueDate(from: dueSuggestion, relativeTo: meetingDate)
                let priorityStr = (itemJson["priority"] as? String)?.lowercased() ?? "medium"

                let item = ActionItem(
                    meetingId: meetingId,
                    task: task,
                    assignee: itemJson["assignee"] as? String,
                    dueDate: dueDate,
                    dueSuggestion: dueSuggestion,
                    priority: ActionItem.Priority(rawValue: priorityStr) ?? .medium,
                    context: itemJson["context"] as? String
                )
                actionItems.append(item)
            }
        }

        return IntelligenceResult(
            brief: brief,
            actionItems: actionItems,
            costCents: costCents,
            model: model
        )
    }

    private func parseDueDate(from suggestion: String?, relativeTo baseDate: Date) -> Date? {
        guard let suggestion = suggestion?.lowercased() else { return nil }

        let calendar = Calendar.current

        // Common patterns
        if suggestion.contains("today") || suggestion.contains("asap") || suggestion.contains("immediately") {
            return calendar.startOfDay(for: baseDate)
        }
        if suggestion.contains("tomorrow") {
            return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: baseDate))
        }
        if suggestion.contains("next week") {
            return calendar.date(byAdding: .weekOfYear, value: 1, to: calendar.startOfDay(for: baseDate))
        }
        if suggestion.contains("end of week") || suggestion.contains("by friday") {
            // Find next Friday
            var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: baseDate)
            components.weekday = 6 // Friday
            return calendar.date(from: components)
        }
        if suggestion.contains("end of day") || suggestion.contains("eod") {
            return calendar.startOfDay(for: baseDate)
        }

        // Try to parse day names
        let dayNames = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        for (index, dayName) in dayNames.enumerated() {
            if suggestion.contains(dayName) {
                // Find next occurrence of this day
                let targetWeekday = index + 2 // Calendar uses 1=Sunday
                var components = DateComponents()
                components.weekday = targetWeekday > 7 ? targetWeekday - 7 : targetWeekday
                return calendar.nextDate(after: baseDate, matching: components, matchingPolicy: .nextTime)
            }
        }

        return nil
    }

    // MARK: - Provider Selection

    private func selectProvider(preferred: SummarizationProvider?) throws -> SummarizationProvider {
        if let preferred, preferred.isConfigured {
            return preferred
        }

        // Priority: OpenAI > Claude > Gemini
        let priority: [SummarizationProvider] = [.openai, .anthropic, .gemini]
        for provider in priority {
            if provider.isConfigured {
                return provider
            }
        }

        throw SummarizationProcessError.noProviderConfigured
    }

    // MARK: - Preprocessing

    private func preprocessTranscript(
        transcript: String,
        speakerSegments: [TranscriptSegment]?
    ) -> String {
        // If we have speaker segments, format them nicely
        if let segments = speakerSegments, !segments.isEmpty {
            return segments.map { seg in
                let speaker = seg.speaker ?? "Unknown"
                let time = formatTime(seg.start)
                return "[\(time)] \(speaker): \(seg.text)"
            }.joined(separator: "\n")
        }

        return transcript
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    // MARK: - Summarization Dispatch

    private struct InternalResult {
        let summary: String
        let keyPoints: [String]?
        let actionItems: [LegacyActionItem]?
        let decisions: [String]?
        let topics: [String]?
        let costCents: Int
        let model: String
    }

    private func performSummarization(
        transcript: String,
        provider: SummarizationProvider,
        options: SummarizationProcessOptions
    ) async throws -> InternalResult {
        switch provider {
        case .openai:
            return try await summarizeWithOpenAI(transcript: transcript, options: options)
        case .anthropic:
            return try await summarizeWithClaude(transcript: transcript, options: options)
        case .gemini:
            return try await summarizeWithGemini(transcript: transcript, options: options)
        }
    }

    // MARK: - OpenAI Summarization

    private func summarizeWithOpenAI(
        transcript: String,
        options: SummarizationProcessOptions
    ) async throws -> InternalResult {
        let callStartTime = CFAbsoluteTimeGetCurrent()

        guard let apiKey = KeychainHelper.readOpenAIKey() else {
            throw SummarizationProcessError.noAPIKey(.openai)
        }

        let model = options.modelId ?? "gpt-4o-mini"
        let prompt = buildPrompt(transcript: transcript, options: options)

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "You are an expert meeting summarizer. Extract key information concisely."],
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 2000,
            "temperature": 0.3,
            "response_format": ["type": "json_object"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let durationMs = Int((CFAbsoluteTimeGetCurrent() - callStartTime) * 1000)

            guard let httpResponse = response as? HTTPURLResponse else {
                await APICallLogManager.shared.logFailure(
                    type: .summarization,
                    provider: "OpenAI",
                    model: model,
                    endpoint: "/v1/chat/completions",
                    durationMs: durationMs,
                    error: "Invalid response"
                )
                throw SummarizationProcessError.networkError(NSError(domain: "OpenAI", code: -1))
            }

            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown"
                await APICallLogManager.shared.logFailure(
                    type: .summarization,
                    provider: "OpenAI",
                    model: model,
                    endpoint: "/v1/chat/completions",
                    durationMs: durationMs,
                    error: "HTTP \(httpResponse.statusCode): \(errorMessage)"
                )
                throw SummarizationProcessError.serverError(httpResponse.statusCode, errorMessage)
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                await APICallLogManager.shared.logFailure(
                    type: .summarization,
                    provider: "OpenAI",
                    model: model,
                    endpoint: "/v1/chat/completions",
                    durationMs: durationMs,
                    error: "Invalid response format"
                )
                throw SummarizationProcessError.invalidResponse
            }

            // Estimate cost
            let inputTokens = transcript.count / 4
            let outputTokens = content.count / 4
            let costCents = Int(ceil(Double(inputTokens) * 0.00015 + Double(outputTokens) * 0.0006))

            // Log successful summarization
            await APICallLogManager.shared.logSuccess(
                type: .summarization,
                provider: "OpenAI",
                model: model,
                endpoint: "/v1/chat/completions",
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                durationMs: durationMs,
                costCents: costCents
            )

            return try parseJSONResponse(content, model: model, costCents: costCents)
        } catch let error as SummarizationProcessError {
            throw error
        } catch {
            let durationMs = Int((CFAbsoluteTimeGetCurrent() - callStartTime) * 1000)
            await APICallLogManager.shared.logFailure(
                type: .summarization,
                provider: "OpenAI",
                model: model,
                endpoint: "/v1/chat/completions",
                durationMs: durationMs,
                error: error.localizedDescription
            )
            throw SummarizationProcessError.networkError(error)
        }
    }

    // MARK: - Claude Summarization

    private func summarizeWithClaude(
        transcript: String,
        options: SummarizationProcessOptions
    ) async throws -> InternalResult {
        let callStartTime = CFAbsoluteTimeGetCurrent()

        guard let apiKey = KeychainHelper.readAnthropicKey() else {
            throw SummarizationProcessError.noAPIKey(.anthropic)
        }

        let model = options.modelId ?? "claude-3-5-haiku-20241022"
        let prompt = buildPrompt(transcript: transcript, options: options)

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2000,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "system": "You are an expert meeting summarizer. Extract key information concisely. Always respond with valid JSON."
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let durationMs = Int((CFAbsoluteTimeGetCurrent() - callStartTime) * 1000)

            guard let httpResponse = response as? HTTPURLResponse else {
                await APICallLogManager.shared.logFailure(
                    type: .summarization,
                    provider: "Anthropic",
                    model: model,
                    endpoint: "/v1/messages",
                    durationMs: durationMs,
                    error: "Invalid response"
                )
                throw SummarizationProcessError.networkError(NSError(domain: "Anthropic", code: -1))
            }

            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown"
                await APICallLogManager.shared.logFailure(
                    type: .summarization,
                    provider: "Anthropic",
                    model: model,
                    endpoint: "/v1/messages",
                    durationMs: durationMs,
                    error: "HTTP \(httpResponse.statusCode): \(errorMessage)"
                )
                throw SummarizationProcessError.serverError(httpResponse.statusCode, errorMessage)
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = json["content"] as? [[String: Any]],
                  let text = content.first?["text"] as? String else {
                await APICallLogManager.shared.logFailure(
                    type: .summarization,
                    provider: "Anthropic",
                    model: model,
                    endpoint: "/v1/messages",
                    durationMs: durationMs,
                    error: "Invalid response format"
                )
                throw SummarizationProcessError.invalidResponse
            }

            // Estimate cost (Haiku: $0.25/1M input, $1.25/1M output)
            let inputTokens = transcript.count / 4
            let outputTokens = text.count / 4
            let costCents = Int(ceil(Double(inputTokens) * 0.000025 + Double(outputTokens) * 0.000125))

            // Log successful summarization
            await APICallLogManager.shared.logSuccess(
                type: .summarization,
                provider: "Anthropic",
                model: model,
                endpoint: "/v1/messages",
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                durationMs: durationMs,
                costCents: costCents
            )

            return try parseJSONResponse(text, model: model, costCents: costCents)
        } catch let error as SummarizationProcessError {
            throw error
        } catch {
            let durationMs = Int((CFAbsoluteTimeGetCurrent() - callStartTime) * 1000)
            await APICallLogManager.shared.logFailure(
                type: .summarization,
                provider: "Anthropic",
                model: model,
                endpoint: "/v1/messages",
                durationMs: durationMs,
                error: error.localizedDescription
            )
            throw SummarizationProcessError.networkError(error)
        }
    }

    // MARK: - Gemini Summarization

    private func summarizeWithGemini(
        transcript: String,
        options: SummarizationProcessOptions
    ) async throws -> InternalResult {
        let callStartTime = CFAbsoluteTimeGetCurrent()

        guard let apiKey = KeychainHelper.readGeminiKey() else {
            throw SummarizationProcessError.noAPIKey(.gemini)
        }

        let model = options.modelId ?? "gemini-2.0-flash"
        let prompt = buildPrompt(transcript: transcript, options: options)

        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let payload: [String: Any] = [
            "contents": [[
                "parts": [["text": prompt]]
            ]],
            "generationConfig": [
                "temperature": 0.3,
                "maxOutputTokens": 2000,
                "responseMimeType": "application/json"
            ],
            "systemInstruction": [
                "parts": [["text": "You are an expert meeting summarizer. Extract key information concisely."]]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let durationMs = Int((CFAbsoluteTimeGetCurrent() - callStartTime) * 1000)

            guard let httpResponse = response as? HTTPURLResponse else {
                await APICallLogManager.shared.logFailure(
                    type: .summarization,
                    provider: "Gemini",
                    model: model,
                    endpoint: "/v1beta/models/\(model):generateContent",
                    durationMs: durationMs,
                    error: "Invalid response"
                )
                throw SummarizationProcessError.networkError(NSError(domain: "Gemini", code: -1))
            }

            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown"
                await APICallLogManager.shared.logFailure(
                    type: .summarization,
                    provider: "Gemini",
                    model: model,
                    endpoint: "/v1beta/models/\(model):generateContent",
                    durationMs: durationMs,
                    error: "HTTP \(httpResponse.statusCode): \(errorMessage)"
                )
                throw SummarizationProcessError.serverError(httpResponse.statusCode, errorMessage)
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let text = parts.first?["text"] as? String else {
                await APICallLogManager.shared.logFailure(
                    type: .summarization,
                    provider: "Gemini",
                    model: model,
                    endpoint: "/v1beta/models/\(model):generateContent",
                    durationMs: durationMs,
                    error: "Invalid response format"
                )
                throw SummarizationProcessError.invalidResponse
            }

            // Estimate cost (very cheap for Flash)
            let inputTokens = transcript.count / 4
            let outputTokens = text.count / 4
            let costCents = max(1, Int(ceil((Double(inputTokens) + Double(outputTokens)) * 0.0001)))

            // Log successful summarization
            await APICallLogManager.shared.logSuccess(
                type: .summarization,
                provider: "Gemini",
                model: model,
                endpoint: "/v1beta/models/\(model):generateContent",
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                durationMs: durationMs,
                costCents: costCents
            )

            return try parseJSONResponse(text, model: model, costCents: costCents)
        } catch let error as SummarizationProcessError {
            throw error
        } catch {
            let durationMs = Int((CFAbsoluteTimeGetCurrent() - callStartTime) * 1000)
            await APICallLogManager.shared.logFailure(
                type: .summarization,
                provider: "Gemini",
                model: model,
                endpoint: "/v1beta/models/\(model):generateContent",
                durationMs: durationMs,
                error: error.localizedDescription
            )
            throw SummarizationProcessError.networkError(error)
        }
    }

    // MARK: - Prompt Building

    private func buildPrompt(transcript: String, options: SummarizationProcessOptions) -> String {
        // Truncate if too long
        let maxTranscriptLength = 30000
        let truncatedTranscript = transcript.count > maxTranscriptLength
            ? String(transcript.prefix(maxTranscriptLength)) + "\n\n[... transcript truncated ...]"
            : transcript

        var extractionInstructions: [String] = []

        if options.extractKeyPoints {
            extractionInstructions.append("\"key_points\": array of 3-7 key points discussed")
        }
        if options.extractActionItems {
            extractionInstructions.append("\"action_items\": array of {\"task\": string, \"assignee\": string or null, \"dueDate\": string or null}")
        }
        if options.extractDecisions {
            extractionInstructions.append("\"decisions\": array of decisions made during the meeting")
        }
        if options.extractTopics {
            extractionInstructions.append("\"topics\": array of main topics discussed")
        }

        let langInstruction = options.language != nil
            ? "Respond in \(options.language!)."
            : ""

        return """
        Summarize this meeting transcript. \(langInstruction)

        Respond with JSON in this exact format:
        {
            "summary": "A clear \(options.maxSummaryLength)-word summary of the meeting"\(extractionInstructions.isEmpty ? "" : ",")
            \(extractionInstructions.joined(separator: ",\n            "))
        }

        TRANSCRIPT:
        \(truncatedTranscript)
        """
    }

    // MARK: - Response Parsing

    private func parseJSONResponse(_ content: String, model: String, costCents: Int) throws -> InternalResult {
        // Try to extract JSON from the response
        var jsonString = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle markdown code blocks
        if jsonString.hasPrefix("```json") {
            jsonString = String(jsonString.dropFirst(7))
        } else if jsonString.hasPrefix("```") {
            jsonString = String(jsonString.dropFirst(3))
        }
        if jsonString.hasSuffix("```") {
            jsonString = String(jsonString.dropLast(3))
        }
        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // If parsing fails, treat the whole response as the summary
            return InternalResult(
                summary: content,
                keyPoints: nil,
                actionItems: nil,
                decisions: nil,
                topics: nil,
                costCents: costCents,
                model: model
            )
        }

        let summary = json["summary"] as? String ?? content
        let keyPoints = json["key_points"] as? [String]
        let decisions = json["decisions"] as? [String]
        let topics = json["topics"] as? [String]

        // Parse action items
        var actionItems: [LegacyActionItem]? = nil
        if let items = json["action_items"] as? [[String: Any]] {
            actionItems = items.compactMap { item in
                guard let task = item["task"] as? String else { return nil }
                return LegacyActionItem(
                    task: task,
                    assignee: item["assignee"] as? String,
                    dueDate: item["dueDate"] as? String ?? item["due_date"] as? String
                )
            }
            if actionItems?.isEmpty == true { actionItems = nil }
        }

        return InternalResult(
            summary: summary,
            keyPoints: keyPoints,
            actionItems: actionItems,
            decisions: decisions,
            topics: topics,
            costCents: costCents,
            model: model
        )
    }
}

// Note: readAnthropicKey is defined in KeychainHelper.swift
