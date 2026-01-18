//
//  SpeakerProfile.swift
//  MeetingRecorder
//
//  Persistent speaker profiles with voice embeddings for cross-meeting identification
//

import Foundation
import GRDB

// MARK: - Speaker Profile

/// A speaker profile with voice embedding for cross-meeting identification
struct SpeakerProfile: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String?
    var email: String?

    /// 256-dimensional voice embedding vector
    var embedding: [Float]

    /// When this profile was created
    let createdAt: Date

    /// When this profile was last matched in a meeting
    var lastSeenAt: Date?

    /// Number of meetings this speaker has been identified in
    var meetingCount: Int

    /// Average confidence score across all matches
    var averageConfidence: Float?

    /// User's notes about this speaker
    var notes: String?

    /// Whether this profile is actively used for matching
    var isActive: Bool

    init(
        id: UUID = UUID(),
        name: String? = nil,
        email: String? = nil,
        embedding: [Float],
        createdAt: Date = Date(),
        lastSeenAt: Date? = nil,
        meetingCount: Int = 1,
        averageConfidence: Float? = nil,
        notes: String? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.embedding = embedding
        self.createdAt = createdAt
        self.lastSeenAt = lastSeenAt
        self.meetingCount = meetingCount
        self.averageConfidence = averageConfidence
        self.notes = notes
        self.isActive = isActive
    }

    // MARK: - Computed Properties

    /// Display name (name or "Unknown Speaker")
    var displayName: String {
        name ?? "Unknown Speaker"
    }

    /// Whether this speaker has been named
    var isNamed: Bool {
        name != nil && !name!.isEmpty
    }

    /// First initial for avatar
    var initial: String {
        if let name = name, !name.isEmpty {
            return String(name.prefix(1)).uppercased()
        }
        return "?"
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: SpeakerProfile, rhs: SpeakerProfile) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - GRDB Persistence

extension SpeakerProfile: FetchableRecord, PersistableRecord {
    static let databaseTableName = "speaker_profiles"

    enum Columns: String, ColumnExpression {
        case id, name, email, embedding, createdAt, lastSeenAt
        case meetingCount, averageConfidence, notes, isActive
    }

    init(row: Row) throws {
        let idString: String = try row[Columns.id]
        id = UUID(uuidString: idString) ?? UUID()
        name = row[Columns.name]
        email = row[Columns.email]
        createdAt = try row[Columns.createdAt]
        lastSeenAt = row[Columns.lastSeenAt]
        meetingCount = try row[Columns.meetingCount]
        averageConfidence = row[Columns.averageConfidence]
        notes = row[Columns.notes]
        isActive = try row[Columns.isActive]

        // Decode embedding from JSON blob
        let embeddingData: Data = try row[Columns.embedding]
        embedding = try JSONDecoder().decode([Float].self, from: embeddingData)
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id.uuidString
        container[Columns.name] = name
        container[Columns.email] = email
        container[Columns.createdAt] = createdAt
        container[Columns.lastSeenAt] = lastSeenAt
        container[Columns.meetingCount] = meetingCount
        container[Columns.averageConfidence] = averageConfidence
        container[Columns.notes] = notes
        container[Columns.isActive] = isActive

        // Encode embedding as JSON blob
        container[Columns.embedding] = try JSONEncoder().encode(embedding)
    }
}

// MARK: - Meeting-Speaker Link

/// Links a speaker profile to a meeting with match confidence
struct MeetingSpeakerLink: Identifiable, Codable {
    let id: UUID
    let meetingId: UUID
    let speakerProfileId: UUID

    /// The speaker ID within the meeting (e.g., "speaker_0")
    let meetingSpeakerId: String

    /// Confidence of the match (cosine similarity)
    let confidence: Float

    /// When this link was created
    let createdAt: Date

    init(
        id: UUID = UUID(),
        meetingId: UUID,
        speakerProfileId: UUID,
        meetingSpeakerId: String,
        confidence: Float,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.meetingId = meetingId
        self.speakerProfileId = speakerProfileId
        self.meetingSpeakerId = meetingSpeakerId
        self.confidence = confidence
        self.createdAt = createdAt
    }
}

