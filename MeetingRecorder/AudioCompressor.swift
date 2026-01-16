//
//  AudioCompressor.swift
//  MeetingRecorder
//
//  Utility for compressing audio files to fit OpenAI's 25MB limit
//  Uses AVAssetExportSession with progressive compression levels
//

import Foundation
import AVFoundation

/// Compression levels for audio files
enum CompressionLevel: Int, CaseIterable, Comparable {
    case standard = 0   // 32kbps - good quality for speech
    case aggressive = 1 // 16kbps - acceptable quality
    case extreme = 2    // 8kbps - last resort, may affect quality

    var bitRate: Int {
        switch self {
        case .standard: return 32000   // 32kbps
        case .aggressive: return 16000 // 16kbps
        case .extreme: return 8000     // 8kbps
        }
    }

    var displayName: String {
        switch self {
        case .standard: return "Standard (32kbps)"
        case .aggressive: return "Aggressive (16kbps)"
        case .extreme: return "Extreme (8kbps)"
        }
    }

    /// Bytes per second at this compression level (approximate)
    var bytesPerSecond: Double {
        Double(bitRate) / 8.0
    }

    static func < (lhs: CompressionLevel, rhs: CompressionLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Errors that can occur during audio compression
enum AudioCompressionError: LocalizedError {
    case fileNotFound(String)
    case compressionFailed(String)
    case cannotCreateExportSession
    case exportCancelled
    case fileTooLargeAfterCompression(originalMB: Int, estimatedMinutes: Int, provider: String)
    case invalidAudioFile

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Audio file not found: \(path)"
        case .compressionFailed(let reason):
            return "Compression failed: \(reason)"
        case .cannotCreateExportSession:
            return "Cannot create audio export session"
        case .exportCancelled:
            return "Audio export was cancelled"
        case .fileTooLargeAfterCompression(let originalMB, let estimatedMinutes, let provider):
            return "Recording is too long for \(provider) (~\(estimatedMinutes) minutes, \(originalMB)MB). Try using AssemblyAI or Gemini for longer recordings, or enable 'Crop silences' in settings."
        case .invalidAudioFile:
            return "Invalid audio file format"
        }
    }
}

