//
//  ProjectManager.swift
//  MeetingRecorder
//
//  Manages meeting projects: CRUD operations, membership, auto-classification, and cached stats.
//  Uses DatabaseManager for persistence and AgentAPIManager for JSON export.
//

import Foundation
import GRDB
import Combine

/// Manages meeting projects and their memberships
actor ProjectManager {
    // MARK: - Database Access

    /// Lazily get database queue from DatabaseManager (no explicit initialization needed)
    private func getDbQueue() async -> DatabaseQueue? {
        return await DatabaseManager.shared.getDbQueue()
    }

    // MARK: - Project CRUD

    /// Create a new project
    func createProject(
        name: String,
        description: String? = nil,
        emoji: String? = nil,
        color: String? = nil,
        speakerPatterns: [String]? = nil,
        themeKeywords: [String]? = nil,
        autoClassifyEnabled: Bool = true
    ) async throws -> Project {
        guard let db = await getDbQueue() else {
            throw ProjectManagerError.notInitialized
        }

        let project = Project(
            name: name,
            description: description,
            emoji: emoji,
            color: color,
            speakerPatterns: speakerPatterns,
            themeKeywords: themeKeywords,
            autoClassifyEnabled: autoClassifyEnabled
        )

        try await db.write { db in
            try ProjectRecord(project).insert(db)
        }

        print("[ProjectManager] Created project: \(project.name)")
        return project
    }

    /// Update an existing project
    func updateProject(_ project: Project) async throws {
        guard let db = await getDbQueue() else {
            throw ProjectManagerError.notInitialized
        }

        var updatedProject = project
        updatedProject.touch()
        let projectToWrite = updatedProject

        try await db.write { db in
            try ProjectRecord(projectToWrite).update(db)
        }

        print("[ProjectManager] Updated project: \(project.name)")
    }

    /// Delete a project (memberships are cascade-deleted)
    func deleteProject(_ projectId: UUID) async throws {
        guard let db = await getDbQueue() else {
            throw ProjectManagerError.notInitialized
        }

        try await db.write { db in
            try db.execute(sql: "DELETE FROM groups WHERE id = ?", arguments: [projectId.uuidString])
        }

        // Also delete the exported JSON
        await AgentAPIManager.shared.deleteGroup(projectId)

        print("[ProjectManager] Deleted project: \(projectId)")
    }

    /// Get a project by ID
    func getProject(id: UUID) async throws -> Project? {
        guard let db = await getDbQueue() else { return nil }

        return try await db.read { db in
            let record = try ProjectRecord.fetchOne(db, sql: "SELECT * FROM groups WHERE id = ?", arguments: [id.uuidString])
            return record?.toProject()
        }
    }

    /// Get all projects, ordered by name
    func getAllProjects() async throws -> [Project] {
        guard let db = await getDbQueue() else { return [] }

        return try await db.read { db in
            let records = try ProjectRecord.fetchAll(db, sql: "SELECT * FROM groups ORDER BY name ASC")
            return records.map { $0.toProject() }
        }
    }

    // MARK: - Membership Management

    /// Add a meeting to a project
    func addMeeting(_ meetingId: UUID, to projectId: UUID) async throws {
        guard let db = await getDbQueue() else {
            throw ProjectManagerError.notInitialized
        }

        try await db.write { db in
            // Check if already a member
            let exists = try Bool.fetchOne(
                db,
                sql: "SELECT 1 FROM meeting_group_members WHERE group_id = ? AND meeting_id = ?",
                arguments: [projectId.uuidString, meetingId.uuidString]
            ) ?? false

            if !exists {
                try db.execute(
                    sql: "INSERT INTO meeting_group_members (group_id, meeting_id, added_at) VALUES (?, ?, ?)",
                    arguments: [projectId.uuidString, meetingId.uuidString, Date()]
                )
            }
        }

        // Update cached stats
        try await updateProjectStats(projectId)

        print("[ProjectManager] Added meeting \(meetingId) to project \(projectId)")
    }

    /// Add multiple meetings to a project
    func addMeetings(_ meetingIds: [UUID], to projectId: UUID) async throws {
        guard let db = await getDbQueue() else {
            throw ProjectManagerError.notInitialized
        }

        try await db.write { db in
            for meetingId in meetingIds {
                let exists = try Bool.fetchOne(
                    db,
                    sql: "SELECT 1 FROM meeting_group_members WHERE group_id = ? AND meeting_id = ?",
                    arguments: [projectId.uuidString, meetingId.uuidString]
                ) ?? false

                if !exists {
                    try db.execute(
                        sql: "INSERT INTO meeting_group_members (group_id, meeting_id, added_at) VALUES (?, ?, ?)",
                        arguments: [projectId.uuidString, meetingId.uuidString, Date()]
                    )
                }
            }
        }

        try await updateProjectStats(projectId)

        print("[ProjectManager] Added \(meetingIds.count) meetings to project \(projectId)")
    }

    /// Remove a meeting from a project
    func removeMeeting(_ meetingId: UUID, from projectId: UUID) async throws {
        guard let db = await getDbQueue() else {
            throw ProjectManagerError.notInitialized
        }

        try await db.write { db in
            try db.execute(
                sql: "DELETE FROM meeting_group_members WHERE group_id = ? AND meeting_id = ?",
                arguments: [projectId.uuidString, meetingId.uuidString]
            )
        }

        try await updateProjectStats(projectId)

        print("[ProjectManager] Removed meeting \(meetingId) from project \(projectId)")
    }

    /// Get all meetings in a project, ordered by start time (newest first)
    func getMeetings(in projectId: UUID) async throws -> [Meeting] {
        guard let db = await getDbQueue() else { return [] }

        return try await db.read { db in
            let sql = """
                SELECT m.* FROM meetings m
                JOIN meeting_group_members mgm ON m.id = mgm.meeting_id
                WHERE mgm.group_id = ?
                ORDER BY m.start_time DESC
            """
            let records = try MeetingRecordForProject.fetchAll(db, sql: sql, arguments: [projectId.uuidString])
            return records.map { $0.toMeeting() }
        }
    }

    /// Get all projects that a meeting belongs to
    func getProjects(for meetingId: UUID) async throws -> [Project] {
        guard let db = await getDbQueue() else { return [] }

        return try await db.read { db in
            let sql = """
                SELECT g.* FROM groups g
                JOIN meeting_group_members mgm ON g.id = mgm.group_id
                WHERE mgm.meeting_id = ?
                ORDER BY g.name ASC
            """
            let records = try ProjectRecord.fetchAll(db, sql: sql, arguments: [meetingId.uuidString])
            return records.map { $0.toProject() }
        }
    }

    /// Check if a meeting is in a specific project
    func isMeetingInProject(_ meetingId: UUID, projectId: UUID) async throws -> Bool {
        guard let db = await getDbQueue() else { return false }

        return try await db.read { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT 1 FROM meeting_group_members WHERE group_id = ? AND meeting_id = ?",
                arguments: [projectId.uuidString, meetingId.uuidString]
            ) ?? false
        }
    }

    /// Check if a meeting belongs to any project
    func meetingHasProject(_ meetingId: UUID) async throws -> Bool {
        guard let db = await getDbQueue() else { return false }

        return try await db.read { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT 1 FROM meeting_group_members WHERE meeting_id = ?",
                arguments: [meetingId.uuidString]
            ) ?? false
        }
    }

    // MARK: - Auto-Classification

    /// Classify a meeting into the best matching project
    func classifyMeeting(_ meeting: Meeting) async throws -> Project? {
        let projects = try await getAllProjects()
        let enabledProjects = projects.filter { $0.autoClassifyEnabled }

        guard !enabledProjects.isEmpty else { return nil }

        var bestMatch: (project: Project, score: Double)?

        for project in enabledProjects {
            let score = project.matchesMeeting(meeting)
            if score > 0.5 { // Threshold for auto-classification
                if bestMatch == nil || score > bestMatch!.score {
                    bestMatch = (project, score)
                }
            }
        }

        if let match = bestMatch {
            print("[ProjectManager] Auto-classified meeting '\(meeting.title)' to project '\(match.project.name)' with score \(match.score)")
            return match.project
        }

        return nil
    }

    /// Auto-classify a meeting and add it to the matched project
    func autoClassifyAndAdd(_ meeting: Meeting) async throws -> Project? {
        guard let project = try await classifyMeeting(meeting) else {
            return nil
        }

        try await addMeeting(meeting.id, to: project.id)
        return project
    }

    /// Learn speaker patterns from a project's meetings
    func learnSpeakerPatterns(for projectId: UUID) async throws -> [String] {
        let meetings = try await getMeetings(in: projectId)
        var speakerCounts: [String: Int] = [:]

        for meeting in meetings {
            if let labels = meeting.speakerLabels {
                for label in labels {
                    let name = label.name
                    if !name.isEmpty {
                        speakerCounts[name, default: 0] += 1
                    }
                }
            }
        }

        // Return speakers that appear in at least 2 meetings
        let patterns = speakerCounts.filter { $0.value >= 2 }.map { $0.key }.sorted()
        print("[ProjectManager] Learned \(patterns.count) speaker patterns for project \(projectId)")
        return patterns
    }

    /// Learn theme keywords from a project's meetings
    func learnThemeKeywords(for projectId: UUID) async throws -> [String] {
        let meetings = try await getMeetings(in: projectId)

        // Simple keyword extraction from titles
        var wordCounts: [String: Int] = [:]
        let stopWords = Set(["the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by", "meeting", "call", "sync"])

        for meeting in meetings {
            let words = meeting.title.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 && !stopWords.contains($0) }

            for word in words {
                wordCounts[word, default: 0] += 1
            }
        }

        // Return words that appear in at least 2 meetings
        let keywords = wordCounts.filter { $0.value >= 2 }.map { $0.key }.sorted()
        print("[ProjectManager] Learned \(keywords.count) theme keywords for project \(projectId)")
        return keywords
    }

    // MARK: - Stats

    /// Update cached stats for a project
    private func updateProjectStats(_ projectId: UUID) async throws {
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
            """, arguments: [projectId.uuidString])

            let count: Int = statsRow?["count"] ?? 0
            let duration: Double = statsRow?["duration"] ?? 0
            let cost: Int = statsRow?["cost"] ?? 0

            try db.execute(sql: """
                UPDATE groups
                SET meeting_count = ?, total_duration = ?, total_cost_cents = ?, last_updated = ?
                WHERE id = ?
            """, arguments: [count, duration, cost, Date(), projectId.uuidString])
        }
    }

    /// Recalculate stats for all projects (maintenance task)
    func recalculateAllStats() async throws {
        let projects = try await getAllProjects()
        for project in projects {
            try await updateProjectStats(project.id)
        }
        print("[ProjectManager] Recalculated stats for \(projects.count) projects")
    }

    // MARK: - Combined Transcript

    /// Get combined transcript for all meetings in a project
    func getCombinedTranscript(for projectId: UUID) async throws -> String? {
        let meetings = try await getMeetings(in: projectId)
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

    /// Export a project to JSON for agent access
    func exportProject(_ projectId: UUID) async throws {
        // TODO: Implement project export when Project feature is complete
        print("[ProjectManager] exportProject not yet implemented")
    }

    /// Export all projects to JSON
    func exportAllProjects() async throws {
        // TODO: Implement when Project feature is complete
        print("[ProjectManager] exportAllProjects not yet implemented")
    }
}

// MARK: - Errors

enum ProjectManagerError: LocalizedError {
    case notInitialized
    case projectNotFound(UUID)
    case writeFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "ProjectManager not initialized"
        case .projectNotFound(let id):
            return "Project not found: \(id)"
        case .writeFailed(let error):
            return "Database write failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Database Record

/// GRDB record type for groups table (using existing table)
private struct ProjectRecord: Codable, FetchableRecord, PersistableRecord {
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
    var speakerPatterns: String?  // JSON array
    var themeKeywords: String?    // JSON array
    var autoClassifyEnabled: Int  // SQLite boolean

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
        case speakerPatterns = "speaker_patterns"
        case themeKeywords = "theme_keywords"
        case autoClassifyEnabled = "auto_classify_enabled"
    }

    init(_ project: Project) {
        self.id = project.id.uuidString
        self.name = project.name
        self.description = project.description
        self.emoji = project.emoji
        self.color = project.color
        self.createdAt = project.createdAt
        self.lastUpdated = project.lastUpdated
        self.meetingCount = project.meetingCount
        self.totalDuration = project.totalDuration
        self.totalCostCents = project.totalCostCents
        self.autoClassifyEnabled = project.autoClassifyEnabled ? 1 : 0

        // Encode arrays to JSON
        if let patterns = project.speakerPatterns {
            self.speakerPatterns = try? String(data: JSONEncoder().encode(patterns), encoding: .utf8)
        } else {
            self.speakerPatterns = nil
        }
        if let keywords = project.themeKeywords {
            self.themeKeywords = try? String(data: JSONEncoder().encode(keywords), encoding: .utf8)
        } else {
            self.themeKeywords = nil
        }
    }

    func toProject() -> Project {
        var speakerPatternsArray: [String]?
        if let json = speakerPatterns, let data = json.data(using: .utf8) {
            speakerPatternsArray = try? JSONDecoder().decode([String].self, from: data)
        }

        var themeKeywordsArray: [String]?
        if let json = themeKeywords, let data = json.data(using: .utf8) {
            themeKeywordsArray = try? JSONDecoder().decode([String].self, from: data)
        }

        return Project(
            id: UUID(uuidString: id) ?? UUID(),
            name: name,
            description: description,
            emoji: emoji,
            color: color,
            createdAt: createdAt,
            lastUpdated: lastUpdated,
            meetingCount: meetingCount,
            totalDuration: totalDuration,
            totalCostCents: totalCostCents,
            speakerPatterns: speakerPatternsArray,
            themeKeywords: themeKeywordsArray,
            autoClassifyEnabled: autoClassifyEnabled != 0
        )
    }
}

// MARK: - MeetingRecord Extension (Private)

/// Make MeetingRecord accessible to ProjectManager
private struct MeetingRecordForProject: Codable, FetchableRecord, PersistableRecord {
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

extension ProjectManager {
    static let shared = ProjectManager()
}

// Note: GroupManager.swift still exists for backwards compatibility
// The old GroupManager and new ProjectManager types coexist during migration
