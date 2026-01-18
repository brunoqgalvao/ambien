//
//  TranscriptCitation.swift
//  MeetingRecorder
//
//  Represents a reference to a specific moment in the transcript.
//  Citations link brief content back to the original spoken words.
//

import Foundation

// MARK: - Citation Model

/// A reference to a specific segment of the transcript
struct TranscriptCitation: Identifiable, Codable, Hashable {
    let id: UUID
    let startTime: TimeInterval      // Start timestamp in seconds
    let endTime: TimeInterval        // End timestamp in seconds
    let speakerId: String?           // Speaker ID (e.g., "speaker_0")
    let speakerName: String?         // Resolved speaker name if available
    let text: String                 // The actual quoted text

    init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        speakerId: String? = nil,
        speakerName: String? = nil,
        text: String
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.speakerId = speakerId
        self.speakerName = speakerName
        self.text = text
    }

    // MARK: - Computed Properties

    /// Formatted timestamp range (e.g., "05:23 - 05:45")
    var formattedTimeRange: String {
        "\(formatTime(startTime)) - \(formatTime(endTime))"
    }

    /// Formatted start time only (e.g., "05:23")
    var formattedStartTime: String {
        formatTime(startTime)
    }

    /// Duration in seconds
    var duration: TimeInterval {
        endTime - startTime
    }

    /// Display name (speaker name or ID)
    var displaySpeaker: String {
        speakerName ?? speakerId ?? "Unknown"
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Citation Parser

/// Parses citation syntax from markdown text
/// Citation format: [[cite:MM:SS-MM:SS|speaker_id|"quoted text"]]
/// Example: [[cite:05:23-05:45|speaker_0|"We need to finalize the pricing by Friday"]]
enum CitationParser {

    /// The regex pattern for citations
    /// Format: [[cite:START-END|SPEAKER|"TEXT"]]
    static let pattern = #"\[\[cite:(\d{1,2}:\d{2})-(\d{1,2}:\d{2})\|([^\|]*)\|"([^"]+)"\]\]"#

    /// Parse all citations from a markdown string
    static func parse(_ text: String) -> [ParsedCitation] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let nsString = text as NSString
        let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))

        return results.compactMap { match -> ParsedCitation? in
            guard match.numberOfRanges >= 5 else { return nil }

            let fullMatch = nsString.substring(with: match.range)
            let startTimeStr = nsString.substring(with: match.range(at: 1))
            let endTimeStr = nsString.substring(with: match.range(at: 2))
            let speakerId = nsString.substring(with: match.range(at: 3))
            let quotedText = nsString.substring(with: match.range(at: 4))

            guard let startTime = parseTimestamp(startTimeStr),
                  let endTime = parseTimestamp(endTimeStr) else {
                return nil
            }

            let citation = TranscriptCitation(
                startTime: startTime,
                endTime: endTime,
                speakerId: speakerId.isEmpty ? nil : speakerId,
                text: quotedText
            )

            return ParsedCitation(
                citation: citation,
                range: match.range,
                originalText: fullMatch
            )
        }
    }

    /// Parse a timestamp string (MM:SS) to seconds
    static func parseTimestamp(_ str: String) -> TimeInterval? {
        let parts = str.split(separator: ":")
        guard parts.count == 2,
              let mins = Int(parts[0]),
              let secs = Int(parts[1]) else {
            return nil
        }
        return TimeInterval(mins * 60 + secs)
    }

    /// Replace citations with display markers in text
    /// Returns the modified text and an array of citations keyed by their marker
    static func replaceCitationsWithMarkers(_ text: String) -> (String, [String: TranscriptCitation]) {
        let parsed = parse(text)
        var result = text
        var citations: [String: TranscriptCitation] = [:]

        // Process in reverse order to maintain valid ranges
        for item in parsed.reversed() {
            let marker = "[[REF:\(item.citation.id.uuidString)]]"
            citations[marker] = item.citation

            let nsString = result as NSString
            result = nsString.replacingCharacters(in: item.range, with: marker)
        }

        return (result, citations)
    }
}

/// A parsed citation with its location in the original text
struct ParsedCitation {
    let citation: TranscriptCitation
    let range: NSRange
    let originalText: String
}

// MARK: - Citation Display Format

/// Describes how to render a citation in the UI
struct CitationDisplayInfo {
    let citation: TranscriptCitation
    let displayText: String      // What appears in the inline badge (e.g., "05:23 🎤 Bruno")
    let fullContext: String      // Full quote for the popover

    init(citation: TranscriptCitation, speakerName: String? = nil) {
        self.citation = citation

        // Build display text: timestamp + speaker indicator
        let speaker = speakerName ?? citation.speakerName ?? citation.speakerId
        if let speaker = speaker {
            self.displayText = "\(citation.formattedStartTime) 🎤 \(speaker)"
        } else {
            self.displayText = citation.formattedStartTime
        }

        self.fullContext = citation.text
    }
}

// MARK: - System Prompt for Citations

/// The base system prompt that instructs the AI how to cite transcript sources
/// This should be prepended to ALL brief generation prompts
enum CitationSystemPrompt {

    static let instructions = """
    **TRANSCRIPT CITATION RULES:**

    When referencing specific statements, quotes, or information from the transcript, you MUST include citations using this exact format:

    `[[cite:START-END|SPEAKER_ID|"quoted text"]]`

    Where:
    - START = timestamp when the quote starts (MM:SS format)
    - END = timestamp when the quote ends (MM:SS format)
    - SPEAKER_ID = the speaker label (e.g., "speaker_0", "Bruno", etc.) or leave empty if unknown
    - "quoted text" = the relevant text being referenced (keep it brief, 1-2 sentences max)

    **Examples:**
    - "The team decided to launch next month [[cite:12:34-12:45|speaker_0|"We should target a March 15th launch"]]"
    - "There was concern about the timeline [[cite:08:15-08:32|Bruno|"I'm worried we won't have enough time for QA"]]"

    **When to cite:**
    - Direct quotes or specific statements
    - Key decisions with attribution
    - Action item commitments ("I'll do X")
    - Important insights or realizations
    - Contentious points or disagreements

    **Do NOT cite:**
    - General summaries or your own synthesis
    - Every single sentence (be selective, cite the important stuff)
    - Information that's obvious or contextual

    Citations help readers verify claims and understand who said what. Use them judiciously on the most important points.

    """
}

// MARK: - Sample Citations

extension TranscriptCitation {
    static var samples: [TranscriptCitation] {
        [
            TranscriptCitation(
                startTime: 323,  // 05:23
                endTime: 345,    // 05:45
                speakerId: "speaker_0",
                speakerName: "Bruno",
                text: "We need to finalize the pricing by Friday or we'll miss the launch window"
            ),
            TranscriptCitation(
                startTime: 754,  // 12:34
                endTime: 765,    // 12:45
                speakerId: "speaker_1",
                speakerName: "Sarah",
                text: "I can handle the competitor analysis if someone else takes the pricing doc"
            ),
            TranscriptCitation(
                startTime: 1203, // 20:03
                endTime: 1218,   // 20:18
                speakerId: "speaker_0",
                speakerName: "Bruno",
                text: "Let's schedule a follow-up for next Tuesday to review the final numbers"
            )
        ]
    }
}
