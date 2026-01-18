//
//  MeetingRecorderApp.swift
//  MeetingRecorder
//
//  Main app entry point
//  Menu bar for quick actions + Recording Island + Main app window
//

import SwiftUI
import AppKit
import Combine
import Sparkle

@main
struct MeetingRecorderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Initialize database on app launch
        // GroupManager gets database access lazily via DatabaseManager.shared.getDbQueue()
        Task {
            do {
                try await DatabaseManager.shared.initialize()
                print("[App] Database initialized")
            } catch {
                print("[App] Database initialization error: \(error)")
            }
        }
    }

    var body: some Scene {
        // We use a custom NSStatusItem in AppDelegate for left-click/right-click behavior
        // This Settings scene enables the Settings menu item
        Settings {
            EmptyView()
        }
        .commands {
            // Global keyboard shortcuts
            CommandGroup(replacing: .newItem) {
                Button("Open App") {
                    MainAppWindowController.shared.showWindow()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Search Meetings...") {
                    MainAppWindowController.shared.showWindow()
                }
                .keyboardShortcut("f", modifiers: .command)

                Divider()

                Button("Start Recording") {
                    Task {
                        if let appDelegate = NSApp.delegate as? AppDelegate {
                            await appDelegate.toggleRecording()
                        }
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }

            // About menu
            CommandGroup(replacing: .appInfo) {
                Button("About Ambient") {
                    AboutWindowController.shared.showWindow()
                }
            }

            // Settings menu
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    MainAppWindowController.shared.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            // Check for Updates (Sparkle)
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: appDelegate.updaterController.updater)
            }
        }
    }
}

// MARK: - Sparkle Check for Updates View

struct CheckForUpdatesView: View {
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

// MARK: - Menu Bar Dropdown (Quick Actions)

struct MenuBarDropdown: View {
    @ObservedObject var audioManager: AudioCaptureManager
    @StateObject private var micRecorder = MicRecorderWithTranscription()

    // Access MeetingDetector settings directly via AppStorage instead of observing the singleton
    @AppStorage("autoDetectMeetings") private var autoDetectMeetings = true

    var body: some View {
        VStack(spacing: 0) {
            // Recording status
            if audioManager.isRecording || micRecorder.isRecording {
                RecordingStatusCard(
                    isRecording: audioManager.isRecording || micRecorder.isRecording,
                    duration: audioManager.isRecording ? audioManager.currentDuration : micRecorder.currentDuration,
                    title: audioManager.currentMeeting?.title ?? "Recording"
                )
                .padding(12)

                Divider()
            }

            // Quick actions
            VStack(spacing: 2) {
                if audioManager.isRecording || micRecorder.isRecording {
                    MenuQuickActionButton(
                        icon: "stop.fill",
                        title: "Stop Recording",
                        subtitle: nil,
                        color: .red
                    ) {
                        Task {
                            if audioManager.isRecording {
                                _ = try? await audioManager.stopRecording()
                                RecordingIslandController.shared.hide()
                            } else {
                                await micRecorder.stopRecording()
                            }
                        }
                    }
                } else {
                    MenuQuickActionButton(
                        icon: "record.circle",
                        title: "Start Recording",
                        subtitle: "Mic + System Audio",
                        color: .red
                    ) {
                        Task {
                            try? await audioManager.startRecording()
                            // Show recording island
                            RecordingIslandController.shared.show(audioManager: audioManager)
                        }
                    }

                    MenuQuickActionButton(
                        icon: "mic.fill",
                        title: "Quick Record",
                        subtitle: "Mic only",
                        color: .blue
                    ) {
                        Task {
                            await micRecorder.startRecording()
                        }
                    }
                }
            }
            .padding(.vertical, 4)

            Divider()

            // Navigation
            VStack(spacing: 2) {
                BrandMenuButton(icon: "rectangle.stack", title: "Open App", shortcut: "O") {
                    MainAppWindowController.shared.showWindow()
                }

                MenuToggleButton(
                    icon: autoDetectMeetings ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash",
                    title: "Auto-detect Meetings",
                    isOn: autoDetectMeetings
                ) {
                    autoDetectMeetings.toggle()
                }

                BrandMenuButton(icon: "magnifyingglass", title: "Search", shortcut: "F") {
                    MainAppWindowController.shared.showWindow()
                }
            }
            .padding(.vertical, 4)

            Divider()

            // Transcription progress
            if let progress = audioManager.transcriptionProgress {
                HStack(spacing: 8) {
                    BrandLoadingIndicator(size: .tiny)
                    Text(progress)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider()
            }

            // Footer
            VStack(spacing: 2) {
                BrandMenuButton(icon: "gear", title: "Settings...", shortcut: ",") {
                    MainAppWindowController.shared.openSettings()
                }

                BrandMenuButton(icon: "power", title: "Quit", shortcut: "Q") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(width: 280)
    }
}

// MARK: - Menu Toggle Button

struct MenuToggleButton: View {
    let icon: String
    let title: String
    let isOn: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(isOn ? .green : .secondary)
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 13))

                Spacer()

                // Checkmark when enabled
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isHovered ? Color.brandViolet.opacity(0.1) : Color.clear)
            .cornerRadius(BrandRadius.small)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Recording Status Card

struct RecordingStatusCard: View {
    let isRecording: Bool
    let duration: TimeInterval
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            // Recording indicator - static red dot (no distracting animation)
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                Text(formatDuration(duration))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(Color.red.opacity(0.08))
        .cornerRadius(BrandRadius.medium)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Menu Quick Action Button

struct MenuQuickActionButton: View {
    let icon: String
    let title: String
    let subtitle: String?
    let color: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.1))
                        .frame(width: 36, height: 36)

                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(color)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHovered ? color.opacity(0.08) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - App Delegate

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    let audioManager = AudioCaptureManager.shared

