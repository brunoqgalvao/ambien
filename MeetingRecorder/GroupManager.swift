//
//  GroupManager.swift
//  MeetingRecorder
//
//  Manages meeting groups: CRUD operations, membership, and cached stats.
//  Uses DatabaseManager for persistence and AgentAPIManager for JSON export.
//

import Foundation
import GRDB
import Combine

/// Manages meeting groups and their memberships
actor GroupManager {
    // MARK: - Database Access

    /// Lazily get database queue from DatabaseManager (no explicit initialization needed)
    private func getDbQueue() async -> DatabaseQueue? {
        return await DatabaseManager.shared.getDbQueue()
    }

    // MARK: - Group CRUD

    /// Create a new group
    func createGroup(name: String, description: String? = nil, emoji: String? = nil, color: String? = nil) async throws -> MeetingGroup {
        guard let db = await getDbQueue() else {
            throw GroupManagerError.notInitialized
        }

        let group = MeetingGroup(
            name: name,
            description: description,
            emoji: emoji,
            color: color
        )

        try await db.write { db in
            try GroupRecord(group).insert(db)
        }

        print("[GroupManager] Created group: \(group.name)")
        return group
    }

    /// Update an existing group
    func updateGroup(_ group: MeetingGroup) async throws {
        guard let db = await getDbQueue() else {
            throw GroupManagerError.notInitialized
        }

        var updatedGroup = group
        updatedGroup.touch()
        let groupToWrite = updatedGroup

        try await db.write { db in
            try GroupRecord(groupToWrite).update(db)
        }

        print("[GroupManager] Updated group: \(group.name)")
    }

    /// Delete a group (memberships are cascade-deleted)
    func deleteGroup(_ groupId: UUID) async throws {
        guard let db = await getDbQueue() else {
            throw GroupManagerError.notInitialized
        }

        try await db.write { db in
            try db.execute(sql: "DELETE FROM groups WHERE id = ?", arguments: [groupId.uuidString])
        }

        // Also delete the exported JSON
        await AgentAPIManager.shared.deleteGroup(groupId)

        print("[GroupManager] Deleted group: \(groupId)")
    }

    /// Get a group by ID
    func getGroup(id: UUID) async throws -> MeetingGroup? {
        guard let db = await getDbQueue() else { return nil }

        return try await db.read { db in
            let record = try GroupRecord.fetchOne(db, sql: "SELECT * FROM groups WHERE id = ?", arguments: [id.uuidString])
            return record?.toGroup()
        }
    }

    /// Get all groups, ordered by name
    func getAllGroups() async throws -> [MeetingGroup] {
        guard let db = await getDbQueue() else { return [] }

        return try await db.read { db in
            let records = try GroupRecord.fetchAll(db, sql: "SELECT * FROM groups ORDER BY name ASC")
            return records.map { $0.toGroup() }
        }
    }

    // MARK: - Membership Management

    /// Add a meeting to a group
    func addMeeting(_ meetingId: UUID, to groupId: UUID) async throws {
        guard let db = await getDbQueue() else {
            throw GroupManagerError.notInitialized
        }

        try await db.write { db in
            // Check if already a member
            let exists = try Bool.fetchOne(
                db,
                sql: "SELECT 1 FROM meeting_group_members WHERE group_id = ? AND meeting_id = ?",
                arguments: [groupId.uuidString, meetingId.uuidString]
            ) ?? false

            if !exists {
                try db.execute(
                    sql: "INSERT INTO meeting_group_members (group_id, meeting_id, added_at) VALUES (?, ?, ?)",
                    arguments: [groupId.uuidString, meetingId.uuidString, Date()]
                )
            }
        }

        // Update cached stats
        try await updateGroupStats(groupId)

        print("[GroupManager] Added meeting \(meetingId) to group \(groupId)")
    }

    /// Add multiple meetings to a group
    func addMeetings(_ meetingIds: [UUID], to groupId: UUID) async throws {
        guard let db = await getDbQueue() else {
            throw GroupManagerError.notInitialized
        }

        try await db.write { db in
            for meetingId in meetingIds {
                let exists = try Bool.fetchOne(
                    db,
                    sql: "SELECT 1 FROM meeting_group_members WHERE group_id = ? AND meeting_id = ?",
                    arguments: [groupId.uuidString, meetingId.uuidString]
                ) ?? false

                if !exists {
                    try db.execute(
                        sql: "INSERT INTO meeting_group_members (group_id, meeting_id, added_at) VALUES (?, ?, ?)",
                        arguments: [groupId.uuidString, meetingId.uuidString, Date()]
                    )
                }
            }
        }

        try await updateGroupStats(groupId)

        print("[GroupManager] Added \(meetingIds.count) meetings to group \(groupId)")
    }

    /// Remove a meeting from a group
    func removeMeeting(_ meetingId: UUID, from groupId: UUID) async throws {
        guard let db = await getDbQueue() else {
            throw GroupManagerError.notInitialized
        }

        try await db.write { db in
            try db.execute(
                sql: "DELETE FROM meeting_group_members WHERE group_id = ? AND meeting_id = ?",
                arguments: [groupId.uuidString, meetingId.uuidString]
            )
        }

        try await updateGroupStats(groupId)

        print("[GroupManager] Removed meeting \(meetingId) from group \(groupId)")
    }

    /// Get all meetings in a group, ordered by start time (newest first)
    func getMeetings(in groupId: UUID) async throws -> [Meeting] {
        guard let db = await getDbQueue() else { return [] }

        return try await db.read { db in
            let sql = """
                SELECT m.* FROM meetings m
                JOIN meeting_group_members mgm ON m.id = mgm.meeting_id
                WHERE mgm.group_id = ?
                ORDER BY m.start_time DESC
            """
            let records = try MeetingRecord.fetchAll(db, sql: sql, arguments: [groupId.uuidString])
            return records.map { $0.toMeeting() }
        }
    }

    /// Get all groups that a meeting belongs to
    func getGroups(for meetingId: UUID) async throws -> [MeetingGroup] {
        guard let db = await getDbQueue() else { return [] }

        return try await db.read { db in
            let sql = """
                SELECT g.* FROM groups g
                JOIN meeting_group_members mgm ON g.id = mgm.group_id
                WHERE mgm.meeting_id = ?
                ORDER BY g.name ASC
            """
            let records = try GroupRecord.fetchAll(db, sql: sql, arguments: [meetingId.uuidString])
            return records.map { $0.toGroup() }
        }
    }

    /// Check if a meeting is in a specific group
    func isMeetingInGroup(_ meetingId: UUID, groupId: UUID) async throws -> Bool {
        guard let db = await getDbQueue() else { return false }

        return try await db.read { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT 1 FROM meeting_group_members WHERE group_id = ? AND meeting_id = ?",
                arguments: [groupId.uuidString, meetingId.uuidString]
            ) ?? false
        }
    }

    // MARK: - Stats

    /// Update cached stats for a group
    private func updateGroupStats(_ groupId: UUID) async throws {
        guard let db = await getDbQueue() else { return }

        try await db.write { db in
            // Calculate stats from joined meetings
            let statsRow = try Row.fetchOne(db, sql: """
                SELECT
                    COUNT(*) as count,
                    COALESCE(SUM(m.duration), 0) as duration,
                    COALESCE(SUM(m.api_cost_cents), 0) as cost
                FROM meeting_group_members mgm
                JOIN meetings m ON m.id = mgm.meeting_id
                WHERE mgm.group_id = ?
            """, arguments: [groupId.uuidString])

            let count: Int = statsRow?["count"] ?? 0
            let duration: Double = statsRow?["duration"] ?? 0
            let cost: Int = statsRow?["cost"] ?? 0

            try db.execute(sql: """
                UPDATE groups
                SET meeting_count = ?, total_duration = ?, total_cost_cents = ?, last_updated = ?
                WHERE id = ?
            """, arguments: [count, duration, cost, Date(), groupId.uuidString])
        }
    }

    /// Recalculate stats for all groups (maintenance task)
    func recalculateAllStats() async throws {
        let groups = try await getAllGroups()
        for group in groups {
            try await updateGroupStats(group.id)
        }
        print("[GroupManager] Recalculated stats for \(groups.count) groups")
    }

    // MARK: - Combined Transcript

    /// Get combined transcript for all meetings in a group
    func getCombinedTranscript(for groupId: UUID) async throws -> String? {
        let meetings = try await getMeetings(in: groupId)
        let readyMeetings = meetings.filter { $0.status == .ready && $0.transcript != nil }

        guard !readyMeetings.isEmpty else { return nil }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, yyyy h:mm a"

        let parts = readyMeetings.compactMap { meeting -> String? in
            guard let transcript = meeting.transcript else { return nil }
            let dateStr = dateFormatter.string(from: meeting.startTime)
            return "## \(meeting.title) (\(dateStr))\n\n\(transcript)"
        }

        return parts.joined(separator: "\n\n---\n\n")
    }

    // MARK: - Agent API Export

    /// Export a group to JSON for agent access
    func exportGroup(_ groupId: UUID) async throws {
        guard let group = try await getGroup(id: groupId) else {
            throw GroupManagerError.groupNotFound(groupId)
        }

        let meetings = try await getMeetings(in: groupId)
        try await AgentAPIManager.shared.exportGroup(group, meetings: meetings)
    }

    /// Export all groups to JSON
    func exportAllGroups() async throws {
        let groups = try await getAllGroups()
        for group in groups {
            let meetings = try await getMeetings(in: group.id)
            try await AgentAPIManager.shared.exportGroup(group, meetings: meetings)
        }
        print("[GroupManager] Exported \(groups.count) groups")
    }
}

