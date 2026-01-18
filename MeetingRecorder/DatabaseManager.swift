//
//  DatabaseManager.swift
//  MeetingRecorder
//
//  SQLite database via GRDB.swift with FTS5 full-text search
//  Stores meetings at ~/Library/Application Support/MeetingRecorder/database.sqlite
//

import Foundation
import GRDB

/// Database errors
enum DatabaseError: LocalizedError {
    case initializationFailed(Error)
    case migrationFailed(Error)
    case meetingNotFound(UUID)
    case writeFailed(Error)

    var errorDescription: String? {
        switch self {
        case .initializationFailed(let error):
            return "Database initialization failed: \(error.localizedDescription)"
        case .migrationFailed(let error):
            return "Database migration failed: \(error.localizedDescription)"
        case .meetingNotFound(let id):
            return "Meeting not found: \(id)"
        case .writeFailed(let error):
            return "Database write failed: \(error.localizedDescription)"
        }
    }
}

/// Manages SQLite database for meeting storage
actor DatabaseManager {
    private var dbQueue: DatabaseQueue?
    private let databasePath: URL

    init() {
        // Database at ~/Library/Application Support/MeetingRecorder/database.sqlite
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("MeetingRecorder", isDirectory: true)
        self.databasePath = appFolder.appendingPathComponent("database.sqlite")
    }

    // MARK: - Initialization

    /// Wait until database is initialized - call this before any DB operations
    func waitForInitialization() async throws {
        try await initialize()
    }

    /// Initialize the database and run migrations
    func initialize() async throws {
        // Fast path - already initialized
        if dbQueue != nil {
            return
        }

        // We're the first caller - do the initialization synchronously
        // Actor isolation ensures only one caller runs at a time
        // (no need for a Task since we're already in an async context on the actor)
        do {
            try performInitialization()
        } catch {
            dbQueue = nil
            if let databaseError = error as? DatabaseError {
                throw databaseError
            }
            throw DatabaseError.initializationFailed(error)
        }
    }

    private func performInitialization() throws {
        // Create directory if needed
        let directory = databasePath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var config = Configuration()
        config.prepareDatabase { db in
            // Enable foreign keys
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        let queue = try DatabaseQueue(path: databasePath.path, configuration: config)
        try Self.runMigrations(on: queue)
        dbQueue = queue

        // Initialize APICallLogManager with the database queue
        Task {
            await APICallLogManager.shared.initialize(with: queue)
        }

        // Initialize ActionItemManager with the database queue
        Task {
            await ActionItemManager.shared.initialize(with: queue)
        }

        print("[DatabaseManager] Initialized at \(databasePath.path)")
    }

    private static func runMigrations(on db: DatabaseQueue) throws {

        var migrator = DatabaseMigrator()

        // Migration 1: Initial schema
        migrator.registerMigration("v1_initial") { db in
            // Meetings table
            try db.create(table: "meetings") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("start_time", .datetime).notNull()
                t.column("end_time", .datetime)
                t.column("duration", .double).notNull().defaults(to: 0)
                t.column("source_app", .text)
                t.column("audio_path", .text).notNull()
                t.column("transcript", .text)
                t.column("action_items", .text)  // JSON array
                t.column("api_cost_cents", .integer)
                t.column("status", .text).notNull().defaults(to: "recording")
                t.column("created_at", .datetime).notNull()
                t.column("error_message", .text)
            }

            // Index for date-based queries
            try db.create(index: "idx_meetings_start_time", on: "meetings", columns: ["start_time"])

            // FTS5 virtual table for full-text search
            try db.execute(sql: """
                CREATE VIRTUAL TABLE meetings_fts USING fts5(
                    title,
                    transcript,
                    content=meetings,
                    content_rowid=rowid
                )
            """)

            // Triggers to keep FTS in sync
            try db.execute(sql: """
                CREATE TRIGGER meetings_ai AFTER INSERT ON meetings BEGIN
                    INSERT INTO meetings_fts(rowid, title, transcript)
                    VALUES (NEW.rowid, NEW.title, NEW.transcript);
                END
            """)

            try db.execute(sql: """
                CREATE TRIGGER meetings_ad AFTER DELETE ON meetings BEGIN
                    INSERT INTO meetings_fts(meetings_fts, rowid, title, transcript)
                    VALUES('delete', OLD.rowid, OLD.title, OLD.transcript);
                END
            """)

            try db.execute(sql: """
                CREATE TRIGGER meetings_au AFTER UPDATE ON meetings BEGIN
                    INSERT INTO meetings_fts(meetings_fts, rowid, title, transcript)
                    VALUES('delete', OLD.rowid, OLD.title, OLD.transcript);
                    INSERT INTO meetings_fts(rowid, title, transcript)
                    VALUES (NEW.rowid, NEW.title, NEW.transcript);
                END
            """)

            print("[DatabaseManager] Migration v1_initial applied")
        }

        // Migration 2: Add isDictation column
        migrator.registerMigration("v2_add_is_dictation") { db in
            try db.alter(table: "meetings") { t in
                t.add(column: "is_dictation", .boolean).notNull().defaults(to: false)
            }
            print("[DatabaseManager] Migration v2_add_is_dictation applied")
        }

        // Migration 3: Add participant and speaker fields
        migrator.registerMigration("v3_add_participants_speakers") { db in
            try db.alter(table: "meetings") { t in
                t.add(column: "window_title", .text)
                t.add(column: "screenshot_path", .text)
                t.add(column: "participants", .text)        // JSON encoded [MeetingParticipant]
                t.add(column: "speaker_count", .integer)
                t.add(column: "speaker_labels", .text)      // JSON encoded [SpeakerLabel]
                t.add(column: "diarization_segments", .text) // JSON encoded [DiarizationSegment]
            }
            print("[DatabaseManager] Migration v3_add_participants_speakers applied")
        }

        // Migration 4: Add meeting groups
        migrator.registerMigration("v4_add_meeting_groups") { db in
            // Groups table
            try db.create(table: "groups") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("description", .text)
                t.column("emoji", .text)
                t.column("color", .text)
                t.column("created_at", .datetime).notNull()
                t.column("last_updated", .datetime)
                // Cached stats (updated on group membership changes)
                t.column("meeting_count", .integer).notNull().defaults(to: 0)
                t.column("total_duration", .double).notNull().defaults(to: 0)
                t.column("total_cost_cents", .integer).notNull().defaults(to: 0)
            }

            // Junction table for many-to-many relationship
            try db.create(table: "meeting_group_members") { t in
                t.column("group_id", .text).notNull()
                    .references("groups", onDelete: .cascade)
                t.column("meeting_id", .text).notNull()
                    .references("meetings", onDelete: .cascade)
                t.column("added_at", .datetime).notNull()
                t.primaryKey(["group_id", "meeting_id"])
            }

            // Indexes for fast lookups
            try db.create(index: "idx_group_members_group", on: "meeting_group_members", columns: ["group_id"])
            try db.create(index: "idx_group_members_meeting", on: "meeting_group_members", columns: ["meeting_id"])

            print("[DatabaseManager] Migration v4_add_meeting_groups applied")
        }

        // Migration 5: Add API call logs table
        migrator.registerMigration("v5_add_api_logs") { db in
            try db.create(table: "api_logs") { t in
                t.column("id", .text).primaryKey()
                t.column("timestamp", .datetime).notNull()
                t.column("call_type", .text).notNull()
                t.column("provider", .text).notNull()
                t.column("model", .text).notNull()
                t.column("status", .text).notNull()
                t.column("endpoint", .text).notNull()
                t.column("input_size_bytes", .integer)
                t.column("input_tokens", .integer)
                t.column("output_tokens", .integer)
                t.column("duration_ms", .integer).notNull()
                t.column("cost_cents", .integer).notNull()
                t.column("meeting_id", .text)
                t.column("error_message", .text)
            }

            // Indexes for common queries
            try db.create(index: "idx_api_logs_timestamp", on: "api_logs", columns: ["timestamp"])
            try db.create(index: "idx_api_logs_meeting", on: "api_logs", columns: ["meeting_id"])
            try db.create(index: "idx_api_logs_provider", on: "api_logs", columns: ["provider"])

            print("[DatabaseManager] Migration v5_add_api_logs applied")
        }

        // Migration 6: Add project auto-classification fields (rename groups -> projects conceptually)
        migrator.registerMigration("v6_add_project_classification") { db in
            try db.alter(table: "groups") { t in
                t.add(column: "speaker_patterns", .text)     // JSON array of speaker names
                t.add(column: "theme_keywords", .text)       // JSON array of keywords
                t.add(column: "auto_classify_enabled", .integer).notNull().defaults(to: 1)
            }
            print("[DatabaseManager] Migration v6_add_project_classification applied")
        }

        // Migration 7: Add action_items table and meeting_brief column
        migrator.registerMigration("v7_add_action_items") { db in
            // Action items table - first-class entity
            try db.create(table: "action_items") { t in
                t.column("id", .text).primaryKey()
                t.column("meeting_id", .text).notNull()
                    .references("meetings", onDelete: .cascade)
                t.column("task", .text).notNull()
                t.column("assignee", .text)
                t.column("due_date", .datetime)
                t.column("due_suggestion", .text)
                t.column("priority", .text).notNull().defaults(to: "medium")
                t.column("context", .text)
                t.column("status", .text).notNull().defaults(to: "open")
                t.column("created_at", .datetime).notNull()
                t.column("completed_at", .datetime)
                t.column("updated_at", .datetime)
                t.column("synced_to", .text)        // JSON array
                t.column("external_ids", .text)     // JSON object
            }

            // Indexes for fast queries
            try db.create(index: "idx_action_items_meeting", on: "action_items", columns: ["meeting_id"])
            try db.create(index: "idx_action_items_status", on: "action_items", columns: ["status"])
            try db.create(index: "idx_action_items_due", on: "action_items", columns: ["due_date"])
            try db.create(index: "idx_action_items_assignee", on: "action_items", columns: ["assignee"])

            // Add meeting_brief column to meetings
            try db.alter(table: "meetings") { t in
                t.add(column: "meeting_brief", .text)        // JSON MeetingBrief
                t.add(column: "brief_generated_at", .datetime)
            }

            print("[DatabaseManager] Migration v7_add_action_items applied")
        }

        // Migration 8: Speaker profiles for voice embeddings
        migrator.registerMigration("v8_add_speaker_profiles") { db in
            // Speaker profiles table - persistent speaker identities with embeddings
            try db.create(table: "speaker_profiles") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text)
                t.column("email", .text)
                t.column("embedding", .blob).notNull()       // JSON-encoded [Float]
                t.column("created_at", .datetime).notNull()
                t.column("last_seen_at", .datetime)
                t.column("meeting_count", .integer).notNull().defaults(to: 1)
                t.column("average_confidence", .double)
                t.column("notes", .text)
                t.column("is_active", .boolean).notNull().defaults(to: true)
            }

            // Meeting-speaker links - tracks which speakers are in which meetings
            try db.create(table: "meeting_speaker_links") { t in
                t.column("id", .text).primaryKey()
                t.column("meeting_id", .text).notNull()
                    .references("meetings", onDelete: .cascade)
                t.column("speaker_profile_id", .text).notNull()
                    .references("speaker_profiles", onDelete: .cascade)
                t.column("meeting_speaker_id", .text).notNull()  // "speaker_0", etc.
                t.column("confidence", .double).notNull()
                t.column("created_at", .datetime).notNull()
            }

            // Indexes for fast lookups
            try db.create(index: "idx_speaker_profiles_name", on: "speaker_profiles", columns: ["name"])
            try db.create(index: "idx_meeting_speaker_links_meeting", on: "meeting_speaker_links", columns: ["meeting_id"])
            try db.create(index: "idx_meeting_speaker_links_profile", on: "meeting_speaker_links", columns: ["speaker_profile_id"])

            // Add speaker_naming_dismissed to meetings
            try db.alter(table: "meetings") { t in
                t.add(column: "speaker_naming_dismissed", .boolean).notNull().defaults(to: false)
            }

            print("[DatabaseManager] Migration v8_add_speaker_profiles applied")
        }

        do {
            try migrator.migrate(db)
        } catch {
            throw DatabaseError.migrationFailed(error)
        }
    }

    // MARK: - CRUD Operations

    /// Insert a new meeting
    func insert(_ meeting: Meeting) async throws {
        guard let db = dbQueue else {
            throw DatabaseError.initializationFailed(NSError(domain: "DatabaseManager", code: -1))
        }

        do {
            try await db.write { db in
                try MeetingRecord(meeting).insert(db)
            }
            print("[DatabaseManager] Inserted meeting: \(meeting.id)")
        } catch {
            throw DatabaseError.writeFailed(error)
        }
    }

    /// Update an existing meeting
    func update(_ meeting: Meeting) async throws {
        guard let db = dbQueue else {
            throw DatabaseError.initializationFailed(NSError(domain: "DatabaseManager", code: -1))
        }

        do {
            try await db.write { db in
                try MeetingRecord(meeting).update(db)
            }
            print("[DatabaseManager] Updated meeting: \(meeting.id)")
        } catch {
            throw DatabaseError.writeFailed(error)
        }
    }

    /// Delete a meeting
    func delete(_ meetingId: UUID) async throws {
        guard let db = dbQueue else {
            throw DatabaseError.initializationFailed(NSError(domain: "DatabaseManager", code: -1))
        }

        do {
            try await db.write { db in
                try db.execute(sql: "DELETE FROM meetings WHERE id = ?", arguments: [meetingId.uuidString])
            }
            print("[DatabaseManager] Deleted meeting: \(meetingId)")
        } catch {
            throw DatabaseError.writeFailed(error)
        }
    }

    /// Get a meeting by ID
    func getMeeting(id: UUID) async throws -> Meeting? {
        guard let db = dbQueue else { return nil }

        return try await db.read { db in
            let record = try MeetingRecord.fetchOne(db, sql: "SELECT * FROM meetings WHERE id = ?", arguments: [id.uuidString])
            return record?.toMeeting()
        }
    }

    /// Get all meetings, ordered by start time (newest first)
    func getAllMeetings() async throws -> [Meeting] {
        guard let db = dbQueue else { return [] }

        return try await db.read { db in
            let records = try MeetingRecord.fetchAll(db, sql: "SELECT * FROM meetings ORDER BY start_time DESC")
            return records.map { $0.toMeeting() }
        }
    }

    /// Get meetings for a specific date
    func getMeetings(for date: Date) async throws -> [Meeting] {
        guard let db = dbQueue else { return [] }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        return try await db.read { db in
            let records = try MeetingRecord.fetchAll(
                db,
                sql: "SELECT * FROM meetings WHERE start_time >= ? AND start_time < ? ORDER BY start_time DESC",
                arguments: [startOfDay, endOfDay]
            )
            return records.map { $0.toMeeting() }
        }
    }

    /// Get meetings with pending transcription status
    func getPendingMeetings() async throws -> [Meeting] {
        guard let db = dbQueue else { return [] }

        return try await db.read { db in
            let records = try MeetingRecord.fetchAll(
                db,
                sql: "SELECT * FROM meetings WHERE status = ? ORDER BY created_at ASC",
                arguments: [MeetingStatus.pendingTranscription.rawValue]
            )
            return records.map { $0.toMeeting() }
        }
    }

    /// Get meetings with failed transcription status
    func getFailedMeetings() async throws -> [Meeting] {
        guard let db = dbQueue else { return [] }

        return try await db.read { db in
            let records = try MeetingRecord.fetchAll(
                db,
                sql: "SELECT * FROM meetings WHERE status = ? ORDER BY created_at DESC",
                arguments: [MeetingStatus.failed.rawValue]
            )
            return records.map { $0.toMeeting() }
        }
    }

    // MARK: - Full-Text Search

    /// Search meetings by title and transcript
    func search(query: String) async throws -> [Meeting] {
        guard let db = dbQueue else { return [] }
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return try await getAllMeetings()
        }

        return try await db.read { db in
            // Use FTS5 match syntax
            let ftsQuery = query.split(separator: " ").map { "\($0)*" }.joined(separator: " ")
            let records = try MeetingRecord.fetchAll(
                db,
                sql: """
                    SELECT meetings.*
                    FROM meetings
                    JOIN meetings_fts ON meetings.rowid = meetings_fts.rowid
                    WHERE meetings_fts MATCH ?
                    ORDER BY rank
                """,
                arguments: [ftsQuery]
            )
            return records.map { $0.toMeeting() }
        }
    }

    // MARK: - Statistics

    /// Get total API cost in cents for a date range
    func getTotalCost(from startDate: Date, to endDate: Date) async throws -> Int {
        guard let db = dbQueue else { return 0 }

        return try await db.read { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(api_cost_cents), 0) as total FROM meetings WHERE start_time >= ? AND start_time < ?",
                arguments: [startDate, endDate]
            )
            return row?["total"] ?? 0
        }
    }

    /// Get meeting count
    func getMeetingCount() async throws -> Int {
        guard let db = dbQueue else { return 0 }

        return try await db.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM meetings") ?? 0
        }
    }
}