/// Audio compressor utility for fitting files within API limits
actor AudioCompressor {
    static let shared = AudioCompressor()

    /// OpenAI's file size limit with safety margin
    static let openAILimit: Int64 = 25_000_000     // 25MB hard limit
    static let targetSizeBytes: Int64 = 24_000_000 // 24MB with safety margin

    // MARK: - Public Methods

    /// Check if a file needs compression for OpenAI
    /// - Parameter filePath: Path to the audio file
    /// - Returns: true if the file exceeds the OpenAI limit
    func needsCompression(filePath: String) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: filePath),
              let fileSize = attributes[.size] as? Int64 else {
            return false
        }
        return fileSize > Self.openAILimit
    }

    /// Get the file size in bytes
    /// - Parameter filePath: Path to the file
    /// - Returns: File size in bytes, or nil if file doesn't exist
    func getFileSize(filePath: String) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: filePath),
              let fileSize = attributes[.size] as? Int64 else {
            return nil
        }
        return fileSize
    }

    /// Estimate the compressed size for a given compression level
    /// - Parameters:
    ///   - inputPath: Path to the input audio file
    ///   - level: Compression level to estimate
    /// - Returns: Estimated size in bytes
    func estimateCompressedSize(inputPath: String, level: CompressionLevel) async -> Int64 {
        guard let duration = await getAudioDuration(filePath: inputPath) else {
            return 0
        }
        return Int64(duration * level.bytesPerSecond)
    }

    /// Get the audio duration in seconds
    /// - Parameter filePath: Path to the audio file
    /// - Returns: Duration in seconds, or nil if cannot be determined
    func getAudioDuration(filePath: String) async -> TimeInterval? {
        let url = URL(fileURLWithPath: filePath)
        let asset = AVAsset(url: url)

        do {
            let duration = try await asset.load(.duration)
            return CMTimeGetSeconds(duration)
        } catch {
            print("[AudioCompressor] Failed to get duration: \(error)")
            return nil
        }
    }

    /// Compress audio file to target size
    /// - Parameters:
    ///   - inputPath: Path to the input audio file
    ///   - targetSizeBytes: Target size in bytes (default: 24MB)
    ///   - maxLevel: Maximum compression level to try (default: .aggressive)
    /// - Returns: Path to the compressed file
    func compress(
        inputPath: String,
        targetSizeBytes: Int64 = AudioCompressor.targetSizeBytes,
        maxLevel: CompressionLevel = .aggressive
    ) async throws -> String {
        // Verify input file exists
        guard FileManager.default.fileExists(atPath: inputPath) else {
            throw AudioCompressionError.fileNotFound(inputPath)
        }

        // Check current file size
        guard let currentSize = getFileSize(filePath: inputPath) else {
            throw AudioCompressionError.fileNotFound(inputPath)
        }

        // If already under target, return original
        if currentSize <= targetSizeBytes {
            print("[AudioCompressor] File already under target size (\(currentSize / 1_000_000)MB)")
            return inputPath
        }

        print("[AudioCompressor] File size: \(currentSize / 1_000_000)MB, target: \(targetSizeBytes / 1_000_000)MB")

        // Get audio duration for estimation
        guard let duration = await getAudioDuration(filePath: inputPath) else {
            throw AudioCompressionError.invalidAudioFile
        }

        // Try compression levels from standard to max allowed
        for level in CompressionLevel.allCases where level <= maxLevel {
            let estimatedSize = Int64(duration * level.bytesPerSecond)

            print("[AudioCompressor] Trying \(level.displayName), estimated: \(estimatedSize / 1_000_000)MB")

            if estimatedSize > targetSizeBytes {
                print("[AudioCompressor] Estimated size too large, skipping level")
                continue
            }

            // Try compression at this level
            do {
                let outputPath = try await compressWithLevel(inputPath: inputPath, level: level)

                // Verify output size
                if let outputSize = getFileSize(filePath: outputPath), outputSize <= targetSizeBytes {
                    print("[AudioCompressor] Successfully compressed to \(outputSize / 1_000_000)MB")
                    return outputPath
                } else {
                    // Clean up failed attempt
                    try? FileManager.default.removeItem(atPath: outputPath)
                }
            } catch {
                print("[AudioCompressor] Compression at \(level.displayName) failed: \(error)")
            }
        }

        // If we get here, even max compression wasn't enough
        let estimatedMinutes = Int(duration / 60)
        throw AudioCompressionError.fileTooLargeAfterCompression(
            originalMB: Int(currentSize / 1_000_000),
            estimatedMinutes: estimatedMinutes,
            provider: "OpenAI"
        )
    }

    /// Compress with a specific level
    /// - Parameters:
    ///   - inputPath: Path to input file
    ///   - level: Compression level
    /// - Returns: Path to compressed file
    private func compressWithLevel(inputPath: String, level: CompressionLevel) async throws -> String {
        let inputURL = URL(fileURLWithPath: inputPath)

        // Create output path
        let fileName = inputURL.deletingPathExtension().lastPathComponent
        let outputFileName = "\(fileName)_compressed_\(level.rawValue).m4a"
        let outputURL = inputURL.deletingLastPathComponent().appendingPathComponent(outputFileName)

        // Remove existing output file
        try? FileManager.default.removeItem(at: outputURL)

        // Create asset and export session
        let asset = AVAsset(url: inputURL)

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioCompressionError.cannotCreateExportSession
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        // Note: AVAssetExportSession doesn't directly support custom audio settings
        // We'll use the preset which provides good compression
        // For more control, we'd need to use AVAssetWriter directly (see compressWithWriter)

        print("[AudioCompressor] Exporting with preset: \(AVAssetExportPresetAppleM4A)")

        // Export
        await exportSession.export()

        switch exportSession.status {
        case .completed:
            return outputURL.path
        case .cancelled:
            throw AudioCompressionError.exportCancelled
        case .failed:
            let errorMessage = exportSession.error?.localizedDescription ?? "Unknown error"
            throw AudioCompressionError.compressionFailed(errorMessage)
        default:
            throw AudioCompressionError.compressionFailed("Export ended with status: \(exportSession.status.rawValue)")
        }
    }

    /// Compress using AVAssetWriter for finer control over bitrate
    /// - Parameters:
    ///   - inputPath: Path to input file
    ///   - level: Compression level
    /// - Returns: Path to compressed file
    func compressWithWriter(inputPath: String, level: CompressionLevel) async throws -> String {
        let inputURL = URL(fileURLWithPath: inputPath)

        // Create output path
        let fileName = inputURL.deletingPathExtension().lastPathComponent
        let outputFileName = "\(fileName)_compressed_\(level.rawValue).m4a"
        let outputURL = inputURL.deletingLastPathComponent().appendingPathComponent(outputFileName)

        // Remove existing output file
        try? FileManager.default.removeItem(at: outputURL)

        // Create asset
        let asset = AVAsset(url: inputURL)

        // Load tracks
        guard let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first else {
            throw AudioCompressionError.invalidAudioFile
        }

        // Create reader
        let reader = try AVAssetReader(asset: asset)

        // Configure reader output - request PCM for re-encoding
        let readerOutputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: readerOutputSettings)
        reader.add(readerOutput)

        // Create writer
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)

        // Configure writer input with target bitrate
        let writerInputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: level.bitRate,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: writerInputSettings)
        writerInput.expectsMediaDataInRealTime = false
        writer.add(writerInput)

        // Start reading and writing
        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // Process samples
        let processingQueue = DispatchQueue(label: "com.meetingrecorder.audiocompression")

        return try await withCheckedThrowingContinuation { continuation in
            writerInput.requestMediaDataWhenReady(on: processingQueue) {
                while writerInput.isReadyForMoreMediaData {
                    if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                        writerInput.append(sampleBuffer)
                    } else {
                        writerInput.markAsFinished()

                        if reader.status == .failed {
                            continuation.resume(throwing: AudioCompressionError.compressionFailed(
                                reader.error?.localizedDescription ?? "Reader failed"
                            ))
                            return
                        }

                        writer.finishWriting {
                            if writer.status == .completed {
                                continuation.resume(returning: outputURL.path)
                            } else {
                                continuation.resume(throwing: AudioCompressionError.compressionFailed(
                                    writer.error?.localizedDescription ?? "Writer failed"
                                ))
                            }
                        }
                        return
                    }
                }
            }
        }
    }
}

