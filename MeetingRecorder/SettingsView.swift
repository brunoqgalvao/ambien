//
//  SettingsView.swift
//  MeetingRecorder
//
//  Full settings panel with toolbar-style tabs:
//  General, API, Costs, About
//

import SwiftUI
import AVFoundation

// MARK: - Settings Window Controller

class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var windowController: NSWindowController?

    private init() {}

    func showWindow() {
        if let existingWindow = windowController?.window, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = FullSettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 600, height: 520))
        window.center()
        window.isReleasedWhenClosed = false

        windowController = NSWindowController(window: window)
        windowController?.showWindow(nil)

        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Main Settings View

struct FullSettingsView: View {
    @State private var selectedTab: SettingsTab = .general

    enum SettingsTab: String, CaseIterable {
        case general = "General"
        case templates = "Templates"
        case api = "API"
        case costs = "Costs"
        case about = "About"

        var icon: String {
            switch self {
            case .general: return "gear"
            case .templates: return "doc.text.magnifyingglass"
            case .api: return "key.fill"
            case .costs: return "dollarsign.circle.fill"
            case .about: return "info.circle.fill"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with title
            HStack {
                Text("Settings")
                    .font(.brandDisplay(24, weight: .bold))
                Spacer()
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 16)

            // Toolbar-style tab selector
            HStack(spacing: 4) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    SettingsTabButton(
                        tab: tab,
                        isSelected: selectedTab == tab,
                        action: { selectedTab = tab }
                    )
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            Divider()

            // Content
            ScrollView {
                Group {
                    switch selectedTab {
                    case .general:
                        GeneralSettingsTab()
                    case .templates:
                        SummaryTemplatesSettingsTab()
                    case .api:
                        APISettingsTab()
                    case .costs:
                        CostsSettingsTab()
                    case .about:
                        AboutSettingsTab()
                    }
                }
                .frame(maxWidth: 600, alignment: .leading)
                .padding(32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.brandBackground)
    }
}

struct SettingsTabButton: View {
    let tab: FullSettingsView.SettingsTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 20))
                Text(tab.rawValue)
                    .font(.caption)
            }
            .frame(width: 70, height: 50)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .foregroundColor(isSelected ? .accentColor : .secondary)
    }
}

// MARK: - General Tab

struct GeneralSettingsTab: View {
    @AppStorage("recordingShortcut") private var recordingShortcut = "⌘⇧R"
    @AppStorage("dictationShortcut") private var dictationShortcut = "^⌘D"
    @AppStorage("autoDetectMeetings") private var autoDetectMeetings = true
    @AppStorage("autoRecordZoom") private var autoRecordZoom = false
    @AppStorage("autoRecordMeet") private var autoRecordMeet = false
    @AppStorage("autoRecordTeams") private var autoRecordTeams = false
    @AppStorage("autoRecordSlack") private var autoRecordSlack = false
    @AppStorage("autoRecordFaceTime") private var autoRecordFaceTime = false
    @AppStorage("aiCleanupEnabled") private var aiCleanupEnabled = false
    @AppStorage("dictationStyleConfigured") private var dictationStyleConfigured = false
    @AppStorage("dictationAddPunctuation") private var dictationAddPunctuation = true
    @AppStorage("dictationAddParagraphs") private var dictationAddParagraphs = true
    @AppStorage("dictationWritingStyle") private var dictationWritingStyle = "natural"
    @AppStorage("dictationCustomPrompt") private var dictationCustomPrompt = ""
    @AppStorage("appTheme") private var appTheme = "system"

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Recording section
            SettingsSection(title: "Recording") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Start recording shortcut")
                        Spacer()
                        Text(recordingShortcut)
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(6)
                    }

                    Toggle("Auto-detect meetings", isOn: $autoDetectMeetings)

                    if autoDetectMeetings {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Auto-record these apps:")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Group {
                                Toggle("Zoom", isOn: $autoRecordZoom)
                                Toggle("Google Meet", isOn: $autoRecordMeet)
                                Toggle("Microsoft Teams", isOn: $autoRecordTeams)
                                Toggle("Slack Huddles", isOn: $autoRecordSlack)
                                Toggle("FaceTime", isOn: $autoRecordFaceTime)
                            }
                            .toggleStyle(.checkbox)
                            .padding(.leading, 16)
                        }
                    }
                }
            }

            // Dictation section
            SettingsSection(title: "Dictation") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Dictation hotkey")
                        Spacer()
                        Text(dictationShortcut)
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(6)
                    }

                    Toggle("AI cleanup (grammar, filler words)", isOn: Binding(
                        get: { aiCleanupEnabled },
                        set: { newValue in
                            aiCleanupEnabled = newValue
                            if newValue { dictationStyleConfigured = true }
                        }
                    ))

                    if aiCleanupEnabled {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Add punctuation (periods, commas)", isOn: $dictationAddPunctuation)
                                .toggleStyle(.checkbox)
                                .padding(.leading, 16)

                            Toggle("Auto-detect paragraphs", isOn: $dictationAddParagraphs)
                                .toggleStyle(.checkbox)
                                .padding(.leading, 16)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Writing style")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                Picker("", selection: $dictationWritingStyle) {
                                    Text("Natural (as spoken)").tag("natural")
                                    Text("Professional").tag("professional")
                                    Text("Casual").tag("casual")
                                    Text("Technical").tag("technical")
                                }
                                .labelsHidden()
                                .pickerStyle(.radioGroup)
                                .padding(.leading, 16)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Custom instructions (optional)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                TextField("e.g., Always use British spelling", text: $dictationCustomPrompt)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }

            // Appearance section
            SettingsSection(title: "Appearance") {
                Picker("Theme", selection: $appTheme) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            Spacer()
        }
    }
}

