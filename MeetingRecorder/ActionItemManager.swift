//
//  ActionItemManager.swift
//  MeetingRecorder
//
//  Manages action items as a first-class app primitive.
//  Handles CRUD, filtering, grouping, and export.
//

import Foundation
import GRDB
import Combine

// MARK: - Manager

/// Manages action items across all meetings
actor ActionItemManager {
    static let shared = ActionItemManager()

    private var dbQueue: DatabaseQueue?

    // MARK: - Initialization

    func initialize(with dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
        logInfo("[ActionItemManager] Initialized")
    }

    // MARK: - CRUD Operations

    /// Insert a new action item
    func insert(_ item: ActionItem) async throws {
        guard let db = dbQueue else { return }

        try await db.write { db in
            try ActionItemRecord(item).insert(db)
        }
        logInfo("[ActionItemManager] Inserted action item: \(item.id)")
        await notifyChange()
    }

    /// Insert multiple action items
    func insert(_ items: [ActionItem]) async throws {
        guard let db = dbQueue, !items.isEmpty else { return }

        try await db.write { db in
            for item in items {
                try ActionItemRecord(item).insert(db)
            }
        }
        logInfo("[ActionItemManager] Inserted \(items.count) action items")
        await notifyChange()
    }

    /// Update an action item
    func update(_ item: ActionItem) async throws {
        guard let db = dbQueue else { return }

        try await db.write { db in
            try ActionItemRecord(item).update(db)
        }
        logInfo("[ActionItemManager] Updated action item: \(item.id)")
        await notifyChange()
    }

    /// Delete an action item
    func delete(_ itemId: UUID) async throws {
        guard let db = dbQueue else { return }

        try await db.write { db in
            try db.execute(sql: "DELETE FROM action_items WHERE id = ?", arguments: [itemId.uuidString])
        }
        logInfo("[ActionItemManager] Deleted action item: \(itemId)")
        await notifyChange()
    }

    /// Delete all action items for a meeting
    func deleteForMeeting(_ meetingId: UUID) async throws {
        guard let db = dbQueue else { return }

        try await db.write { db in
            try db.execute(sql: "DELETE FROM action_items WHERE meeting_id = ?", arguments: [meetingId.uuidString])
        }
        logInfo("[ActionItemManager] Deleted action items for meeting: \(meetingId)")
        await notifyChange()
    }

    // MARK: - Mark Complete/Reopen

    /// Mark action item as complete
    func complete(_ itemId: UUID) async throws {
        guard let db = dbQueue else { return }

        let now = Date()
        try await db.write { db in
            try db.execute(
                sql: "UPDATE action_items SET status = ?, completed_at = ?, updated_at = ? WHERE id = ?",
                arguments: ["completed", now, now, itemId.uuidString]
            )
        }
        logInfo("[ActionItemManager] Completed action item: \(itemId)")
        await notifyChange()
    }

    /// Reopen a completed action item
    func reopen(_ itemId: UUID) async throws {
        guard let db = dbQueue else { return }

        let now = Date()
        try await db.write { db in
            try db.execute(
                sql: "UPDATE action_items SET status = ?, completed_at = NULL, updated_at = ? WHERE id = ?",
                arguments: ["open", now, itemId.uuidString]
            )
        }
        logInfo("[ActionItemManager] Reopened action item: \(itemId)")
        await notifyChange()
    }

    /// Snooze action item to a new date
    func snooze(_ itemId: UUID, to newDate: Date) async throws {
        guard let db = dbQueue else { return }

        let now = Date()
        try await db.write { db in
            try db.execute(
                sql: "UPDATE action_items SET due_date = ?, due_suggestion = NULL, updated_at = ? WHERE id = ?",
                arguments: [newDate, now, itemId.uuidString]
            )
        }
        logInfo("[ActionItemManager] Snoozed action item: \(itemId) to \(newDate)")
        await notifyChange()
    }

    // MARK: - Fetch Operations

    /// Get an action item by ID
    func getItem(_ id: UUID) async throws -> ActionItem? {
        guard let db = dbQueue else { return nil }

        return try await db.read { db in
            let record = try ActionItemRecord.fetchOne(db, sql: "SELECT * FROM action_items WHERE id = ?", arguments: [id.uuidString])
            return record?.toActionItem()
        }
    }

    /// Get all action items for a meeting
    func getItemsForMeeting(_ meetingId: UUID) async throws -> [ActionItem] {
        guard let db = dbQueue else { return [] }

        return try await db.read { db in
            let records = try ActionItemRecord.fetchAll(
                db,
                sql: "SELECT * FROM action_items WHERE meeting_id = ? ORDER BY created_at ASC",
                arguments: [meetingId.uuidString]
            )
            return records.map { $0.toActionItem() }
        }
    }

    /// Get all open action items
    func getOpenItems() async throws -> [ActionItem] {
        guard let db = dbQueue else { return [] }

        return try await db.read { db in
            let records = try ActionItemRecord.fetchAll(
                db,
                sql: """
                    SELECT * FROM action_items
                    WHERE status = 'open'
                    ORDER BY
                        CASE WHEN due_date IS NULL THEN 1 ELSE 0 END,
                        due_date ASC,
                        CASE priority
                            WHEN 'high' THEN 0
                            WHEN 'medium' THEN 1
                            ELSE 2
                        END,
                        created_at ASC
                """
            )
            return records.map { $0.toActionItem() }
        }
    }

    /// Get all action items (open + completed)
    func getAllItems() async throws -> [ActionItem] {
        guard let db = dbQueue else { return [] }

        return try await db.read { db in
            let records = try ActionItemRecord.fetchAll(
                db,
                sql: "SELECT * FROM action_items ORDER BY created_at DESC"
            )
            return records.map { $0.toActionItem() }
        }
    }

    /// Get completed action items
    func getCompletedItems(limit: Int = 50) async throws -> [ActionItem] {
        guard let db = dbQueue else { return [] }

        return try await db.read { db in
            let records = try ActionItemRecord.fetchAll(
                db,
                sql: "SELECT * FROM action_items WHERE status = 'completed' ORDER BY completed_at DESC LIMIT ?",
                arguments: [limit]
            )
            return records.map { $0.toActionItem() }
        }
    }

    /// Get overdue action items
    func getOverdueItems() async throws -> [ActionItem] {
        guard let db = dbQueue else { return [] }

        let now = Date()
        return try await db.read { db in
            let records = try ActionItemRecord.fetchAll(
                db,
                sql: """
                    SELECT * FROM action_items
                    WHERE status = 'open' AND due_date < ?
                    ORDER BY due_date ASC
                """,
                arguments: [now]
            )
            return records.map { $0.toActionItem() }
        }
    }

    /// Get items due today
    func getItemsDueToday() async throws -> [ActionItem] {
        guard let db = dbQueue else { return [] }

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday)!

        return try await db.read { db in
            let records = try ActionItemRecord.fetchAll(
                db,
                sql: """
                    SELECT * FROM action_items
                    WHERE status = 'open' AND due_date >= ? AND due_date < ?
                    ORDER BY due_date ASC
                """,
                arguments: [startOfToday, endOfToday]
            )
            return records.map { $0.toActionItem() }
        }
    }

    // MARK: - Statistics

    /// Get counts for dashboard display
    func getCounts() async throws -> ActionItemCounts {
        guard let db = dbQueue else { return ActionItemCounts() }

        let now = Date()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday)!
        let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfToday)!

        return try await db.read { db in
            let overdue = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM action_items WHERE status = 'open' AND due_date < ?",
                arguments: [startOfToday]
            ) ?? 0

            let dueToday = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM action_items WHERE status = 'open' AND due_date >= ? AND due_date < ?",
                arguments: [startOfToday, endOfToday]
            ) ?? 0

            let dueThisWeek = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM action_items WHERE status = 'open' AND due_date >= ? AND due_date < ?",
                arguments: [endOfToday, endOfWeek]
            ) ?? 0

            let totalOpen = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM action_items WHERE status = 'open'"
            ) ?? 0

            let totalCompleted = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM action_items WHERE status = 'completed'"
            ) ?? 0

            return ActionItemCounts(
                overdue: overdue,
                dueToday: dueToday,
                dueThisWeek: dueThisWeek,
                totalOpen: totalOpen,
                totalCompleted: totalCompleted
            )
        }
    }

    // MARK: - Export

    /// Export action items as Markdown
    func exportAsMarkdown(items: [ActionItem], meetingTitle: String? = nil) -> String {
        var md = ""

        if let title = meetingTitle {
            md += "## Action Items from \(title)\n\n"
        } else {
            md += "## Action Items\n\n"
        }

        let openItems = items.filter { $0.status == .open }
        let completedItems = items.filter { $0.status == .completed }

        if !openItems.isEmpty {
            md += "### Open\n\n"
            for item in openItems {
                md += "- [ ] **\(item.task)**\n"
                var details: [String] = []
                if let assignee = item.assignee {
                    details.append("Assigned: \(assignee)")
                }
                if let due = item.formattedDueDate {
                    details.append("Due: \(due)")
                }
                details.append("Priority: \(item.priority.displayName)")
                md += "  - \(details.joined(separator: " | "))\n"
                md += "\n"
            }
        }

        if !completedItems.isEmpty {
            md += "### Completed\n\n"
            for item in completedItems {
                md += "- [x] **\(item.task)**\n"
                var details: [String] = []
                if let assignee = item.assignee {
                    details.append("Assigned: \(assignee)")
                }
                if let completed = item.formattedCompletedDate {
                    details.append(completed)
                }
                md += "  - \(details.joined(separator: " | "))\n"
                md += "\n"
            }
        }

        return md
    }

    /// Export action items as plain text
    func exportAsPlainText(items: [ActionItem], meetingTitle: String? = nil) -> String {
        var txt = ""

        if let title = meetingTitle {
            txt += "ACTION ITEMS - \(title)\n"
        } else {
            txt += "ACTION ITEMS\n"
        }
        txt += String(repeating: "═", count: 50) + "\n\n"

        let openItems = items.filter { $0.status == .open }
        let completedItems = items.filter { $0.status == .completed }

        for item in openItems {
            txt += "□ \(item.task)\n"
            var details: [String] = []
            if let assignee = item.assignee {
                details.append(assignee)
            }
            if let due = item.formattedDueDate {
                details.append("Due \(due)")
            }
            details.append(item.priority.displayName)
            txt += "  \(details.joined(separator: " | "))\n\n"
        }

        for item in completedItems {
            txt += "☑ \(item.task)\n"
            if let assignee = item.assignee {
                txt += "  \(assignee)"
            }
            if let completed = item.formattedCompletedDate {
                txt += " | \(completed)"
            }
            txt += "\n\n"
        }

        return txt
    }

    // MARK: - Notification

    private func notifyChange() async {
        await MainActor.run {
            NotificationCenter.default.post(name: .actionItemsDidChange, object: nil)
        }
    }
}