// MARK: - Database Record

/// GRDB record type for meetings table
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
    var actionItems: String?  // JSON encoded
    var apiCostCents: Int?
    var status: String
    let createdAt: Date
    var errorMessage: String?
    var isDictation: Bool

    // Participant & speaker fields
    var windowTitle: String?
    var screenshotPath: String?
    var participants: String?        // JSON encoded [MeetingParticipant]
    var speakerCount: Int?
    var speakerLabels: String?       // JSON encoded [SpeakerLabel]
    var diarizationSegments: String? // JSON encoded [DiarizationSegment]

    // Meeting brief fields
    var meetingBrief: String?        // JSON encoded MeetingBrief
    var briefGeneratedAt: Date?

    // Speaker naming prompt dismissed
    var speakerNamingDismissed: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case startTime = "start_time"
        case endTime = "end_time"
        case duration
        case sourceApp = "source_app"
        case audioPath = "audio_path"
        case transcript
        case actionItems = "action_items"
        case apiCostCents = "api_cost_cents"
        case status
        case createdAt = "created_at"
        case errorMessage = "error_message"
        case isDictation = "is_dictation"
        case windowTitle = "window_title"
        case screenshotPath = "screenshot_path"
        case participants
        case speakerCount = "speaker_count"
        case speakerLabels = "speaker_labels"
        case diarizationSegments = "diarization_segments"
        case meetingBrief = "meeting_brief"
        case briefGeneratedAt = "brief_generated_at"
        case speakerNamingDismissed = "speaker_naming_dismissed"
    }

    init(_ meeting: Meeting) {
        self.id = meeting.id.uuidString
        self.title = meeting.title
        self.startTime = meeting.startTime
        self.endTime = meeting.endTime
        self.duration = meeting.duration
        self.sourceApp = meeting.sourceApp
        self.audioPath = meeting.audioPath
        self.transcript = meeting.transcript
        self.apiCostCents = meeting.apiCostCents
        self.status = meeting.status.rawValue
        self.createdAt = meeting.createdAt
        self.errorMessage = meeting.errorMessage
        self.isDictation = meeting.isDictation

        // Participant & speaker fields
        self.windowTitle = meeting.windowTitle
        self.screenshotPath = meeting.screenshotPath
        self.speakerCount = meeting.speakerCount

        // Encode action items as JSON
        if let items = meeting.actionItems {
            self.actionItems = try? String(data: JSONEncoder().encode(items), encoding: .utf8)
        } else {
            self.actionItems = nil
        }

        // Encode participants as JSON
        if let items = meeting.participants {
            self.participants = try? String(data: JSONEncoder().encode(items), encoding: .utf8)
        } else {
            self.participants = nil
        }

        // Encode speaker labels as JSON
        if let items = meeting.speakerLabels {
            self.speakerLabels = try? String(data: JSONEncoder().encode(items), encoding: .utf8)
        } else {
            self.speakerLabels = nil
        }

        // Encode diarization segments as JSON
        if let items = meeting.diarizationSegments {
            self.diarizationSegments = try? String(data: JSONEncoder().encode(items), encoding: .utf8)
        } else {
            self.diarizationSegments = nil
        }

        // Encode meeting brief as JSON
        if let brief = meeting.meetingBrief {
            self.meetingBrief = try? String(data: JSONEncoder().encode(brief), encoding: .utf8)
        } else {
            self.meetingBrief = nil
        }
        self.briefGeneratedAt = meeting.briefGeneratedAt
        self.speakerNamingDismissed = meeting.speakerNamingDismissed
    }

    func toMeeting() -> Meeting {
        // Decode action items from JSON
        var actionItemsArray: [String]? = nil
        if let json = actionItems, let data = json.data(using: .utf8) {
            actionItemsArray = try? JSONDecoder().decode([String].self, from: data)
        }

        // Decode participants from JSON
        var participantsArray: [MeetingParticipant]? = nil
        if let json = participants, let data = json.data(using: .utf8) {
            participantsArray = try? JSONDecoder().decode([MeetingParticipant].self, from: data)
        }

        // Decode speaker labels from JSON
        var speakerLabelsArray: [SpeakerLabel]? = nil
        if let json = speakerLabels, let data = json.data(using: .utf8) {
            speakerLabelsArray = try? JSONDecoder().decode([SpeakerLabel].self, from: data)
        }

        // Decode diarization segments from JSON
        var segmentsArray: [DiarizationSegment]? = nil
        if let json = diarizationSegments, let data = json.data(using: .utf8) {
            segmentsArray = try? JSONDecoder().decode([DiarizationSegment].self, from: data)
        }

        // Decode meeting brief from JSON
        var briefObject: MeetingBrief? = nil
        if let json = meetingBrief, let data = json.data(using: .utf8) {
            briefObject = try? JSONDecoder().decode(MeetingBrief.self, from: data)
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
            isDictation: isDictation,
            windowTitle: windowTitle,
            screenshotPath: screenshotPath,
            participants: participantsArray,
            speakerCount: speakerCount,
            speakerLabels: speakerLabelsArray,
            diarizationSegments: segmentsArray,
            meetingBrief: briefObject,
            briefGeneratedAt: briefGeneratedAt,
            speakerNamingDismissed: speakerNamingDismissed
        )
    }
}

