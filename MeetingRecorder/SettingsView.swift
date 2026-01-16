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
        case models = "Models"
        case api = "API"
        case costs = "Costs"
        case about = "About"

        var icon: String {
            switch self {
            case .general: return "gear"
            case .templates: return "doc.text.magnifyingglass"
            case .models: return "cpu"
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
                    case .models:
                        ModelsSettingsTab()
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
    @AppStorage("cropLongSilences") private var cropLongSilences = false
    @AppStorage("silenceCropThreshold") private var silenceCropThreshold = 300.0  // 5 min
    @AppStorage("autoStopOnSilence") private var autoStopOnSilence = true
    @AppStorage("silenceWarningThreshold") private var silenceWarningThreshold = 300.0  // 5 min
    @AppStorage("silenceAutoStopThreshold") private var silenceAutoStopThreshold = 600.0  // 10 min
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

                    Divider()
                        .padding(.vertical, 4)

                    Toggle("Crop long silences before transcription", isOn: $cropLongSilences)

                    if cropLongSilences {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Remove silences longer than")
                                    .foregroundColor(.secondary)
                                TextField("", value: $silenceCropThreshold, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 70)
                                Text("seconds")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.leading, 16)

                            Text("Reduces file size and transcription costs for long recordings with breaks.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 16)
                        }
                    }

                    Divider()
                        .padding(.vertical, 4)

                    Toggle("Auto-stop after extended silence", isOn: $autoStopOnSilence)

                    if autoStopOnSilence {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Show warning after")
                                    .foregroundColor(.secondary)
                                TextField("", value: $silenceWarningThreshold, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 70)
                                Text("seconds of silence")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.leading, 16)

                            HStack {
                                Text("Auto-stop after")
                                    .foregroundColor(.secondary)
                                TextField("", value: $silenceAutoStopThreshold, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 70)
                                Text("seconds of silence")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.leading, 16)

                            Text("Prevents recordings from running forever if you forget to stop. You can dismiss the warning to keep recording.")
                                .font(.caption)
                                .foregroundColor(.secondary)
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

// MARK: - API Keys Tab

/// Status of an API key
enum KeyStatus {
    case unknown
    case valid
    case invalid
    case notSet
}

struct APISettingsTab: View {
    @State private var expandedProvider: TranscriptionProvider? = nil
    @State private var providerKeys: [TranscriptionProvider: String] = [:]
    @State private var providerStatuses: [TranscriptionProvider: KeyStatus] = [:]
    @State private var showKeys: [TranscriptionProvider: Bool] = [:]

    // Anthropic (for chat, separate from transcription)
    @State private var anthropicKey: String = ""
    @State private var showAnthropicKey = false
    @State private var anthropicStatus: KeyStatus = .unknown
    @State private var anthropicExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Transcription Providers")
                    .font(.headline)
                Text("Configure API keys for speech-to-text services")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Transcription providers list
            VStack(spacing: 0) {
                ForEach(TranscriptionProvider.allCases) { provider in
                    ProviderRow(
                        provider: provider,
                        isExpanded: expandedProvider == provider,
                        apiKey: Binding(
                            get: { providerKeys[provider] ?? "" },
                            set: { providerKeys[provider] = $0 }
                        ),
                        showKey: Binding(
                            get: { showKeys[provider] ?? false },
                            set: { showKeys[provider] = $0 }
                        ),
                        status: providerStatuses[provider] ?? .unknown,
                        onToggleExpand: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                expandedProvider = expandedProvider == provider ? nil : provider
                            }
                        },
                        onSave: {
                            saveKey(for: provider)
                        },
                        onDelete: {
                            deleteKey(for: provider)
                        }
                    )

                    if provider != TranscriptionProvider.allCases.last {
                        Divider()
                            .padding(.leading, 44)
                    }
                }
            }
            .background(Color(.controlBackgroundColor).opacity(0.5))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )

            // Anthropic section (for chat)
            SettingsSection(title: "Chat Provider") {
                VStack(spacing: 0) {
                    AnthropicProviderRow(
                        isExpanded: anthropicExpanded,
                        apiKey: $anthropicKey,
                        showKey: $showAnthropicKey,
                        status: anthropicStatus,
                        onToggleExpand: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                anthropicExpanded.toggle()
                            }
                        },
                        onSave: saveAnthropicKey,
                        onDelete: deleteAnthropicKey
                    )
                }
                .background(Color(.controlBackgroundColor).opacity(0.5))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            }

            // Info box
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your API keys are stored locally in your Mac's Keychain.")
                        .font(.caption)
                    Text("They never leave your device and are encrypted by macOS.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(12)
            .background(Color.green.opacity(0.05))
            .cornerRadius(8)

            Spacer()
        }
        .onAppear {
            loadAllKeys()
        }
    }

    private func loadAllKeys() {
        // Load transcription provider keys
        for provider in TranscriptionProvider.allCases {
            if let key = KeychainHelper.readKey(for: provider), !key.isEmpty {
                providerKeys[provider] = key
                providerStatuses[provider] = .valid
            } else {
                providerStatuses[provider] = .notSet
            }
            showKeys[provider] = false
        }

        // Load Anthropic key
        if let key = KeychainHelper.readAnthropicKey(), !key.isEmpty {
            anthropicKey = key
            anthropicStatus = .valid
        } else {
            anthropicStatus = .notSet
        }
    }

    private func saveKey(for provider: TranscriptionProvider) {
        guard let key = providerKeys[provider], !key.isEmpty else { return }
        if KeychainHelper.saveKey(for: provider, key: key) {
            providerStatuses[provider] = .valid
        }
    }

    private func deleteKey(for provider: TranscriptionProvider) {
        if KeychainHelper.deleteKey(for: provider) {
            providerKeys[provider] = ""
            providerStatuses[provider] = .notSet
        }
    }

    private func saveAnthropicKey() {
        if KeychainHelper.saveAnthropicKey(anthropicKey) {
            anthropicStatus = .valid
        }
    }

    private func deleteAnthropicKey() {
        if KeychainHelper.deleteAnthropicKey() {
            anthropicKey = ""
            anthropicStatus = .notSet
        }
    }
}