// MARK: - API Tab

struct APISettingsTab: View {
    @State private var openAIKey: String = ""
    @State private var showOpenAIKey = false
    @State private var anthropicKey: String = ""
    @State private var showAnthropicKey = false
    @State private var openAIStatus: KeyStatus = .unknown
    @State private var anthropicStatus: KeyStatus = .unknown
    @State private var isValidating = false
    @AppStorage("transcriptionModel") private var transcriptionModel = "gpt-4o-mini-transcribe"

    enum KeyStatus {
        case unknown
        case valid
        case invalid
        case notSet
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // OpenAI section
            SettingsSection(title: "OpenAI") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("API Key")
                            .frame(width: 80, alignment: .leading)

                        HStack {
                            if showOpenAIKey {
                                TextField("sk-...", text: $openAIKey)
                            } else {
                                SecureField("sk-...", text: $openAIKey)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                        Button(action: { showOpenAIKey.toggle() }) {
                            Image(systemName: showOpenAIKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)

                        Button("Save") {
                            saveOpenAIKey()
                        }
                        .buttonStyle(.bordered)
                        .disabled(openAIKey.isEmpty)
                    }

                    HStack {
                        Spacer()
                        KeyStatusIndicator(status: openAIStatus)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Transcription model")
                            .font(.subheadline)

                        Picker("", selection: $transcriptionModel) {
                            Text("gpt-4o-mini-transcribe ($0.003/min)")
                                .tag("gpt-4o-mini-transcribe")
                            Text("whisper-1 ($0.006/min)")
                                .tag("whisper-1")
                        }
                        .labelsHidden()
                        .pickerStyle(.radioGroup)
                    }
                }
            }

            // Anthropic section (for chat)
            SettingsSection(title: "Anthropic (for chat)") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("API Key")
                            .frame(width: 80, alignment: .leading)

                        HStack {
                            if showAnthropicKey {
                                TextField("sk-ant-...", text: $anthropicKey)
                            } else {
                                SecureField("sk-ant-...", text: $anthropicKey)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                        Button(action: { showAnthropicKey.toggle() }) {
                            Image(systemName: showAnthropicKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)

                        Button("Save") {
                            saveAnthropicKey()
                        }
                        .buttonStyle(.bordered)
                        .disabled(anthropicKey.isEmpty)
                    }

                    HStack {
                        Spacer()
                        KeyStatusIndicator(status: anthropicStatus)
                    }
                }
            }

            // Info box
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your API keys are stored locally in your Mac's Keychain.")
                        .font(.caption)
                    Text("They never leave your device.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color.blue.opacity(0.05))
            .cornerRadius(8)

            Spacer()
        }
        .onAppear {
            loadKeys()
        }
    }

    private func loadKeys() {
        if let key = KeychainHelper.read(key: KeychainHelper.openAIKeyName), !key.isEmpty {
            openAIKey = key
            openAIStatus = .valid  // Assume valid if exists
        } else {
            openAIStatus = .notSet
        }

        if let key = KeychainHelper.read(key: "anthropic-api-key"), !key.isEmpty {
            anthropicKey = key
            anthropicStatus = .valid
        } else {
            anthropicStatus = .notSet
        }
    }

