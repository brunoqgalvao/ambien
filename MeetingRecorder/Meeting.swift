//
//  Meeting.swift
//  MeetingRecorder
//
//  Data model for recorded meetings
//

import Foundation

/// Status of a meeting in the transcription pipeline
enum MeetingStatus: String, Codable, CaseIterable {
    case recording
    case pendingTranscription
    case transcribing
    case ready
    case failed

    var displayName: String {
        switch self {
        case .recording: return "Recording"
        case .pendingTranscription: return "Pending"
        case .transcribing: return "Transcribing..."
        case .ready: return "Ready"
        case .failed: return "Failed"
        }
    }

    var icon: String {
        switch self {
        case .recording: return "record.circle.fill"
        case .pendingTranscription: return "clock"
        case .transcribing: return "waveform"
        case .ready: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    var color: String {
        switch self {
        case .recording: return "red"
        case .pendingTranscription: return "orange"
        case .transcribing: return "blue"
        case .ready: return "green"
        case .failed: return "red"
        }
    }
}

/// A participant detected in a meeting
struct MeetingParticipant: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var email: String?
    var source: ParticipantSource

    enum ParticipantSource: String, Codable {
        case screenshot      // Detected via OCR from screenshot
        case calendar        // From calendar event
        case manual          // Manually added by user
        case speakerLabel    // User labeled a speaker
    }
}

/// Speaker label mapping (speaker_0 -> "John", etc.)
struct SpeakerLabel: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var speakerId: String   // "speaker_0", "speaker_1", etc.
    var name: String        // User-assigned or AI-inferred name
    var confidence: Double? // AI confidence score (nil for user-assigned)
    var evidence: String?   // AI reasoning for inference
    var role: String?       // Inferred role (e.g., "Host", "Customer")
    var isUserAssigned: Bool = false // True if user manually set this

    init(
        id: UUID = UUID(),
        speakerId: String,
        name: String,
        confidence: Double? = nil,
        evidence: String? = nil,
        role: String? = nil,
        isUserAssigned: Bool = false
    ) {
        self.id = id
        self.speakerId = speakerId
        self.name = name
        self.confidence = confidence
        self.evidence = evidence
        self.role = role
        self.isUserAssigned = isUserAssigned
    }
}

/// A diarization segment from transcription
struct DiarizationSegment: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var speakerId: String   // "speaker_0", "speaker_1", etc.
    var start: TimeInterval
    var end: TimeInterval
    var text: String
}

