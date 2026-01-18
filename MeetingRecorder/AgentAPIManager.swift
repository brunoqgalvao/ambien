//
//  AgentAPIManager.swift
//  MeetingRecorder
//
//  Exports meetings to ~/.ambient/meetings/ as JSON for AI agents.
//  Uses atomic writes with lock files to prevent partial reads.
//

import Foundation

/// Errors that can occur during agent API export
enum AgentAPIError: LocalizedError {
    case directoryCreationFailed(Error)
    case writeFailed(Error)
    case encodingFailed(Error)
    case lockAcquisitionFailed

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let error):
            return "Failed to create directory: \(error.localizedDescription)"
        case .writeFailed(let error):
            return "Failed to write file: \(error.localizedDescription)"
        case .encodingFailed(let error):
            return "Failed to encode JSON: \(error.localizedDescription)"
        case .lockAcquisitionFailed:
            return "Failed to acquire lock file"
        }
    }
}

/// JSON format for exported meetings (agent-readable)
struct AgentMeeting: Codable {
    let id: String
    let title: String
    let date: String
    let startTime: String
    let endTime: String?
    let duration: Int
    let sourceApp: String?
    let transcript: String?
    let actionItems: [String]?
    let status: String
    let audioPath: String
    let apiCostCents: Int?
    let createdAt: String

    init(from meeting: Meeting) {
        self.id = meeting.id.uuidString.lowercased()
        self.title = meeting.title

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        self.date = dateFormatter.string(from: meeting.startTime)

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        self.startTime = timeFormatter.string(from: meeting.startTime)
        self.endTime = meeting.endTime.map { timeFormatter.string(from: $0) }

        self.duration = Int(meeting.duration)
        self.sourceApp = meeting.sourceApp?.lowercased()
        self.transcript = meeting.transcript
        self.actionItems = meeting.actionItems
        self.status = meeting.status.rawValue
        self.audioPath = meeting.audioPath
        self.apiCostCents = meeting.apiCostCents

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        self.createdAt = isoFormatter.string(from: meeting.createdAt)
    }
}

/// Index entry for a meeting
struct AgentMeetingIndex: Codable {
    let id: String
    let date: String
    let title: String
    let status: String
    let path: String
}

/// Index file format
struct AgentIndex: Codable {
    let version: Int
    let lastUpdated: String
    var meetings: [AgentMeetingIndex]
    var groups: [AgentGroupIndex]?
}

/// Index entry for a group
struct AgentGroupIndex: Codable {
    let id: String
    let name: String
    let emoji: String?
    let meetingCount: Int
    let path: String
}

