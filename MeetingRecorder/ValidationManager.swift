//
//  ValidationManager.swift
//  MeetingRecorder
//
//  Validates M0 requirements: ScreenCaptureKit, AVAudioEngine, Keychain
//

import Foundation
import SwiftUI
import ScreenCaptureKit
import AVFoundation
import Security

@MainActor
class ValidationManager: ObservableObject {
    @Published var screenCaptureStatus: ValidationStatus = .pending
    @Published var screenCaptureDetail: String = ""

    @Published var audioEngineStatus: ValidationStatus = .pending
    @Published var audioEngineDetail: String = ""

    @Published var keychainStatus: ValidationStatus = .pending
    @Published var keychainDetail: String = ""

    func runAllTests() async {
        await testScreenCaptureKit()
        await testAVAudioEngine()
        testKeychain()
    }

    // MARK: - ScreenCaptureKit Validation

    func testScreenCaptureKit() async {
        screenCaptureStatus = .running
        screenCaptureDetail = "Requesting permission..."

        do {
            let content = try await SCShareableContent.current
            screenCaptureStatus = .success
            screenCaptureDetail = "Apps: \(content.applications.count), Windows: \(content.windows.count)"
            print("[ScreenCaptureKit] SUCCESS")
            print("  - Applications: \(content.applications.count)")
            print("  - Windows: \(content.windows.count)")

            // List some running apps with audio
            let audioApps = content.applications.filter { app in
                ["zoom.us", "Google Chrome", "Safari", "Microsoft Teams", "Slack"].contains(where: { app.applicationName.contains($0) })
            }
            if !audioApps.isEmpty {
                print("  - Audio-capable apps detected: \(audioApps.map { $0.applicationName }.joined(separator: ", "))")
            }
        } catch {
            screenCaptureStatus = .failure
            screenCaptureDetail = error.localizedDescription
            print("[ScreenCaptureKit] FAILED: \(error)")
        }
    }

    // MARK: - AVAudioEngine Validation

    func testAVAudioEngine() async {
        audioEngineStatus = .running
        audioEngineDetail = "Checking microphone..."

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        if format.sampleRate > 0 && format.channelCount > 0 {
            audioEngineStatus = .success
            audioEngineDetail = "\(Int(format.sampleRate))Hz, \(format.channelCount)ch"
            print("[AVAudioEngine] SUCCESS")
            print("  - Sample Rate: \(format.sampleRate)Hz")
            print("  - Channels: \(format.channelCount)")
            print("  - Format: \(format)")
        } else {
            audioEngineStatus = .failure
            audioEngineDetail = "Invalid format or no permission"
            print("[AVAudioEngine] FAILED: Invalid audio format")
        }
    }

    // MARK: - Keychain Validation

    func testKeychain() {
        keychainStatus = .running
        keychainDetail = "Testing read/write..."

        let testKey = "test-api-key-\(UUID().uuidString.prefix(8))"
        let testValue = "sk-test-\(UUID().uuidString)"

        // Test write
        let writeResult = KeychainHelper.save(key: testKey, value: testValue)
        guard writeResult else {
            keychainStatus = .failure
            keychainDetail = "Failed to write"
            print("[Keychain] FAILED: Could not write to keychain")
            return
        }

        // Test read
        guard let readValue = KeychainHelper.read(key: testKey) else {
            keychainStatus = .failure
            keychainDetail = "Failed to read"
            print("[Keychain] FAILED: Could not read from keychain")
            return
        }

        guard readValue == testValue else {
            keychainStatus = .failure
            keychainDetail = "Value mismatch"
            print("[Keychain] FAILED: Read value doesn't match written value")
            return
        }

        // Test delete
        let deleteResult = KeychainHelper.delete(key: testKey)
        guard deleteResult else {
            keychainStatus = .failure
            keychainDetail = "Failed to delete"
            print("[Keychain] FAILED: Could not delete from keychain")
            return
        }

        keychainStatus = .success
        keychainDetail = "Read/write/delete OK"
        print("[Keychain] SUCCESS")
        print("  - Write: OK")
        print("  - Read: OK")
        print("  - Delete: OK")
    }
}
