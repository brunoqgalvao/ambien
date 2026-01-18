//
//  ContentView.swift
//  MeetingRecorder
//
//  Menu bar dropdown view with recording controls and validation
//

import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var audioManager: AudioCaptureManager
    @ObservedObject var validationManager: ValidationManager
    @State private var selectedTab: Tab = .record

    enum Tab {
        case record
        case meetings
        case settings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with tabs
            HStack(spacing: 0) {
                TabButton(title: "Record", isSelected: selectedTab == .record) {
                    selectedTab = .record
                }
                TabButton(title: "Meetings", isSelected: selectedTab == .meetings) {
                    selectedTab = .meetings
                }
                TabButton(title: "Settings", isSelected: selectedTab == .settings) {
                    selectedTab = .settings
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Divider()
                .padding(.top, 8)

            // Content
            switch selectedTab {
            case .record:
                RecordingView(audioManager: audioManager)
            case .meetings:
                MeetingListView()
                    .frame(height: 350)
            case .settings:
                QuickSettingsView()
            }

            Divider()

            // Footer with menu items
            VStack(spacing: 0) {
                Divider()

                // Import Audio
                MenuBarButton(
                    title: "Import Audio...",
                    icon: "square.and.arrow.down",
                    shortcut: "⌘I",
                    action: { AudioImportManager.shared.showImportDialog() }
                )

                Divider()

                // Open Calendar
                MenuBarButton(
                    title: "Open Calendar",
                    icon: "calendar",
                    shortcut: "⌘O",
                    action: { openCalendarWindow() }
                )

                Divider()

                // Search
                MenuBarButton(
                    title: "Search...",
                    icon: "magnifyingglass",
                    shortcut: "⌘F",
                    action: { openCalendarWindow() }
                )

                Divider()

                // Transcription progress (if any)
                if let progress = audioManager.transcriptionProgress {
                    HStack(spacing: 6) {
                        BrandLoadingIndicator(size: .tiny)
                        Text(progress)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    Divider()
                }

                // Settings
                MenuBarButton(
                    title: "Settings...",
                    icon: "gear",
                    shortcut: "⌘,",
                    action: { SettingsWindowController.shared.showWindow() }
                )

                Divider()

                // Quit
                MenuBarButton(
                    title: "Quit",
                    icon: "power",
                    shortcut: "⌘Q",
                    action: { NSApplication.shared.terminate(nil) }
                )
            }
        }
        .frame(width: 320)
    }

    private func openCalendarWindow() {
        CalendarWindowController.shared.showWindow()
    }
}

// MARK: - Menu Bar Button

struct MenuBarButton: View {
    let title: String
    let icon: String
    let shortcut: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 20)
                Text(title)
                    .font(.subheadline)
                Spacer()
                Text(shortcut)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHovered ? Color.brandViolet.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Calendar Window Controller

class CalendarWindowController {
    static let shared = CalendarWindowController()

    private var windowController: NSWindowController?

    private init() {}

    func showWindow() {
        if let existingWindow = windowController?.window, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let calendarView = CalendarView()
        let hostingController = NSHostingController(rootView: calendarView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Meetings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 600, height: 700))
        window.minSize = NSSize(width: 500, height: 500)
        window.center()
        window.isReleasedWhenClosed = false

        windowController = NSWindowController(window: window)
        windowController?.showWindow(nil)

        NSApp.activate(ignoringOtherApps: true)
    }

    func closeWindow() {
        windowController?.close()
    }
}

// MARK: - Tab Button

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .primary : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.brandViolet.opacity(0.1) : Color.clear)
                .cornerRadius(BrandRadius.small)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recording View

struct RecordingView: View {
    @ObservedObject var audioManager: AudioCaptureManager
    @StateObject private var micRecorder = MicRecorderWithTranscription()
    @State private var useMicOnly = true  // Use mic-only mode for now

