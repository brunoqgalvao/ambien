//
//  Project.swift
//  MeetingRecorder
//
//  Data model for organizing meetings into projects.
//  Projects have descriptions with speaker patterns and themes for auto-classification.
//

import Foundation

/// A named project/collection of meetings
struct Project: Identifiable, Codable, Hashable {
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

    // Auto-classification fields
    var speakerPatterns: [String]?   // Known speaker names/patterns for this project
    var themeKeywords: [String]?     // Keywords that indicate this project's theme
    var autoClassifyEnabled: Bool     // Whether to auto-classify meetings to this project

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
        totalCostCents: Int = 0,
        speakerPatterns: [String]? = nil,
        themeKeywords: [String]? = nil,
        autoClassifyEnabled: Bool = true
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
        self.speakerPatterns = speakerPatterns
        self.themeKeywords = themeKeywords
        self.autoClassifyEnabled = autoClassifyEnabled
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Project, rhs: Project) -> Bool {
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

    /// Check if a meeting matches this project's patterns
    func matchesMeeting(_ meeting: Meeting) -> Double {
        var score: Double = 0
        var maxScore: Double = 0

        // Check speaker patterns
        if let patterns = speakerPatterns, !patterns.isEmpty {
            maxScore += 1.0
            if let labels = meeting.speakerLabels {
                let speakerNames = labels.map { $0.name.lowercased() }
                for pattern in patterns {
                    let patternLower = pattern.lowercased()
                    if speakerNames.contains(where: { $0.contains(patternLower) }) {
                        score += 1.0
                        break
                    }
                }
            }
        }

        // Check theme keywords in transcript
        if let keywords = themeKeywords, !keywords.isEmpty, let transcript = meeting.transcript?.lowercased() {
            maxScore += 1.0
            let matchedKeywords = keywords.filter { transcript.contains($0.lowercased()) }
            if !matchedKeywords.isEmpty {
                score += min(1.0, Double(matchedKeywords.count) / Double(keywords.count) * 2)
            }
        }

        // Check title keywords
        if let keywords = themeKeywords, !keywords.isEmpty {
            maxScore += 0.5
            let titleLower = meeting.title.lowercased()
            if keywords.contains(where: { titleLower.contains($0.lowercased()) }) {
                score += 0.5
            }
        }

        return maxScore > 0 ? score / maxScore : 0
    }
}

// MARK: - Project Colors

extension Project {
    /// Available colors for projects
    enum ProjectColor: String, CaseIterable {
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

/// JSON format for exported projects (agent-readable)
struct AgentProject: Codable {
    let id: String
    let name: String
    let description: String?
    let emoji: String?
    let meetingCount: Int
    let totalDurationMinutes: Int
    let meetings: [AgentProjectMeeting]
    let combinedTranscript: String?
    let lastUpdated: String
    let speakerPatterns: [String]?
    let themeKeywords: [String]?

    init(from project: Project, meetings: [Meeting]) {
        self.id = project.id.uuidString.lowercased()
        self.name = project.name
        self.description = project.description
        self.emoji = project.emoji
        self.meetingCount = meetings.count
        self.totalDurationMinutes = Int(meetings.reduce(0) { $0 + $1.duration } / 60)
        self.speakerPatterns = project.speakerPatterns
        self.themeKeywords = project.themeKeywords

        // Convert meetings to agent format with minimal fields
        self.meetings = meetings.compactMap { meeting in
            guard meeting.status == .ready else { return nil }
            return AgentProjectMeeting(from: meeting)
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
        self.lastUpdated = isoFormatter.string(from: project.lastUpdated ?? project.createdAt)
    }
}

/// Minimal meeting info for project export
struct AgentProjectMeeting: Codable {
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

extension Project {
    static var sampleProjects: [Project] {
        [
            Project(
                name: "Project Phoenix",
                description: "All meetings related to the Phoenix rewrite",
                emoji: "🚀",
                color: "violet",
                meetingCount: 12,
                totalDuration: 7200,
                totalCostCents: 145,
                speakerPatterns: ["John", "Sarah", "DevTeam"],
                themeKeywords: ["phoenix", "rewrite", "migration", "architecture"],
                autoClassifyEnabled: true
            ),
            Project(
                name: "Client: Acme Corp",
                description: "Weekly syncs with Acme Corp",
                emoji: "💼",
                color: "coral",
                meetingCount: 8,
                totalDuration: 14400,
                totalCostCents: 287,
                speakerPatterns: ["Acme", "Mike", "Client"],
                themeKeywords: ["acme", "contract", "deliverables"],
                autoClassifyEnabled: true
            ),
            Project(
                name: "1:1s with Manager",
                description: nil,
                emoji: "👥",
                color: "mint",
                meetingCount: 24,
                totalDuration: 43200,
                totalCostCents: 540,
                speakerPatterns: ["Manager", "Boss"],
                themeKeywords: ["1:1", "feedback", "career", "goals"],
                autoClassifyEnabled: true
            )
        ]
    }
}

// Note: MeetingGroup.swift still exists for backwards compatibility
// The old MeetingGroup and new Project types coexist during migration