    // Sparkle updater controller
    let updaterController: SPUStandardUpdaterController

    override init() {
        // Initialize Sparkle updater before super.init()
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[App] Launched")

        // Setup debug tools (Cmd+Shift+D to toggle frame inspection)
        #if DEBUG
        DebugKeyboardHandler.shared.setup()

        // Start test API server if enabled
        if TestAPIServer.shouldAutoStart {
            TestAPIServer.shared.start()
        }
        #endif

        setupStatusItem()

        // Initialize dictation manager (Ctrl+Cmd+D hotkey)
        Task { @MainActor in
            DictationManager.shared.initialize()
        }

        // Initialize and show the quick recording pill at bottom center (fn key)
        Task { @MainActor in
            QuickRecordingManager.shared.initialize()
            QuickRecordingPillController.shared.show(manager: QuickRecordingManager.shared)
        }

        // Initialize meeting detector for auto-recording
        Task { @MainActor in
            MeetingDetector.shared.start(audioManager: audioManager)
        }

        // Show onboarding on first launch
        if !hasCompletedOnboarding {
            showOnboarding()
        }

        // Offer CLI installation on first launch (after a short delay)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            CLIInstaller.shared.offerInstallIfNeeded()
        }

        // Update icon when recording state changes
        audioManager.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItemIcon()
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()
    private var lastRecordingState: Bool?

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem?.button else { return }

        updateStatusItemIcon()

        // Custom click handling
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        // Setup popover for right-click menu
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 280, height: 400)
        popover?.behavior = .transient
        popover?.animates = false  // No animation - instant open/close
        popover?.contentViewController = NSHostingController(rootView: MenuBarDropdown(audioManager: audioManager))
    }

    private func updateStatusItemIcon() {
        guard let button = statusItem?.button else { return }

        // Always use waveform icon - simple and consistent
        let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Ambient")
        image?.isTemplate = true
        button.image = image
        button.contentTintColor = nil
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        // Both left and right click show the menu - that's how menu bar apps work
        showPopover(sender)
    }

    private func showPopover(_ sender: NSStatusBarButton) {
        guard let popover = popover else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            // Update popover content
            popover.contentViewController = NSHostingController(rootView: MenuBarDropdown(audioManager: audioManager))
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)

            // Activate app to ensure popover gets focus
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @MainActor
    func toggleRecording() async {
        if audioManager.isRecording {
            print("[App] Left-click: Stopping recording")
            _ = try? await audioManager.stopRecording()
            RecordingIslandController.shared.hide()
        } else {
            print("[App] Left-click: Starting recording")
            try? await audioManager.startRecording()
            RecordingIslandController.shared.show(audioManager: audioManager)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't quit when windows close (it's a menu bar app)
        return false
    }

    private func showOnboarding() {
        OnboardingWizardController.shared.showWindow {
            // Onboarding completed - optionally open main app
            // MainAppWindowController.shared.showWindow()
        }
    }
}

// MARK: - About Window Controller

class AboutWindowController {
    static let shared = AboutWindowController()

    private var windowController: NSWindowController?

    private init() {}

    func showWindow() {
        if let existingWindow = windowController?.window, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let aboutView = AboutView()

        let hostingController = NSHostingController(rootView: aboutView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "About Ambient"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 400, height: 480))
        window.center()
        window.isReleasedWhenClosed = false

        windowController = NSWindowController(window: window)
        windowController?.showWindow(nil)

        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - About View

struct AboutView: View {
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
                .frame(height: 20)

            // App icon
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(LinearGradient(
                        colors: [Color.orange, Color.red],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 100, height: 100)
                    .shadow(color: .orange.opacity(0.3), radius: 20, x: 0, y: 10)

                Image(systemName: "waveform")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(spacing: 8) {
                Text("Ambient")
                    .font(.system(size: 24, weight: .bold))

                Text("Version \(appVersion) (\(buildNumber))")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            Divider()
                .padding(.horizontal, 40)

            Text("Your Mac's memory for everything\nyou say and hear.")
                .font(.system(size: 15))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Spacer()

            // Links
            VStack(spacing: 12) {
                Link(destination: URL(string: "https://ambient.app")!) {
                    HStack {
                        Image(systemName: "globe")
                        Text("Website")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10))
                    }
                    .font(.system(size: 13))
                    .foregroundColor(.brandViolet)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.brandViolet.opacity(0.08))
                    .cornerRadius(8)
                }

                Link(destination: URL(string: "mailto:support@ambient.app")!) {
                    HStack {
                        Image(systemName: "envelope")
                        Text("Contact Support")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10))
                    }
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.brandSurface)
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal, 40)

            Spacer()
                .frame(height: 12)

            // Footer
            VStack(spacing: 4) {
                Text("Built with Swift & SwiftUI")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Text("Transcription powered by OpenAI")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Text("© 2025 Ambient")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()
                .frame(height: 20)
        }
        .frame(width: 400, height: 480)
    }
}

// MARK: - Previews

#Preview("Menu Bar Dropdown") {
    MenuBarDropdown(audioManager: AudioCaptureManager())
}

#Preview("Recording Status Card") {
    RecordingStatusCard(isRecording: true, duration: 125.5, title: "Team Standup")
        .frame(width: 256)
        .padding()
}

#Preview("About View") {
    AboutView()
}