/// A recorded meeting or dictation with transcript
struct Meeting: Identifiable, Codable, Hashable {
    let id: UUID

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Meeting, rhs: Meeting) -> Bool {
        lhs.id == rhs.id
    }

    var title: String
    let startTime: Date
    var endTime: Date?
    var duration: TimeInterval
    var sourceApp: String?
    var audioPath: String
    var transcript: String?
    var actionItems: [String]?
    var apiCostCents: Int?
    var status: MeetingStatus
    let createdAt: Date
    var errorMessage: String?

    /// True if this is a quick dictation (not a meeting recording)
    var isDictation: Bool

    // MARK: - Amie Feature Parity Fields

    /// Meeting subtitle/description (editable by user)
    var description: String?

    /// User's private notes (local-only, not sent to AI)
    var privateNotes: String?

    /// Detected or user-selected language for transcription
    var language: String?

    /// Track when meeting was last modified (for "Updated X ago" display)
    var lastUpdated: Date?

    /// Link to calendar event
    var calendarEventId: String?

    // MARK: - Post-Processing Fields

    /// AI-generated summary (from selected template)
    var summary: String?

    /// Cleaned up transcript with speaker identification
    var diarizedTranscript: String?

    /// All processed summaries from different templates
    var processedSummaries: [ProcessedSummary]?

    /// Total cost including transcription + post-processing
    var totalCostCents: Int? {
        let transcriptionCost = apiCostCents ?? 0
        let processingCost = processedSummaries?.reduce(0) { $0 + $1.costCents } ?? 0
        return transcriptionCost + processingCost
    }

    /// Which template was used for the main summary
    var summaryTemplateId: UUID?

    /// When post-processing was completed
    var processedAt: Date?

    // MARK: - Participant & Speaker Fields

    /// Window title captured at recording start
    var windowTitle: String?

    /// Path to screenshot captured at recording start
    var screenshotPath: String?

    /// Participants detected from screenshot OCR, calendar, or manual entry
    var participants: [MeetingParticipant]?

    /// Number of speakers detected by diarization
    var speakerCount: Int?

    /// User-assigned labels for speakers (speaker_0 -> "John")
    var speakerLabels: [SpeakerLabel]?

    /// Raw diarization segments from OpenAI
    var diarizationSegments: [DiarizationSegment]?

    // MARK: - Meeting Brief & Intelligence Fields

    /// Structured meeting brief (generated by AI)
    var meetingBrief: MeetingBrief?

    /// When the brief was generated
    var briefGeneratedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        startTime: Date,
        endTime: Date? = nil,
        duration: TimeInterval = 0,
        sourceApp: String? = nil,
        audioPath: String,
        transcript: String? = nil,
        actionItems: [String]? = nil,
        apiCostCents: Int? = nil,
        status: MeetingStatus = .recording,
        createdAt: Date = Date(),
        errorMessage: String? = nil,
        isDictation: Bool = false,
        // Amie feature parity fields
        description: String? = nil,
        privateNotes: String? = nil,
        language: String? = nil,
        lastUpdated: Date? = nil,
        calendarEventId: String? = nil,
        // Post-processing fields
        summary: String? = nil,
        diarizedTranscript: String? = nil,
        processedSummaries: [ProcessedSummary]? = nil,
        summaryTemplateId: UUID? = nil,
        processedAt: Date? = nil,
        // Participant & speaker fields
        windowTitle: String? = nil,
        screenshotPath: String? = nil,
        participants: [MeetingParticipant]? = nil,
        speakerCount: Int? = nil,
        speakerLabels: [SpeakerLabel]? = nil,
        diarizationSegments: [DiarizationSegment]? = nil,
        // Meeting brief fields
        meetingBrief: MeetingBrief? = nil,
        briefGeneratedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.sourceApp = sourceApp
        self.audioPath = audioPath
        self.transcript = transcript
        self.actionItems = actionItems
        self.apiCostCents = apiCostCents
        self.status = status
        self.createdAt = createdAt
        self.errorMessage = errorMessage
        self.isDictation = isDictation
        // Amie feature parity fields
        self.description = description
        self.privateNotes = privateNotes
        self.language = language
        self.lastUpdated = lastUpdated
        self.calendarEventId = calendarEventId
        // Post-processing fields
        self.summary = summary
        self.diarizedTranscript = diarizedTranscript
        self.processedSummaries = processedSummaries
        self.summaryTemplateId = summaryTemplateId
        self.processedAt = processedAt
        // Participant & speaker fields
        self.windowTitle = windowTitle
        self.screenshotPath = screenshotPath
        self.participants = participants
        self.speakerCount = speakerCount
        self.speakerLabels = speakerLabels
        self.diarizationSegments = diarizationSegments
        // Meeting brief fields
        self.meetingBrief = meetingBrief
        self.briefGeneratedAt = briefGeneratedAt
    }

    /// Check if this meeting has been post-processed
    var isProcessed: Bool {
        processedAt != nil
    }

    /// Check if this meeting has a generated brief
    var hasBrief: Bool {
        meetingBrief != nil
    }

    /// Get a specific processed summary by template ID
    func getSummary(for templateId: UUID) -> ProcessedSummary? {
        processedSummaries?.first { $0.templateId == templateId }
    }

    /// Get the display name for a speaker (user label, AI inference, or default)
    func speakerName(for speakerId: String) -> String {
        if let label = speakerLabels?.first(where: { $0.speakerId == speakerId }) {
            return label.name
        }
        // Convert "speaker_0" to "Speaker 1" for display
        if speakerId.hasPrefix("speaker_") {
            let numStr = speakerId.replacingOccurrences(of: "speaker_", with: "")
            if let num = Int(numStr) {
                return "Speaker \(num + 1)"
            }
        }
        // Handle "Speaker A", "Speaker B" format from Gemini
        if speakerId.hasPrefix("Speaker ") {
            return speakerId
        }
        return speakerId
    }

    /// Get the speaker label with full metadata
    func speakerLabel(for speakerId: String) -> SpeakerLabel? {
        speakerLabels?.first(where: { $0.speakerId == speakerId })
    }

    /// Check if a speaker name is AI-inferred (not user-assigned)
    func isSpeakerAIInferred(_ speakerId: String) -> Bool {
        guard let label = speakerLabels?.first(where: { $0.speakerId == speakerId }) else {
            return false
        }
        return !label.isUserAssigned && label.confidence != nil
    }

    /// Get all unique speakers from diarization
    var uniqueSpeakers: [String] {
        guard let segments = diarizationSegments else { return [] }
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

    /// Check if speaker labeling is available
    var hasSpeakerData: Bool {
        speakerCount != nil || (diarizationSegments?.isEmpty == false)
    }

    /// Cost formatted as dollars
    var formattedCost: String? {
        guard let cents = apiCostCents else { return nil }
        let dollars = Double(cents) / 100.0
        return String(format: "$%.2f", dollars)
    }

    /// Duration formatted as mm:ss
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Date formatted for grouping (e.g., "Today", "Yesterday", "Jan 15")
    var dateGroupKey: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(startTime) {
            return "Today"
        } else if calendar.isDateInYesterday(startTime) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: startTime)
        }
    }

    /// Time formatted as "9:00 AM"
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: startTime)
    }

    /// Relative time for last updated (e.g., "Updated 1 day ago")
    var formattedLastUpdated: String? {
        guard let lastUpdated = lastUpdated else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Updated \(formatter.localizedString(for: lastUpdated, relativeTo: Date()))"
    }

    /// Update the lastUpdated timestamp - call whenever the meeting is modified
    mutating func touch() {
        lastUpdated = Date()
    }
}