// MARK: - Singleton

extension DatabaseManager {
    static let shared = DatabaseManager()

    /// Expose the database queue for GroupManager to use
    func getDbQueue() -> DatabaseQueue? {
        return dbQueue
    }
}

// MARK: - Speaker Profile Operations

extension DatabaseManager {
    /// Fetch all speaker profiles
    func fetchSpeakerProfiles() async throws -> [SpeakerProfile] {
        guard let db = dbQueue else { return [] }

        return try await db.read { db in
            try SpeakerProfile.fetchAll(db)
        }
    }

    /// Fetch active speaker profiles only
    func fetchActiveSpeakerProfiles() async throws -> [SpeakerProfile] {
        guard let db = dbQueue else { return [] }

        return try await db.read { db in
            try SpeakerProfile.filter(SpeakerProfile.Columns.isActive == true).fetchAll(db)
        }
    }

    /// Get a speaker profile by ID
    func getSpeakerProfile(id: UUID) async throws -> SpeakerProfile? {
        guard let db = dbQueue else { return nil }

        return try await db.read { db in
            try SpeakerProfile.filter(SpeakerProfile.Columns.id == id.uuidString).fetchOne(db)
        }
    }

    /// Save (insert or update) a speaker profile
    func saveSpeakerProfile(_ profile: SpeakerProfile) async throws {
        guard let db = dbQueue else {
            throw DatabaseError.initializationFailed(NSError(domain: "DatabaseManager", code: -1))
        }

        try await db.write { db in
            try profile.save(db)
        }
        print("[DatabaseManager] Saved speaker profile: \(profile.id)")
    }