// MARK: - Provider Row

struct ProviderRow: View {
    let provider: TranscriptionProvider
    let isExpanded: Bool
    @Binding var apiKey: String
    @Binding var showKey: Bool
    let status: KeyStatus
    let onToggleExpand: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header row (always visible)
            Button(action: onToggleExpand) {
                HStack(spacing: 12) {
                    // Provider icon
                    ZStack {
                        Circle()
                            .fill(provider.isRecommended ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.1))
                            .frame(width: 32, height: 32)
                        Image(systemName: provider.icon)
                            .font(.system(size: 14))
                            .foregroundColor(provider.isRecommended ? .accentColor : .secondary)
                    }

                    // Provider name and description
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(provider.displayName)
                                .font(.body.weight(.medium))
                                .foregroundColor(.primary)
                            if provider.isRecommended {
                                Text("Recommended")
                                    .font(.caption2.weight(.medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor)
                                    .cornerRadius(4)
                            }
                        }
                        Text(provider.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Status indicator
                    KeyStatusIndicator(status: status)

                    // Expand/collapse chevron
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    // API key field
                    HStack(spacing: 8) {
                        Group {
                            if showKey {
                                TextField("Enter API key...", text: $apiKey)
                            } else {
                                SecureField("Enter API key...", text: $apiKey)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                        Button(action: { showKey.toggle() }) {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help(showKey ? "Hide API key" : "Show API key")
                    }

                    // Action buttons
                    HStack(spacing: 12) {
                        Button("Save") {
                            onSave()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(apiKey.isEmpty)

                        if status == .valid {
                            Button("Remove", role: .destructive) {
                                onDelete()
                            }
                            .buttonStyle(.bordered)
                        }

                        Spacer()

                        // Get API key link
                        if let url = provider.apiKeyURL {
                            Link(destination: url) {
                                HStack(spacing: 4) {
                                    Text("Get API key")
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption)
                                }
                                .font(.caption)
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .padding(.leading, 44)  // Align with text
            }
        }
    }
}

// MARK: - Anthropic Provider Row

struct AnthropicProviderRow: View {
    let isExpanded: Bool
    @Binding var apiKey: String
    @Binding var showKey: Bool
    let status: KeyStatus
    let onToggleExpand: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            Button(action: onToggleExpand) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.1))
                            .frame(width: 32, height: 32)
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.orange)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Anthropic Claude")
                            .font(.body.weight(.medium))
                            .foregroundColor(.primary)
                        Text("Powers the AI chat feature for meeting Q&A")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    KeyStatusIndicator(status: status)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Group {
                            if showKey {
                                TextField("sk-ant-...", text: $apiKey)
                            } else {
                                SecureField("sk-ant-...", text: $apiKey)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                        Button(action: { showKey.toggle() }) {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }

                    HStack(spacing: 12) {
                        Button("Save") {
                            onSave()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(apiKey.isEmpty)

                        if status == .valid {
                            Button("Remove", role: .destructive) {
                                onDelete()
                            }
                            .buttonStyle(.bordered)
                        }

                        Spacer()

                        Link(destination: URL(string: "https://console.anthropic.com/settings/keys")!) {
                            HStack(spacing: 4) {
                                Text("Get API key")
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                            }
                            .font(.caption)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .padding(.leading, 44)
            }
        }
    }
}

// MARK: - Key Status Indicator

struct KeyStatusIndicator: View {
    let status: KeyStatus

    var body: some View {
        HStack(spacing: 4) {
            switch status {
            case .valid:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Configured")
                    .font(.caption)
                    .foregroundColor(.green)
            case .invalid:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text("Invalid")
                    .font(.caption)
                    .foregroundColor(.red)
            case .notSet:
                Circle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 10, height: 10)
                Text("Not set")
                    .font(.caption)
                    .foregroundColor(.secondary)
            case .unknown:
                Circle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 10, height: 10)
            }
        }
    }
}

// MARK: - Models Tab

struct ModelsSettingsTab: View {
    @AppStorage("selectedTranscriptionModel") private var selectedModelId = "openai:gpt-4o-mini-transcribe"

    /// All providers (configured ones shown first)
    private var allProviders: [TranscriptionProvider] {
        TranscriptionProvider.allCases
    }

    /// Check if any provider is configured
    private var hasConfiguredProviders: Bool {
        allProviders.contains { $0.isConfigured }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if hasConfiguredProviders {
                // Header info
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Select the model used for transcription.")
                            .font(.caption)
                        Text("Providers without API keys are shown grayed out.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(Color.blue.opacity(0.05))
                .cornerRadius(8)

                // Provider sections
                ForEach(allProviders) { provider in
                    ProviderModelSection(
                        provider: provider,
                        selectedModelId: $selectedModelId
                    )
                }
            } else {
                // No providers configured
                VStack(spacing: 16) {
                    Image(systemName: "key.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No API Keys Configured")
                        .font(.headline)

                    Text("Configure API keys in the API tab to select a transcription model.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Go to API Settings") {
                        // This would ideally switch tabs, but for now just show a hint
                        NotificationCenter.default.post(name: .switchToAPITab, object: nil)
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 40)
            }

            Spacer()
        }
    }
}

/// A section showing models for a single provider
struct ProviderModelSection: View {
    let provider: TranscriptionProvider
    @Binding var selectedModelId: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Provider header
            HStack {
                Image(systemName: provider.icon)
                    .foregroundColor(provider.isConfigured ? .primary : .secondary)
                Text(provider.displayName)
                    .font(.headline)
                    .foregroundColor(provider.isConfigured ? .primary : .secondary)

                if provider.isRecommended && provider.isConfigured {
                    Text("Recommended")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2))
                        .foregroundColor(.accentColor)
                        .cornerRadius(4)
                }

                Spacer()

                // Limits info with tooltip
                ProviderLimitsView(provider: provider)
            }

            // Models
            VStack(alignment: .leading, spacing: 8) {
                ForEach(provider.models) { model in
                    ModelRadioRow(
                        model: model,
                        isSelected: selectedModelId == model.fullId,
                        isEnabled: provider.isConfigured,
                        onSelect: {
                            selectedModelId = model.fullId
                        }
                    )
                }
            }
            .padding(.leading, 24)
            .opacity(provider.isConfigured ? 1.0 : 0.5)
        }
        .padding(.vertical, 8)
    }
}