    private func saveOpenAIKey() {
        if KeychainHelper.saveOpenAIKey(openAIKey) {
            openAIStatus = .valid
            Task {
                let valid = await TranscriptionService.shared.validateAPIKey()
                await MainActor.run {
                    openAIStatus = valid ? .valid : .invalid
                }
            }
        }
    }

    private func saveAnthropicKey() {
        if KeychainHelper.save(key: "anthropic-api-key", value: anthropicKey) {
            anthropicStatus = .valid
        }
    }
}

struct KeyStatusIndicator: View {
    let status: APISettingsTab.KeyStatus

    var body: some View {
        HStack(spacing: 4) {
            switch status {
            case .valid:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Connected")
                    .font(.caption)
                    .foregroundColor(.green)
            case .invalid:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text("Invalid key")
                    .font(.caption)
                    .foregroundColor(.red)
            case .notSet:
                Circle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 12, height: 12)
                Text("Not set")
                    .font(.caption)
                    .foregroundColor(.secondary)
            case .unknown:
                Circle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 12, height: 12)
            }
        }
    }
}

// MARK: - Costs Tab

struct CostsSettingsTab: View {
    @AppStorage("monthlySpendingAlert") private var monthlySpendingAlert: Double = 10.0
    @AppStorage("spendingAlertEnabled") private var spendingAlertEnabled = true

    // These would normally come from the database
    @State private var totalSpent: Double = 4.32
    @State private var totalHours: Double = 14.4
    @State private var meetingsCount: Int = 28
    @State private var dictationCount: Int = 143
    @State private var chatCount: Int = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // This Month section
            SettingsSection(title: "This Month — January 2025") {
                VStack(spacing: 16) {
                    // Big number
                    Text("$\(String(format: "%.2f", totalSpent))")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("Total spent")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Progress bar
                    VStack(alignment: .leading, spacing: 4) {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.secondary.opacity(0.2))
                                    .frame(height: 8)

                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.accentColor)
                                    .frame(width: geometry.size.width * min(totalHours / 100, 1.0), height: 8)
                            }
                        }
                        .frame(height: 8)

                        Text("\(String(format: "%.1f", totalHours)) hours")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Stats grid
                    HStack(spacing: 32) {
                        StatItem(label: "Meetings transcribed", value: "\(meetingsCount)")
                        StatItem(label: "Dictation uses", value: "\(dictationCount)")
                        StatItem(label: "Chat queries", value: "\(chatCount)")
                    }
                }
                .frame(maxWidth: .infinity)
            }

            // Budget section
            SettingsSection(title: "Budget") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Monthly spending alert")
                        Spacer()
                        TextField("", value: $monthlySpendingAlert, format: .currency(code: "USD"))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                    }

                    Toggle("Notify when reached", isOn: $spendingAlertEnabled)
                }
            }

            // Average costs
            HStack(spacing: 16) {
                Text("Avg cost per meeting: ~$0.15")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("•")
                    .foregroundColor(.secondary)
                Text("Avg cost per dictation: ~$0.01")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}

struct StatItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - About Tab

struct AboutSettingsTab: View {
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    var body: some View {
        VStack(spacing: 24) {
            // App icon and name
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 80, height: 80)
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)
                }

                Text("MeetingRecorder")
                    .font(.title2.weight(.semibold))

                Text("Version \(appVersion) (\(buildNumber))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Links
            VStack(spacing: 12) {
                AboutLink(icon: "globe", title: "Website", url: "https://meetingrecorder.app")
                AboutLink(icon: "doc.text", title: "Documentation", url: "https://meetingrecorder.app/docs")
                AboutLink(icon: "envelope", title: "Contact Support", url: "mailto:support@meetingrecorder.app")
                AboutLink(icon: "star", title: "Rate on App Store", url: "macappstore://")
            }

            Divider()

            // Credits
            VStack(spacing: 4) {
                Text("Built with Swift & SwiftUI")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Transcription powered by OpenAI")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text("© 2025 MeetingRecorder. All rights reserved.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

struct AboutLink: View {
    let icon: String
    let title: String
    let url: String

    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 24)
                Text(title)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Settings Section Helper

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            content()
        }
    }
}

// MARK: - Previews

#Preview("General") {
    GeneralSettingsTab()
        .frame(width: 500)
        .padding()
}

#Preview("API") {
    APISettingsTab()
        .frame(width: 500)
        .padding()
}

#Preview("Costs") {
    CostsSettingsTab()
        .frame(width: 500)
        .padding()
}

#Preview("About") {
    AboutSettingsTab()
        .frame(width: 500)
        .padding()
}

#Preview("Full Settings") {
    FullSettingsView()
}
