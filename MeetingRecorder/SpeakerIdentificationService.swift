//
//  SpeakerIdentificationService.swift
//  MeetingRecorder
//
//  Two-pass speaker identification using Gemini 2.0 Flash (primary) or GPT-4o-mini (fallback).
//  Pass 1: Transcription with speaker diarization (Speaker A, B, C...)
//  Pass 2: Analyze transcript to infer speaker names from context.
//

import Foundation

// MARK: - Speaker Identification Result

/// Result of speaker identification analysis
struct SpeakerIdentificationResult: Codable {
    /// Mapping of speaker labels to inferred identities
    let speakers: [InferredSpeaker]

    /// Cost of the inference in cents
    let costCents: Int

    /// Processing time in milliseconds
    let durationMs: Int
}

/// An inferred speaker identity
struct InferredSpeaker: Codable, Equatable, Identifiable {
    let id: UUID

    /// Original speaker label (e.g., "Speaker A", "speaker_0")
    let speakerId: String

    /// Inferred name (e.g., "John", "The Host", "Customer")
    let inferredName: String

    /// Confidence score 0.0-1.0
    let confidence: Double

    /// Evidence from transcript that led to this inference
    let evidence: String?

    /// Role or description (e.g., "Interviewer", "Product Manager")
    let role: String?

    init(
        id: UUID = UUID(),
        speakerId: String,
        inferredName: String,
        confidence: Double,
        evidence: String? = nil,
        role: String? = nil
    ) {
        self.id = id
        self.speakerId = speakerId
        self.inferredName = inferredName
        self.confidence = confidence
        self.evidence = evidence
        self.role = role
    }
}

// MARK: - Speaker Identification Service