    /// Delete a speaker profile
    func deleteSpeakerProfile(_ profileId: UUID) async throws {
        guard let db = dbQueue else {
            throw DatabaseError.initializationFailed(NSError(domain: "DatabaseManager", code: -1))
        }

        try await db.write { db in
            try db.execute(
                sql: "DELETE FROM speaker_profiles WHERE id = ?",
                arguments: [profileId.uuidString]
            )
        }
        print("[DatabaseManager] Deleted speaker profile: \(profileId)")
    }

    /// Fetch meeting-speaker links for a profile
    func fetchMeetingSpeakerLinks(forProfileId profileId: UUID) async throws -> [MeetingSpeakerLink] {
        guard let db = dbQueue else { return [] }

        return try await db.read { db in
            try MeetingSpeakerLink.filter(
                MeetingSpeakerLink.Columns.speakerProfileId == profileId.uuidString
            ).fetchAll(db)
        }
    }

    /// Fetch meeting-speaker links for a meeting
    func fetchMeetingSpeakerLinks(forMeetingId meetingId: UUID) async throws -> [MeetingSpeakerLink] {
        guard let db = dbQueue else { return [] }

        return try await db.read { db in
            try MeetingSpeakerLink.filter(
                MeetingSpeakerLink.Columns.meetingId == meetingId.uuidString
            ).fetchAll(db)
        }
    }

    /// Save a meeting-speaker link
    func saveMeetingSpeakerLink(_ link: MeetingSpeakerLink) async throws {
        guard let db = dbQueue else {
            throw DatabaseError.initializationFailed(NSError(domain: "DatabaseManager", code: -1))
        }

        try await db.write { db in
            try link.save(db)
        }
        print("[DatabaseManager] Saved meeting-speaker link: \(link.meetingId) -> \(link.speakerProfileId)")
    }

    /// Update meeting-speaker links when merging profiles
    func updateMeetingSpeakerLinks(fromProfileId: UUID, toProfileId: UUID) async throws {
        guard let db = dbQueue else {
            throw DatabaseError.initializationFailed(NSError(domain: "DatabaseManager", code: -1))
        }

        try await db.write { db in
            try db.execute(
                sql: "UPDATE meeting_speaker_links SET speaker_profile_id = ? WHERE speaker_profile_id = ?",
                arguments: [toProfileId.uuidString, fromProfileId.uuidString]
            )
        }
        print("[DatabaseManager] Moved speaker links from \(fromProfileId) to \(toProfileId)")
    }
}
