//
//  APICallLog.swift
//  MeetingRecorder
//
//  Logs all AI API calls with provider, model, cost, response times.
//  Stored in SQLite for history and displayed in Settings > Logs.
//

import Foundation
import GRDB

// MARK: - API Call Type

/// The type of API operation
enum APICallType: String, Codable, CaseIterable {
    case transcription = "transcription"
    case diarization = "diarization"
    case summarization = "summarization"
    case titleGeneration = "title_generation"
    case dictation = "dictation"
    case chat = "chat"
    case aiCleanup = "ai_cleanup"
    case qualityValidation = "quality_validation"
    case speakerIdentification = "speaker_identification"

    var displayName: String {
        switch self {
        case .transcription: return "Transcription"
        case .diarization: return "Diarization"
        case .summarization: return "Summarization"
        case .titleGeneration: return "Title Generation"
        case .dictation: return "Dictation"
        case .chat: return "Chat"
        case .aiCleanup: return "AI Cleanup"
        case .qualityValidation: return "Quality Check"
        case .speakerIdentification: return "Speaker ID"
        }
    }

    var icon: String {
        switch self {
        case .transcription: return "waveform"
        case .diarization: return "person.2"
        case .summarization: return "doc.text"
        case .titleGeneration: return "textformat"
        case .dictation: return "mic"
        case .chat: return "bubble.left.and.bubble.right"
        case .aiCleanup: return "sparkles"
        case .qualityValidation: return "checkmark.shield"
        case .speakerIdentification: return "person.crop.circle.badge.questionmark"
        }
    }
}

// MARK: - API Call Status

enum APICallStatus: String, Codable {
    case success = "success"
    case failed = "failed"
    case timeout = "timeout"
    case rateLimited = "rate_limited"

    var displayName: String {
        switch self {
        case .success: return "Success"
        case .failed: return "Failed"
        case .timeout: return "Timeout"
        case .rateLimited: return "Rate Limited"
        }
    }
}

// MARK: - API Call Log Model

/// A logged API call with all relevant metadata
struct APICallLog: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let callType: APICallType
    let provider: String        // "OpenAI", "Anthropic", "AssemblyAI", etc.
    let model: String           // "whisper-1", "gpt-4o-mini", etc.
    let status: APICallStatus

    // Request details
    let endpoint: String        // "/v1/audio/transcriptions", etc.
    let inputSizeBytes: Int?    // Size of audio/text input
    let inputTokens: Int?       // For text-based APIs

    // Response details
    let outputTokens: Int?
    let durationMs: Int         // Time to complete the request
    let costCents: Int          // Estimated cost in cents

    // Context
    let meetingId: UUID?        // Associated meeting if any
    let errorMessage: String?   // Error details if failed

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        callType: APICallType,
        provider: String,
        model: String,
        status: APICallStatus,
        endpoint: String,
        inputSizeBytes: Int? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        durationMs: Int,
        costCents: Int,
        meetingId: UUID? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.callType = callType
        self.provider = provider
        self.model = model
        self.status = status
        self.endpoint = endpoint
        self.inputSizeBytes = inputSizeBytes
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.durationMs = durationMs
        self.costCents = costCents
        self.meetingId = meetingId
        self.errorMessage = errorMessage
    }

    // MARK: - Computed Properties

    var formattedDuration: String {
        if durationMs < 1000 {
            return "\(durationMs)ms"
        } else {
            let seconds = Double(durationMs) / 1000.0
            return String(format: "%.1fs", seconds)
        }
    }

    var formattedCost: String {
        if costCents == 0 {
            return "Free"
        } else if costCents < 100 {
            return "\(costCents)¢"
        } else {
            return String(format: "$%.2f", Double(costCents) / 100.0)
        }
    }

    var formattedInputSize: String? {
        guard let size = inputSizeBytes else { return nil }
        if size < 1024 {
            return "\(size) B"
        } else if size < 1024 * 1024 {
            return String(format: "%.1f KB", Double(size) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(size) / (1024.0 * 1024.0))
        }
    }
}

// MARK: - GRDB Record