// MARK: - Preview Sample Data

extension Meeting {
    static var sampleMeetings: [Meeting] {
        let now = Date()
        let calendar = Calendar.current

        return [
            Meeting(
                title: "Daily Standup",
                startTime: calendar.date(byAdding: .hour, value: -1, to: now)!,
                endTime: calendar.date(byAdding: .minute, value: -45, to: now)!,
                duration: 900,
                sourceApp: "Zoom",
                audioPath: "/path/to/standup.m4a",
                transcript: "Good morning everyone! Let's go around the room...\n\nAlice: Yesterday I finished the login feature. Today I'm working on the password reset flow. No blockers.\n\nBob: I'm still debugging that weird race condition. Making progress but might need help later.\n\nCarol: Wrapped up code review, starting on the API integration today.",
                actionItems: ["Bob to pair with Alice on race condition", "Review API docs before tomorrow"],
                apiCostCents: 27,
                status: .ready
            ),
            Meeting(
                title: "Client Call - Acme Corp",
                startTime: calendar.date(byAdding: .hour, value: -3, to: now)!,
                duration: 2700,
                sourceApp: "Google Meet",
                audioPath: "/path/to/client.m4a",
                status: .transcribing
            ),
            Meeting(
                title: "1:1 with Manager",
                startTime: calendar.date(byAdding: .day, value: -1, to: now)!,
                duration: 1800,
                sourceApp: "Zoom",
                audioPath: "/path/to/1on1.m4a",
                transcript: "Let's talk about your career goals...",
                apiCostCents: 54,
                status: .ready
            ),
            Meeting(
                title: "Product Planning",
                startTime: calendar.date(byAdding: .day, value: -2, to: now)!,
                duration: 3600,
                sourceApp: "Microsoft Teams",
                audioPath: "/path/to/planning.m4a",
                status: .failed,
                errorMessage: "API key invalid"
            )
        ]
    }
}
