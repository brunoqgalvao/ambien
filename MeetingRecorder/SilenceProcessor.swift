//
//  SilenceProcessor.swift
//  MeetingRecorder
//
//  Detects and crops long silences from audio files before transcription
//  to reduce file size and API costs.
//

import Foundation
import AVFoundation

/// Errors that can occur during silence processing
enum SilenceProcessorError: LocalizedError {
    case fileNotFound(String)
    case invalidAudioFormat
    case exportFailed(String)
    case readError(String)
    case noAudioTrack

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Audio file not found: \(path)"
        case .invalidAudioFormat:
            return "Invalid audio format - cannot process file"
        case .exportFailed(let reason):
            return "Failed to export audio: \(reason)"
        case .readError(let reason):
            return "Failed to read audio: \(reason)"
        case .noAudioTrack:
            return "No audio track found in file"
        }
    }
}

/// Service for detecting and cropping long silences from audio files
actor SilenceProcessor {
    static let shared = SilenceProcessor()

    /// A region of silence in the audio file
    struct SilenceRegion {
        let start: TimeInterval
        let end: TimeInterval
        var duration: TimeInterval { end - start }
    }

    /// Result of processing an audio file
    struct ProcessingResult {
        let outputPath: String
        let originalDuration: TimeInterval
        let newDuration: TimeInterval
        let silencesCropped: Int
        let timeSaved: TimeInterval
    }

    // MARK: - Public Methods

    /// Detect silence regions in an audio file
    /// - Parameters:
    ///   - audioPath: Path to the audio file
    ///   - threshold: Volume threshold in dB (default -40dB)
    ///   - minDuration: Minimum silence duration to detect (default 5 seconds)
    /// - Returns: Array of detected silence regions
    func detectSilences(
        audioPath: String,
        threshold: Float = -40,
        minDuration: TimeInterval = 5.0
    ) async throws -> [SilenceRegion] {
        let fileURL = URL(fileURLWithPath: audioPath)
        guard FileManager.default.fileExists(atPath: audioPath) else {
            throw SilenceProcessorError.fileNotFound(audioPath)
        }

        // Use AVAudioFile to read the audio
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: fileURL)
        } catch {
            throw SilenceProcessorError.readError(error.localizedDescription)
        }

        let format = audioFile.processingFormat
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(audioFile.length)

        // Analysis parameters
        let windowSize: AVAudioFrameCount = AVAudioFrameCount(0.1 * sampleRate) // 100ms windows
        let thresholdLinear = pow(10, threshold / 20) // Convert dB to linear amplitude

        var silenceRegions: [SilenceRegion] = []
        var currentSilenceStart: TimeInterval? = nil
        var framePosition: AVAudioFramePosition = 0

        // Create buffer for reading
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: windowSize) else {
            throw SilenceProcessorError.invalidAudioFormat
        }

        while framePosition < audioFile.length {
            // Calculate frames to read
            let remainingFrames = AVAudioFrameCount(audioFile.length - framePosition)
            let framesToRead = min(windowSize, remainingFrames)

            // Seek to position
            audioFile.framePosition = framePosition

            // Read audio data
            do {
                try audioFile.read(into: buffer, frameCount: framesToRead)
            } catch {
                throw SilenceProcessorError.readError(error.localizedDescription)
            }

            // Calculate RMS power
            let rms = calculateRMS(buffer: buffer, frameCount: framesToRead)
            let currentTime = Double(framePosition) / sampleRate

            if rms < thresholdLinear {
                // We're in silence
                if currentSilenceStart == nil {
                    currentSilenceStart = currentTime
                }
            } else {
                // We're in audio
                if let silenceStart = currentSilenceStart {
                    let silenceDuration = currentTime - silenceStart
                    if silenceDuration >= minDuration {
                        silenceRegions.append(SilenceRegion(start: silenceStart, end: currentTime))
                    }
                    currentSilenceStart = nil
                }
            }

            framePosition += AVAudioFramePosition(framesToRead)
        }

        // Handle silence at end of file
        let totalDuration = Double(frameCount) / sampleRate
        if let silenceStart = currentSilenceStart {
            let silenceDuration = totalDuration - silenceStart
            if silenceDuration >= minDuration {
                silenceRegions.append(SilenceRegion(start: silenceStart, end: totalDuration))
            }
        }

        print("[SilenceProcessor] Detected \(silenceRegions.count) silence regions longer than \(minDuration)s")
        return silenceRegions
    }

    /// Crop long silences from audio file
    /// - Parameters:
    ///   - audioPath: Input audio file path
    ///   - minSilenceDuration: Only crop silences longer than this (default 300 = 5 minutes)
    ///   - keepDuration: How much silence to keep at each gap (default 1 second)
    /// - Returns: ProcessingResult with output path and statistics
    func cropLongSilences(
        audioPath: String,
        minSilenceDuration: TimeInterval = 300,
        keepDuration: TimeInterval = 1.0
    ) async throws -> ProcessingResult {
        let fileURL = URL(fileURLWithPath: audioPath)
        guard FileManager.default.fileExists(atPath: audioPath) else {
            throw SilenceProcessorError.fileNotFound(audioPath)
        }

        // Detect long silences
        let silences = try await detectSilences(
            audioPath: audioPath,
            threshold: -40,
            minDuration: minSilenceDuration
        )

        // Get original duration
        let asset = AVAsset(url: fileURL)
        let originalDuration = try await asset.load(.duration).seconds

        // If no silences found, return original file
        if silences.isEmpty {
            print("[SilenceProcessor] No long silences found, using original file")
            return ProcessingResult(
                outputPath: audioPath,
                originalDuration: originalDuration,
                newDuration: originalDuration,
                silencesCropped: 0,
                timeSaved: 0
            )
        }

        // Calculate time ranges to keep (exclude silences but keep keepDuration at each gap)
        let timeRanges = calculateTimeRangesToKeep(
            totalDuration: originalDuration,
            silences: silences,
            keepDuration: keepDuration
        )

        // Create output path
        let outputURL = createOutputURL(for: fileURL)

        // Export the cropped audio
        try await exportAudio(from: asset, timeRanges: timeRanges, to: outputURL)

        // Calculate new duration
        var newDuration: TimeInterval = 0
        for range in timeRanges {
            newDuration += range.duration.seconds
        }

        let timeSaved = originalDuration - newDuration

        print("[SilenceProcessor] Cropped \(silences.count) silences, saved \(String(format: "%.1f", timeSaved / 60)) minutes")

        return ProcessingResult(
            outputPath: outputURL.path,
            originalDuration: originalDuration,
            newDuration: newDuration,
            silencesCropped: silences.count,
            timeSaved: timeSaved
        )
    }

    // MARK: - Private Helpers

    /// Calculate RMS (Root Mean Square) amplitude from audio buffer
    private func calculateRMS(buffer: AVAudioPCMBuffer, frameCount: AVAudioFrameCount) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }

        let channelCount = Int(buffer.format.channelCount)
        var sum: Float = 0

        for channel in 0..<channelCount {
            let data = channelData[channel]
            for frame in 0..<Int(frameCount) {
                let sample = data[frame]
                sum += sample * sample
            }
        }

        let meanSquare = sum / (Float(frameCount) * Float(channelCount))
        return sqrt(meanSquare)
    }

    /// Calculate time ranges to keep (non-silent portions plus small gap at silence boundaries)
    private func calculateTimeRangesToKeep(
        totalDuration: TimeInterval,
        silences: [SilenceRegion],
        keepDuration: TimeInterval
    ) -> [CMTimeRange] {
        var ranges: [CMTimeRange] = []
        var currentStart: TimeInterval = 0

        for silence in silences {
            // Keep audio up to silence start + half of keepDuration
            let endOfGood = silence.start + (keepDuration / 2)
            if endOfGood > currentStart {
                let start = CMTime(seconds: currentStart, preferredTimescale: 1000)
                let duration = CMTime(seconds: endOfGood - currentStart, preferredTimescale: 1000)
                ranges.append(CMTimeRange(start: start, duration: duration))
            }

            // Resume from end of silence - half of keepDuration
            currentStart = max(silence.end - (keepDuration / 2), 0)
        }

        // Add final segment
        if currentStart < totalDuration {
            let start = CMTime(seconds: currentStart, preferredTimescale: 1000)
            let duration = CMTime(seconds: totalDuration - currentStart, preferredTimescale: 1000)
            ranges.append(CMTimeRange(start: start, duration: duration))
        }

        return ranges
    }

    /// Create output URL with "_cropped" suffix
    private func createOutputURL(for inputURL: URL) -> URL {
        let directory = inputURL.deletingLastPathComponent()
        let filename = inputURL.deletingPathExtension().lastPathComponent
        let ext = inputURL.pathExtension
        return directory.appendingPathComponent("\(filename)_cropped.\(ext)")
    }

    /// Export audio with specified time ranges
    private func exportAudio(
        from asset: AVAsset,
        timeRanges: [CMTimeRange],
        to outputURL: URL
    ) async throws {
        // Remove existing file if it exists
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        // Create composition to hold all segments
        let composition = AVMutableComposition()

        guard let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw SilenceProcessorError.exportFailed("Failed to create composition track")
        }

        // Load audio tracks from source
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let sourceTrack = audioTracks.first else {
            throw SilenceProcessorError.noAudioTrack
        }

        // Insert each time range into the composition
        var insertTime = CMTime.zero
        for range in timeRanges {
            do {
                try compositionAudioTrack.insertTimeRange(
                    range,
                    of: sourceTrack,
                    at: insertTime
                )
                insertTime = CMTimeAdd(insertTime, range.duration)
            } catch {
                throw SilenceProcessorError.exportFailed("Failed to insert time range: \(error.localizedDescription)")
            }
        }

        // Determine output file type based on extension
        let ext = outputURL.pathExtension.lowercased()
        let outputFileType: AVFileType
        switch ext {
        case "m4a":
            outputFileType = .m4a
        case "wav":
            outputFileType = .wav
        case "mp3":
            outputFileType = .mp3
        default:
            outputFileType = .m4a
        }

        // Export the composition
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw SilenceProcessorError.exportFailed("Failed to create export session")
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = outputFileType

        await exportSession.export()

        switch exportSession.status {
        case .completed:
            print("[SilenceProcessor] Export completed: \(outputURL.lastPathComponent)")
        case .failed:
            let errorMsg = exportSession.error?.localizedDescription ?? "Unknown error"
            throw SilenceProcessorError.exportFailed(errorMsg)
        case .cancelled:
            throw SilenceProcessorError.exportFailed("Export cancelled")
        default:
            throw SilenceProcessorError.exportFailed("Export finished with status: \(exportSession.status.rawValue)")
        }
    }
}