// MARK: - Errors

enum GroupManagerError: LocalizedError {
    case notInitialized
    case groupNotFound(UUID)
    case writeFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "GroupManager not initialized"
        case .groupNotFound(let id):
            return "Group not found: \(id)"
        case .writeFailed(let error):
            return "Database write failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Database Record

/// GRDB record type for groups table
private struct GroupRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "groups"

    let id: String
    var name: String
    var description: String?
    var emoji: String?
    var color: String?
    let createdAt: Date
    var lastUpdated: Date?
    var meetingCount: Int
    var totalDuration: Double
    var totalCostCents: Int

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case emoji
        case color
        case createdAt = "created_at"
        case lastUpdated = "last_updated"
        case meetingCount = "meeting_count"
        case totalDuration = "total_duration"
        case totalCostCents = "total_cost_cents"
    }

    init(_ group: MeetingGroup) {
        self.id = group.id.uuidString
        self.name = group.name
        self.description = group.description
        self.emoji = group.emoji
        self.color = group.color
        self.createdAt = group.createdAt
        self.lastUpdated = group.lastUpdated
        self.meetingCount = group.meetingCount
        self.totalDuration = group.totalDuration
        self.totalCostCents = group.totalCostCents
    }

    func toGroup() -> MeetingGroup {
        MeetingGroup(
            id: UUID(uuidString: id) ?? UUID(),
            name: name,
            description: description,
            emoji: emoji,
            color: color,
            createdAt: createdAt,
            lastUpdated: lastUpdated,
            meetingCount: meetingCount,
            totalDuration: totalDuration,
            totalCostCents: totalCostCents
        )
    }
}

