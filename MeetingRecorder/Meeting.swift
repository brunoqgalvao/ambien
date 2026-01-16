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

/// A recorded meeting with transcript
struct Meeting: Identifiable, Codable, Equatable {
    let id: UUID
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
        errorMessage: String? = nil
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
