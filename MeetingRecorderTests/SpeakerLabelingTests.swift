//
//  SpeakerLabelingTests.swift
//  MeetingRecorderTests
//
//  Unit tests for speaker labeling functionality
//

import XCTest
@testable import MeetingRecorder

final class SpeakerLabelingTests: XCTestCase {

    // MARK: - SpeakerLabel Tests

    func testSpeakerLabelInit() {
        let label = SpeakerLabel(
            speakerId: "speaker_0",
            name: "Alice",
            isUserAssigned: true
        )

        XCTAssertEqual(label.speakerId, "speaker_0")
        XCTAssertEqual(label.name, "Alice")
        XCTAssertTrue(label.isUserAssigned)
        XCTAssertNil(label.confidence)
        XCTAssertNil(label.evidence)
        XCTAssertNil(label.role)
    }

    func testSpeakerLabelWithAIInference() {
        let label = SpeakerLabel(
            speakerId: "speaker_1",
            name: "Bob",
            confidence: 0.85,
            evidence: "Mentioned 'my team' and 'I manage'",
            role: "Manager",
            isUserAssigned: false
        )

        XCTAssertEqual(label.speakerId, "speaker_1")
        XCTAssertEqual(label.name, "Bob")
        XCTAssertFalse(label.isUserAssigned)
        XCTAssertEqual(label.confidence, 0.85)
        XCTAssertEqual(label.evidence, "Mentioned 'my team' and 'I manage'")
        XCTAssertEqual(label.role, "Manager")
    }

