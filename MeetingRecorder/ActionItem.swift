//
//  ActionItem.swift
//  MeetingRecorder
//
//  ActionItem is a first-class app primitive - trackable tasks extracted from meetings.
//  Each action item has an owner, due date, priority, and links back to its source meeting.
//

import Foundation

// MARK: - ActionItem Model

/// A trackable action item extracted from a meeting
struct ActionItem: Identifiable, Codable, Hashable {
    let id: UUID
    let meetingId: UUID

    var task: String
    var assignee: String?
    var dueDate: Date?
    var dueSuggestion: String?      // Raw AI suggestion like "by Friday"
    var priority: Priority
    var context: String?            // Additional context from meeting
    var status: Status

    let createdAt: Date
    var completedAt: Date?
    var updatedAt: Date?

    // Sync tracking
    var syncedTo: [String]?         // ["reminders", "todoist", "linear"]
    var externalIds: [String: String]?  // {"todoist": "123", "linear": "ABC-123"}

    // MARK: - Enums

    enum Priority: String, Codable, CaseIterable {
        case high
        case medium
        case low

        var displayName: String {
            switch self {
            case .high: return "High"
            case .medium: return "Medium"
            case .low: return "Low"
            }
        }

        var emoji: String {
            switch self {
            case .high: return "🔴"
            case .medium: return "🟡"
            case .low: return "🟢"
            }
        }

        var sortOrder: Int {
            switch self {
            case .high: return 0
            case .medium: return 1
            case .low: return 2
            }
        }
    }

    enum Status: String, Codable, CaseIterable {
        case open
        case completed
        case cancelled

        var displayName: String {
            switch self {
            case .open: return "Open"
            case .completed: return "Completed"
            case .cancelled: return "Cancelled"
            }
        }
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        meetingId: UUID,
        task: String,
        assignee: String? = nil,
        dueDate: Date? = nil,
        dueSuggestion: String? = nil,
        priority: Priority = .medium,
        context: String? = nil,
        status: Status = .open,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        updatedAt: Date? = nil,
        syncedTo: [String]? = nil,
        externalIds: [String: String]? = nil
    ) {
        self.id = id
        self.meetingId = meetingId
        self.task = task
        self.assignee = assignee
        self.dueDate = dueDate
        self.dueSuggestion = dueSuggestion
        self.priority = priority
        self.context = context
        self.status = status
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.updatedAt = updatedAt
        self.syncedTo = syncedTo
        self.externalIds = externalIds
    }

    // MARK: - Computed Properties

    /// Check if action item is overdue
    var isOverdue: Bool {
        guard status == .open, let dueDate = dueDate else { return false }
        return dueDate < Date()
    }

    /// Check if due today
    var isDueToday: Bool {
        guard let dueDate = dueDate else { return false }
        return Calendar.current.isDateInToday(dueDate)
    }

    /// Check if due this week
    var isDueThisWeek: Bool {
        guard let dueDate = dueDate else { return false }
        let calendar = Calendar.current
        let now = Date()
        let weekFromNow = calendar.date(byAdding: .day, value: 7, to: now)!
        return dueDate >= now && dueDate <= weekFromNow
    }

    /// Grouping key for dashboard
    var dueDateGroup: DueDateGroup {
        guard status == .open else { return .completed }
        guard let dueDate = dueDate else { return .noDueDate }

        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
        let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfToday)!
        let endOfNextWeek = calendar.date(byAdding: .day, value: 14, to: startOfToday)!

        if dueDate < startOfToday {
            return .overdue
        } else if dueDate < startOfTomorrow {
            return .today
        } else if dueDate < endOfWeek {
            return .thisWeek
        } else if dueDate < endOfNextWeek {
            return .nextWeek
        } else {
            return .later
        }
    }

    /// Formatted due date string
    var formattedDueDate: String? {
        guard let dueDate = dueDate else { return nil }

        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(dueDate) {
            return "Today"
        } else if calendar.isDateInTomorrow(dueDate) {
            return "Tomorrow"
        } else if calendar.isDateInYesterday(dueDate) {
            return "Yesterday"
        } else {
            // Check if overdue
            if dueDate < now {
                let days = calendar.dateComponents([.day], from: dueDate, to: now).day ?? 0
                return "\(days) day\(days == 1 ? "" : "s") overdue"
            }

            // Format as "Fri, Jan 24"
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, MMM d"
            return formatter.string(from: dueDate)
        }
    }

    /// Formatted completed date
    var formattedCompletedDate: String? {
        guard let completedAt = completedAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "Completed \(formatter.string(from: completedAt))"
    }

    // MARK: - Mutations

    /// Mark as completed
    mutating func complete() {
        status = .completed
        completedAt = Date()
        updatedAt = Date()
    }

    /// Reopen (undo complete)
    mutating func reopen() {
        status = .open
        completedAt = nil
        updatedAt = Date()
    }

    /// Cancel
    mutating func cancel() {
        status = .cancelled
        updatedAt = Date()
    }

    /// Snooze to a new date
    mutating func snooze(to newDate: Date) {
        dueDate = newDate
        dueSuggestion = nil
        updatedAt = Date()
    }

    /// Touch the updated timestamp
    mutating func touch() {
        updatedAt = Date()
    }
}

// MARK: - Due Date Grouping

enum DueDateGroup: String, CaseIterable {
    case overdue
    case today
    case thisWeek
    case nextWeek
    case later
    case noDueDate
    case completed

    var displayName: String {
        switch self {
        case .overdue: return "Overdue"
        case .today: return "Today"
        case .thisWeek: return "This Week"
        case .nextWeek: return "Next Week"
        case .later: return "Later"
        case .noDueDate: return "No Due Date"
        case .completed: return "Completed"
        }
    }

