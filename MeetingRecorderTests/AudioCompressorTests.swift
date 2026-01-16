//
//  AudioCompressorTests.swift
//  MeetingRecorderTests
//
//  Unit tests for AudioCompressor file size management
//

import XCTest
import AVFoundation
@testable import MeetingRecorder

final class AudioCompressorTests: XCTestCase {

    var testAudioURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("AudioCompressorTests")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        testAudioURL = tempDir.appendingPathComponent("test_audio.wav")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: testAudioURL)
        try super.tearDownWithError()
    }

    // MARK: - Helper Methods

    func generateTestAudio(url: URL, duration: TimeInterval) throws {
        let sampleRate: Double = 16000
        let channels: UInt32 = 1
        let frameCount = AVAudioFrameCount(duration * sampleRate)

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "Test", code: -1)
        }

        buffer.frameLength = frameCount

        if let channelData = buffer.floatChannelData {
            for frame in 0..<Int(frameCount) {
                channelData[0][frame] = 0.3 * sin(Float(frame) * 0.05)
            }
        }

        let audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        try audioFile.write(from: buffer)
    }

    // MARK: - Compression Level Tests

    func testCompressionLevel_BitRates() {
        XCTAssertEqual(CompressionLevel.standard.bitRate, 32000)
        XCTAssertEqual(CompressionLevel.aggressive.bitRate, 16000)
        XCTAssertEqual(CompressionLevel.extreme.bitRate, 8000)
    }

    func testCompressionLevel_BytesPerSecond() {
        XCTAssertEqual(CompressionLevel.standard.bytesPerSecond, 4000.0)  // 32000 / 8
        XCTAssertEqual(CompressionLevel.aggressive.bytesPerSecond, 2000.0)  // 16000 / 8
        XCTAssertEqual(CompressionLevel.extreme.bytesPerSecond, 1000.0)  // 8000 / 8
    }

    func testCompressionLevel_Comparison() {
        XCTAssertLessThan(CompressionLevel.standard, CompressionLevel.aggressive)
        XCTAssertLessThan(CompressionLevel.aggressive, CompressionLevel.extreme)
    }

    // MARK: - File Size Tests

    func testNeedsCompression_SmallFile() async throws {
        // Generate a small audio file (5 seconds = ~160KB WAV)
        try generateTestAudio(url: testAudioURL, duration: 5.0)

        let needsCompression = await AudioCompressor.shared.needsCompression(filePath: testAudioURL.path)
        XCTAssertFalse(needsCompression, "Small file should not need compression")
    }

    func testGetFileSize_ValidFile() async throws {
        try generateTestAudio(url: testAudioURL, duration: 5.0)

        let size = await AudioCompressor.shared.getFileSize(filePath: testAudioURL.path)
        XCTAssertNotNil(size)
        XCTAssertGreaterThan(size!, 0)
    }

    func testGetFileSize_InvalidFile() async {
        let size = await AudioCompressor.shared.getFileSize(filePath: "/nonexistent/file.wav")
        XCTAssertNil(size)
    }

    func testGetAudioDuration_ValidFile() async throws {
        try generateTestAudio(url: testAudioURL, duration: 10.0)

        let duration = await AudioCompressor.shared.getAudioDuration(filePath: testAudioURL.path)
        XCTAssertNotNil(duration)
        XCTAssertEqual(duration!, 10.0, accuracy: 0.5)
    }

    // MARK: - Estimation Tests

    func testEstimateCompressedSize() async throws {
        try generateTestAudio(url: testAudioURL, duration: 60.0)  // 1 minute

        let estimatedStandard = await AudioCompressor.shared.estimateCompressedSize(
            inputPath: testAudioURL.path,
            level: .standard
        )
        let estimatedAggressive = await AudioCompressor.shared.estimateCompressedSize(
            inputPath: testAudioURL.path,
            level: .aggressive
        )

        // 60 seconds at 4000 bytes/sec = 240,000 bytes
        XCTAssertEqual(estimatedStandard, 240_000, accuracy: 10_000)

        // 60 seconds at 2000 bytes/sec = 120,000 bytes
        XCTAssertEqual(estimatedAggressive, 120_000, accuracy: 10_000)

        // Aggressive should be smaller
        XCTAssertLessThan(estimatedAggressive, estimatedStandard)
    }

    // MARK: - Compression Tests

    func testCompress_AlreadyUnderTarget() async throws {
        // Generate small file that's already under target
        try generateTestAudio(url: testAudioURL, duration: 5.0)

        let outputPath = try await AudioCompressor.shared.compress(
            inputPath: testAudioURL.path,
            targetSizeBytes: 1_000_000_000  // 1GB target
        )

        // Should return original file
        XCTAssertEqual(outputPath, testAudioURL.path)
    }

    func testCompress_FileNotFound() async {
        do {
            _ = try await AudioCompressor.shared.compress(
                inputPath: "/nonexistent/audio.wav"
            )
            XCTFail("Should throw error for non-existent file")
        } catch {
            XCTAssertTrue(error is AudioCompressionError)
        }
    }

    // MARK: - AudioRecordingSettings Tests

    func testAudioRecordingSettings_EstimateFileSize_AAC() {
        // 1 hour at 32kbps = 32000 / 8 * 3600 = 14,400,000 bytes (~14MB)
        let size = AudioRecordingSettings.estimateFileSize(
            duration: 3600,
            settings: AudioRecordingSettings.openAIOptimized
        )

        XCTAssertEqual(size, 14_400_000, accuracy: 100_000)
    }

    func testAudioRecordingSettings_EstimateFileSize_WAV() {
        // 1 minute at 16kHz mono 16-bit = 16000 * 1 * 2 * 60 = 1,920,000 bytes
        let size = AudioRecordingSettings.estimateFileSize(
            duration: 60,
            settings: AudioRecordingSettings.wavUncompressed
        )

        XCTAssertEqual(size, 1_920_000)
    }

    func testAudioRecordingSettings_MaxDuration_AAC() {
        // 25MB at 32kbps = 25,000,000 / (32000/8) = 6250 seconds (~104 min)
        let maxDuration = AudioRecordingSettings.maxDuration(
            forBytes: 25_000_000,
            settings: AudioRecordingSettings.openAIOptimized
        )

        XCTAssertEqual(maxDuration, 6250, accuracy: 100)
    }

    func testAudioRecordingSettings_MaxDuration_WAV() {
        // 25MB at 16kHz mono 16-bit = 25,000,000 / (16000 * 1 * 2) = 781 seconds (~13 min)
        let maxDuration = AudioRecordingSettings.maxDuration(
            forBytes: 25_000_000,
            settings: AudioRecordingSettings.wavUncompressed
        )

        XCTAssertEqual(maxDuration, 781.25, accuracy: 10)
    }

    // MARK: - Constants Tests

    func testOpenAILimits() {
        XCTAssertEqual(AudioCompressor.openAILimit, 25_000_000)
        XCTAssertEqual(AudioCompressor.targetSizeBytes, 24_000_000)  // With safety margin
    }
}