// MARK: - Audio Recording Settings Constants

/// Standard audio recording settings optimized for different use cases
struct AudioRecordingSettings {
    /// Settings optimized for OpenAI's 25MB limit
    /// 16kHz mono AAC at 32kbps = ~4KB/sec = ~104 min max
    static let openAIOptimized: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 16000.0,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 32000,
        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
    ]

    /// Settings for higher quality when file size isn't a concern
    static let highQuality: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 44100.0,
        AVNumberOfChannelsKey: 2,
        AVEncoderBitRateKey: 128000,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ]

    /// WAV format for maximum compatibility (larger files)
    static let wavUncompressed: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16000.0,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false
    ]

    /// Calculate estimated file size for given duration
    /// - Parameters:
    ///   - duration: Duration in seconds
    ///   - settings: Audio settings dictionary
    /// - Returns: Estimated file size in bytes
    static func estimateFileSize(duration: TimeInterval, settings: [String: Any]) -> Int64 {
        let formatID = settings[AVFormatIDKey] as? AudioFormatID ?? kAudioFormatMPEG4AAC

        if formatID == kAudioFormatLinearPCM {
            // PCM: sampleRate * channels * bytesPerSample * duration
            let sampleRate = settings[AVSampleRateKey] as? Double ?? 16000
            let channels = settings[AVNumberOfChannelsKey] as? Int ?? 1
            let bitDepth = settings[AVLinearPCMBitDepthKey] as? Int ?? 16
            let bytesPerSample = bitDepth / 8
            return Int64(sampleRate * Double(channels) * Double(bytesPerSample) * duration)
        } else {
            // AAC: bitRate / 8 * duration
            let bitRate = settings[AVEncoderBitRateKey] as? Int ?? 32000
            return Int64(Double(bitRate) / 8.0 * duration)
        }
    }

    /// Calculate maximum recording duration for a given file size limit
    /// - Parameters:
    ///   - maxBytes: Maximum file size in bytes
    ///   - settings: Audio settings dictionary
    /// - Returns: Maximum duration in seconds
    static func maxDuration(forBytes maxBytes: Int64, settings: [String: Any]) -> TimeInterval {
        let formatID = settings[AVFormatIDKey] as? AudioFormatID ?? kAudioFormatMPEG4AAC

        if formatID == kAudioFormatLinearPCM {
            let sampleRate = settings[AVSampleRateKey] as? Double ?? 16000
            let channels = settings[AVNumberOfChannelsKey] as? Int ?? 1
            let bitDepth = settings[AVLinearPCMBitDepthKey] as? Int ?? 16
            let bytesPerSample = bitDepth / 8
            let bytesPerSecond = sampleRate * Double(channels) * Double(bytesPerSample)
            return Double(maxBytes) / bytesPerSecond
        } else {
            let bitRate = settings[AVEncoderBitRateKey] as? Int ?? 32000
            let bytesPerSecond = Double(bitRate) / 8.0
            return Double(maxBytes) / bytesPerSecond
        }
    }
}