/// GRDB record for api_logs table
struct APICallLogRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "api_logs"

    let id: String
    let timestamp: Date
    let callType: String
    let provider: String
    let model: String
    let status: String
    let endpoint: String
    let inputSizeBytes: Int?
    let inputTokens: Int?
    let outputTokens: Int?
    let durationMs: Int
    let costCents: Int
    let meetingId: String?
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case callType = "call_type"
        case provider
        case model
        case status
        case endpoint
        case inputSizeBytes = "input_size_bytes"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case durationMs = "duration_ms"
        case costCents = "cost_cents"
        case meetingId = "meeting_id"
        case errorMessage = "error_message"
    }

    init(_ log: APICallLog) {
        self.id = log.id.uuidString
        self.timestamp = log.timestamp
        self.callType = log.callType.rawValue
        self.provider = log.provider
        self.model = log.model
        self.status = log.status.rawValue
        self.endpoint = log.endpoint
        self.inputSizeBytes = log.inputSizeBytes
        self.inputTokens = log.inputTokens
        self.outputTokens = log.outputTokens
        self.durationMs = log.durationMs
        self.costCents = log.costCents
        self.meetingId = log.meetingId?.uuidString
        self.errorMessage = log.errorMessage
    }

    func toLog() -> APICallLog {
        APICallLog(
            id: UUID(uuidString: id) ?? UUID(),
            timestamp: timestamp,
            callType: APICallType(rawValue: callType) ?? .transcription,
            provider: provider,
            model: model,
            status: APICallStatus(rawValue: status) ?? .success,
            endpoint: endpoint,
            inputSizeBytes: inputSizeBytes,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            durationMs: durationMs,
            costCents: costCents,
            meetingId: meetingId.flatMap { UUID(uuidString: $0) },
            errorMessage: errorMessage
        )
    }
}

// MARK: - API Call Log Manager