    func testSpeakerLabelCodable() throws {
        let original = SpeakerLabel(
            speakerId: "speaker_0",
            name: "Alice",
            confidence: 0.9,
            evidence: "Test evidence",
            role: "Host",
            isUserAssigned: true
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SpeakerLabel.self, from: encoded)

        XCTAssertEqual(decoded.speakerId, original.speakerId)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.confidence, original.confidence)
        XCTAssertEqual(decoded.evidence, original.evidence)
        XCTAssertEqual(decoded.role, original.role)
        XCTAssertEqual(decoded.isUserAssigned, original.isUserAssigned)
    }

    func testSpeakerLabelArrayCodable() throws {
        let labels = [
            SpeakerLabel(speakerId: "speaker_0", name: "Alice", isUserAssigned: true),
            SpeakerLabel(speakerId: "speaker_1", name: "Bob", isUserAssigned: false)
        ]

        let encoded = try JSONEncoder().encode(labels)
        let decoded = try JSONDecoder().decode([SpeakerLabel].self, from: encoded)

        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].name, "Alice")
        XCTAssertEqual(decoded[1].name, "Bob")
    }

    // MARK: - Meeting Speaker Name Resolution Tests

    func testSpeakerNameWithUserLabel() {
        var meeting = createTestMeeting()
        meeting.speakerLabels = [
            SpeakerLabel(speakerId: "speaker_0", name: "Alice", isUserAssigned: true)
        ]

        XCTAssertEqual(meeting.speakerName(for: "speaker_0"), "Alice")
    }

    func testSpeakerNameWithAILabel() {
        var meeting = createTestMeeting()
        meeting.speakerLabels = [
            SpeakerLabel(speakerId: "speaker_0", name: "Bob", confidence: 0.8, isUserAssigned: false)
        ]

        XCTAssertEqual(meeting.speakerName(for: "speaker_0"), "Bob")
    }

    func testSpeakerNameFallbackToDefault() {
        let meeting = createTestMeeting()

        // No labels assigned - should fall back to "Speaker 1", "Speaker 2", etc.
        XCTAssertEqual(meeting.speakerName(for: "speaker_0"), "Speaker 1")
        XCTAssertEqual(meeting.speakerName(for: "speaker_1"), "Speaker 2")
        XCTAssertEqual(meeting.speakerName(for: "speaker_9"), "Speaker 10")
    }

    func testSpeakerNameWithGeminiFormat() {
        let meeting = createTestMeeting()

        // Gemini uses "Speaker A", "Speaker B" format
        XCTAssertEqual(meeting.speakerName(for: "Speaker A"), "Speaker A")
        XCTAssertEqual(meeting.speakerName(for: "Speaker B"), "Speaker B")
    }

    func testSpeakerNameWithUnknownFormat() {
        let meeting = createTestMeeting()

        // Unknown format should return as-is
        XCTAssertEqual(meeting.speakerName(for: "unknown_speaker"), "unknown_speaker")
    }

    // MARK: - Meeting Unique Speakers Tests

    func testUniqueSpeakers() {
        var meeting = createTestMeeting()
        meeting.diarizationSegments = [
            DiarizationSegment(speakerId: "speaker_0", start: 0, end: 10, text: "Hello"),
            DiarizationSegment(speakerId: "speaker_1", start: 10, end: 20, text: "Hi"),
            DiarizationSegment(speakerId: "speaker_0", start: 20, end: 30, text: "Good morning"),
            DiarizationSegment(speakerId: "speaker_2", start: 30, end: 40, text: "Hey"),
            DiarizationSegment(speakerId: "speaker_1", start: 40, end: 50, text: "Welcome"),
        ]

        let speakers = meeting.uniqueSpeakers

        XCTAssertEqual(speakers.count, 3)
        XCTAssertEqual(speakers, ["speaker_0", "speaker_1", "speaker_2"])
    }

    func testUniqueSpeakersPreservesOrder() {
        var meeting = createTestMeeting()
        meeting.diarizationSegments = [
            DiarizationSegment(speakerId: "speaker_2", start: 0, end: 10, text: "First"),
            DiarizationSegment(speakerId: "speaker_0", start: 10, end: 20, text: "Second"),
            DiarizationSegment(speakerId: "speaker_1", start: 20, end: 30, text: "Third"),
        ]

        let speakers = meeting.uniqueSpeakers

        // Should preserve order of first appearance
        XCTAssertEqual(speakers[0], "speaker_2")
        XCTAssertEqual(speakers[1], "speaker_0")
        XCTAssertEqual(speakers[2], "speaker_1")
    }

    func testUniqueSpeakersEmpty() {
        let meeting = createTestMeeting()

        XCTAssertTrue(meeting.uniqueSpeakers.isEmpty)
    }

    // MARK: - Has Speaker Data Tests

    func testHasSpeakerDataWithCount() {
        var meeting = createTestMeeting()
        meeting.speakerCount = 3

        XCTAssertTrue(meeting.hasSpeakerData)
    }

    func testHasSpeakerDataWithSegments() {
        var meeting = createTestMeeting()
        meeting.diarizationSegments = [
            DiarizationSegment(speakerId: "speaker_0", start: 0, end: 10, text: "Hello")
        ]

        XCTAssertTrue(meeting.hasSpeakerData)
    }

    func testHasSpeakerDataFalse() {
        let meeting = createTestMeeting()

        XCTAssertFalse(meeting.hasSpeakerData)
    }

    // MARK: - AI Inferred Check Tests

    func testIsSpeakerAIInferred() {
        var meeting = createTestMeeting()
        meeting.speakerLabels = [
            SpeakerLabel(speakerId: "speaker_0", name: "Alice", confidence: 0.9, isUserAssigned: false),
            SpeakerLabel(speakerId: "speaker_1", name: "Bob", isUserAssigned: true)
        ]

        XCTAssertTrue(meeting.isSpeakerAIInferred("speaker_0"))
        XCTAssertFalse(meeting.isSpeakerAIInferred("speaker_1"))
        XCTAssertFalse(meeting.isSpeakerAIInferred("speaker_2")) // Not labeled at all
    }

    // MARK: - Speaker Naming Prompt Tests

    func testShouldShowSpeakerNamingPrompt_NoSpeakers() {
        let meeting = createTestMeeting()

        XCTAssertFalse(meeting.shouldShowSpeakerNamingPrompt)
    }

    func testShouldShowSpeakerNamingPrompt_WithUnnamedSpeakers() {
        var meeting = createTestMeeting()
        meeting.speakerCount = 2
        meeting.diarizationSegments = [
            DiarizationSegment(speakerId: "speaker_0", start: 0, end: 10, text: "Hello"),
            DiarizationSegment(speakerId: "speaker_1", start: 10, end: 20, text: "Hi")
        ]

        XCTAssertTrue(meeting.shouldShowSpeakerNamingPrompt)
    }

    func testShouldShowSpeakerNamingPrompt_AllNamed() {
        var meeting = createTestMeeting()
        meeting.speakerCount = 2
        meeting.diarizationSegments = [
            DiarizationSegment(speakerId: "speaker_0", start: 0, end: 10, text: "Hello"),
            DiarizationSegment(speakerId: "speaker_1", start: 10, end: 20, text: "Hi")
        ]
        meeting.speakerLabels = [
            SpeakerLabel(speakerId: "speaker_0", name: "Alice", isUserAssigned: true),
            SpeakerLabel(speakerId: "speaker_1", name: "Bob", isUserAssigned: true)
        ]

        XCTAssertFalse(meeting.shouldShowSpeakerNamingPrompt)
    }

    func testShouldShowSpeakerNamingPrompt_PartiallyNamed() {
        var meeting = createTestMeeting()
        meeting.speakerCount = 2
        meeting.diarizationSegments = [
            DiarizationSegment(speakerId: "speaker_0", start: 0, end: 10, text: "Hello"),
            DiarizationSegment(speakerId: "speaker_1", start: 10, end: 20, text: "Hi")
        ]
        meeting.speakerLabels = [
            SpeakerLabel(speakerId: "speaker_0", name: "Alice", isUserAssigned: true)
            // speaker_1 not named
        ]

        XCTAssertTrue(meeting.shouldShowSpeakerNamingPrompt)
    }

    func testShouldShowSpeakerNamingPrompt_Dismissed() {
        var meeting = createTestMeeting()
        meeting.speakerCount = 2
        meeting.diarizationSegments = [
            DiarizationSegment(speakerId: "speaker_0", start: 0, end: 10, text: "Hello"),
            DiarizationSegment(speakerId: "speaker_1", start: 10, end: 20, text: "Hi")
        ]
        meeting.speakerNamingDismissed = true

        XCTAssertFalse(meeting.shouldShowSpeakerNamingPrompt)
    }

    func testShouldShowSpeakerNamingPrompt_AIInferredNotCounted() {
        var meeting = createTestMeeting()
        meeting.speakerCount = 2
        meeting.diarizationSegments = [
            DiarizationSegment(speakerId: "speaker_0", start: 0, end: 10, text: "Hello"),
            DiarizationSegment(speakerId: "speaker_1", start: 10, end: 20, text: "Hi")
        ]
        meeting.speakerLabels = [
            // AI-inferred labels don't count as "user assigned"
            SpeakerLabel(speakerId: "speaker_0", name: "Alice", confidence: 0.9, isUserAssigned: false),
            SpeakerLabel(speakerId: "speaker_1", name: "Bob", confidence: 0.8, isUserAssigned: false)
        ]

        // Should still show prompt because AI labels aren't user-assigned
        XCTAssertTrue(meeting.shouldShowSpeakerNamingPrompt)
    }

    // MARK: - Speaker Label Get/Set Tests

    func testSpeakerLabelRetrieval() {
        var meeting = createTestMeeting()
        meeting.speakerLabels = [
            SpeakerLabel(speakerId: "speaker_0", name: "Alice", role: "Host", isUserAssigned: true)
        ]

        let label = meeting.speakerLabel(for: "speaker_0")

        XCTAssertNotNil(label)
        XCTAssertEqual(label?.name, "Alice")
        XCTAssertEqual(label?.role, "Host")
    }

    func testSpeakerLabelRetrievalNotFound() {
        let meeting = createTestMeeting()

        let label = meeting.speakerLabel(for: "speaker_0")

        XCTAssertNil(label)
    }

    // MARK: - Speaker Label Update Logic Tests

    func testUpdateSpeakerLabel_AddNew() {
        var labels: [SpeakerLabel] = []

        // Simulate adding a new label
        labels.append(SpeakerLabel(speakerId: "speaker_0", name: "Alice", isUserAssigned: true))

        XCTAssertEqual(labels.count, 1)
        XCTAssertEqual(labels[0].name, "Alice")
    }

    func testUpdateSpeakerLabel_ReplaceExisting() {
        var labels: [SpeakerLabel] = [
            SpeakerLabel(speakerId: "speaker_0", name: "Alice", isUserAssigned: false)
        ]

        // Simulate updating - remove existing, add new
        labels.removeAll { $0.speakerId == "speaker_0" }
        labels.append(SpeakerLabel(speakerId: "speaker_0", name: "Bob", isUserAssigned: true))

        XCTAssertEqual(labels.count, 1)
        XCTAssertEqual(labels[0].name, "Bob")
        XCTAssertTrue(labels[0].isUserAssigned)
    }

    func testUpdateSpeakerLabel_RemoveWithEmptyName() {
        var labels: [SpeakerLabel] = [
            SpeakerLabel(speakerId: "speaker_0", name: "Alice", isUserAssigned: true)
        ]

        // Simulate clearing - remove existing, don't add if name is empty
        labels.removeAll { $0.speakerId == "speaker_0" }
        let newName = ""
        if !newName.isEmpty {
            labels.append(SpeakerLabel(speakerId: "speaker_0", name: newName, isUserAssigned: true))
        }

        XCTAssertEqual(labels.count, 0)
    }

    // MARK: - DiarizationSegment Tests

    func testDiarizationSegmentInit() {
        let segment = DiarizationSegment(
            speakerId: "speaker_0",
            start: 10.5,
            end: 25.3,
            text: "Hello everyone, welcome to the meeting."
        )

        XCTAssertEqual(segment.speakerId, "speaker_0")
        XCTAssertEqual(segment.start, 10.5)
        XCTAssertEqual(segment.end, 25.3)
        XCTAssertEqual(segment.text, "Hello everyone, welcome to the meeting.")
    }

    func testDiarizationSegmentCodable() throws {
        let original = DiarizationSegment(
            speakerId: "speaker_0",
            start: 0,
            end: 10,
            text: "Test text"
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DiarizationSegment.self, from: encoded)

        XCTAssertEqual(decoded.speakerId, original.speakerId)
        XCTAssertEqual(decoded.start, original.start)
        XCTAssertEqual(decoded.end, original.end)
        XCTAssertEqual(decoded.text, original.text)
    }

    // MARK: - Helper Methods

    private func createTestMeeting() -> Meeting {
        Meeting(
            title: "Test Meeting",
            startTime: Date(),
            audioPath: "/path/to/audio.m4a",
            status: .ready
        )
    }
}