/// Manages JSON export for AI agents (Claude Code, Codex, etc.)
actor AgentAPIManager {
    private let fileManager = FileManager.default

    /// Base directory: ~/.ambient/meetings/
    private var baseDirectory: URL {
        let home = fileManager.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".ambient", isDirectory: true)
            .appendingPathComponent("meetings", isDirectory: true)
    }

    /// Index file path
    private var indexPath: URL {
        baseDirectory.appendingPathComponent("index.json")
    }

    /// Lock file path
    private var lockPath: URL {
        baseDirectory.appendingPathComponent(".lock")
    }

    // MARK: - Public Methods

    /// Export a single meeting to JSON
    /// Call this after transcription completes
    func exportMeeting(_ meeting: Meeting) async throws {
        // Only export ready meetings
        guard meeting.status == .ready else {
            print("[AgentAPI] Skipping export for non-ready meeting: \(meeting.id)")
            return
        }

        try await withLock {
            try await self.writeOneMeeting(meeting)
            try await self.updateIndex()
        }

        print("[AgentAPI] Exported meeting: \(meeting.id)")
    }

    /// Export all ready meetings from the database
    /// Use this to sync the JSON files with the database
    func exportAll() async throws {
        let meetings = try await DatabaseManager.shared.getAllMeetings()
        let readyMeetings = meetings.filter { $0.status == .ready }

        try await withLock {
            for meeting in readyMeetings {
                try await self.writeOneMeeting(meeting)
            }
            try await self.updateIndex()
        }

        print("[AgentAPI] Exported \(readyMeetings.count) meetings")
    }

    /// Delete a meeting's JSON file
    func deleteMeeting(_ meetingId: UUID) async throws {
        try await withLock {
            // Find and delete the meeting file
            let meetings = try await DatabaseManager.shared.getAllMeetings()
            if let meeting = meetings.first(where: { $0.id == meetingId }) {
                let path = self.meetingFilePath(for: meeting)
                try? self.fileManager.removeItem(at: path)
            }
            try await self.updateIndex()
        }

        print("[AgentAPI] Deleted meeting JSON: \(meetingId)")
    }

    // MARK: - Group Export

    /// Groups directory: ~/.ambient/meetings/groups/
    private var groupsDirectory: URL {
        baseDirectory.appendingPathComponent("groups", isDirectory: true)
    }

    /// Export a group with all its meetings to JSON
    func exportGroup(_ group: MeetingGroup, meetings: [Meeting]) async throws {
        try await withLock {
            try await self.writeOneGroup(group, meetings: meetings)
            try await self.updateIndex()
        }

        print("[AgentAPI] Exported group: \(group.name) with \(meetings.count) meetings")
    }

    /// Delete a group's JSON file
    func deleteGroup(_ groupId: UUID) async {
        do {
            try await withLock {
                let path = self.groupFilePath(for: groupId)
                try? self.fileManager.removeItem(at: path)
                try await self.updateIndex()
            }
            print("[AgentAPI] Deleted group JSON: \(groupId)")
        } catch {
            print("[AgentAPI] Error deleting group: \(error)")
        }
    }

    /// Write a single group to its JSON file
    private func writeOneGroup(_ group: MeetingGroup, meetings: [Meeting]) async throws {
        let filePath = groupFilePath(for: group.id)
        let directoryPath = filePath.deletingLastPathComponent()

        // Create groups directory if needed
        try fileManager.createDirectory(at: directoryPath, withIntermediateDirectories: true)

        // Create agent group format with combined transcript
        let agentGroup = AgentGroup(from: group, meetings: meetings)

        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data: Data
        do {
            data = try encoder.encode(agentGroup)
        } catch {
            throw AgentAPIError.encodingFailed(error)
        }

        // Atomic write
        let tmpPath = filePath.appendingPathExtension("tmp")
        try? fileManager.removeItem(at: tmpPath)

        do {
            try data.write(to: tmpPath)
            try? fileManager.removeItem(at: filePath)
            try fileManager.moveItem(at: tmpPath, to: filePath)
        } catch {
            try? fileManager.removeItem(at: tmpPath)
            throw AgentAPIError.writeFailed(error)
        }
    }

    /// Get the file path for a group
    private func groupFilePath(for groupId: UUID) -> URL {
        groupsDirectory.appendingPathComponent("\(groupId.uuidString.lowercased()).json")
    }

    /// Build index entries for all groups
    private func buildGroupIndexEntries() async throws -> [AgentGroupIndex] {
        let groups = try await GroupManager.shared.getAllGroups()

        return groups.map { group in
            AgentGroupIndex(
                id: group.id.uuidString.lowercased(),
                name: group.name,
                emoji: group.emoji,
                meetingCount: group.meetingCount,
                path: "groups/\(group.id.uuidString.lowercased()).json"
            )
        }
    }

    // MARK: - Private Methods

    /// Write a single meeting to its JSON file
    private func writeOneMeeting(_ meeting: Meeting) async throws {
        let filePath = meetingFilePath(for: meeting)
        let directoryPath = filePath.deletingLastPathComponent()

        // Create date directory if needed
        try fileManager.createDirectory(at: directoryPath, withIntermediateDirectories: true)

        // Create agent meeting format
        let agentMeeting = AgentMeeting(from: meeting)

        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data: Data
        do {
            data = try encoder.encode(agentMeeting)
        } catch {
            throw AgentAPIError.encodingFailed(error)
        }

        // Atomic write: write to .tmp, then rename
        let tmpPath = filePath.appendingPathExtension("tmp")
        try? fileManager.removeItem(at: tmpPath)

        do {
            try data.write(to: tmpPath)
            try? fileManager.removeItem(at: filePath)
            try fileManager.moveItem(at: tmpPath, to: filePath)
        } catch {
            try? fileManager.removeItem(at: tmpPath)
            throw AgentAPIError.writeFailed(error)
        }
    }

    /// Update the index.json file
    private func updateIndex() async throws {
        // Ensure base directory exists
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        // Get all ready meetings
        let meetings = try await DatabaseManager.shared.getAllMeetings()
        let readyMeetings = meetings.filter { $0.status == .ready }

        // Build meeting index entries
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        let meetingEntries = readyMeetings.map { meeting -> AgentMeetingIndex in
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateStr = dateFormatter.string(from: meeting.startTime)

            return AgentMeetingIndex(
                id: meeting.id.uuidString.lowercased(),
                date: dateStr,
                title: meeting.title,
                status: meeting.status.rawValue,
                path: "\(dateStr)/\(slugify(meeting.title)).json"
            )
        }

        // Build group index entries
        let groupEntries = try await buildGroupIndexEntries()

        let index = AgentIndex(
            version: 1,
            lastUpdated: isoFormatter.string(from: Date()),
            meetings: meetingEntries,
            groups: groupEntries.isEmpty ? nil : groupEntries
        )

        // Encode
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data: Data
        do {
            data = try encoder.encode(index)
        } catch {
            throw AgentAPIError.encodingFailed(error)
        }

        // Atomic write
        let tmpPath = indexPath.appendingPathExtension("tmp")
        try? fileManager.removeItem(at: tmpPath)

        do {
            try data.write(to: tmpPath)
            try? fileManager.removeItem(at: indexPath)
            try fileManager.moveItem(at: tmpPath, to: indexPath)
        } catch {
            try? fileManager.removeItem(at: tmpPath)
            throw AgentAPIError.writeFailed(error)
        }
    }

    /// Get the file path for a meeting
    private func meetingFilePath(for meeting: Meeting) -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateDir = dateFormatter.string(from: meeting.startTime)
        let filename = slugify(meeting.title) + ".json"

        return baseDirectory
            .appendingPathComponent(dateDir, isDirectory: true)
            .appendingPathComponent(filename)
    }

    /// Convert a title to a URL-safe slug
    private func slugify(_ title: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let slug = title
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .unicodeScalars
            .filter { allowed.contains($0) }
            .map { Character($0) }

        var result = String(slug)

        // Remove consecutive dashes
        while result.contains("--") {
            result = result.replacingOccurrences(of: "--", with: "-")
        }

        // Trim dashes from ends
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        // Default if empty
        if result.isEmpty {
            result = "meeting"
        }

        return result
    }

    // MARK: - Lock File Protocol

    /// Execute a block with a lock file
    private func withLock<T>(_ block: () async throws -> T) async throws -> T {
        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        // Create lock file
        let created = fileManager.createFile(atPath: lockPath.path, contents: nil)
        guard created || fileManager.fileExists(atPath: lockPath.path) else {
            throw AgentAPIError.lockAcquisitionFailed
        }

        // Mark lock as in use
        let pid = ProcessInfo.processInfo.processIdentifier
        let lockData = "\(pid)".data(using: .utf8)
        try? lockData?.write(to: lockPath)

        defer {
            // Remove lock file
            try? fileManager.removeItem(at: lockPath)
        }

        return try await block()
    }
}

// MARK: - Singleton

extension AgentAPIManager {
    static let shared = AgentAPIManager()
}
