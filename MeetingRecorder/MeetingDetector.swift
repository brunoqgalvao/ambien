//
//  MeetingDetector.swift
//  MeetingRecorder
//
//  Automatic meeting detection for Zoom, Google Meet, Teams, Slack, FaceTime
//  Uses NSWorkspace for native apps and AppleScript for browser-based meetings
//

import Foundation
import AppKit
import Combine
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.meetingrecorder.app", category: "MeetingDetector")

/// Represents a detected meeting session
struct DetectedMeeting: Equatable {
    let app: MeetingApp
    let title: String
    let startedAt: Date
    let bundleIdentifier: String?
    let browserURL: String?

    static func == (lhs: DetectedMeeting, rhs: DetectedMeeting) -> Bool {
        lhs.app == rhs.app && lhs.bundleIdentifier == rhs.bundleIdentifier && lhs.browserURL == rhs.browserURL
    }
}

/// Supported meeting applications
enum MeetingApp: String, CaseIterable {
    case zoom = "Zoom"
    case googleMeet = "Google Meet"
    case teams = "Microsoft Teams"
    case slack = "Slack"
    case faceTime = "FaceTime"

    var icon: String {
        switch self {
        case .zoom: return "video.fill"
        case .googleMeet: return "globe"
        case .teams: return "person.3.fill"
        case .slack: return "bubble.left.and.bubble.right.fill"
        case .faceTime: return "video.fill"
        }
    }

    /// Bundle identifiers for native apps
    var bundleIdentifiers: [String] {
        switch self {
        case .zoom:
            return ["us.zoom.xos", "us.zoom.videomeetings"]
        case .googleMeet:
            return [] // Browser-based only
        case .teams:
            return ["com.microsoft.teams", "com.microsoft.teams2"]
        case .slack:
            return ["com.tinyspeck.slackmacgap"]
        case .faceTime:
            return ["com.apple.FaceTime"]
        }
    }

    /// Window title patterns that indicate an active meeting
    var activeWindowPatterns: [String] {
        switch self {
        case .zoom:
            return ["Zoom Meeting", "Zoom Webinar", "Meeting ID"]
        case .googleMeet:
            return ["meet.google.com"]
        case .teams:
            return ["Meeting", "Call"]
        case .slack:
            return ["Huddle"]
        case .faceTime:
            return ["FaceTime"]
        }
    }
}

/// Main meeting detection manager
@MainActor
class MeetingDetector: ObservableObject {
    static let shared = MeetingDetector()

    // MARK: - Published Properties

    @Published var isEnabled: Bool = false
    @Published var currentMeeting: DetectedMeeting?
    @Published var isRecording: Bool = false
    @Published var detectionStatus: String = "Idle"

    // MARK: - Settings (read from UserDefaults)

    @AppStorage("autoDetectMeetings") private var autoDetectMeetings = true
    @AppStorage("autoRecordZoom") private var autoRecordZoom = false
    @AppStorage("autoRecordMeet") private var autoRecordMeet = false
    @AppStorage("autoRecordTeams") private var autoRecordTeams = false
    @AppStorage("autoRecordSlack") private var autoRecordSlack = false
    @AppStorage("autoRecordFaceTime") private var autoRecordFaceTime = false

    // MARK: - Private Properties

    private var pollingTimer: Timer?
    private var workspaceObserver: NSObjectProtocol?
    private var lastKnownApps: Set<String> = []
    private var cancellables = Set<AnyCancellable>()

    private weak var audioManager: AudioCaptureManager?
    private var autoStartedRecording: Bool = false

    // Polling interval (seconds)
    private let pollingInterval: TimeInterval = 3.0

    // Cooldown to prevent rapid start/stop cycles
    private var lastStopTime: Date?
    private let cooldownSeconds: TimeInterval = 5.0

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Start meeting detection with an audio manager reference
    func start(audioManager: AudioCaptureManager) {
        logger.info("start() called")
        logger.info("autoDetectMeetings = \(self.autoDetectMeetings)")
        logger.info("autoRecordMeet = \(self.autoRecordMeet)")
        logger.info("autoRecordZoom = \(self.autoRecordZoom)")

        guard autoDetectMeetings else {
            logger.warning("Auto-detection disabled in settings")
            return
        }

        guard !isEnabled else {
            logger.info("Already running")
            return
        }

        self.audioManager = audioManager
        isEnabled = true
        detectionStatus = "Monitoring..."

        // Start polling timer for active detection
        startPolling()

        // Also watch for app launches/terminations
        setupWorkspaceObservers()

        logger.info("Started monitoring for meetings")
    }

    /// Stop meeting detection
    func stop() {
        isEnabled = false
        detectionStatus = "Stopped"

        pollingTimer?.invalidate()
        pollingTimer = nil

        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }

