//
//  KeychainHelperTests.swift
//  MeetingRecorderTests
//
//  Unit tests for KeychainHelper and TranscriptionProvider/Model types
//

import XCTest
@testable import MeetingRecorder

final class KeychainHelperTests: XCTestCase {

    // Use unique test keys to avoid affecting real app data
    private let testKeyPrefix = "test-"

    override func tearDownWithError() throws {
        // Clean up any test keys
        _ = KeychainHelper.delete(key: testKeyPrefix + "api-key")
        try super.tearDownWithError()
    }

    // MARK: - Basic Keychain Operations

    func testSaveAndRead() {
        let testKey = testKeyPrefix + "api-key"
        let testValue = "sk-test-key-12345"

        let saved = KeychainHelper.save(key: testKey, value: testValue)
        XCTAssertTrue(saved, "Should successfully save to keychain")

        let retrieved = KeychainHelper.read(key: testKey)
        XCTAssertEqual(retrieved, testValue, "Retrieved value should match saved value")
    }

    func testReadNonExistent() {
        let result = KeychainHelper.read(key: "nonexistent-key-12345")
        XCTAssertNil(result, "Should return nil for non-existent key")
    }

    func testDelete() {
        let testKey = testKeyPrefix + "api-key"

        // Save first
        _ = KeychainHelper.save(key: testKey, value: "test-value")

        // Delete
        let deleted = KeychainHelper.delete(key: testKey)
        XCTAssertTrue(deleted, "Should successfully delete key")

        // Verify deleted
        let retrieved = KeychainHelper.read(key: testKey)
        XCTAssertNil(retrieved, "Should return nil after deletion")
    }

    func testDeleteNonExistent() {
        let deleted = KeychainHelper.delete(key: "nonexistent-key-12345")
        XCTAssertTrue(deleted, "Delete should return true for non-existent key")
    }

    func testUpdate() {
        let testKey = testKeyPrefix + "api-key"

        // Save initial value
        _ = KeychainHelper.save(key: testKey, value: "initial-value")

        // Update
        let updated = KeychainHelper.update(key: testKey, value: "updated-value")
        XCTAssertTrue(updated, "Should successfully update key")

        // Verify updated
        let retrieved = KeychainHelper.read(key: testKey)
        XCTAssertEqual(retrieved, "updated-value")
    }

    func testExists() {
        let testKey = testKeyPrefix + "api-key"

        XCTAssertFalse(KeychainHelper.exists(key: testKey), "Should not exist initially")

        _ = KeychainHelper.save(key: testKey, value: "test")

        XCTAssertTrue(KeychainHelper.exists(key: testKey), "Should exist after save")
    }

    func testSaveOverwrites() {
        let testKey = testKeyPrefix + "api-key"

        _ = KeychainHelper.save(key: testKey, value: "first")
        _ = KeychainHelper.save(key: testKey, value: "second")

        let retrieved = KeychainHelper.read(key: testKey)
        XCTAssertEqual(retrieved, "second", "Save should overwrite existing value")
    }
}

// MARK: - TranscriptionProvider Tests

final class TranscriptionProviderTests: XCTestCase {

    func testAllCases() {
        let providers = TranscriptionProvider.allCases
        XCTAssertEqual(providers.count, 4)
        XCTAssertTrue(providers.contains(.openai))
        XCTAssertTrue(providers.contains(.gemini))
        XCTAssertTrue(providers.contains(.assemblyai))
        XCTAssertTrue(providers.contains(.deepgram))
    }

    func testDisplayNames() {
        XCTAssertEqual(TranscriptionProvider.openai.displayName, "OpenAI")
        XCTAssertEqual(TranscriptionProvider.gemini.displayName, "Google Gemini")
        XCTAssertEqual(TranscriptionProvider.assemblyai.displayName, "AssemblyAI")
        XCTAssertEqual(TranscriptionProvider.deepgram.displayName, "Deepgram")
    }

