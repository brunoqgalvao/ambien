//
//  ParticipantService.swift
//  MeetingRecorder
//
//  Captures meeting window screenshots and extracts participant names using Vision OCR
//  Also captures window titles from meeting apps
//

import Foundation
import AppKit
import ScreenCaptureKit
import Vision

/// Service for detecting meeting participants
actor ParticipantService {
    static let shared = ParticipantService()

    // MARK: - Screenshot Capture

    /// Capture a screenshot of the meeting window
    /// - Parameters:
    ///   - bundleIdentifier: Bundle ID of the meeting app (optional)
    ///   - windowTitle: Title pattern to match (optional)
    /// - Returns: Path to saved screenshot or nil
    func captureScreenshot(bundleIdentifier: String? = nil, windowTitle: String? = nil) async throws -> String? {
        // Get shareable content
        let content = try await SCShareableContent.current

        // Find the best window to capture
        var targetWindow: SCWindow?

        // First try to find by bundle identifier
        if let bundleId = bundleIdentifier {
            let matchingApps = content.applications.filter { $0.bundleIdentifier == bundleId }
            for app in matchingApps {
                let appWindows = content.windows.filter { $0.owningApplication?.bundleIdentifier == bundleId }
                // Prefer windows with meeting-related titles
                for window in appWindows {
                    if let title = window.title, isMeetingWindow(title: title) {
                        targetWindow = window
                        break
                    }
                }
                if targetWindow == nil {
                    targetWindow = appWindows.first
                }
            }
        }

        // Fallback: find any meeting window
        if targetWindow == nil {
            for window in content.windows {
                if let title = window.title, isMeetingWindow(title: title) {
                    targetWindow = window
                    break
                }
            }
        }

        guard let window = targetWindow else {
            print("[ParticipantService] No meeting window found to capture")
            return nil
        }

        print("[ParticipantService] Capturing window: \(window.title ?? "Untitled")")

        // Configure capture
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width) * 2  // Retina
        config.height = Int(window.frame.height) * 2
        config.showsCursor = false
        config.capturesAudio = false

        // Create filter for single window
        let filter = SCContentFilter(desktopIndependentWindow: window)

        // Capture the screenshot
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        // Save to disk
        let screenshotPath = createScreenshotPath()
        try saveImage(image, to: screenshotPath)

        print("[ParticipantService] Screenshot saved: \(screenshotPath)")
        return screenshotPath
    }

    /// Check if a window title indicates a meeting window
    private func isMeetingWindow(title: String) -> Bool {
        let lowercased = title.lowercased()
        let meetingIndicators = [
            "zoom meeting", "zoom webinar",
            "meet.google.com", "google meet",
            "microsoft teams", "teams meeting",
            "slack huddle", "slack call",
            "facetime"
        ]
        return meetingIndicators.contains { lowercased.contains($0) }
    }

    /// Create a path for saving screenshots
    private func createScreenshotPath() -> String {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let screenshotsFolder = documentsPath.appendingPathComponent("MeetingRecorder/screenshots", isDirectory: true)

        try? FileManager.default.createDirectory(at: screenshotsFolder, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())

        return screenshotsFolder.appendingPathComponent("meeting_\(timestamp).png").path
    }

    /// Save CGImage to disk as PNG
    private func saveImage(_ image: CGImage, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        let destination = CGImageDestinationCreateWithURL(url as CFURL, kUTTypePNG, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    // MARK: - Window Title Detection

    /// Get the title of the active meeting window
    func getMeetingWindowTitle(bundleIdentifier: String? = nil) async -> String? {
        // Check running apps for meeting window titles
        let runningApps = NSWorkspace.shared.runningApplications

        // Bundle IDs to check
        let meetingBundleIds = [
            bundleIdentifier,
            "us.zoom.xos",
            "us.zoom.videomeetings",
            "com.microsoft.teams",
            "com.microsoft.teams2",
            "com.tinyspeck.slackmacgap",
            "com.apple.FaceTime",
            "com.google.Chrome",
            "com.apple.Safari",
            "company.thebrowser.Browser",  // Arc
            "org.mozilla.firefox"
        ].compactMap { $0 }

        for app in runningApps {
            guard let bundleId = app.bundleIdentifier,
                  meetingBundleIds.contains(bundleId) else { continue }

            // Use Accessibility API to get window titles
            if let title = getWindowTitleViaAccessibility(for: app) {
                return title
            }
        }

        return nil
    }

    /// Get window title using Accessibility API
    private func getWindowTitleViaAccessibility(for app: NSRunningApplication) -> String? {
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return nil
        }

        for window in windows {
            var titleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
                  let title = titleRef as? String else {
                continue
            }

            // Check if it looks like a meeting window
            if isMeetingWindow(title: title) {
                return cleanWindowTitle(title)
            }
        }

        return nil
    }

    /// Clean up window title for storage
    private func cleanWindowTitle(_ title: String) -> String {
        var cleaned = title

        // Remove browser suffixes
        let suffixes = [
            " - Google Chrome",
            " - Safari",
            " - Arc",
            " - Firefox",
            " - Brave"
        ]
        for suffix in suffixes {
            if cleaned.hasSuffix(suffix) {
                cleaned = String(cleaned.dropLast(suffix.count))
            }
        }

        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Vision OCR for Participant Detection

    /// Extract participant names from a screenshot using Vision OCR
    /// - Parameter screenshotPath: Path to the screenshot image
    /// - Returns: Array of detected participant names
    func extractParticipants(from screenshotPath: String) async throws -> [MeetingParticipant] {
        guard FileManager.default.fileExists(atPath: screenshotPath) else {
            return []
        }

        let imageURL = URL(fileURLWithPath: screenshotPath)
        guard let image = NSImage(contentsOf: imageURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return []
        }

        // Perform OCR
        let recognizedText = try await performOCR(on: cgImage)

        // Parse participant names from OCR text
        let participants = parseParticipantNames(from: recognizedText)

        print("[ParticipantService] Extracted \(participants.count) participants from screenshot")
        return participants
    }

    /// Perform OCR using Vision framework
    private func performOCR(on image: CGImage) async throws -> [String] {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let recognizedStrings = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }

                continuation.resume(returning: recognizedStrings)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Parse OCR text to extract participant names
    private func parseParticipantNames(from lines: [String]) -> [MeetingParticipant] {
        var participants: [MeetingParticipant] = []
        var seenNames = Set<String>()

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines and common UI text
            guard !trimmed.isEmpty,
                  !isUIText(trimmed) else { continue }

            // Look for patterns that indicate participant names
            if let name = extractName(from: trimmed) {
                let normalizedName = name.trimmingCharacters(in: .whitespaces)

                // Skip duplicates
                if seenNames.contains(normalizedName.lowercased()) { continue }

                // Skip if it looks like a UI element
                if normalizedName.count < 2 || normalizedName.count > 50 { continue }

                seenNames.insert(normalizedName.lowercased())
                participants.append(MeetingParticipant(
                    name: normalizedName,
                    source: .screenshot
                ))
            }
        }

        return participants
    }

    /// Check if text is common UI text to skip
    private func isUIText(_ text: String) -> Bool {
        let uiPatterns = [
            "mute", "unmute", "video", "audio", "share", "screen",
            "chat", "record", "leave", "end", "meeting", "participants",
            "waiting", "room", "host", "co-host", "settings",
            "invite", "security", "reactions", "more", "view",
            "gallery", "speaker", "grid", "zoom", "teams", "meet"
        ]

        let lowercased = text.lowercased()
        return uiPatterns.contains { lowercased == $0 }
    }

    /// Extract a name from a line of text
    private func extractName(from text: String) -> String? {
        // Common patterns in meeting participant lists:
        // - "John Doe" (plain name)
        // - "John Doe (Host)"
        // - "John Doe - Speaking"
        // - "JD John Doe" (initials + name)

        var name = text

        // Remove common suffixes
        let suffixes = ["(Host)", "(Co-host)", "(You)", "- Speaking", "- Presenting", "(Guest)", "(Me)"]
        for suffix in suffixes {
            if name.hasSuffix(suffix) {
                name = String(name.dropLast(suffix.count))
            }
            // Case insensitive
            let lowercasedSuffix = suffix.lowercased()
            if name.lowercased().hasSuffix(lowercasedSuffix) {
                name = String(name.dropLast(lowercasedSuffix.count))
            }
        }

        name = name.trimmingCharacters(in: .whitespaces)

        // Basic validation: should look like a name (letters, spaces, maybe punctuation)
        let nameCharacterSet = CharacterSet.letters.union(.whitespaces).union(CharacterSet(charactersIn: "-'."))
        if name.unicodeScalars.allSatisfy({ nameCharacterSet.contains($0) }) {
            // Should have at least one letter
            if name.contains(where: { $0.isLetter }) {
                return name
            }
        }

        return nil
    }
}

// MARK: - Meeting Context Capture

extension ParticipantService {
    /// Capture meeting context (screenshot + window title) when recording starts
    /// - Parameter bundleIdentifier: Optional bundle ID of known meeting app
    /// - Returns: Tuple of (screenshotPath, windowTitle, participants)
    func captureMeetingContext(bundleIdentifier: String? = nil) async -> (screenshotPath: String?, windowTitle: String?, participants: [MeetingParticipant]) {
        var screenshotPath: String?
        var windowTitle: String?
        var participants: [MeetingParticipant] = []

        // Get window title first
        windowTitle = await getMeetingWindowTitle(bundleIdentifier: bundleIdentifier)

        // Capture screenshot
        do {
            screenshotPath = try await captureScreenshot(bundleIdentifier: bundleIdentifier)

            // Extract participants from screenshot
            if let path = screenshotPath {
                participants = try await extractParticipants(from: path)
            }
        } catch {
            print("[ParticipantService] Failed to capture/process screenshot: \(error)")
        }

        return (screenshotPath, windowTitle, participants)
    }
}
