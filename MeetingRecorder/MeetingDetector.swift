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
import CoreGraphics
import CoreAudio
import os.log

private let logger = Logger(subsystem: "com.ambient.app", category: "MeetingDetector")

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
    case whatsApp = "WhatsApp"

    var icon: String {
        switch self {
        case .zoom: return "video.fill"
        case .googleMeet: return "globe"
        case .teams: return "person.3.fill"
        case .slack: return "bubble.left.and.bubble.right.fill"
        case .faceTime: return "video.fill"
        case .whatsApp: return "phone.fill"
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
        case .whatsApp:
            return ["net.whatsapp.WhatsApp", "WhatsApp"]
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
        case .whatsApp:
            // WhatsApp call window patterns (detected from actual app)
            // Format: "Whatsapp voice call" or "Whatsapp video call"
            return [
                "Whatsapp voice call", "Whatsapp video call", "Whatsapp group call",
                "Voice call", "Video call", "Group call", "Calling", "Ringing",
                "Chamada de voz", "Chamada de vídeo", "Chamada em grupo", "Chamando", "Tocando"
            ]
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
    @AppStorage("autoRecordWhatsApp") private var autoRecordWhatsApp = false

    // MARK: - Private Properties

    private var pollingTimer: Timer?
    private var workspaceObserver: NSObjectProtocol?
    private var lastKnownApps: Set<String> = []
    private var cancellables = Set<AnyCancellable>()

    private weak var audioManager: AudioCaptureManager?
    private var autoStartedRecording: Bool = false

    // WhatsApp call detection
    private var whatsAppCallObserver: NSObjectProtocol?
    private var whatsAppEndObserver: NSObjectProtocol?

    // Track which app triggered the current auto-recording
    private var autoRecordingApp: MeetingApp?

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

        // Start WhatsApp call detection if enabled
        if autoRecordWhatsApp {
            setupWhatsAppDetection()
        }

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

        // Stop WhatsApp detection
        stopWhatsAppDetection()

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
        case .whatsApp: return autoRecordWhatsApp
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
            if let meeting = await detectGoogleMeetInBrowser() {
                logger.debug("Active Google Meet found: \(meeting.title)")
                await handleMeetingDetected(meeting)
                return
            } else if currentMeeting?.app == .googleMeet {
                // Google Meet was active but no longer detected
                // This means either: tab closed, URL changed, or meeting ended screen shown
                logger.info("Google Meet no longer detected - meeting likely ended")
            }
        }

        // Note: WhatsApp detection is handled by WhatsAppCallDetector via notifications
        // (WhatsApp doesn't expose window titles, so we use dedicated audio-based detection)

        // No meeting detected - stop recording if we auto-started
        // Skip auto-stop for WhatsApp since it's handled by WhatsAppCallDetector notifications
        if currentMeeting != nil && autoStartedRecording && currentMeeting?.app != .whatsApp {
            logger.info("No active meeting detected, triggering auto-stop")
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
        let pid = runningApp.processIdentifier

        // First try CGWindowList (more reliable for apps like WhatsApp)
        if let title = getWindowTitleViaCGWindowList(pid: pid, app: app) {
            return title
        }

        // Fallback to Accessibility API
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

    /// Use CGWindowList to get window titles (works for apps like WhatsApp that don't expose windows via Accessibility API)
    private func getWindowTitleViaCGWindowList(pid: pid_t, app: MeetingApp) -> String? {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for window in windowList {
            guard let windowPID = window[kCGWindowOwnerPID as String] as? pid_t,
                  windowPID == pid else { continue }

            guard let windowName = window[kCGWindowName as String] as? String,
                  !windowName.isEmpty else { continue }

            // Check if window name matches any of the app's patterns
            for pattern in app.activeWindowPatterns {
                if windowName.localizedCaseInsensitiveContains(pattern) {
                    logger.info("CGWindowList found match: '\(windowName)' matches '\(pattern)'")
                    return cleanWindowTitle(windowName, for: app)
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

            // Skip if this is a post-meeting page (meeting has ended)
            // Google Meet shows these titles when the meeting is over:
            // - "You left the meeting"
            // - "Meeting ended"
            // - "The meeting has ended"
            // - "Call ended"
            // - "Your meeting has ended"
            // - "Return to home screen" (sometimes shown after leaving)
            if isGoogleMeetEndedTitle(lowercased) {
                logger.debug("Detected Google Meet ended state in \(browserName): '\(title)'")
                continue
            }

            if lowercased.contains("meet.google.com") ||
               (lowercased.contains("google meet") && !lowercased.contains("calendar")) ||
               (lowercased.contains(" - meet") && !lowercased.contains("calendar")) {

                logger.info("Found active Google Meet in \(browserName): '\(title)'")

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

    /// Check if a window title indicates the Google Meet has ended
    private func isGoogleMeetEndedTitle(_ lowercasedTitle: String) -> Bool {
        // Patterns that indicate the meeting is over
        let endedPatterns = [
            "you left the meeting",
            "left the meeting",
            "meeting ended",
            "meeting has ended",
            "call ended",
            "the call has ended",
            "your meeting has ended",
            "return to home screen",
            "rejoin the meeting",      // Shows after leaving with rejoin option
            "you've left the meeting",
            "meeting code not valid",  // Invalid/expired meeting
            "meeting hasn't started",  // Pre-meeting lobby (not active yet)
            "check your meeting code"  // Error state
        ]

        for pattern in endedPatterns {
            if lowercasedTitle.contains(pattern) {
                return true
            }
        }

        return false
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
                autoRecordingApp = meeting.app
                isRecording = true
                print("[MeetingDetector] Auto-started recording")

                // Track the trigger
                AutoRuleStatsManager.shared.recordTrigger(for: meeting.app)

                // Show recording island
                RecordingIslandController.shared.show(audioManager: audioManager)

                // Show toast with Stop/Discard option
                showAutoRecordingToast(for: meeting, audioManager: audioManager)

            } catch {
                print("[MeetingDetector] Failed to auto-start recording: \(error)")
            }
        }
    }

    /// Show a toast notification when auto-recording starts with option to stop/discard
    private func showAutoRecordingToast(for meeting: DetectedMeeting, audioManager: AudioCaptureManager) {
        let app = meeting.app

        ToastController.shared.show(ToastData(
            type: .info,
            title: "Recording \(meeting.app.rawValue)",
            message: meeting.title,
            duration: 6.0,  // Longer duration for user to react
            action: ToastAction(title: "Stop") { [weak self] in
                Task { @MainActor in
                    await self?.handleAutoRecordingDiscard(app: app, audioManager: audioManager)
                }
            },
            onTap: nil
        ))
    }

    /// Handle when user discards an auto-started recording
    private func handleAutoRecordingDiscard(app: MeetingApp, audioManager: AudioCaptureManager) async {
        // Discard the recording
        await audioManager.discardRecording()

        // Record the discard and check if we should auto-disable
        let shouldDisable = AutoRuleStatsManager.shared.recordDiscard(for: app)

        if shouldDisable {
            // Auto-disable the rule
            AutoRuleStatsManager.shared.markAutoDisabled(for: app)

            // Show notification about auto-disable
            ToastController.shared.showWarning(
                "Auto-record disabled",
                message: "\(app.rawValue) auto-record was disabled after 5 discards. Re-enable in Settings.",
                duration: 5.0,
                action: ToastAction(title: "Settings") {
                    SettingsWindowController.shared.showWindow()
                }
            )

            logger.info("Auto-disabled \(app.rawValue) recording due to repeated discards")
        } else {
            let stat = AutoRuleStatsManager.shared.getStat(for: app)
            let remaining = 5 - (stat?.consecutiveDiscards ?? 0)
            if remaining <= 3 && remaining > 0 {
                // Warn user they're close to auto-disable threshold
                ToastController.shared.showWarning(
                    "Recording discarded",
                    message: "\(remaining) more discard\(remaining == 1 ? "" : "s") will disable \(app.rawValue) auto-record"
                )
            }
        }

        // Clean up meeting detector state
        currentMeeting = nil
        autoStartedRecording = false
        autoRecordingApp = nil
        isRecording = false
        detectionStatus = "Monitoring..."
        lastStopTime = Date()

        // Hide recording island
        RecordingIslandController.shared.hide()
    }

    /// Record that a recording was kept (not discarded)
    func recordKept() {
        guard let app = autoRecordingApp else { return }
        AutoRuleStatsManager.shared.recordKept(for: app)
        autoRecordingApp = nil
    }

    private var isHandlingMeetingEnd = false

    private func handleMeetingEnded() async {
        // Prevent double-triggering (race condition between polling and notifications)
        guard !isHandlingMeetingEnd else {
            logger.debug("Already handling meeting end, skipping duplicate call")
            return
        }

        guard let meeting = currentMeeting else { return }

        isHandlingMeetingEnd = true
        defer { isHandlingMeetingEnd = false }

        logger.info("Meeting ended: \(meeting.title) (\(meeting.app.rawValue))")

        currentMeeting = nil
        detectionStatus = "Monitoring..."
        lastStopTime = Date()

        // Auto-stop recording if we auto-started it
        if autoStartedRecording, let audioManager = audioManager, audioManager.isRecording {
            do {
                logger.info("Auto-stopping recording for ended meeting...")
                _ = try await audioManager.stopRecording()
                logger.info("Auto-stopped recording successfully")

                // Recording completed successfully - record as kept
                recordKept()

                // Hide recording island (dispatch to avoid threading issues)
                await MainActor.run {
                    RecordingIslandController.shared.hide()
                }

            } catch {
                logger.error("Failed to auto-stop recording: \(error.localizedDescription)")
            }
        } else {
            logger.debug("No auto-stop needed: autoStartedRecording=\(self.autoStartedRecording), isRecording=\(self.audioManager?.isRecording ?? false)")
        }

        autoStartedRecording = false
        autoRecordingApp = nil
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

    // MARK: - WhatsApp Detection (Audio-based)

    /// Set up WhatsApp call detection using audio activity monitoring
    private func setupWhatsAppDetection() {
        logger.info("Setting up WhatsApp audio-based call detection")

        // Start the WhatsApp call detector
        WhatsAppCallDetector.shared.startMonitoring()

        // Listen for call start notifications
        whatsAppCallObserver = NotificationCenter.default.addObserver(
            forName: .whatsAppCallStarted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            let startTime = notification.userInfo?["startTime"] as? Date ?? Date()

            Task { @MainActor in
                let meeting = DetectedMeeting(
                    app: .whatsApp,
                    title: "WhatsApp Call",
                    startedAt: startTime,
                    bundleIdentifier: "net.whatsapp.WhatsApp",
                    browserURL: nil
                )
                await self.handleMeetingDetected(meeting)
            }
        }

        // Listen for call end notifications
        whatsAppEndObserver = NotificationCenter.default.addObserver(
            forName: .whatsAppCallEnded,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }

            Task { @MainActor in
                // Only end if current meeting is WhatsApp
                if self.currentMeeting?.app == .whatsApp {
                    await self.handleMeetingEnded()
                }
            }
        }
    }

    /// Stop WhatsApp call detection
    private func stopWhatsAppDetection() {
        WhatsAppCallDetector.shared.stopMonitoring()

        if let observer = whatsAppCallObserver {
            NotificationCenter.default.removeObserver(observer)
            whatsAppCallObserver = nil
        }
        if let observer = whatsAppEndObserver {
            NotificationCenter.default.removeObserver(observer)
            whatsAppEndObserver = nil
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