    func testIcons() {
        XCTAssertFalse(TranscriptionProvider.openai.icon.isEmpty)
        XCTAssertFalse(TranscriptionProvider.gemini.icon.isEmpty)
        XCTAssertFalse(TranscriptionProvider.assemblyai.icon.isEmpty)
        XCTAssertFalse(TranscriptionProvider.deepgram.icon.isEmpty)
    }

    func testAPIKeyURLs() {
        for provider in TranscriptionProvider.allCases {
            XCTAssertNotNil(provider.apiKeyURL, "\(provider) should have API key URL")
        }
    }

    func testIsRecommended() {
        XCTAssertTrue(TranscriptionProvider.openai.isRecommended)
        XCTAssertFalse(TranscriptionProvider.gemini.isRecommended)
        XCTAssertFalse(TranscriptionProvider.assemblyai.isRecommended)
        XCTAssertFalse(TranscriptionProvider.deepgram.isRecommended)
    }

    func testKeychainKeys() {
        XCTAssertEqual(TranscriptionProvider.openai.keychainKey, "openai-api-key")
        XCTAssertEqual(TranscriptionProvider.gemini.keychainKey, "gemini-api-key")
        XCTAssertEqual(TranscriptionProvider.assemblyai.keychainKey, "assemblyai-api-key")
        XCTAssertEqual(TranscriptionProvider.deepgram.keychainKey, "deepgram-api-key")
    }

    func testModels() {
        // OpenAI should have 2 models
        XCTAssertEqual(TranscriptionProvider.openai.models.count, 2)

        // Gemini should have 1 model
        XCTAssertEqual(TranscriptionProvider.gemini.models.count, 1)

        // AssemblyAI should have 2 models
        XCTAssertEqual(TranscriptionProvider.assemblyai.models.count, 2)

        // Deepgram should have 1 model
        XCTAssertEqual(TranscriptionProvider.deepgram.models.count, 1)
    }

    func testMaxFileSize() {
        XCTAssertEqual(TranscriptionProvider.openai.maxFileSize, 25 * 1024 * 1024)  // 25MB
        XCTAssertEqual(TranscriptionProvider.gemini.maxFileSize, 2 * 1024 * 1024 * 1024)  // 2GB
        XCTAssertEqual(TranscriptionProvider.assemblyai.maxFileSize, 5 * 1024 * 1024 * 1024)  // 5GB
        XCTAssertEqual(TranscriptionProvider.deepgram.maxFileSize, 2 * 1024 * 1024 * 1024)  // 2GB
    }

    func testMaxFileSizeFormatted() {
        XCTAssertEqual(TranscriptionProvider.openai.maxFileSizeFormatted, "25MB")
        XCTAssertEqual(TranscriptionProvider.gemini.maxFileSizeFormatted, "2GB")
        XCTAssertEqual(TranscriptionProvider.assemblyai.maxFileSizeFormatted, "5GB")
        XCTAssertEqual(TranscriptionProvider.deepgram.maxFileSizeFormatted, "2GB")
    }

    func testMaxDuration() {
        XCTAssertEqual(TranscriptionProvider.openai.maxDuration, 4 * 60 * 60)  // 4 hours
        XCTAssertEqual(TranscriptionProvider.gemini.maxDuration, 8 * 60 * 60)  // 8 hours
        XCTAssertEqual(TranscriptionProvider.assemblyai.maxDuration, 10 * 60 * 60)  // 10 hours
        XCTAssertEqual(TranscriptionProvider.deepgram.maxDuration, 2 * 60 * 60)  // 2 hours
    }

    func testMaxDurationFormatted() {
        XCTAssertEqual(TranscriptionProvider.openai.maxDurationFormatted, "4 hours")
        XCTAssertEqual(TranscriptionProvider.gemini.maxDurationFormatted, "8 hours")
        XCTAssertEqual(TranscriptionProvider.assemblyai.maxDurationFormatted, "10 hours")
        XCTAssertEqual(TranscriptionProvider.deepgram.maxDurationFormatted, "2 hours")
    }
}

