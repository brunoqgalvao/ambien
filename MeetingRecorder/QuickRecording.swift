//
//  QuickRecording.swift
//  MeetingRecorder
//
//  Model for quick recordings (separate from meetings)
//  These are stored in a hidden list, not shown in the calendar
//

import Foundation
import GRDB

/// A quick recording (voice note) - separate from meetings
struct QuickRecording: Codable, Identifiable, Equatable {
    var id: Int64?
    var text: String
    var createdAt: Date
    var durationSeconds: Double
    var copiedToClipboard: Bool

    init(
        id: Int64? = nil,
        text: String,
        createdAt: Date = Date(),
        durationSeconds: Double = 0,
        copiedToClipboard: Bool = true
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.copiedToClipboard = copiedToClipboard
    }
}

// MARK: - GRDB Conformance

extension QuickRecording: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "quick_recordings" }

    enum Columns: String, ColumnExpression {
        case id, text, createdAt, durationSeconds, copiedToClipboard
    }
}

// MARK: - Quick Recording Storage

@MainActor
class QuickRecordingStorage: ObservableObject {
    static let shared = QuickRecordingStorage()

    @Published var recordings: [QuickRecording] = []

    private var dbQueue: DatabaseQueue?

    private init() {
        setupDatabase()
        loadRecordings()
    }

    // MARK: - Database Setup

    private func setupDatabase() {
        do {
            let fileManager = FileManager.default
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let appFolder = appSupport.appendingPathComponent("MeetingRecorder")

            try fileManager.createDirectory(at: appFolder, withIntermediateDirectories: true)

            let dbPath = appFolder.appendingPathComponent("quick_recordings.sqlite")
            dbQueue = try DatabaseQueue(path: dbPath.path)

            try dbQueue?.write { db in
                try db.create(table: "quick_recordings", ifNotExists: true) { t in
                    t.autoIncrementedPrimaryKey("id")
                    t.column("text", .text).notNull()
                    t.column("createdAt", .datetime).notNull()
                    t.column("durationSeconds", .double).notNull().defaults(to: 0)
                    t.column("copiedToClipboard", .boolean).notNull().defaults(to: true)
                }
            }

            print("[QuickRecordingStorage] Database ready at \(dbPath.path)")
        } catch {
            print("[QuickRecordingStorage] Database setup failed: \(error)")
        }
    }

    // MARK: - CRUD Operations

    func loadRecordings() {
        do {
            recordings = try dbQueue?.read { db in
                try QuickRecording
                    .order(QuickRecording.Columns.createdAt.desc)
                    .limit(100)  // Keep last 100
                    .fetchAll(db)
            } ?? []
        } catch {
            print("[QuickRecordingStorage] Load failed: \(error)")
        }
    }

    func save(_ recording: QuickRecording) {
        do {
            var mutableRecording = recording
            try dbQueue?.write { db in
                try mutableRecording.insert(db)
            }
            recordings.insert(mutableRecording, at: 0)

            // Prune old recordings (keep last 100)
            if recordings.count > 100 {
                pruneOldRecordings()
            }
        } catch {
            print("[QuickRecordingStorage] Save failed: \(error)")
        }
    }

    func delete(_ recording: QuickRecording) {
        guard let id = recording.id else { return }

        do {
            try dbQueue?.write { db in
                _ = try QuickRecording.deleteOne(db, key: id)
            }
            recordings.removeAll { $0.id == id }
        } catch {
            print("[QuickRecordingStorage] Delete failed: \(error)")
        }
    }

    func clearAll() {
        do {
            try dbQueue?.write { db in
                _ = try QuickRecording.deleteAll(db)
            }
            recordings = []
        } catch {
            print("[QuickRecordingStorage] Clear failed: \(error)")
        }
    }

    private func pruneOldRecordings() {
        do {
            try dbQueue?.write { db in
                // Delete all but the most recent 100
                let sql = """
                    DELETE FROM quick_recordings
                    WHERE id NOT IN (
                        SELECT id FROM quick_recordings
                        ORDER BY createdAt DESC
                        LIMIT 100
                    )
                """
                try db.execute(sql: sql)
            }
            loadRecordings()
        } catch {
            print("[QuickRecordingStorage] Prune failed: \(error)")
        }
    }
}

// MARK: - Preview Helpers

extension QuickRecording {
    static var preview: QuickRecording {
        QuickRecording(
            id: 1,
            text: "Remember to buy groceries and call mom",
            createdAt: Date(),
            durationSeconds: 3.2
        )
    }

    static var previews: [QuickRecording] {
        [
            QuickRecording(id: 1, text: "Buy groceries", createdAt: Date(), durationSeconds: 1.5),
            QuickRecording(id: 2, text: "Call the dentist to reschedule", createdAt: Date().addingTimeInterval(-3600), durationSeconds: 2.8),
            QuickRecording(id: 3, text: "Send the proposal to John by Friday", createdAt: Date().addingTimeInterval(-7200), durationSeconds: 4.1),
        ]
    }
}