/// A single model radio button row
struct ModelRadioRow: View {
    let model: TranscriptionModelOption
    let isSelected: Bool
    let isEnabled: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: {
            if isEnabled {
                onSelect()
            }
        }) {
            HStack {
                // Radio button
                ZStack {
                    Circle()
                        .stroke(isEnabled ? Color.accentColor : Color.secondary, lineWidth: 1.5)
                        .frame(width: 16, height: 16)

                    if isSelected {
                        Circle()
                            .fill(isEnabled ? Color.accentColor : Color.secondary)
                            .frame(width: 8, height: 8)
                    }
                }

                // Model name
                Text(model.displayName)
                    .foregroundColor(isEnabled ? .primary : .secondary)

                Spacer()

                // Price
                Text(model.formattedCost)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(isEnabled ? .secondary : .secondary.opacity(0.5))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

/// Shows provider limits with hover tooltip
struct ProviderLimitsView: View {
    let provider: TranscriptionProvider
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Max: \(provider.maxFileSizeFormatted)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isHovering ? Color.secondary.opacity(0.1) : Color.clear)
        .cornerRadius(4)
        .onHover { hovering in
            isHovering = hovering
        }
        .help("Max file size: \(provider.maxFileSizeFormatted)\nMax duration: \(provider.maxDurationFormatted)")
    }
}

// Notification for switching tabs
extension Notification.Name {
    static let switchToAPITab = Notification.Name("switchToAPITab")
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

#Preview("Models") {
    ModelsSettingsTab()
        .frame(width: 500)
        .padding()
}

#Preview("Full Settings") {
    FullSettingsView()
}