// MARK: - Action Item Counts

struct ActionItemCounts {
    var overdue: Int = 0
    var dueToday: Int = 0
    var dueThisWeek: Int = 0
    var totalOpen: Int = 0
    var totalCompleted: Int = 0

    var hasUrgent: Bool {
        overdue > 0 || dueToday > 0
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let actionItemsDidChange = Notification.Name("actionItemsDidChange")
}

// MARK: - Database Record

/// GRDB record type for action_items table
private struct ActionItemRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "action_items"

    let id: String
    let meetingId: String
    var task: String
    var assignee: String?
    var dueDate: Date?
    var dueSuggestion: String?
    var priority: String
    var context: String?
    var status: String
    let createdAt: Date
    var completedAt: Date?
    var updatedAt: Date?
    var syncedTo: String?
    var externalIds: String?

    enum CodingKeys: String, CodingKey {
        case id
        case meetingId = "meeting_id"
        case task
        case assignee
        case dueDate = "due_date"
        case dueSuggestion = "due_suggestion"
        case priority
        case context
        case status
        case createdAt = "created_at"
        case completedAt = "completed_at"
        case updatedAt = "updated_at"
        case syncedTo = "synced_to"
        case externalIds = "external_ids"
    }

    init(_ item: ActionItem) {
        self.id = item.id.uuidString
        self.meetingId = item.meetingId.uuidString
        self.task = item.task
        self.assignee = item.assignee
        self.dueDate = item.dueDate
        self.dueSuggestion = item.dueSuggestion
        self.priority = item.priority.rawValue
        self.context = item.context
        self.status = item.status.rawValue
        self.createdAt = item.createdAt
        self.completedAt = item.completedAt
        self.updatedAt = item.updatedAt

        // Encode arrays/objects as JSON
        if let syncedTo = item.syncedTo {
            self.syncedTo = try? String(data: JSONEncoder().encode(syncedTo), encoding: .utf8)
        } else {
            self.syncedTo = nil
        }
        if let externalIds = item.externalIds {
            self.externalIds = try? String(data: JSONEncoder().encode(externalIds), encoding: .utf8)
        } else {
            self.externalIds = nil
        }
    }

    func toActionItem() -> ActionItem {
        // Decode JSON arrays
        var syncedToArray: [String]? = nil
        if let json = syncedTo, let data = json.data(using: .utf8) {
            syncedToArray = try? JSONDecoder().decode([String].self, from: data)
        }

        var externalIdsDict: [String: String]? = nil
        if let json = externalIds, let data = json.data(using: .utf8) {
            externalIdsDict = try? JSONDecoder().decode([String: String].self, from: data)
        }

        return ActionItem(
            id: UUID(uuidString: id) ?? UUID(),
            meetingId: UUID(uuidString: meetingId) ?? UUID(),
            task: task,
            assignee: assignee,
            dueDate: dueDate,
            dueSuggestion: dueSuggestion,
            priority: ActionItem.Priority(rawValue: priority) ?? .medium,
            context: context,
            status: ActionItem.Status(rawValue: status) ?? .open,
            createdAt: createdAt,
            completedAt: completedAt,
            updatedAt: updatedAt,
            syncedTo: syncedToArray,
            externalIds: externalIdsDict
        )
    }
}