        print("[MeetingDetector] Stopped monitoring")
    }

    /// Check if a specific app should be auto-recorded
    func shouldAutoRecord(_ app: MeetingApp) -> Bool {
        switch app {
        case .zoom: return autoRecordZoom
        case .googleMeet: return autoRecordMeet
        case .teams: return autoRecordTeams
        case .slack: return autoRecordSlack
        case .faceTime: return autoRecordFaceTime
        }
    }

    /// Manually trigger a check
    func checkNow() {
        Task {
            await performDetection()
        }
    }

    // MARK: - Private Methods

    private func startPolling() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: pollingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.performDetection()
            }
        }

        // Run immediately
        Task {
            await performDetection()
        }
    }

    private func setupWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter

        // Watch for app terminations
        workspaceObserver = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleId = app.bundleIdentifier else { return }

            Task { @MainActor [weak self] in
                self?.handleAppTerminated(bundleId: bundleId)
            }
        }
    }

    private func performDetection() async {
        // Check native apps first
        if let meeting = await detectNativeAppMeeting() {
            await handleMeetingDetected(meeting)
            return
        }

        // Check browser-based meetings (Google Meet)
        if autoRecordMeet {
            logger.debug("Checking for Google Meet...")
            if let meeting = await detectGoogleMeetInBrowser() {
                logger.info("Found Google Meet: \(meeting.title)")
                await handleMeetingDetected(meeting)
                return
            }
        } else {
            logger.debug("autoRecordMeet is disabled, skipping Google Meet check")
        }

        // No meeting detected - stop recording if we auto-started
        if currentMeeting != nil && autoStartedRecording {
            await handleMeetingEnded()
        }
    }

    private func detectNativeAppMeeting() async -> DetectedMeeting? {
        let runningApps = NSWorkspace.shared.runningApplications

        for app in MeetingApp.allCases {
            guard shouldAutoRecord(app), !app.bundleIdentifiers.isEmpty else { continue }

            for runningApp in runningApps {
                guard let bundleId = runningApp.bundleIdentifier,
                      app.bundleIdentifiers.contains(bundleId) else { continue }

                // Check if there's an active meeting window
                if let title = await getActiveWindowTitle(for: runningApp, app: app) {
                    return DetectedMeeting(
                        app: app,
                        title: title,
                        startedAt: Date(),
                        bundleIdentifier: bundleId,
                        browserURL: nil
                    )
                }
            }
        }

        return nil
    }

    private func getActiveWindowTitle(for runningApp: NSRunningApplication, app: MeetingApp) async -> String? {
        // Use Accessibility API to check window titles
        // Fall back to basic detection if accessibility is not available

        let pid = runningApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)

        guard result == .success, let windows = windowsRef as? [AXUIElement] else {
            // Fallback: assume meeting is active if app is running and frontmost
            if runningApp.isActive {
                return "Meeting in \(app.rawValue)"
            }
            return nil
        }

        for window in windows {
            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
               let title = titleRef as? String {

                // Check if title matches meeting patterns
                for pattern in app.activeWindowPatterns {
                    if title.localizedCaseInsensitiveContains(pattern) {
                        return cleanWindowTitle(title, for: app)
                    }
                }
            }
        }

        return nil
    }

    private func cleanWindowTitle(_ title: String, for app: MeetingApp) -> String {
        var cleaned = title

        // Remove common suffixes
        let suffixes = [" - Zoom", " | Microsoft Teams", " - Google Chrome", " - Safari"]
        for suffix in suffixes {
            if cleaned.hasSuffix(suffix) {
                cleaned = String(cleaned.dropLast(suffix.count))
            }
        }

        // Truncate if too long
        if cleaned.count > 60 {
            cleaned = String(cleaned.prefix(57)) + "..."
        }

        // Fallback to generic title
        if cleaned.isEmpty {
            cleaned = "Meeting in \(app.rawValue)"
        }

        return cleaned
    }

    private func detectGoogleMeetInBrowser() async -> DetectedMeeting? {
        // Use Accessibility API to read browser window titles
        // This doesn't require AppleScript automation permission

        // Check Chrome
        if let meeting = detectGoogleMeetViaAccessibility(bundleId: "com.google.Chrome", browserName: "Chrome") {
            return meeting
        }

        // Check Safari
        if let meeting = detectGoogleMeetViaAccessibility(bundleId: "com.apple.Safari", browserName: "Safari") {
            return meeting
        }

        // Check Arc
        if let meeting = detectGoogleMeetViaAccessibility(bundleId: "company.thebrowser.Browser", browserName: "Arc") {
            return meeting
        }

        // Check Firefox
        if let meeting = detectGoogleMeetViaAccessibility(bundleId: "org.mozilla.firefox", browserName: "Firefox") {
            return meeting
        }

        // Check Brave
        if let meeting = detectGoogleMeetViaAccessibility(bundleId: "com.brave.Browser", browserName: "Brave") {
            return meeting
        }

        return nil
    }

    /// Detect Google Meet by reading browser window titles via Accessibility API
    private func detectGoogleMeetViaAccessibility(bundleId: String, browserName: String) -> DetectedMeeting? {
        // Find the running browser
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId }) else {
            return nil
        }

        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        // Get all windows
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return nil
        }

        // Check each window title for Google Meet indicators
        for window in windows {
            var titleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
                  let title = titleRef as? String else {
                continue
            }

            // Google Meet window titles contain "Meet" and often the meeting code or name
            // Examples: "Meet - abc-defg-hij", "Meeting Name - Google Meet", "meet.google.com/xxx-xxxx-xxx"
            let lowercased = title.lowercased()
            if lowercased.contains("meet.google.com") ||
               (lowercased.contains("google meet") && !lowercased.contains("calendar")) ||
               (lowercased.contains(" - meet") && !lowercased.contains("calendar")) {

                logger.info("Found Google Meet in \(browserName): '\(title)'")

                let cleanTitle = cleanGoogleMeetTitle(title)

                return DetectedMeeting(
                    app: .googleMeet,
                    title: cleanTitle,
                    startedAt: Date(),
                    bundleIdentifier: bundleId,
                    browserURL: nil
                )
            }
        }

        return nil
    }

    private func cleanGoogleMeetTitle(_ title: String) -> String {
        var cleaned = title

        // Remove "Meet - " prefix
        if cleaned.hasPrefix("Meet - ") {
            cleaned = String(cleaned.dropFirst(7))
        }

        // Remove " - Google Meet" suffix
        if cleaned.hasSuffix(" - Google Meet") {
            cleaned = String(cleaned.dropLast(14))
        }

        // If it's just a meeting code, make it more readable
        if cleaned.count <= 12 && cleaned.contains("-") {
            cleaned = "Google Meet"
        }

        return cleaned.isEmpty ? "Google Meet" : cleaned
    }

    private func handleMeetingDetected(_ meeting: DetectedMeeting) async {
        // Check if this is a new meeting or same as current
        if let current = currentMeeting, current == meeting {
            return // Same meeting, no action needed
        }

        // Check cooldown
        if let lastStop = lastStopTime, Date().timeIntervalSince(lastStop) < cooldownSeconds {
            print("[MeetingDetector] In cooldown period, skipping")
            return
        }

        currentMeeting = meeting
        detectionStatus = "Detected: \(meeting.app.rawValue)"

        print("[MeetingDetector] Meeting detected: \(meeting.title) (\(meeting.app.rawValue))")

        // Auto-start recording if not already recording
        if let audioManager = audioManager, !audioManager.isRecording {
            do {
                try await audioManager.startRecording(
                    title: meeting.title,
                    sourceApp: meeting.app.rawValue
                )
                autoStartedRecording = true
                isRecording = true
                print("[MeetingDetector] Auto-started recording")

                // Show recording island
                RecordingIslandController.shared.show(audioManager: audioManager)

            } catch {
                print("[MeetingDetector] Failed to auto-start recording: \(error)")
            }
        }
    }

    private func handleMeetingEnded() async {
        guard let meeting = currentMeeting else { return }

        print("[MeetingDetector] Meeting ended: \(meeting.title)")

        currentMeeting = nil
        detectionStatus = "Monitoring..."
        lastStopTime = Date()

        // Auto-stop recording if we auto-started it
        if autoStartedRecording, let audioManager = audioManager, audioManager.isRecording {
            do {
                _ = try await audioManager.stopRecording()
                print("[MeetingDetector] Auto-stopped recording")

                // Hide recording island
                RecordingIslandController.shared.hide()

            } catch {
                print("[MeetingDetector] Failed to auto-stop recording: \(error)")
            }
        }

        autoStartedRecording = false
        isRecording = false
    }

    private func handleAppTerminated(bundleId: String) {
        guard let meeting = currentMeeting else { return }

        // Check if terminated app was our meeting app
        let wasOurMeeting = meeting.bundleIdentifier == bundleId ||
            meeting.app.bundleIdentifiers.contains(bundleId)

        if wasOurMeeting {
            Task {
                await handleMeetingEnded()
            }
        }
    }
}

// MARK: - Preview Support

#if DEBUG
extension MeetingDetector {
    /// Create a mock instance for previews
    static var preview: MeetingDetector {
        let detector = MeetingDetector.shared
        detector.detectionStatus = "Monitoring..."
        return detector
    }
}
#endif
