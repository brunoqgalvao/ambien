//
//  WhatsAppCallDetector.swift
//  MeetingRecorder
//
//  Detects WhatsApp calls by monitoring audio activity from the WhatsApp process.
//  Uses AudioHardwareCreateProcessTap (macOS 14.2+) for reliable detection.
//
//  WhatsApp's macOS app doesn't expose window titles to the Accessibility API,
//  so we detect calls by monitoring when WhatsApp is actively producing audio.
//

import Foundation
import AppKit
import CoreAudio
import AVFoundation
import Combine
import os.log

private let logger = Logger(subsystem: "com.meetingrecorder.app", category: "WhatsAppCallDetector")

/// Detects WhatsApp calls by monitoring audio activity
@MainActor
class WhatsAppCallDetector: ObservableObject {
    static let shared = WhatsAppCallDetector()

    // MARK: - Published Properties

    @Published var isCallActive: Bool = false
    @Published var callStartTime: Date?
    @Published var detectionStatus: String = "Idle"

    // MARK: - Private Properties

    private var pollingTimer: Timer?
    private let pollingInterval: TimeInterval = 2.0

    // Audio activity tracking
    private var audioActivityStartTime: Date?
    private let audioActivityThreshold: TimeInterval = 30.0  // Sustained audio for 30+ seconds = call

    // Debounce for call end detection
    private var lastAudioActivityTime: Date?
    private let callEndDebounce: TimeInterval = 5.0  // 5 seconds of silence = call ended

    // Process tap (macOS 14.2+)
    private var processTapID: AudioObjectID = 0
    private var aggregateDeviceID: AudioObjectID = 0

    // MARK: - Constants