extension MeetingSpeakerLink: FetchableRecord, PersistableRecord {
    static let databaseTableName = "meeting_speaker_links"

    enum Columns: String, ColumnExpression {
        case id
        case meetingId = "meeting_id"
        case speakerProfileId = "speaker_profile_id"
        case meetingSpeakerId = "meeting_speaker_id"
        case confidence
        case createdAt = "created_at"
    }

    init(row: Row) throws {
        id = UUID(uuidString: try row[Columns.id]) ?? UUID()
        meetingId = UUID(uuidString: try row[Columns.meetingId]) ?? UUID()
        speakerProfileId = UUID(uuidString: try row[Columns.speakerProfileId]) ?? UUID()
        meetingSpeakerId = try row[Columns.meetingSpeakerId]
        confidence = try row[Columns.confidence]
        createdAt = try row[Columns.createdAt]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id.uuidString
        container[Columns.meetingId] = meetingId.uuidString
        container[Columns.speakerProfileId] = speakerProfileId.uuidString
        container[Columns.meetingSpeakerId] = meetingSpeakerId
        container[Columns.confidence] = confidence
        container[Columns.createdAt] = createdAt
    }
}

// MARK: - Speaker Profile Manager

/// Manages speaker profiles and cross-meeting identification
@MainActor
class SpeakerProfileManager: ObservableObject {
    static let shared = SpeakerProfileManager()

    @Published var profiles: [SpeakerProfile] = []
    @Published var isLoading = false

    private init() {}

    // MARK: - CRUD Operations

    /// Load all speaker profiles
    func loadProfiles() async {
        isLoading = true
        defer { isLoading = false }

        do {
            profiles = try await DatabaseManager.shared.fetchSpeakerProfiles()
            logInfo("[SpeakerProfileManager] Loaded \(profiles.count) speaker profiles")
        } catch {
            logError("[SpeakerProfileManager] Failed to load profiles: \(error)")
        }
    }

    /// Create a new speaker profile from an embedding
    func createProfile(embedding: [Float], name: String? = nil) async throws -> SpeakerProfile {
        let profile = SpeakerProfile(
            name: name,
            embedding: embedding,
            lastSeenAt: Date()
        )

        try await DatabaseManager.shared.saveSpeakerProfile(profile)
        await loadProfiles()

        logInfo("[SpeakerProfileManager] Created new speaker profile: \(profile.id)")
        return profile
    }

    /// Update a speaker profile's name (syncs across all meetings)
    func updateName(_ profileId: UUID, name: String) async throws {
        guard var profile = profiles.first(where: { $0.id == profileId }) else {
            throw SpeakerProfileError.notFound
        }

        profile.name = name
        try await DatabaseManager.shared.saveSpeakerProfile(profile)

        // Update all meetings that have this speaker
        try await syncSpeakerNameToMeetings(profileId: profileId, name: name)

        await loadProfiles()
        logInfo("[SpeakerProfileManager] Updated speaker name to: \(name)")
    }

    /// Delete a speaker profile
    func deleteProfile(_ profileId: UUID) async throws {
        try await DatabaseManager.shared.deleteSpeakerProfile(profileId)
        await loadProfiles()
        logInfo("[SpeakerProfileManager] Deleted speaker profile: \(profileId)")
    }

    /// Merge two speaker profiles (when user confirms they're the same person)
    func mergeProfiles(keep: UUID, delete: UUID) async throws {
        guard let keepProfile = profiles.first(where: { $0.id == keep }),
              let deleteProfile = profiles.first(where: { $0.id == delete }) else {
            throw SpeakerProfileError.notFound
        }

        // Update all meeting links from deleted profile to kept profile
        try await DatabaseManager.shared.updateMeetingSpeakerLinks(
            fromProfileId: delete,
            toProfileId: keep
        )

        // Update kept profile stats
        var updated = keepProfile
        updated.meetingCount += deleteProfile.meetingCount

        // Average the embeddings for better accuracy
        if keepProfile.embedding.count == deleteProfile.embedding.count {
            updated.embedding = zip(keepProfile.embedding, deleteProfile.embedding)
                .map { ($0 + $1) / 2 }
        }

        try await DatabaseManager.shared.saveSpeakerProfile(updated)

        // Delete the old profile
        try await DatabaseManager.shared.deleteSpeakerProfile(delete)

        await loadProfiles()
        logInfo("[SpeakerProfileManager] Merged profiles: \(delete) into \(keep)")
    }

