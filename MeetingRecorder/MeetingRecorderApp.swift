//
//  MeetingRecorderApp.swift
//  MeetingRecorder
//
//  Main app entry point - Menu bar app with audio recording and dictation
//

import SwiftUI
import AppKit

@main
struct MeetingRecorderApp: App {
    @StateObject private var audioManager = AudioCaptureManager()
    @StateObject private var validationManager = ValidationManager()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Initialize database on app launch
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
        MenuBarExtra {
            ContentView(audioManager: audioManager, validationManager: validationManager)
        } label: {
            Label("MeetingRecorder", systemImage: menuBarIcon)
        }
        .menuBarExtraStyle(.window)
        .commands {
            // Global keyboard shortcuts
            CommandGroup(replacing: .newItem) {
                Button("Open Calendar") {
                    CalendarWindowController.shared.showWindow()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Search Meetings...") {
                    CalendarWindowController.shared.showWindow()
                }
                .keyboardShortcut("f", modifiers: .command)
            }

            // About menu
            CommandGroup(replacing: .appInfo) {
                Button("About MeetingRecorder") {
                    AboutWindowController.shared.showWindow()
                }
            }

            // Settings menu
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    SettingsWindowController.shared.showWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

    /// Menu bar icon changes based on state
    private var menuBarIcon: String {
        if audioManager.isRecording {
            return "record.circle.fill"
        } else {
            return "mic.circle"
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    private var onboardingWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("[App] Launched")

        // Initialize dictation manager
        Task { @MainActor in
            DictationManager.shared.initialize()
        }

        // Show onboarding on first launch
        if !hasCompletedOnboarding {
            showOnboarding()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't quit when calendar window closes (it's a menu bar app)
        return false
    }

    private func showOnboarding() {
        let onboardingView = OnboardingView {
            // Onboarding completed
            self.onboardingWindowController?.close()
            self.onboardingWindowController = nil
        }

        let hostingController = NSHostingController(rootView: onboardingView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Welcome to MeetingRecorder"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 500, height: 450))
        window.center()
        window.isReleasedWhenClosed = false

        onboardingWindowController = NSWindowController(window: window)
        onboardingWindowController?.showWindow(nil)

        NSApp.activate(ignoringOtherApps: true)
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
            .frame(width: 350, height: 400)
            .padding()

        let hostingController = NSHostingController(rootView: aboutView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "About MeetingRecorder"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 350, height: 400))
        window.center()
        window.isReleasedWhenClosed = false

        windowController = NSWindowController(window: window)
        windowController?.showWindow(nil)

        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Simple About View (fallback)

struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("MeetingRecorder")
                .font(.title)
                .fontWeight(.bold)

            Text("Version 1.0.0")
                .foregroundColor(.secondary)

            Divider()

            Text("Your Mac's memory for everything you say and hear.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Spacer()

            Text("© 2025")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

#Preview {
    AboutView()
}
