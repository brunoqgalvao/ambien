//
//  SilenceProcessorTests.swift
//  MeetingRecorderTests
//
//  Unit tests for SilenceProcessor audio silence detection and cropping
//

import XCTest
import AVFoundation
@testable import MeetingRecorder

final class SilenceProcessorTests: XCTestCase {

    // MARK: - Test Fixtures

    var testAudioURL: URL!
    var silentAudioURL: URL!
    var mixedAudioURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()

        // Create temp directory for test files
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("SilenceProcessorTests")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        testAudioURL = tempDir.appendingPathComponent("test_audio.wav")
        silentAudioURL = tempDir.appendingPathComponent("silent_audio.wav")
        mixedAudioURL = tempDir.appendingPathComponent("mixed_audio.wav")
    }

    override func tearDownWithError() throws {
        // Clean up test files
        try? FileManager.default.removeItem(at: testAudioURL)
        try? FileManager.default.removeItem(at: silentAudioURL)
        try? FileManager.default.removeItem(at: mixedAudioURL)
        try super.tearDownWithError()
    }

    // MARK: - Helper Methods

    /// Generate a test audio file with specified duration and amplitude
    func generateTestAudio(url: URL, duration: TimeInterval, amplitude: Float) throws {
        let sampleRate: Double = 16000
        let channels: UInt32 = 1
        let frameCount = AVAudioFrameCount(duration * sampleRate)

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(domain: "Test", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer"])
        }

        buffer.frameLength = frameCount

        // Fill with audio data
        if let channelData = buffer.floatChannelData {
            for frame in 0..<Int(frameCount) {
                // Generate sine wave or silence based on amplitude
                let sample = amplitude * sin(Float(frame) * 0.1)
                channelData[0][frame] = sample
            }
        }

        // Write to file
        let audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        try audioFile.write(from: buffer)
    }

    /// Generate audio with alternating silence and sound
    func generateMixedAudio(url: URL, segments: [(duration: TimeInterval, isSilent: Bool)]) throws {
        let sampleRate: Double = 16000
        let channels: UInt32 = 1

        let totalDuration = segments.reduce(0.0) { $0 + $1.duration }
        let totalFrames = AVAudioFrameCount(totalDuration * sampleRate)

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
            throw NSError(domain: "Test", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer"])
        }

        buffer.frameLength = totalFrames

        if let channelData = buffer.floatChannelData {
            var frameOffset = 0
            for segment in segments {
                let segmentFrames = Int(segment.duration * sampleRate)
                let amplitude: Float = segment.isSilent ? 0.0001 : 0.5

                for frame in 0..<segmentFrames {
                    let sample = amplitude * sin(Float(frame) * 0.1)
                    channelData[0][frameOffset + frame] = sample
                }
                frameOffset += segmentFrames
            }
        }

        let audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        try audioFile.write(from: buffer)
    }

    // MARK: - Detection Tests

    func testDetectSilences_NoSilence() async throws {
        // Generate audio with constant amplitude (no silence)
        try generateTestAudio(url: testAudioURL, duration: 10.0, amplitude: 0.5)

        let silences = try await SilenceProcessor.shared.detectSilences(
            audioPath: testAudioURL.path,
            threshold: -40,
            minDuration: 1.0
        )

        XCTAssertTrue(silences.isEmpty, "Should detect no silences in audio with constant amplitude")
    }

    func testDetectSilences_AllSilence() async throws {
        // Generate completely silent audio
        try generateTestAudio(url: silentAudioURL, duration: 10.0, amplitude: 0.00001)

        let silences = try await SilenceProcessor.shared.detectSilences(
            audioPath: silentAudioURL.path,
            threshold: -40,
            minDuration: 1.0
        )

        XCTAssertEqual(silences.count, 1, "Should detect one silence region for all-silent audio")
        if let silence = silences.first {
            XCTAssertEqual(silence.start, 0.0, accuracy: 0.5, "Silence should start at beginning")
            XCTAssertEqual(silence.duration, 10.0, accuracy: 1.0, "Silence should be ~10 seconds")
        }
    }

    func testDetectSilences_MixedAudio() async throws {
        // Generate audio: 5s sound, 10s silence, 5s sound
        try generateMixedAudio(url: mixedAudioURL, segments: [
            (duration: 5.0, isSilent: false),
            (duration: 10.0, isSilent: true),
            (duration: 5.0, isSilent: false)
        ])

        let silences = try await SilenceProcessor.shared.detectSilences(
            audioPath: mixedAudioURL.path,
            threshold: -40,
            minDuration: 5.0
        )

        XCTAssertEqual(silences.count, 1, "Should detect one silence region")
        if let silence = silences.first {
            XCTAssertEqual(silence.start, 5.0, accuracy: 1.0, "Silence should start around 5s")
            XCTAssertEqual(silence.duration, 10.0, accuracy: 2.0, "Silence should be ~10 seconds")
        }
    }

    func testDetectSilences_FileNotFound() async {
        do {
            _ = try await SilenceProcessor.shared.detectSilences(
                audioPath: "/nonexistent/path/audio.wav",
                threshold: -40,
                minDuration: 1.0
            )
            XCTFail("Should throw error for non-existent file")
        } catch {
            XCTAssertTrue(error is SilenceProcessorError)
        }
    }

    // MARK: - Cropping Tests

    func testCropLongSilences_NoLongSilences() async throws {
        // Generate audio with short silences only
        try generateMixedAudio(url: mixedAudioURL, segments: [
            (duration: 10.0, isSilent: false),
            (duration: 2.0, isSilent: true),  // Too short to crop
            (duration: 10.0, isSilent: false)
        ])

        let result = try await SilenceProcessor.shared.cropLongSilences(
            audioPath: mixedAudioURL.path,
            minSilenceDuration: 300,  // 5 minutes
            keepDuration: 1.0
        )

        XCTAssertEqual(result.silencesCropped, 0, "Should not crop any silences")
        XCTAssertEqual(result.outputPath, mixedAudioURL.path, "Should return original path when no cropping")
        XCTAssertEqual(result.timeSaved, 0, "Should save no time")
    }

    func testCropLongSilences_WithLongSilence() async throws {
        // Generate audio with a long silence (using shorter threshold for testing)
        try generateMixedAudio(url: mixedAudioURL, segments: [
            (duration: 5.0, isSilent: false),
            (duration: 15.0, isSilent: true),  // Long silence
            (duration: 5.0, isSilent: false)
        ])

        let result = try await SilenceProcessor.shared.cropLongSilences(
            audioPath: mixedAudioURL.path,
            minSilenceDuration: 10.0,  // 10 seconds for testing
            keepDuration: 1.0
        )

        XCTAssertEqual(result.silencesCropped, 1, "Should crop one silence")
        XCTAssertNotEqual(result.outputPath, mixedAudioURL.path, "Should return new file path")
        XCTAssertGreaterThan(result.timeSaved, 10.0, "Should save significant time")
        XCTAssertLessThan(result.newDuration, result.originalDuration, "New duration should be shorter")

        // Verify output file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.outputPath))

        // Clean up cropped file
        try? FileManager.default.removeItem(atPath: result.outputPath)
    }

    // MARK: - SilenceRegion Tests

    func testSilenceRegion_Duration() {
        let region = SilenceProcessor.SilenceRegion(start: 10.0, end: 25.0)
        XCTAssertEqual(region.duration, 15.0, "Duration should be end - start")
    }
}