// MARK: - TranscriptionModelOption Tests

final class TranscriptionModelOptionTests: XCTestCase {

    func testFormattedCost() {
        let expensiveModel = TranscriptionModelOption(
            id: "test",
            displayName: "Test",
            costPerMinute: 0.006,
            provider: .openai
        )
        XCTAssertEqual(expensiveModel.formattedCost, "$0.006/min")

        let cheapModel = TranscriptionModelOption(
            id: "test",
            displayName: "Test",
            costPerMinute: 0.0002,
            provider: .gemini
        )
        XCTAssertEqual(cheapModel.formattedCost, "$0.0002/min")
    }

    func testFullId() {
        let model = TranscriptionModelOption(
            id: "whisper-1",
            displayName: "Whisper",
            costPerMinute: 0.006,
            provider: .openai
        )
        XCTAssertEqual(model.fullId, "openai:whisper-1")
    }

    func testFindByFullId() {
        let model = TranscriptionModelOption.find(byFullId: "openai:whisper-1")
        XCTAssertNotNil(model)
        XCTAssertEqual(model?.id, "whisper-1")
        XCTAssertEqual(model?.provider, .openai)
    }

    func testFindByFullId_Invalid() {
        let model = TranscriptionModelOption.find(byFullId: "invalid:model")
        XCTAssertNil(model)
    }

    func testFindByFullId_MalformedInput() {
        let model = TranscriptionModelOption.find(byFullId: "no-colon")
        XCTAssertNil(model)
    }

    func testAllModels() {
        let allModels = TranscriptionModelOption.allModels
        // 2 (OpenAI) + 1 (Gemini) + 2 (AssemblyAI) + 1 (Deepgram) = 6
        XCTAssertEqual(allModels.count, 6)
    }

    func testEquatable() {
        let model1 = TranscriptionModelOption(
            id: "whisper-1",
            displayName: "Whisper",
            costPerMinute: 0.006,
            provider: .openai
        )
        let model2 = TranscriptionModelOption(
            id: "whisper-1",
            displayName: "Different Name",  // Name doesn't matter
            costPerMinute: 0.1,  // Cost doesn't matter
            provider: .openai
        )
        let model3 = TranscriptionModelOption(
            id: "different-id",
            displayName: "Whisper",
            costPerMinute: 0.006,
            provider: .openai
        )

        XCTAssertEqual(model1, model2, "Models with same id and provider should be equal")
        XCTAssertNotEqual(model1, model3, "Models with different id should not be equal")
    }

    func testHashable() {
        let model1 = TranscriptionModelOption(
            id: "whisper-1",
            displayName: "Whisper",
            costPerMinute: 0.006,
            provider: .openai
        )
        let model2 = TranscriptionModelOption(
            id: "whisper-1",
            displayName: "Whisper",
            costPerMinute: 0.006,
            provider: .openai
        )

        var set = Set<TranscriptionModelOption>()
        set.insert(model1)
        set.insert(model2)

        XCTAssertEqual(set.count, 1, "Duplicate models should not be added to set")
    }

    func testOpenAIModels() {
        let models = TranscriptionProvider.openai.models

        let whisper = models.first { $0.id == "whisper-1" }
        XCTAssertNotNil(whisper)
        XCTAssertEqual(whisper?.costPerMinute, 0.006)

        let gpt4o = models.first { $0.id == "gpt-4o-mini-transcribe" }
        XCTAssertNotNil(gpt4o)
        XCTAssertEqual(gpt4o?.costPerMinute, 0.003)
    }

    func testGeminiModels() {
        let models = TranscriptionProvider.gemini.models
        XCTAssertEqual(models.count, 1)

        let flashLite = models.first
        XCTAssertEqual(flashLite?.id, "gemini-2.5-flash-lite")
        XCTAssertEqual(flashLite?.costPerMinute, 0.0002)
    }
}