// MARK: - MeetingRecord Extension

/// Make MeetingRecord accessible to GroupManager
private struct MeetingRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "meetings"

    let id: String
    var title: String
    let startTime: Date
    var endTime: Date?
    var duration: Double
    var sourceApp: String?
    var audioPath: String
    var transcript: String?
    var actionItems: String?
    var apiCostCents: Int?
    var status: String
    let createdAt: Date
    var errorMessage: String?
    var isDictation: Bool
    var windowTitle: String?
    var screenshotPath: String?
    var participants: String?
    var speakerCount: Int?
    var speakerLabels: String?
    var diarizationSegments: String?

    enum CodingKeys: String, CodingKey {
        case id, title, duration, transcript, status, isDictation
        case startTime = "start_time"
        case endTime = "end_time"
        case sourceApp = "source_app"
        case audioPath = "audio_path"
        case actionItems = "action_items"
        case apiCostCents = "api_cost_cents"
        case createdAt = "created_at"
        case errorMessage = "error_message"
        case windowTitle = "window_title"
        case screenshotPath = "screenshot_path"
        case participants
        case speakerCount = "speaker_count"
        case speakerLabels = "speaker_labels"
        case diarizationSegments = "diarization_segments"
    }

    func toMeeting() -> Meeting {
        var actionItemsArray: [String]? = nil
        if let json = actionItems, let data = json.data(using: .utf8) {
            actionItemsArray = try? JSONDecoder().decode([String].self, from: data)
        }

        var participantsArray: [MeetingParticipant]? = nil
        if let json = participants, let data = json.data(using: .utf8) {
            participantsArray = try? JSONDecoder().decode([MeetingParticipant].self, from: data)
        }

        var speakerLabelsArray: [SpeakerLabel]? = nil
        if let json = speakerLabels, let data = json.data(using: .utf8) {
            speakerLabelsArray = try? JSONDecoder().decode([SpeakerLabel].self, from: data)
        }

        var segmentsArray: [DiarizationSegment]? = nil
        if let json = diarizationSegments, let data = json.data(using: .utf8) {
            segmentsArray = try? JSONDecoder().decode([DiarizationSegment].self, from: data)
        }

        return Meeting(
            id: UUID(uuidString: id) ?? UUID(),
            title: title,
            startTime: startTime,
            endTime: endTime,
            duration: duration,
            sourceApp: sourceApp,
            audioPath: audioPath,
            transcript: transcript,
            actionItems: actionItemsArray,
            apiCostCents: apiCostCents,
            status: MeetingStatus(rawValue: status) ?? .ready,
            createdAt: createdAt,
            errorMessage: errorMessage,
            isDictation: isDictation == true,
            windowTitle: windowTitle,
            screenshotPath: screenshotPath,
            participants: participantsArray,
            speakerCount: speakerCount,
            speakerLabels: speakerLabelsArray,
            diarizationSegments: segmentsArray
        )
    }
}

// MARK: - Singleton

extension GroupManager {
    static let shared = GroupManager()
}