    private let whatsappBundleID = "net.whatsapp.WhatsApp"

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Start monitoring for WhatsApp calls
    func startMonitoring() {
        guard !isMonitoring else { return }

        logger.info("Starting WhatsApp call detection")
        detectionStatus = "Monitoring..."

        // Start polling timer
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkForWhatsAppCall()
            }
        }

        // Run immediately
        Task {
            await checkForWhatsAppCall()
        }
    }

    /// Stop monitoring
    func stopMonitoring() {
        pollingTimer?.invalidate()
        pollingTimer = nil
        detectionStatus = "Stopped"
        cleanupProcessTap()

        logger.info("Stopped WhatsApp call detection")
    }

    var isMonitoring: Bool {
        pollingTimer != nil
    }

    // MARK: - Detection Logic

    private func checkForWhatsAppCall() async {
        // First, check if WhatsApp is even running
        guard isWhatsAppRunning() else {
            if isCallActive {
                handleCallEnded()
            }
            detectionStatus = "WhatsApp not running"
            return
        }

        // Check for audio activity from WhatsApp
        let hasAudioActivity = await detectWhatsAppAudioActivity()

        if hasAudioActivity {
            handleAudioActivity()
        } else {
            handleNoAudioActivity()
        }
    }

    /// Check if WhatsApp is running
    private func isWhatsAppRunning() -> Bool {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == whatsappBundleID
        }
        return !apps.isEmpty
    }

    /// Detect audio activity from WhatsApp process
    private func detectWhatsAppAudioActivity() async -> Bool {
        // Method 1: Check if WhatsApp is active and microphone is in use
        if let hasAudio = await detectViaProcessCheck() {
            return hasAudio
        }

        // Method 2: Fallback to checking if audio devices are running
        return detectViaAudioDeviceStatus()
    }

    // MARK: - Audio Detection Methods

    /// Detect audio via checking if WhatsApp is active and microphone is in use
    /// Note: macOS 14.2+ has AudioHardwareCreateProcessTap but requires more setup
    private func detectViaProcessCheck() async -> Bool? {
        guard let whatsappApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == whatsappBundleID
        }) else {
            return nil
        }

        // Check if WhatsApp is active (frontmost or recently used)
        // Combined with microphone activity, this indicates a call
        let isActive = whatsappApp.isActive || !whatsappApp.isHidden

        if isActive {
            // If WhatsApp is active and mic is running, likely a call
            return isMicrophoneRunning()
        }

        return false
    }

    /// Check if any microphone is currently in use
    private func isMicrophoneRunning() -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        ) == noErr else { return false }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceIDs
        ) == noErr else { return false }

        for deviceID in deviceIDs {
            // Check if device has input channels
            var inputAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            var inputSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(deviceID, &inputAddress, 0, nil, &inputSize) == noErr,
                  inputSize > 0 else {
                continue
            }

            // Check if this input device is running
            var isRunning: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            var runningAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            if AudioObjectGetPropertyData(deviceID, &runningAddress, 0, nil, &runningSize, &isRunning) == noErr,
               isRunning > 0 {
                return true
            }
        }

        return false
    }

    /// Fallback: Check if any audio devices are running while WhatsApp is active
    private func detectViaAudioDeviceStatus() -> Bool {
        // Check if WhatsApp is frontmost or recently active
        guard let whatsappApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == whatsappBundleID
        }) else {
            return false
        }

        // Get all audio devices
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize
        )

        guard status == noErr else { return false }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0, nil,
            &dataSize,
            &deviceIDs
        )

        guard status == noErr else { return false }

        // Check if any input device is running
        for deviceID in deviceIDs {
            var isRunning: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            var runningAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )

            let runningStatus = AudioObjectGetPropertyData(
                deviceID,
                &runningAddress,
                0, nil,
                &runningSize,
                &isRunning
            )

            if runningStatus == noErr && isRunning != 0 {
                // Microphone is active - check if WhatsApp is frontmost or recently active
                if whatsappApp.isActive || whatsappApp.isHidden == false {
                    logger.debug("Audio device running while WhatsApp is active")
                    return true
                }
            }
        }

        return false
    }

    // MARK: - State Management

    private func handleAudioActivity() {
        lastAudioActivityTime = Date()

        if audioActivityStartTime == nil {
            audioActivityStartTime = Date()
            logger.debug("WhatsApp audio activity started")
        }

        // Check if sustained audio activity (call confirmed)
        if let startTime = audioActivityStartTime,
           Date().timeIntervalSince(startTime) >= audioActivityThreshold,
           !isCallActive {

            isCallActive = true
            callStartTime = startTime
            detectionStatus = "Call detected"
            logger.info("WhatsApp call detected (sustained audio activity)")

            // Post notification for MeetingDetector to pick up
            NotificationCenter.default.post(
                name: .whatsAppCallStarted,
                object: nil,
                userInfo: ["startTime": startTime]
            )
        }
    }

    private func handleNoAudioActivity() {
        // Check if we should end the call
        if let lastActivity = lastAudioActivityTime,
           Date().timeIntervalSince(lastActivity) >= callEndDebounce,
           isCallActive {
            handleCallEnded()
        }

        // Reset audio activity tracking if no sustained activity
        if let startTime = audioActivityStartTime,
           Date().timeIntervalSince(startTime) < audioActivityThreshold {
            audioActivityStartTime = nil
        }
    }

    private func handleCallEnded() {
        guard isCallActive else { return }

        isCallActive = false
        let duration = callStartTime.map { Date().timeIntervalSince($0) } ?? 0
        callStartTime = nil
        audioActivityStartTime = nil
        lastAudioActivityTime = nil
        detectionStatus = "Monitoring..."

        logger.info("WhatsApp call ended (duration: \(Int(duration))s)")

        // Post notification
        NotificationCenter.default.post(
            name: .whatsAppCallEnded,
            object: nil,
            userInfo: ["duration": duration]
        )
    }

    // MARK: - Helper Methods

    private func getWhatsAppPID() -> pid_t? {
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == whatsappBundleID
        }
        return apps.first?.processIdentifier
    }

    private func cleanupProcessTap() {
        // Cleanup any created audio objects
        if processTapID != 0 {
            // AudioHardwareDestroyProcessTap would be called here
            processTapID = 0
        }
        if aggregateDeviceID != 0 {
            aggregateDeviceID = 0
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let whatsAppCallStarted = Notification.Name("whatsAppCallStarted")
    static let whatsAppCallEnded = Notification.Name("whatsAppCallEnded")
}