    var body: some View {
        VStack(spacing: 16) {
            // Mode toggle
            Toggle("Mic Only (skip system audio)", isOn: $useMicOnly)
                .font(.caption)
                .padding(.horizontal)

            // Status indicator
            if useMicOnly {
                MicRecordingStatus(
                    isRecording: micRecorder.isRecording,
                    duration: micRecorder.currentDuration,
                    status: micRecorder.status
                )
            } else {
                RecordingStatusView(state: audioManager.state, duration: audioManager.currentDuration)
            }

            // Record button
            Button(action: {
                if useMicOnly {
                    Task {
                        if micRecorder.isRecording {
                            await micRecorder.stopRecording()
                        } else {
                            await micRecorder.startRecording()
                        }
                    }
                } else {
                    Task {
                        if audioManager.isRecording {
                            do {
                                _ = try await audioManager.stopRecording()
                            } catch {
                                print("Stop error: \(error)")
                            }
                        } else {
                            do {
                                try await audioManager.startRecording()
                            } catch {
                                print("Start error: \(error)")
                            }
                        }
                    }
                }
            }) {
                HStack {
                    Image(systemName: (useMicOnly ? micRecorder.isRecording : audioManager.isRecording) ? "stop.fill" : "record.circle")
                        .font(.title2)
                    Text((useMicOnly ? micRecorder.isRecording : audioManager.isRecording) ? "Stop Recording" : "Start Recording")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background((useMicOnly ? micRecorder.isRecording : audioManager.isRecording) ? Color.red : Color.brandViolet)
                .cornerRadius(BrandRadius.medium)
            }
            .buttonStyle(.plain)

            // Error message
            if let error = micRecorder.errorMessage, useMicOnly {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else if let error = audioManager.errorMessage, !useMicOnly {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Last recording info
            let lastURL = useMicOnly ? micRecorder.lastRecordingURL : audioManager.lastRecordingURL
            let isRecording = useMicOnly ? micRecorder.isRecording : audioManager.isRecording
            if let url = lastURL, !isRecording {
                VStack(spacing: 4) {
                    Text("Last recording:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundColor(.primary)
                }
            }
        }
        .padding()
    }
}

struct MicRecordingStatus: View {
    let isRecording: Bool
    let duration: TimeInterval
    let status: String?

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isRecording ? Color.red : (status != nil ? Color.blue : Color.secondary))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(status ?? (isRecording ? "Recording (Mic)" : "Ready (Mic Only)"))
                    .font(.subheadline.weight(.medium))
                if isRecording {
                    Text(formatDuration(duration))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding()
        .background(Color(.windowBackgroundColor))
        .cornerRadius(8)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}

// MARK: - Recording Status View

struct RecordingStatusView: View {
    let state: RecordingState
    let duration: TimeInterval

    var body: some View {
        HStack(spacing: 12) {
            // Animated recording dot
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(statusColor.opacity(0.3), lineWidth: 2)
                        .scaleEffect(isRecording ? 1.5 : 1.0)
                        .opacity(isRecording ? 0 : 1)
                        .animation(isRecording ? .easeOut(duration: 1).repeatForever(autoreverses: false) : .default, value: isRecording)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(statusText)
                    .font(.subheadline.weight(.medium))
                if isRecording {
                    Text(formatDuration(duration))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding()
        .background(Color(.windowBackgroundColor))
        .cornerRadius(8)
    }

    private var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    private var statusColor: Color {
        switch state {
        case .idle: return .secondary
        case .preparing: return .orange
        case .recording: return .red
        case .stopping: return .orange
        case .error: return .red
        }
    }

    private var statusText: String {
        switch state {
        case .idle: return "Ready to record"
        case .preparing: return "Preparing..."
        case .recording: return "Recording"
        case .stopping: return "Stopping..."
        case .error(let msg): return "Error: \(msg)"
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}

// MARK: - Quick Settings View (Mini version for menu dropdown)

struct QuickSettingsView: View {
    @State private var apiKey: String = ""
    @State private var showKey = false
    @State private var saveStatus: String?
    @State private var hasEnvKey = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Quick Settings")
                    .font(.headline)
                Spacer()
                Button("Open Full Settings") {
                    SettingsWindowController.shared.showWindow()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.top)

            VStack(alignment: .leading, spacing: 12) {
                Text("OpenAI API Key")
                    .font(.subheadline.weight(.medium))

                if hasEnvKey {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Using OPENAI_API_KEY from environment")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    if showKey {
                        TextField("sk-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                    } else {
                        SecureField("sk-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                    }

                    Button(action: { showKey.toggle() }) {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                }

                HStack {
                    Button("Save") {
                        if KeychainHelper.saveOpenAIKey(apiKey) {
                            saveStatus = "Saved!"
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                saveStatus = nil
                            }
                        } else {
                            saveStatus = "Failed to save"
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKey.isEmpty)

                    if let status = saveStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundColor(status == "Saved!" ? .green : .red)
                    }

                    Spacer()

                    if KeychainHelper.readOpenAIKey() != nil {
                        Button("Delete") {
                            _ = KeychainHelper.deleteOpenAIKey()
                            apiKey = ""
                            saveStatus = "Deleted"
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                saveStatus = nil
                            }
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.red)
                    }
                }

                Text("Your API key is stored securely in macOS Keychain")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Transcription Model")
                    .font(.subheadline.weight(.medium))

                Text("gpt-4o-mini-transcribe ($0.003/min)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Fallback: whisper-1 ($0.006/min)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            Spacer()
        }
        .onAppear {
            // Load existing key (masked)
            if let existing = KeychainHelper.read(key: KeychainHelper.openAIKeyName), !existing.isEmpty {
                apiKey = existing
            }
            // Check if env var is available
            if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !envKey.isEmpty {
                hasEnvKey = true
            }
        }
    }
}

// MARK: - Validation View (kept for debugging)

struct ValidationView: View {
    @ObservedObject var validationManager: ValidationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("M0: Dev Workflow Validation")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top)

            VStack(alignment: .leading, spacing: 8) {
                ValidationRow(
                    title: "ScreenCaptureKit",
                    status: validationManager.screenCaptureStatus,
                    detail: validationManager.screenCaptureDetail
                )

                ValidationRow(
                    title: "AVAudioEngine (Mic)",
                    status: validationManager.audioEngineStatus,
                    detail: validationManager.audioEngineDetail
                )

                ValidationRow(
                    title: "Keychain Access",
                    status: validationManager.keychainStatus,
                    detail: validationManager.keychainDetail
                )
            }
            .padding(.horizontal)

            Button("Run All Tests") {
                Task {
                    await validationManager.runAllTests()
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            .padding(.bottom)
        }
    }
}

// MARK: - Validation Row

struct ValidationRow: View {
    let title: String
    let status: ValidationStatus
    let detail: String

    var body: some View {
        HStack {
            Image(systemName: status.icon)
                .foregroundColor(status.color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Validation Status

enum ValidationStatus {
    case pending
    case running
    case success
    case failure

    var icon: String {
        switch self {
        case .pending: return "circle"
        case .running: return "arrow.circlepath"
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .pending: return .secondary
        case .running: return .blue
        case .success: return .green
        case .failure: return .red
        }
    }
}

// MARK: - Previews

#Preview("Recording - Idle") {
    RecordingView(audioManager: AudioCaptureManager())
        .frame(width: 300)
}

#Preview("Full Menu") {
    ContentView(audioManager: AudioCaptureManager(), validationManager: ValidationManager())
}

#Preview("Status - Recording") {
    RecordingStatusView(state: .recording(duration: 125.3), duration: 125.3)
        .frame(width: 280)
        .padding()
}

#Preview("Validation View") {
    ValidationView(validationManager: ValidationManager())
        .frame(width: 300)
}