    // MARK: - Speaker Matching

    /// Find or create a speaker profile for an embedding
    func findOrCreateProfile(
        embedding: [Float],
        meetingId: UUID,
        meetingSpeakerId: String
    ) async throws -> (profile: SpeakerProfile, isNew: Bool, confidence: Float) {
        // Get active profiles
        let activeProfiles = profiles.filter { $0.isActive }

        // Try to find a match locally (fast)
        if let match = await VoiceEmbeddingClient.shared.findMatchingSpeakerLocally(
            embedding: embedding,
            knownProfiles: activeProfiles
        ) {
            // Update the profile's stats
            var updatedProfile = match.profile
            updatedProfile.lastSeenAt = Date()
            updatedProfile.meetingCount += 1

            // Update average confidence
            let oldAvg = updatedProfile.averageConfidence ?? match.similarity
            let newCount = Float(updatedProfile.meetingCount)
            updatedProfile.averageConfidence = (oldAvg * (newCount - 1) + match.similarity) / newCount

            try await DatabaseManager.shared.saveSpeakerProfile(updatedProfile)

            // Create meeting link
            let link = MeetingSpeakerLink(
                meetingId: meetingId,
                speakerProfileId: match.profile.id,
                meetingSpeakerId: meetingSpeakerId,
                confidence: match.similarity
            )
            try await DatabaseManager.shared.saveMeetingSpeakerLink(link)

            await loadProfiles()
            return (updatedProfile, false, match.similarity)
        }

        // No match found - create new profile
        let newProfile = try await createProfile(embedding: embedding)

        // Create meeting link
        let link = MeetingSpeakerLink(
            meetingId: meetingId,
            speakerProfileId: newProfile.id,
            meetingSpeakerId: meetingSpeakerId,
            confidence: 1.0
        )
        try await DatabaseManager.shared.saveMeetingSpeakerLink(link)

        return (newProfile, true, 1.0)
    }

    // MARK: - Cross-Meeting Sync

    /// Sync a speaker's name to all meetings they appear in
    private func syncSpeakerNameToMeetings(profileId: UUID, name: String) async throws {
        // Get all meeting links for this profile
        let links = try await DatabaseManager.shared.fetchMeetingSpeakerLinks(forProfileId: profileId)

        for link in links {
            // Get the meeting
            guard var meeting = try await DatabaseManager.shared.getMeeting(id: link.meetingId) else {
                continue
            }

            // Update the speaker label
            var labels = meeting.speakerLabels ?? []
            labels.removeAll { $0.speakerId == link.meetingSpeakerId }
            labels.append(SpeakerLabel(
                speakerId: link.meetingSpeakerId,
                name: name,
                confidence: Double(link.confidence),
                isUserAssigned: true
            ))
            meeting.speakerLabels = labels

            try await DatabaseManager.shared.update(meeting)
        }

        // Notify UI
        NotificationCenter.default.post(name: .meetingsDidChange, object: nil)
    }

    // MARK: - Computed Properties

    /// Named speaker profiles (sorted by name)
    var namedProfiles: [SpeakerProfile] {
        profiles.filter { $0.isNamed }.sorted { ($0.name ?? "") < ($1.name ?? "") }
    }

    /// Unnamed speaker profiles (sorted by meeting count, most frequent first)
    var unnamedProfiles: [SpeakerProfile] {
        profiles.filter { !$0.isNamed }.sorted { $0.meetingCount > $1.meetingCount }
    }
}

// MARK: - Errors

enum SpeakerProfileError: LocalizedError {
    case notFound
    case embeddingMismatch
    case databaseError(String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Speaker profile not found"
        case .embeddingMismatch:
            return "Embedding dimension mismatch"
        case .databaseError(let message):
            return "Database error: \(message)"
        }
    }
}
