//
//  SpeakerEmbeddingService.swift
//  MeetingRecorder
//
//  Extracts voice embeddings from speaker segments and matches against known profiles
//

import Foundation
import AVFoundation

// MARK: - Service Result

/// Result from speaker embedding extraction
struct SpeakerEmbeddingResult {
    /// Matched or newly created speaker profiles for each speaker in the meeting
    let speakerMatches: [SpeakerMatch]

    /// Whether any new profiles were created
    var hasNewProfiles: Bool {
        speakerMatches.contains { $0.isNewProfile }
    }

    /// Whether any speakers were matched to known profiles
    var hasMatches: Bool {
        speakerMatches.contains { !$0.isNewProfile }
    }
}

/// A match between a meeting speaker and a profile
struct SpeakerMatch {
    /// The speaker ID in the meeting (e.g., "speaker_0")
    let meetingSpeakerId: String

    /// The matched or created profile
    let profile: SpeakerProfile

    /// Whether this is a new profile (not matched to existing)
    let isNewProfile: Bool

    /// Confidence of the match (1.0 if new profile)
    let confidence: Float

    /// The embedding extracted for this speaker
    let embedding: [Float]
}

// MARK: - Speaker Embedding Service

/// Service for extracting speaker embeddings and matching to profiles
actor SpeakerEmbeddingService {
    static let shared = SpeakerEmbeddingService()

    /// Minimum segment duration to extract embedding from (seconds)
    private let minSegmentDuration: TimeInterval = 3.0

    /// Preferred segment duration for best embedding quality
    private let preferredSegmentDuration: TimeInterval = 10.0

    private init() {}

    // MARK: - Main Entry Point

    /// Extract embeddings for all speakers and match to known profiles
    /// - Parameters:
    ///   - audioPath: Path to the meeting audio file
    ///   - segments: Diarization segments with speaker IDs
    ///   - meetingId: ID of the meeting being processed
    /// - Returns: Speaker matches with profiles
    func extractAndMatchSpeakers(
        audioPath: String,
        segments: [DiarizationSegment],
        meetingId: UUID
    ) async throws -> SpeakerEmbeddingResult {
        // Check if service is configured
        await VoiceEmbeddingClient.shared.loadConfiguration()
        guard await VoiceEmbeddingClient.shared.isConfigured else {
            logWarning("[SpeakerEmbeddingService] Voice embedding service not configured, skipping")
            throw SpeakerEmbeddingError.serviceNotConfigured
        }

        // Check service health
        guard await VoiceEmbeddingClient.shared.healthCheck() else {
            logWarning("[SpeakerEmbeddingService] Voice embedding service unhealthy, skipping")
            throw SpeakerEmbeddingError.serviceUnavailable
        }

        // Group segments by speaker
        let speakerSegments = Dictionary(grouping: segments, by: { $0.speakerId })
        let uniqueSpeakers = Array(speakerSegments.keys).sorted()

        logInfo("[SpeakerEmbeddingService] Extracting embeddings for \(uniqueSpeakers.count) speakers")

        // Load known profiles
        let knownProfiles = try await DatabaseManager.shared.fetchActiveSpeakerProfiles()
        logInfo("[SpeakerEmbeddingService] Loaded \(knownProfiles.count) known profiles")

        var matches: [SpeakerMatch] = []

        for speakerId in uniqueSpeakers {
            guard let speakerSegs = speakerSegments[speakerId] else { continue }

            // Find the best segment for this speaker
            guard let bestSegment = selectBestSegment(from: speakerSegs) else {
                logWarning("[SpeakerEmbeddingService] No suitable segment for \(speakerId)")
                continue
            }

            do {
                // Extract audio segment
                let segmentAudio = try await extractAudioSegment(
                    from: audioPath,
                    start: bestSegment.start,
                    duration: min(preferredSegmentDuration, bestSegment.end - bestSegment.start)
                )

                // Get embedding
                let embedding = try await VoiceEmbeddingClient.shared.extractEmbedding(
                    audioData: segmentAudio,
                    format: "wav"
                )

                logInfo("[SpeakerEmbeddingService] Got \(embedding.count)-dim embedding for \(speakerId)")

                // Match against known profiles
                let match = await matchOrCreateProfile(
                    embedding: embedding,
                    speakerId: speakerId,
                    meetingId: meetingId,
                    knownProfiles: knownProfiles
                )

                matches.append(match)

            } catch {
                logError("[SpeakerEmbeddingService] Failed to process \(speakerId): \(error)")
                // Continue with other speakers
            }
        }

        logInfo("[SpeakerEmbeddingService] Completed: \(matches.count) speakers processed")
        return SpeakerEmbeddingResult(speakerMatches: matches)
    }

    // MARK: - Segment Selection

    /// Select the best segment for embedding extraction
    /// Prefers longer segments with clear speech
    private func selectBestSegment(from segments: [DiarizationSegment]) -> DiarizationSegment? {
        // Filter to segments long enough
        let validSegments = segments.filter { ($0.end - $0.start) >= minSegmentDuration }

        guard !validSegments.isEmpty else {
            // If no segment is long enough, try combining adjacent segments
            return combineShortSegments(segments)
        }

        // Find the segment closest to preferred duration (not too short, not too long)
        return validSegments.min(by: { segment1, segment2 in
            let duration1 = segment1.end - segment1.start
            let duration2 = segment2.end - segment2.start

            let diff1 = abs(duration1 - preferredSegmentDuration)
            let diff2 = abs(duration2 - preferredSegmentDuration)

            return diff1 < diff2
        })
    }

    /// Try to combine short adjacent segments
    private func combineShortSegments(_ segments: [DiarizationSegment]) -> DiarizationSegment? {
        guard !segments.isEmpty else { return nil }

        // Sort by start time
        let sorted = segments.sorted { $0.start < $1.start }

        // Return the longest single segment if we can't combine
        return sorted.max(by: { ($0.end - $0.start) < ($1.end - $1.start) })
    }

    // MARK: - Audio Extraction

    /// Extract a segment of audio as WAV data
    private func extractAudioSegment(
        from audioPath: String,
        start: TimeInterval,
        duration: TimeInterval
    ) async throws -> Data {
        let url = URL(fileURLWithPath: audioPath)

        // Use AVAssetReader to extract the segment
        let asset = AVAsset(url: url)

        // Get audio track
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw SpeakerEmbeddingError.noAudioTrack
        }

        let assetReader = try AVAssetReader(asset: asset)

        // Configure output settings for WAV (PCM)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        assetReader.add(trackOutput)

        // Set time range
        let startTime = CMTime(seconds: start, preferredTimescale: 44100)
        let durationTime = CMTime(seconds: duration, preferredTimescale: 44100)
        assetReader.timeRange = CMTimeRange(start: startTime, duration: durationTime)

        assetReader.startReading()

        // Collect audio samples
        var audioData = Data()

        while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
            if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                var length = 0
                var dataPointer: UnsafeMutablePointer<Int8>?
                CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

                if let dataPointer = dataPointer {
                    audioData.append(Data(bytes: dataPointer, count: length))
                }
            }
        }

        // Create WAV header
        let wavData = createWAVFile(from: audioData, sampleRate: 16000, channels: 1, bitsPerSample: 16)

        logInfo("[SpeakerEmbeddingService] Extracted \(wavData.count) bytes of audio")
        return wavData
    }

    /// Create a WAV file from raw PCM data
    private func createWAVFile(from pcmData: Data, sampleRate: Int, channels: Int, bitsPerSample: Int) -> Data {
        var wavData = Data()

        let dataSize = pcmData.count
        let fileSize = 36 + dataSize

        // RIFF header
        wavData.append("RIFF".data(using: .ascii)!)
        wavData.append(UInt32(fileSize).littleEndianData)
        wavData.append("WAVE".data(using: .ascii)!)

        // fmt chunk
        wavData.append("fmt ".data(using: .ascii)!)
        wavData.append(UInt32(16).littleEndianData)  // Chunk size
        wavData.append(UInt16(1).littleEndianData)   // PCM format
        wavData.append(UInt16(channels).littleEndianData)
        wavData.append(UInt32(sampleRate).littleEndianData)
        wavData.append(UInt32(sampleRate * channels * bitsPerSample / 8).littleEndianData)  // Byte rate
        wavData.append(UInt16(channels * bitsPerSample / 8).littleEndianData)  // Block align
        wavData.append(UInt16(bitsPerSample).littleEndianData)

        // data chunk
        wavData.append("data".data(using: .ascii)!)
        wavData.append(UInt32(dataSize).littleEndianData)
        wavData.append(pcmData)

        return wavData
    }

    // MARK: - Profile Matching

    /// Match embedding against known profiles or create a new one
    private func matchOrCreateProfile(
        embedding: [Float],
        speakerId: String,
        meetingId: UUID,
        knownProfiles: [SpeakerProfile]
    ) async -> SpeakerMatch {
        // Try to find a match locally (fast)
        if let match = await VoiceEmbeddingClient.shared.findMatchingSpeakerLocally(
            embedding: embedding,
            knownProfiles: knownProfiles
        ) {
            logInfo("[SpeakerEmbeddingService] Matched \(speakerId) to profile \(match.profile.displayName) (confidence: \(String(format: "%.2f", match.similarity)))")

            // Update the profile
            Task {
                await updateProfileStats(profile: match.profile, meetingId: meetingId, speakerId: speakerId, confidence: match.similarity)
            }

            return SpeakerMatch(
                meetingSpeakerId: speakerId,
                profile: match.profile,
                isNewProfile: false,
                confidence: match.similarity,
                embedding: embedding
            )
        }

        // No match - create new profile
        logInfo("[SpeakerEmbeddingService] No match for \(speakerId), creating new profile")

        let newProfile = SpeakerProfile(
            embedding: embedding,
            lastSeenAt: Date()
        )

        // Save the profile
        Task {
            do {
                try await DatabaseManager.shared.saveSpeakerProfile(newProfile)

                // Create meeting link
                let link = MeetingSpeakerLink(
                    meetingId: meetingId,
                    speakerProfileId: newProfile.id,
                    meetingSpeakerId: speakerId,
                    confidence: 1.0
                )
                try await DatabaseManager.shared.saveMeetingSpeakerLink(link)
            } catch {
                logError("[SpeakerEmbeddingService] Failed to save new profile: \(error)")
            }
        }

        return SpeakerMatch(
            meetingSpeakerId: speakerId,
            profile: newProfile,
            isNewProfile: true,
            confidence: 1.0,
            embedding: embedding
        )
    }

    /// Update profile stats after a match
    private func updateProfileStats(
        profile: SpeakerProfile,
        meetingId: UUID,
        speakerId: String,
        confidence: Float
    ) async {
        var updatedProfile = profile
        updatedProfile.lastSeenAt = Date()
        updatedProfile.meetingCount += 1

        // Update average confidence
        let oldAvg = updatedProfile.averageConfidence ?? confidence
        let newCount = Float(updatedProfile.meetingCount)
        updatedProfile.averageConfidence = (oldAvg * (newCount - 1) + confidence) / newCount

        do {
            try await DatabaseManager.shared.saveSpeakerProfile(updatedProfile)

            // Create meeting link
            let link = MeetingSpeakerLink(
                meetingId: meetingId,
                speakerProfileId: profile.id,
                meetingSpeakerId: speakerId,
                confidence: confidence
            )
            try await DatabaseManager.shared.saveMeetingSpeakerLink(link)
        } catch {
            logError("[SpeakerEmbeddingService] Failed to update profile stats: \(error)")
        }
    }
}

// MARK: - Errors

enum SpeakerEmbeddingError: LocalizedError {
    case serviceNotConfigured
    case serviceUnavailable
    case noAudioTrack
    case extractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .serviceNotConfigured:
            return "Voice embedding service not configured"
        case .serviceUnavailable:
            return "Voice embedding service is unavailable"
        case .noAudioTrack:
            return "No audio track found in file"
        case .extractionFailed(let reason):
            return "Audio extraction failed: \(reason)"
        }
    }
}

// MARK: - Data Extensions

private extension UInt32 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: 4)
    }
}

private extension UInt16 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: 2)
    }
}