    var emoji: String {
        switch self {
        case .overdue: return "🔴"
        case .today: return "📅"
        case .thisWeek: return "📆"
        case .nextWeek: return "📆"
        case .later: return "🗓"
        case .noDueDate: return "🗓"
        case .completed: return "✅"
        }
    }

    var sortOrder: Int {
        switch self {
        case .overdue: return 0
        case .today: return 1
        case .thisWeek: return 2
        case .nextWeek: return 3
        case .later: return 4
        case .noDueDate: return 5
        case .completed: return 6
        }
    }
}

// MARK: - Meeting Brief

/// Structured summary generated from a meeting transcript
struct MeetingBrief: Codable, Equatable {
    var purpose: String
    var participants: [String]           // People who SPOKE in the meeting
    var peopleMentioned: [String]?       // People discussed but not present
    var summary: String?                 // Full markdown summary
    var discussionPoints: [String]
    var keyInsights: [String]?           // Important realizations
    var decisionsMade: [String]
    var decisionsPending: [String]
    var blockers: [String]?
    var followUpsNeeded: [String]?       // Things needing follow-up

    let generatedAt: Date
    let model: String
    let provider: String

    /// Render as markdown for display
    var markdown: String {
        var md = ""

        // Purpose
        md += "## 📌 Purpose\n\n"
        md += "\(purpose)\n\n"

        // Participants (who spoke)
        if !participants.isEmpty {
            md += "## 👥 Participants\n\n"
            md += participants.joined(separator: ", ")
            md += "\n\n"
        }

        // People mentioned (not in call)
        if let mentioned = peopleMentioned, !mentioned.isEmpty {
            md += "**People mentioned:** \(mentioned.joined(separator: ", "))\n\n"
        }

        // Full summary (already in markdown)
        if let summary = summary, !summary.isEmpty {
            md += "## 📋 Summary\n\n"
            md += summary
            md += "\n\n"
        }

        // Key Insights
        if let insights = keyInsights, !insights.isEmpty {
            md += "## 💡 Key Insights\n\n"
            for insight in insights {
                md += "- \(insight)\n"
            }
            md += "\n"
        }

        // Discussion Points
        if !discussionPoints.isEmpty {
            md += "## 📝 Discussion Points\n\n"
            for point in discussionPoints {
                md += "- \(point)\n"
            }
            md += "\n"
        }

        // Decisions Made
        if !decisionsMade.isEmpty {
            md += "## ✅ Decisions Made\n\n"
            for decision in decisionsMade {
                md += "- \(decision)\n"
            }
            md += "\n"
        }

        // Pending Decisions
        if !decisionsPending.isEmpty {
            md += "## ⏳ Pending Decisions\n\n"
            for decision in decisionsPending {
                md += "- \(decision)\n"
            }
            md += "\n"
        }

        // Blockers
        if let blockers = blockers, !blockers.isEmpty {
            md += "## ⚠️ Blockers\n\n"
            for blocker in blockers {
                md += "- \(blocker)\n"
            }
            md += "\n"
        }

        // Follow-ups
        if let followUps = followUpsNeeded, !followUps.isEmpty {
            md += "## 📞 Follow-ups Needed\n\n"
            for followUp in followUps {
                md += "- \(followUp)\n"
            }
            md += "\n"
        }

        return md
    }
}

// MARK: - AI Extraction Result

/// Result from AI extraction containing both brief and action items
struct MeetingIntelligence: Codable {
    let brief: MeetingBrief
    let actionItems: [ActionItemExtraction]

    /// Raw action item from AI before hydration with meeting context
    struct ActionItemExtraction: Codable {
        let task: String
        let assignee: String?
        let dueSuggestion: String?
        let priority: String
        let context: String?

        /// Convert to ActionItem with meeting context
        func toActionItem(meetingId: UUID, meetingDate: Date) -> ActionItem {
            ActionItem(
                meetingId: meetingId,
                task: task,
                assignee: assignee,
                dueDate: parseDueDate(from: dueSuggestion, relativeTo: meetingDate),
                dueSuggestion: dueSuggestion,
                priority: ActionItem.Priority(rawValue: priority.lowercased()) ?? .medium,
                context: context
            )
        }

        /// Parse natural language due date
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
    }
}

// MARK: - Sample Data

extension ActionItem {
    static var sampleItems: [ActionItem] {
        let now = Date()
        let calendar = Calendar.current
        let meetingId = UUID()

        return [
            ActionItem(
                meetingId: meetingId,
                task: "Send pricing proposal to stakeholders",
                assignee: "Bruno",
                dueDate: calendar.date(byAdding: .day, value: 3, to: now),
                priority: .high,
                context: "Include tier comparison table"
            ),
            ActionItem(
                meetingId: meetingId,
                task: "Review competitor analysis spreadsheet",
                assignee: "Sarah",
                dueDate: calendar.date(byAdding: .day, value: 1, to: now),
                priority: .medium
            ),
            ActionItem(
                meetingId: meetingId,
                task: "Schedule follow-up with finance",
                assignee: "Bruno",
                dueDate: now,
                priority: .high
            ),
            ActionItem(
                meetingId: meetingId,
                task: "Draft contract amendment templates",
                assignee: "Mike",
                dueDate: calendar.date(byAdding: .day, value: -2, to: now),
                priority: .medium,
                status: .completed,
                completedAt: calendar.date(byAdding: .day, value: -1, to: now)
            ),
            ActionItem(
                meetingId: meetingId,
                task: "Finalize Q1 retrospective doc",
                assignee: "Bruno",
                dueDate: calendar.date(byAdding: .day, value: -2, to: now),
                priority: .high
            )
        ]
    }
}
