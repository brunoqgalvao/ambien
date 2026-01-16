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

    /// Initialize the database and run migrations
    func initialize() async throws {
        // Create directory if needed
        let directory = databasePath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        do {
            var config = Configuration()
            config.prepareDatabase { db in
                // Enable foreign keys
                try db.execute(sql: "PRAGMA foreign_keys = ON")
            }

            dbQueue = try DatabaseQueue(path: databasePath.path, configuration: config)

            try await runMigrations()

            print("[DatabaseManager] Initialized at \(databasePath.path)")
        } catch {
            throw DatabaseError.initializationFailed(error)
        }
    }

    private func runMigrations() async throws {
        guard let db = dbQueue else { return }

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

        // Encode action items as JSON
        if let items = meeting.actionItems {
            self.actionItems = try? String(data: JSONEncoder().encode(items), encoding: .utf8)
        } else {
            self.actionItems = nil
        }
    }

    func toMeeting() -> Meeting {
        // Decode action items from JSON
        var actionItemsArray: [String]? = nil
        if let json = actionItems, let data = json.data(using: .utf8) {
            actionItemsArray = try? JSONDecoder().decode([String].self, from: data)
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
            errorMessage: errorMessage
        )
    }
}

// MARK: - Singleton

extension DatabaseManager {
    static let shared = DatabaseManager()
}
