//
//  PostProcessingService.swift
//  MeetingRecorder
//
//  Service for post-processing transcripts with GPT-4o-mini:
//  - Generate summaries using templates
//  - Extract action items
//  - Diarize and clean up transcripts
//

import Foundation

/// Errors during post-processing
enum PostProcessingError: LocalizedError {
    case noAPIKey
    case invalidAPIKey
    case networkError(Error)
    case rateLimited
    case invalidResponse
    case serverError(Int, String)
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "OpenAI API key not found. Please add your API key in Settings."
        case .invalidAPIKey:
            return "Invalid API key. Please check your OpenAI API key."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .rateLimited:
            return "Rate limited. Please try again in a moment."
        case .invalidResponse:
            return "Invalid response from OpenAI API"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .emptyTranscript:
            return "Cannot process empty transcript"
        }
    }
}

/// Result from post-processing
struct PostProcessingResult {
    let content: String
    let inputTokens: Int
    let outputTokens: Int
    let costCents: Int
    let latencyMs: Int
}

/// Service for AI-powered post-processing of transcripts
actor PostProcessingService {
    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    /// GPT-4o-mini pricing (as of Jan 2025)
    /// Input: $0.15 / 1M tokens = $0.00015 / 1K tokens
    /// Output: $0.60 / 1M tokens = $0.0006 / 1K tokens
    private let inputCostPer1KTokens: Double = 0.00015
    private let outputCostPer1KTokens: Double = 0.0006

    /// The model to use for post-processing
    let model = "gpt-4o-mini"

    /// Process a transcript with a given template
    /// - Parameters:
    ///   - transcript: The raw transcript text
    ///   - template: The summary template to use
    /// - Returns: PostProcessingResult with content and usage stats
    func process(transcript: String, template: SummaryTemplate) async throws -> PostProcessingResult {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PostProcessingError.emptyTranscript
        }

        guard let apiKey = KeychainHelper.readOpenAIKey() else {
            throw PostProcessingError.noAPIKey
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        // Build the user prompt by replacing {{transcript}}
        let userPrompt = template.userPromptTemplate
            .replacingOccurrences(of: "{{transcript}}", with: transcript)

        // Build request
        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": template.systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "max_tokens": 4096,
            "temperature": 0.3  // Lower temperature for more consistent output
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 60  // 60 second timeout for longer transcripts

        // Make request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PostProcessingError.invalidResponse
        }

        // Handle HTTP errors
        if httpResponse.statusCode != 200 {
            try handleHTTPError(statusCode: httpResponse.statusCode, data: data)
        }

        // Parse response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw PostProcessingError.invalidResponse
        }

        // Extract usage info
        let usage = json["usage"] as? [String: Any]
        let inputTokens = usage?["prompt_tokens"] as? Int ?? 0
        let outputTokens = usage?["completion_tokens"] as? Int ?? 0

        // Calculate cost in cents
        let inputCost = Double(inputTokens) / 1000.0 * inputCostPer1KTokens
        let outputCost = Double(outputTokens) / 1000.0 * outputCostPer1KTokens
        let totalCostDollars = inputCost + outputCost
        let costCents = Int(ceil(totalCostDollars * 100))

        let latencyMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

        print("[PostProcessingService] Processed with \(template.name)")
        print("[PostProcessingService] Tokens: \(inputTokens) in, \(outputTokens) out")
        print("[PostProcessingService] Cost: \(costCents) cents, Latency: \(latencyMs)ms")

        return PostProcessingResult(
            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            costCents: costCents,
            latencyMs: latencyMs
        )
    }

    /// Process transcript with multiple templates at once
    /// - Parameters:
    ///   - transcript: The raw transcript
    ///   - templates: Array of templates to apply
    /// - Returns: Array of ProcessedSummary results
    func processMultiple(transcript: String, templates: [SummaryTemplate]) async throws -> [ProcessedSummary] {
        var results: [ProcessedSummary] = []

        for template in templates {
            do {
                let result = try await process(transcript: transcript, template: template)
                let summary = ProcessedSummary(
                    templateId: template.id,
                    templateName: template.name,
                    outputFormat: template.outputFormat,
                    content: result.content,
                    modelUsed: model,
                    costCents: result.costCents
                )
                results.append(summary)
            } catch {
                print("[PostProcessingService] Failed to process with \(template.name): \(error)")
                // Continue with other templates even if one fails
            }
        }

        return results
    }

    /// Quick action item extraction (uses built-in template)
    func extractActionItems(from transcript: String) async throws -> [String] {
        let result = try await process(transcript: transcript, template: .actionItems)

        // Parse the markdown output to extract action items
        var items: [String] = []
        let lines = result.content.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Match lines starting with "- [ ]" or "- [x]" or just "-"
            if trimmed.hasPrefix("- [ ]") {
                let item = trimmed
                    .replacingOccurrences(of: "- [ ]", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !item.isEmpty {
                    items.append(item)
                }
            } else if trimmed.hasPrefix("- [x]") {
                let item = trimmed
                    .replacingOccurrences(of: "- [x]", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !item.isEmpty {
                    items.append(item)
                }
            }
        }

        return items
    }

    /// Generate a clean, diarized transcript
    func generateDiarizedTranscript(from transcript: String) async throws -> String {
        let result = try await process(transcript: transcript, template: .diarizedTranscript)
        return result.content
    }

    /// Generate executive summary
    func generateSummary(from transcript: String) async throws -> String {
        let result = try await process(transcript: transcript, template: .executiveSummary)
        return result.content
    }

    // MARK: - Dictation Cleanup

    /// Settings for dictation cleanup
    struct DictationCleanupSettings {
        var addPunctuation: Bool = true
        var addParagraphs: Bool = true
        var writingStyle: String = "natural"  // natural, professional, casual, technical
        var customInstructions: String = ""

        static var fromUserDefaults: DictationCleanupSettings {
            let defaults = UserDefaults.standard
            return DictationCleanupSettings(
                addPunctuation: defaults.bool(forKey: "dictationAddPunctuation"),
                addParagraphs: defaults.bool(forKey: "dictationAddParagraphs"),
                writingStyle: defaults.string(forKey: "dictationWritingStyle") ?? "natural",
                customInstructions: defaults.string(forKey: "dictationCustomPrompt") ?? ""
            )
        }
    }

    /// Clean up dictation text using a fast LLM pass
    /// This adds punctuation, paragraphs, and applies writing style
    /// - Parameters:
    ///   - text: Raw transcribed text from dictation
    ///   - settings: Cleanup settings (defaults to user preferences)
    /// - Returns: Cleaned up text ready to paste
    func cleanupDictation(_ text: String, settings: DictationCleanupSettings? = nil) async throws -> PostProcessingResult {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PostProcessingError.emptyTranscript
        }

        guard let apiKey = KeychainHelper.readOpenAIKey() else {
            throw PostProcessingError.noAPIKey
        }

        let settings = settings ?? DictationCleanupSettings.fromUserDefaults
        let startTime = CFAbsoluteTimeGetCurrent()

        // Build dynamic system prompt based on settings
        var instructions: [String] = []
        instructions.append("You are a dictation cleanup assistant. Your job is to clean up transcribed speech into well-formatted text.")
        instructions.append("IMPORTANT: Output ONLY the cleaned text. No explanations, no markdown formatting, no quotes around the text.")

        if settings.addPunctuation {
            instructions.append("Add appropriate punctuation: periods, commas, question marks, etc.")
        }

        if settings.addParagraphs {
            instructions.append("Add paragraph breaks where there are natural topic changes or pauses.")
        }

        let styleInstructions: String
        switch settings.writingStyle {
        case "professional":
            styleInstructions = "Use professional, formal language. Avoid contractions. Be concise."
        case "casual":
            styleInstructions = "Keep it conversational and friendly. Contractions are fine."
        case "technical":
            styleInstructions = "Use precise technical language. Be exact with terminology."
        default: // "natural"
            styleInstructions = "Keep the natural spoken style. Minimal changes beyond punctuation."
        }
        instructions.append(styleInstructions)

        if !settings.customInstructions.isEmpty {
            instructions.append("Additional instructions: \(settings.customInstructions)")
        }

        instructions.append("Remove filler words like 'um', 'uh', 'like' (when used as filler), 'you know'.")
        instructions.append("Fix obvious grammatical errors but preserve the speaker's intended meaning.")

        let systemPrompt = instructions.joined(separator: "\n")

        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "max_tokens": 2048,
            "temperature": 0.2  // Low temperature for consistent cleanup
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 30  // 30 seconds for dictation (should be fast)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PostProcessingError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            try handleHTTPError(statusCode: httpResponse.statusCode, data: data)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw PostProcessingError.invalidResponse
        }

        let usage = json["usage"] as? [String: Any]
        let inputTokens = usage?["prompt_tokens"] as? Int ?? 0
        let outputTokens = usage?["completion_tokens"] as? Int ?? 0

        let inputCost = Double(inputTokens) / 1000.0 * inputCostPer1KTokens
        let outputCost = Double(outputTokens) / 1000.0 * outputCostPer1KTokens
        let costCents = Int(ceil((inputCost + outputCost) * 100))

        let latencyMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

        print("[PostProcessingService] Dictation cleanup completed")
        print("[PostProcessingService] Tokens: \(inputTokens) in, \(outputTokens) out, Cost: \(costCents)¢, Latency: \(latencyMs)ms")

        return PostProcessingResult(
            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            costCents: costCents,
            latencyMs: latencyMs
        )
    }

    // MARK: - Private Helpers

    private func handleHTTPError(statusCode: Int, data: Data) throws -> Never {
        let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"

        print("[PostProcessingService] HTTP Error \(statusCode):")
        print("[PostProcessingService] Response: \(errorMessage)")

        switch statusCode {
        case 401:
            throw PostProcessingError.invalidAPIKey
        case 429:
            throw PostProcessingError.rateLimited
        default:
            throw PostProcessingError.serverError(statusCode, errorMessage)
        }
    }

    /// Estimate token count (rough approximation: ~4 chars per token)
    func estimateTokens(for text: String) -> Int {
        return text.count / 4
    }

    /// Estimate cost before processing
    func estimateCost(transcriptLength: Int, expectedOutputTokens: Int = 1000) -> Int {
        let inputTokens = transcriptLength / 4
        let inputCost = Double(inputTokens) / 1000.0 * inputCostPer1KTokens
        let outputCost = Double(expectedOutputTokens) / 1000.0 * outputCostPer1KTokens
        return Int(ceil((inputCost + outputCost) * 100))
    }
}

// MARK: - Singleton

extension PostProcessingService {
    static let shared = PostProcessingService()
}

// MARK: - Batch Processing

extension PostProcessingService {
    /// Process all enabled templates for a transcript
    func processAllEnabled(transcript: String) async throws -> [ProcessedSummary] {
        let enabledTemplates = await MainActor.run {
            SummaryTemplateManager.shared.enabledTemplates
        }
        return try await processMultiple(transcript: transcript, templates: enabledTemplates)
    }

    /// Process with the currently selected template only
    func processWithSelected(transcript: String) async throws -> ProcessedSummary {
        let template = await MainActor.run {
            SummaryTemplateManager.shared.selectedTemplate
        }

        let result = try await process(transcript: transcript, template: template)

        return ProcessedSummary(
            templateId: template.id,
            templateName: template.name,
            outputFormat: template.outputFormat,
            content: result.content,
            modelUsed: model,
            costCents: result.costCents
        )
    }
}
