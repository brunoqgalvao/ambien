//
//  MeetingGroup.swift
//  MeetingRecorder
//
//  Data model for grouping meetings together (e.g., "Project Phoenix", "Client ABC Calls")
//  Enables cross-meeting queries and combined transcript analysis
//

import Foundation

/// A named group/collection of meetings
struct MeetingGroup: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var description: String?
    var emoji: String?  // Optional icon (e.g., "🚀", "👥", "💼")
    var color: String?  // Optional color identifier for UI
    let createdAt: Date
    var lastUpdated: Date?

    // Cached count (updated when meetings change)
    var meetingCount: Int

    // Total duration of all meetings in seconds
    var totalDuration: TimeInterval

    // Total API cost in cents
    var totalCostCents: Int

    init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        emoji: String? = nil,
        color: String? = nil,
        createdAt: Date = Date(),
        lastUpdated: Date? = nil,
        meetingCount: Int = 0,
        totalDuration: TimeInterval = 0,
        totalCostCents: Int = 0
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.emoji = emoji
        self.color = color
        self.createdAt = createdAt
        self.lastUpdated = lastUpdated
        self.meetingCount = meetingCount
        self.totalDuration = totalDuration
        self.totalCostCents = totalCostCents
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: MeetingGroup, rhs: MeetingGroup) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Computed Properties

    /// Display name with optional emoji
    var displayName: String {
        if let emoji = emoji {
            return "\(emoji) \(name)"
        }
        return name
    }

    /// Formatted total duration (e.g., "2h 30m")
    var formattedDuration: String {
        let hours = Int(totalDuration) / 3600
        let minutes = (Int(totalDuration) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    /// Cost formatted as dollars
    var formattedCost: String {
        let dollars = Double(totalCostCents) / 100.0
        return String(format: "$%.2f", dollars)
    }

    /// Last updated relative time
    var formattedLastUpdated: String? {
        guard let lastUpdated = lastUpdated else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastUpdated, relativeTo: Date())
    }

    mutating func touch() {
        lastUpdated = Date()
    }
}

// MARK: - Group Colors

extension MeetingGroup {
    /// Available colors for groups
    enum GroupColor: String, CaseIterable {
        case violet = "violet"
        case coral = "coral"
        case mint = "mint"
        case amber = "amber"
        case blue = "blue"
        case rose = "rose"
        case emerald = "emerald"
        case orange = "orange"

        var displayName: String {
            rawValue.capitalized
        }
    }

    /// Available emojis for quick selection
    static let suggestedEmojis = [
        "📁", "🚀", "💼", "👥", "📊", "🎯", "💡", "🔥",
        "⭐", "📝", "🎨", "🔧", "📈", "🏆", "💬", "🎙️"
    ]
}

// MARK: - Agent API Export

/// JSON format for exported groups (agent-readable)
struct AgentGroup: Codable {
    let id: String
    let name: String
    let description: String?
    let emoji: String?
    let meetingCount: Int
    let totalDurationMinutes: Int
    let meetings: [AgentGroupMeeting]
    let combinedTranscript: String?
    let lastUpdated: String

    init(from group: MeetingGroup, meetings: [Meeting]) {
        self.id = group.id.uuidString.lowercased()
        self.name = group.name
        self.description = group.description
        self.emoji = group.emoji
        self.meetingCount = meetings.count
        self.totalDurationMinutes = Int(meetings.reduce(0) { $0 + $1.duration } / 60)

        // Convert meetings to agent format with minimal fields
        self.meetings = meetings.compactMap { meeting in
            guard meeting.status == .ready else { return nil }
            return AgentGroupMeeting(from: meeting)
        }

        // Combine all transcripts with meeting headers
        let transcriptParts = meetings.compactMap { meeting -> String? in
            guard let transcript = meeting.transcript, meeting.status == .ready else { return nil }
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d, yyyy h:mm a"
            let dateStr = dateFormatter.string(from: meeting.startTime)
            return "## \(meeting.title) (\(dateStr))\n\n\(transcript)"
        }
        self.combinedTranscript = transcriptParts.isEmpty ? nil : transcriptParts.joined(separator: "\n\n---\n\n")

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        self.lastUpdated = isoFormatter.string(from: group.lastUpdated ?? group.createdAt)
    }
}

/// Minimal meeting info for group export
struct AgentGroupMeeting: Codable {
    let id: String
    let title: String
    let date: String
    let durationMinutes: Int
    let hasTranscript: Bool

    init(from meeting: Meeting) {
        self.id = meeting.id.uuidString.lowercased()
        self.title = meeting.title

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        self.date = dateFormatter.string(from: meeting.startTime)

        self.durationMinutes = Int(meeting.duration / 60)
        self.hasTranscript = meeting.transcript != nil
    }
}

// MARK: - Preview Sample Data

extension MeetingGroup {
    static var sampleGroups: [MeetingGroup] {
        [
            MeetingGroup(
                name: "Project Phoenix",
                description: "All meetings related to the Phoenix rewrite",
                emoji: "🚀",
                color: "violet",
                meetingCount: 12,
                totalDuration: 7200,
                totalCostCents: 145
            ),
            MeetingGroup(
                name: "Client: Acme Corp",
                description: "Weekly syncs with Acme Corp",
                emoji: "💼",
                color: "coral",
                meetingCount: 8,
                totalDuration: 14400,
                totalCostCents: 287
            ),
            MeetingGroup(
                name: "1:1s with Manager",
                description: nil,
                emoji: "👥",
                color: "mint",
                meetingCount: 24,
                totalDuration: 43200,
                totalCostCents: 540
            )
        ]
    }
}