/// Manages storing and retrieving API call logs
actor APICallLogManager {
    static let shared = APICallLogManager()

    private var dbQueue: DatabaseQueue?
    private let maxLogAge: TimeInterval = 30 * 24 * 60 * 60  // 30 days

    private init() {}

    // MARK: - Initialization

    /// Initialize with database queue (called by DatabaseManager)
    func initialize(with dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    // MARK: - Logging

    /// Log an API call
    func log(_ apiLog: APICallLog) async {
        guard let db = dbQueue else {
            logWarning("[APICallLogManager] Database not initialized")
            return
        }

        do {
            try await db.write { db in
                try APICallLogRecord(apiLog).insert(db)
            }
            logDebug("[APICallLogManager] Logged \(apiLog.callType.displayName) call to \(apiLog.provider)")
        } catch {
            logError("[APICallLogManager] Failed to log API call: \(error)")
        }
    }

    /// Convenience method to log a successful call
    func logSuccess(
        type: APICallType,
        provider: String,
        model: String,
        endpoint: String,
        inputSizeBytes: Int? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        durationMs: Int,
        costCents: Int,
        meetingId: UUID? = nil
    ) async {
        await log(APICallLog(
            callType: type,
            provider: provider,
            model: model,
            status: .success,
            endpoint: endpoint,
            inputSizeBytes: inputSizeBytes,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            durationMs: durationMs,
            costCents: costCents,
            meetingId: meetingId
        ))
    }

    /// Convenience method to log a failed call
    func logFailure(
        type: APICallType,
        provider: String,
        model: String,
        endpoint: String,
        durationMs: Int,
        error: String,
        status: APICallStatus = .failed,
        meetingId: UUID? = nil
    ) async {
        await log(APICallLog(
            callType: type,
            provider: provider,
            model: model,
            status: status,
            endpoint: endpoint,
            durationMs: durationMs,
            costCents: 0,
            meetingId: meetingId,
            errorMessage: error
        ))
    }

    // MARK: - Retrieval

    /// Get all logs, newest first
    func getAllLogs(limit: Int = 500) async -> [APICallLog] {
        guard let db = dbQueue else { return [] }

        do {
            return try await db.read { db in
                let records = try APICallLogRecord.fetchAll(
                    db,
                    sql: "SELECT * FROM api_logs ORDER BY timestamp DESC LIMIT ?",
                    arguments: [limit]
                )
                return records.map { $0.toLog() }
            }
        } catch {
            logError("[APICallLogManager] Failed to fetch logs: \(error)")
            return []
        }
    }

    /// Get logs for a specific time period
    func getLogs(from startDate: Date, to endDate: Date) async -> [APICallLog] {
        guard let db = dbQueue else { return [] }

        do {
            return try await db.read { db in
                let records = try APICallLogRecord.fetchAll(
                    db,
                    sql: "SELECT * FROM api_logs WHERE timestamp >= ? AND timestamp <= ? ORDER BY timestamp DESC",
                    arguments: [startDate, endDate]
                )
                return records.map { $0.toLog() }
            }
        } catch {
            logError("[APICallLogManager] Failed to fetch logs: \(error)")
            return []
        }
    }

    /// Get logs for a specific meeting
    func getLogs(forMeeting meetingId: UUID) async -> [APICallLog] {
        guard let db = dbQueue else { return [] }

        do {
            return try await db.read { db in
                let records = try APICallLogRecord.fetchAll(
                    db,
                    sql: "SELECT * FROM api_logs WHERE meeting_id = ? ORDER BY timestamp ASC",
                    arguments: [meetingId.uuidString]
                )
                return records.map { $0.toLog() }
            }
        } catch {
            logError("[APICallLogManager] Failed to fetch logs: \(error)")
            return []
        }
    }

    // MARK: - Statistics

    /// Get statistics for a time period
    func getStatistics(from startDate: Date, to endDate: Date) async -> APICallStatistics {
        guard let db = dbQueue else { return APICallStatistics() }

        do {
            return try await db.read { db in
                // Total calls and cost
                let totalsRow = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT
                            COUNT(*) as total_calls,
                            COALESCE(SUM(cost_cents), 0) as total_cost,
                            COALESCE(SUM(CASE WHEN status = 'success' THEN 1 ELSE 0 END), 0) as success_count,
                            COALESCE(AVG(duration_ms), 0) as avg_duration
                        FROM api_logs
                        WHERE timestamp >= ? AND timestamp <= ?
                    """,
                    arguments: [startDate, endDate]
                )

                // Breakdown by provider
                let providerRows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT
                            provider,
                            COUNT(*) as calls,
                            COALESCE(SUM(cost_cents), 0) as cost
                        FROM api_logs
                        WHERE timestamp >= ? AND timestamp <= ?
                        GROUP BY provider
                        ORDER BY cost DESC
                    """,
                    arguments: [startDate, endDate]
                )

                // Breakdown by type
                let typeRows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT
                            call_type,
                            COUNT(*) as calls,
                            COALESCE(SUM(cost_cents), 0) as cost
                        FROM api_logs
                        WHERE timestamp >= ? AND timestamp <= ?
                        GROUP BY call_type
                        ORDER BY cost DESC
                    """,
                    arguments: [startDate, endDate]
                )

                var stats = APICallStatistics()

                if let row = totalsRow {
                    stats.totalCalls = row["total_calls"] ?? 0
                    stats.totalCostCents = row["total_cost"] ?? 0
                    stats.successCount = row["success_count"] ?? 0
                    stats.averageDurationMs = row["avg_duration"] ?? 0
                }

                for row in providerRows {
                    if let provider: String = row["provider"],
                       let calls: Int = row["calls"],
                       let cost: Int = row["cost"] {
                        stats.byProvider[provider] = (calls: calls, costCents: cost)
                    }
                }

                for row in typeRows {
                    if let typeStr: String = row["call_type"],
                       let type = APICallType(rawValue: typeStr),
                       let calls: Int = row["calls"],
                       let cost: Int = row["cost"] {
                        stats.byType[type] = (calls: calls, costCents: cost)
                    }
                }

                return stats
            }
        } catch {
            logError("[APICallLogManager] Failed to get statistics: \(error)")
            return APICallStatistics()
        }
    }

    // MARK: - Cleanup

    /// Delete old logs
    func pruneOldLogs() async {
        guard let db = dbQueue else { return }

        let cutoffDate = Date().addingTimeInterval(-maxLogAge)

        do {
            try await db.write { db in
                try db.execute(
                    sql: "DELETE FROM api_logs WHERE timestamp < ?",
                    arguments: [cutoffDate]
                )
            }
            logInfo("[APICallLogManager] Pruned logs older than 30 days")
        } catch {
            logError("[APICallLogManager] Failed to prune logs: \(error)")
        }
    }

    /// Clear all logs
    func clearAllLogs() async {
        guard let db = dbQueue else { return }

        do {
            try await db.write { db in
                try db.execute(sql: "DELETE FROM api_logs")
            }
            logInfo("[APICallLogManager] Cleared all API logs")
        } catch {
            logError("[APICallLogManager] Failed to clear logs: \(error)")
        }
    }
}

// MARK: - Statistics

/// Aggregated statistics for API calls
struct APICallStatistics {
    var totalCalls: Int = 0
    var totalCostCents: Int = 0
    var successCount: Int = 0
    var averageDurationMs: Double = 0
    var byProvider: [String: (calls: Int, costCents: Int)] = [:]
    var byType: [APICallType: (calls: Int, costCents: Int)] = [:]

    var failureCount: Int {
        totalCalls - successCount
    }

    var successRate: Double {
        guard totalCalls > 0 else { return 0 }
        return Double(successCount) / Double(totalCalls) * 100
    }

    var formattedTotalCost: String {
        if totalCostCents == 0 {
            return "$0.00"
        } else if totalCostCents < 100 {
            return "\(totalCostCents)¢"
        } else {
            return String(format: "$%.2f", Double(totalCostCents) / 100.0)
        }
    }
}