/// Service for identifying speakers from transcripts using Gemini 2.0 Flash or GPT-4o-mini
actor SpeakerIdentificationService {

    static let shared = SpeakerIdentificationService()

    /// Identify speakers from a diarized transcript
    /// Uses Gemini 2.0 Flash as primary, falls back to GPT-4o-mini if unavailable
    /// - Parameters:
    ///   - transcript: The full transcript text
    ///   - segments: Diarization segments with speaker labels
    ///   - meetingTitle: Optional meeting title for context
    ///   - participants: Optional known participants from calendar/screenshot
    /// - Returns: Speaker identification result with inferred names
    func identifySpeakers(
        transcript: String,
        segments: [DiarizationSegment]?,
        meetingTitle: String? = nil,
        participants: [MeetingParticipant]? = nil
    ) async -> SpeakerIdentificationResult? {
        // Extract unique speakers from segments
        let uniqueSpeakers = extractUniqueSpeakers(from: segments)

        // If no speakers, skip identification
        guard uniqueSpeakers.count >= 1 else {
            logInfo("[SpeakerIdentificationService] Skipping - no speakers detected")
            return nil
        }

        logInfo("[SpeakerIdentificationService] Attempting to identify \(uniqueSpeakers.count) speaker(s)")

        // Build context for the LLM
        let context = buildContext(
            transcript: transcript,
            segments: segments,
            meetingTitle: meetingTitle,
            participants: participants,
            uniqueSpeakers: uniqueSpeakers
        )

        // Build the prompt
        let prompt = buildPrompt(context: context, uniqueSpeakers: uniqueSpeakers)

        // Try Gemini Flash 2.5 first
        if let geminiKey = KeychainHelper.readGeminiKey() {
            let result = await identifyWithGemini(
                apiKey: geminiKey,
                prompt: prompt,
                uniqueSpeakers: uniqueSpeakers
            )
            if let result = result {
                return result
            }
            logInfo("[SpeakerIdentificationService] Gemini failed, trying OpenAI fallback...")
        }

        // Fallback to GPT-4o-mini
        if let openaiKey = KeychainHelper.readOpenAIKey() {
            return await identifyWithOpenAI(
                apiKey: openaiKey,
                prompt: prompt,
                uniqueSpeakers: uniqueSpeakers
            )
        }

        logWarning("[SpeakerIdentificationService] No API keys configured for speaker identification")
        return nil
    }

    // MARK: - Gemini Implementation

    private func identifyWithGemini(
        apiKey: String,
        prompt: String,
        uniqueSpeakers: [String]
    ) async -> SpeakerIdentificationResult? {
        let callStartTime = CFAbsoluteTimeGetCurrent()

        do {
            let result = try await callGeminiFlash(apiKey: apiKey, prompt: prompt)
            let durationMs = Int((CFAbsoluteTimeGetCurrent() - callStartTime) * 1000)

            // Parse the response
            let speakers = parseResponse(result.text, uniqueSpeakers: uniqueSpeakers)

            // Log the API call
            await APICallLogManager.shared.logSuccess(
                type: .speakerIdentification,
                provider: "Gemini",
                model: "gemini-2.0-flash",
                endpoint: "/v1beta/models/gemini-2.0-flash:generateContent",
                inputTokens: result.inputTokens,
                outputTokens: result.outputTokens,
                durationMs: durationMs,
                costCents: result.costCents
            )

            logInfo("[SpeakerIdentificationService] Gemini identified \(speakers.count) speakers in \(durationMs)ms")

            return SpeakerIdentificationResult(
                speakers: speakers,
                costCents: result.costCents,
                durationMs: durationMs
            )

        } catch {
            let durationMs = Int((CFAbsoluteTimeGetCurrent() - callStartTime) * 1000)
            await APICallLogManager.shared.logFailure(
                type: .speakerIdentification,
                provider: "Gemini",
                model: "gemini-2.0-flash",
                endpoint: "/v1beta/models/gemini-2.0-flash:generateContent",
                durationMs: durationMs,
                error: error.localizedDescription
            )
            logError("[SpeakerIdentificationService] Gemini failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - OpenAI Fallback Implementation

    private func identifyWithOpenAI(
        apiKey: String,
        prompt: String,
        uniqueSpeakers: [String]
    ) async -> SpeakerIdentificationResult? {
        let callStartTime = CFAbsoluteTimeGetCurrent()
        let model = "gpt-4o-mini"

        do {
            let result = try await callOpenAI(apiKey: apiKey, prompt: prompt, model: model)
            let durationMs = Int((CFAbsoluteTimeGetCurrent() - callStartTime) * 1000)

            // Parse the response
            let speakers = parseResponse(result.text, uniqueSpeakers: uniqueSpeakers)

            // Log the API call
            await APICallLogManager.shared.logSuccess(
                type: .speakerIdentification,
                provider: "OpenAI",
                model: model,
                endpoint: "/v1/chat/completions",
                inputTokens: result.inputTokens,
                outputTokens: result.outputTokens,
                durationMs: durationMs,
                costCents: result.costCents
            )

            logInfo("[SpeakerIdentificationService] OpenAI identified \(speakers.count) speakers in \(durationMs)ms")

            return SpeakerIdentificationResult(
                speakers: speakers,
                costCents: result.costCents,
                durationMs: durationMs
            )

        } catch {
            let durationMs = Int((CFAbsoluteTimeGetCurrent() - callStartTime) * 1000)
            await APICallLogManager.shared.logFailure(
                type: .speakerIdentification,
                provider: "OpenAI",
                model: model,
                endpoint: "/v1/chat/completions",
                durationMs: durationMs,
                error: error.localizedDescription
            )
            logError("[SpeakerIdentificationService] OpenAI failed: \(error.localizedDescription)")
            return nil
        }
    }

    private struct LLMResult {
        let text: String
        let inputTokens: Int
        let outputTokens: Int
        let costCents: Int
    }

    private func callOpenAI(apiKey: String, prompt: String, model: String) async throws -> LLMResult {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "You identify speakers from meeting transcripts. Return valid JSON only."],
                ["role": "user", "content": prompt]
            ],
            "max_tokens": 2048,
            "temperature": 0.1,
            "response_format": ["type": "json_object"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpeakerIdentificationError.networkError("Invalid response")
        }

        if httpResponse.statusCode == 401 {
            throw SpeakerIdentificationError.apiError(401, "Invalid API key")
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SpeakerIdentificationError.apiError(httpResponse.statusCode, errorMessage)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw SpeakerIdentificationError.parseError("Could not parse OpenAI response")
        }

        // Extract token usage
        var inputTokens = 0
        var outputTokens = 0

        if let usage = json["usage"] as? [String: Any] {
            inputTokens = usage["prompt_tokens"] as? Int ?? 0
            outputTokens = usage["completion_tokens"] as? Int ?? 0
        }

        // GPT-4o-mini pricing: $0.15/1M input, $0.60/1M output
        let inputCost = Double(inputTokens) * 0.15 / 1_000_000.0
        let outputCost = Double(outputTokens) * 0.60 / 1_000_000.0
        let costCents = max(1, Int(ceil((inputCost + outputCost) * 100)))

        return LLMResult(
            text: content,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            costCents: costCents
        )
    }

    // MARK: - Private Helpers

    private func extractUniqueSpeakers(from segments: [DiarizationSegment]?) -> [String] {
        guard let segments = segments else { return [] }
        var seen = Set<String>()
        var speakers: [String] = []
        for segment in segments {
            if !seen.contains(segment.speakerId) {
                seen.insert(segment.speakerId)
                speakers.append(segment.speakerId)
            }
        }
        return speakers
    }

    private func buildContext(
        transcript: String,
        segments: [DiarizationSegment]?,
        meetingTitle: String?,
        participants: [MeetingParticipant]?,
        uniqueSpeakers: [String]
    ) -> String {
        var context = ""

        // Add meeting title if available
        if let title = meetingTitle, !title.isEmpty {
            context += "Meeting Title: \(title)\n\n"
        }

        // Add known participants if available
        if let participants = participants, !participants.isEmpty {
            let names = participants.map { $0.name }.joined(separator: ", ")
            context += "Known Participants: \(names)\n\n"
        }

        // Build diarized transcript excerpt
        if let segments = segments, !segments.isEmpty {
            context += "Transcript with speaker labels:\n\n"

            // Take a representative sample (first 3000 chars worth)
            var charCount = 0
            let maxChars = 3000

            for segment in segments {
                if charCount > maxChars { break }
                let line = "[\(segment.speakerId)]: \(segment.text)\n"
                context += line
                charCount += line.count
            }

            // If we have more, add from middle and end
            if segments.count > 20 {
                context += "\n[...]\n\n"

                // Middle section
                let midIndex = segments.count / 2
                let midEnd = min(midIndex + 5, segments.count)
                for i in midIndex..<midEnd {
                    let segment = segments[i]
                    context += "[\(segment.speakerId)]: \(segment.text)\n"
                }

                context += "\n[...]\n\n"

                // End section
                let endStart = max(segments.count - 5, midEnd)
                for i in endStart..<segments.count {
                    let segment = segments[i]
                    context += "[\(segment.speakerId)]: \(segment.text)\n"
                }
            }
        } else {
            // No segments, use raw transcript
            let sample = String(transcript.prefix(4000))
            context += "Transcript:\n\n\(sample)"
            if transcript.count > 4000 {
                context += "\n\n[...transcript continues...]"
            }
        }

        return context
    }

    private func buildPrompt(context: String, uniqueSpeakers: [String]) -> String {
        let speakerList = uniqueSpeakers.joined(separator: ", ")

        return """
        Analyze this meeting transcript and identify who each speaker is.

        Speakers to identify: \(speakerList)

        Look for clues like:
        - Introductions ("Hi, I'm John" or "Thanks for joining, Sarah")
        - Name mentions in conversation ("John, what do you think?")
        - Role references ("As the product manager..." or "From engineering...")
        - Self-references ("I'll follow up with the client")
        - Email/meeting context clues

        \(context)

        Respond with a JSON object. For each speaker, provide:
        - speakerId: the original label
        - inferredName: your best guess for their name (use "Unknown" if truly uncertain)
        - confidence: 0.0 to 1.0 (1.0 = explicitly stated, 0.5 = inferred, 0.2 = guess)
        - evidence: quote or reasoning that led to this identification
        - role: their role if identifiable (e.g., "Host", "Engineer", "Customer")

        Format:
        {
          "speakers": [
            {
              "speakerId": "Speaker A",
              "inferredName": "John",
              "confidence": 0.9,
              "evidence": "Introduced as 'John from engineering' at the start",
              "role": "Engineer"
            }
          ]
        }

        Return ONLY the JSON object, no other text.
        """
    }

    private func callGeminiFlash(apiKey: String, prompt: String) async throws -> LLMResult {
        let model = "gemini-2.0-flash"
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let payload: [String: Any] = [
            "contents": [[
                "parts": [["text": prompt]]
            ]],
            "generationConfig": [
                "temperature": 0.1,
                "maxOutputTokens": 2048,
                "responseMimeType": "application/json"
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpeakerIdentificationError.networkError("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SpeakerIdentificationError.apiError(httpResponse.statusCode, errorMessage)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw SpeakerIdentificationError.parseError("Could not parse Gemini response")
        }

        // Extract token usage from response
        var inputTokens = 0
        var outputTokens = 0

        if let usageMetadata = json["usageMetadata"] as? [String: Any] {
            inputTokens = usageMetadata["promptTokenCount"] as? Int ?? 0
            outputTokens = usageMetadata["candidatesTokenCount"] as? Int ?? 0
        }

        // Gemini 2.0 Flash pricing: $0.10/1M input, $0.40/1M output (text)
        let inputCost = Double(inputTokens) * 0.10 / 1_000_000.0
        let outputCost = Double(outputTokens) * 0.40 / 1_000_000.0
        let costCents = max(1, Int(ceil((inputCost + outputCost) * 100)))

        return LLMResult(
            text: text,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            costCents: costCents
        )
    }

    private func parseResponse(_ text: String, uniqueSpeakers: [String]) -> [InferredSpeaker] {
        guard let data = text.data(using: .utf8) else { return [] }

        do {
            // Try to parse as JSON
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let speakersArray = json["speakers"] as? [[String: Any]] {
                return speakersArray.compactMap { parseInferredSpeaker($0) }
            }

            // Try direct array
            if let speakersArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return speakersArray.compactMap { parseInferredSpeaker($0) }
            }

        } catch {
            logWarning("[SpeakerIdentificationService] Failed to parse JSON: \(error)")
        }

        // Fallback: return unknown for all speakers
        return uniqueSpeakers.map { speakerId in
            InferredSpeaker(
                speakerId: speakerId,
                inferredName: "Unknown",
                confidence: 0.0,
                evidence: nil,
                role: nil
            )
        }
    }

    private func parseInferredSpeaker(_ dict: [String: Any]) -> InferredSpeaker? {
        guard let speakerId = dict["speakerId"] as? String,
              let inferredName = dict["inferredName"] as? String else {
            return nil
        }

        return InferredSpeaker(
            speakerId: speakerId,
            inferredName: inferredName,
            confidence: dict["confidence"] as? Double ?? 0.5,
            evidence: dict["evidence"] as? String,
            role: dict["role"] as? String
        )
    }
}

// MARK: - Errors

enum SpeakerIdentificationError: LocalizedError {
    case networkError(String)
    case apiError(Int, String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .apiError(let code, let msg):
            return "API error (\(code)): \(msg)"
        case .parseError(let msg):
            return "Parse error: \(msg)"
        }
    }
}

