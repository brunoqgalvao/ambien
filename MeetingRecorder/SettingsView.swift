//
//  SettingsView.swift
//  MeetingRecorder
//
//  Sidebar-based settings with grouped sections:
//  App (General, Recording, Dictation) | Services (AI Providers, Templates) | Audit (Usage) | About
//

import SwiftUI
import AVFoundation
import CoreAudio
import ServiceManagement

// MARK: - Feature Flags

/// Centralized feature flag management
/// Beta features are hidden by default and only visible to beta testers
class FeatureFlags: ObservableObject {
    static let shared = FeatureFlags()

    /// Key for UserDefaults storage
    private let betaTesterKey = "betaTesterEnabled"

    /// Whether the user has opted into beta testing mode
    /// This shows experimental features like cost tracking
    @Published var isBetaTester: Bool {
        didSet {
            UserDefaults.standard.set(isBetaTester, forKey: betaTesterKey)
        }
    }

    private init() {
        self.isBetaTester = UserDefaults.standard.bool(forKey: betaTesterKey)
    }

    // MARK: - Feature Checks

    /// Whether to show cost information in the UI (API logs, meeting cards, etc.)
    var showCosts: Bool { isBetaTester }

    /// Whether to show the Usage section in Settings
    var showUsageSection: Bool { isBetaTester }
}

// MARK: - Launch at Login Manager

class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()

    @Published var isEnabled: Bool = false

    private init() {
        refreshStatus()
    }

    func refreshStatus() {
        if #available(macOS 13.0, *) {
            isEnabled = SMAppService.mainApp.status == .enabled
        } else {
            isEnabled = false
        }
    }

    func setEnabled(_ enabled: Bool) {
        // Optimistic update
        let previousValue = isEnabled
        isEnabled = enabled

        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("[LaunchAtLogin] Failed to \(enabled ? "enable" : "disable"): \(error)")
                // Revert on failure
                self.isEnabled = previousValue
            }
        }
    }
}

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
        window.setContentSize(NSSize(width: 720, height: 560))
        window.minSize = NSSize(width: 640, height: 480)
        window.center()
        window.isReleasedWhenClosed = false

        windowController = NSWindowController(window: window)
        windowController?.showWindow(nil)

        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Settings Navigation

enum SettingsSection: String, CaseIterable, Identifiable {
    // App group
    case general = "General"
    case recording = "Recording"
    case dictation = "Dictation"

    // Services group
    case aiProviders = "AI Providers"
    case templates = "Templates"
    case speakers = "Speakers"

    // Audit group
    case usage = "Usage"

    // Support group
    case about = "About"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gear"
        case .recording: return "waveform"
        case .dictation: return "mic.fill"
        case .aiProviders: return "cpu"
        case .templates: return "doc.text.magnifyingglass"
        case .speakers: return "person.2.fill"
        case .usage: return "chart.bar.fill"
        case .about: return "info.circle.fill"
        }
    }

    var group: SettingsSectionGroup {
        switch self {
        case .general, .recording, .dictation: return .app
        case .aiProviders, .templates, .speakers: return .services
        case .usage: return .audit
        case .about: return .support
        }
    }

    /// Whether this section requires beta tester access
    var requiresBeta: Bool {
        switch self {
        case .usage: return true
        default: return false
        }
    }
}

enum SettingsSectionGroup: String, CaseIterable {
    case app = "App"
    case services = "Services"
    case audit = "Audit"
    case support = "Support"

    var sections: [SettingsSection] {
        SettingsSection.allCases.filter { $0.group == self }
    }
}

// MARK: - Main Settings View

struct FullSettingsView: View {
    @State private var selectedSection: SettingsSection = .general
    @ObservedObject private var featureFlags = FeatureFlags.shared

    /// Sections visible based on feature flags
    private func visibleSections(in group: SettingsSectionGroup) -> [SettingsSection] {
        group.sections.filter { section in
            !section.requiresBeta || featureFlags.isBetaTester
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            SettingsSidebar(
                selectedSection: $selectedSection,
                visibleSections: visibleSections
            )
            .frame(width: 200)

            BrandDivider(vertical: true)

            // Content
            ScrollView {
                settingsContent
                    .frame(maxWidth: 520, alignment: .leading)
                    .padding(32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.brandBackground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var settingsContent: some View {
        switch selectedSection {
        case .general:
            GeneralSettingsContent()
        case .recording:
            RecordingSettingsContent()
        case .dictation:
            DictationSettingsContent()
        case .aiProviders:
            AIProvidersSettingsContent()
        case .templates:
            SummaryTemplatesSettingsTab()
        case .speakers:
            SpeakerProfilesSettingsView()
        case .usage:
            UsageSettingsContent()
        case .about:
            AboutSettingsContent()
        }
    }
}

// MARK: - Settings Sidebar

struct SettingsSidebar: View {
    @Binding var selectedSection: SettingsSection
    let visibleSections: (SettingsSectionGroup) -> [SettingsSection]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("Settings")
                .font(.brandDisplay(20, weight: .bold))
                .foregroundColor(.brandTextPrimary)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 20)

            // Groups
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(SettingsSectionGroup.allCases, id: \.self) { group in
                        let sections = visibleSections(group)
                        if !sections.isEmpty {
                            SettingsSidebarGroup(
                                group: group,
                                sections: sections,
                                selectedSection: $selectedSection
                            )
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.brandSurface.opacity(0.5))
    }
}

struct SettingsSidebarGroup: View {
    let group: SettingsSectionGroup
    let sections: [SettingsSection]
    @Binding var selectedSection: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Group label
            Text(group.rawValue.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.brandTextSecondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)

            // Sections
            ForEach(sections) { section in
                SettingsSidebarItem(
                    section: section,
                    isSelected: selectedSection == section,
                    action: { selectedSection = section }
                )
            }
        }
    }
}

struct SettingsSidebarItem: View {
    let section: SettingsSection
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .white : .brandTextSecondary)
                    .frame(width: 20)

                Text(section.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? .white : .brandTextPrimary)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: BrandRadius.small)
                    .fill(isSelected ? Color.brandViolet : (isHovered ? Color.brandViolet.opacity(0.08) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Audio Device Manager

/// Represents an audio input device (microphone)
struct AudioInputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
    let uid: String

    static func == (lhs: AudioInputDevice, rhs: AudioInputDevice) -> Bool {
        lhs.uid == rhs.uid
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(uid)
    }
}

/// Manager for enumerating and selecting audio input devices
class AudioDeviceManager: ObservableObject {
    static let shared = AudioDeviceManager()

    @Published var inputDevices: [AudioInputDevice] = []
    @Published var selectedDeviceUID: String = ""

    private init() {
        refreshDevices()
        loadSelectedDevice()
    }

    /// Refresh the list of available input devices
    func refreshDevices() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else {
            print("[AudioDeviceManager] Failed to get devices size: \(status)")
            return
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )

        guard status == noErr else {
            print("[AudioDeviceManager] Failed to get devices: \(status)")
            return
        }

        var devices: [AudioInputDevice] = []

        for deviceID in deviceIDs {
            if hasInputChannels(deviceID: deviceID) {
                if let name = getDeviceName(deviceID: deviceID),
                   let uid = getDeviceUID(deviceID: deviceID) {
                    devices.append(AudioInputDevice(id: deviceID, name: name, uid: uid))
                }
            }
        }

        DispatchQueue.main.async {
            self.inputDevices = devices
            if !devices.contains(where: { $0.uid == self.selectedDeviceUID }) {
                self.selectedDeviceUID = ""
            }
        }
    }

    private func hasInputChannels(deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)

        guard status == noErr, dataSize > 0 else { return false }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: 1)
        defer { bufferListPointer.deallocate() }

        let getStatus = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, bufferListPointer)

        guard getStatus == noErr else { return false }

        let bufferList = bufferListPointer.pointee
        return bufferList.mNumberBuffers > 0 && bufferList.mBuffers.mNumberChannels > 0
    }

    private func getDeviceName(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &name)

        guard status == noErr, let deviceName = name else { return nil }
        return deviceName as String
    }

    private func getDeviceUID(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uid: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &uid)

        guard status == noErr, let deviceUID = uid else { return nil }
        return deviceUID as String
    }

    private func loadSelectedDevice() {
        selectedDeviceUID = UserDefaults.standard.string(forKey: "selectedMicrophoneUID") ?? ""
    }

    func selectDevice(uid: String) {
        // Optimistic update
        selectedDeviceUID = uid
        UserDefaults.standard.set(uid, forKey: "selectedMicrophoneUID")

        if !uid.isEmpty, let device = inputDevices.first(where: { $0.uid == uid }) {
            setDefaultInputDevice(deviceID: device.id)
        }
    }

    private func setDefaultInputDevice(deviceID: AudioDeviceID) {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceIDCopy = deviceID
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &deviceIDCopy
        )

        if status != noErr {
            print("[AudioDeviceManager] Failed to set default input device: \(status)")
        }
    }

    var selectedDeviceName: String {
        if selectedDeviceUID.isEmpty {
            return "System Default"
        }
        return inputDevices.first(where: { $0.uid == selectedDeviceUID })?.name ?? "System Default"
    }
}

// MARK: - General Settings Content

struct GeneralSettingsContent: View {
    @AppStorage("appTheme") private var appTheme = "system"
    @ObservedObject private var featureFlags = FeatureFlags.shared
    @ObservedObject private var launchAtLoginManager = LaunchAtLoginManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            // Header
            SettingsSectionHeader(
                title: "General",
                subtitle: "Startup, appearance, and beta settings"
            )

            // Startup
            SettingsGroup(title: "Startup") {
                BrandToggleRow(
                    title: "Launch at login",
                    subtitle: "Start automatically when you log in",
                    isOn: Binding(
                        get: { launchAtLoginManager.isEnabled },
                        set: { launchAtLoginManager.setEnabled($0) }
                    )
                )
            }

            // Appearance
            SettingsGroup(title: "Appearance") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Theme")
                        .font(.system(size: 13))
                        .foregroundColor(.brandTextPrimary)

                    HStack(spacing: 8) {
                        ForEach(["system", "light", "dark"], id: \.self) { theme in
                            BrandThemeButton(
                                title: theme.capitalized,
                                isSelected: appTheme == theme,
                                action: { appTheme = theme }
                            )
                        }
                    }
                }
            }

            // Beta Program
            SettingsGroup(title: "Beta Program") {
                VStack(alignment: .leading, spacing: 8) {
                    BrandToggleRow(
                        title: "Enable beta features",
                        subtitle: nil,
                        isOn: $featureFlags.isBetaTester
                    )

                    Text("Shows experimental features like cost tracking, API logs, and usage statistics.")
                        .font(.caption)
                        .foregroundColor(.brandTextSecondary)
                        .padding(.leading, 2)
                }
            }

            Spacer()
        }
    }
}

// MARK: - Recording Settings Content

struct RecordingSettingsContent: View {
    @AppStorage("recordingShortcut") private var recordingShortcut = "⌘⇧R"
    @AppStorage("autoDetectMeetings") private var autoDetectMeetings = true
    @AppStorage("autoRecordZoom") private var autoRecordZoom = false
    @AppStorage("autoRecordMeet") private var autoRecordMeet = false
    @AppStorage("autoRecordTeams") private var autoRecordTeams = false
    @AppStorage("autoRecordSlack") private var autoRecordSlack = false
    @AppStorage("autoRecordFaceTime") private var autoRecordFaceTime = false
    @AppStorage("autoRecordWhatsApp") private var autoRecordWhatsApp = false
    @AppStorage("cropLongSilences") private var cropLongSilences = false
    @AppStorage("silenceCropThreshold") private var silenceCropThreshold = 300.0
    @AppStorage("autoStopOnSilence") private var autoStopOnSilence = true
    @AppStorage("silenceWarningThreshold") private var silenceWarningThreshold = 300.0
    @AppStorage("silenceAutoStopThreshold") private var silenceAutoStopThreshold = 600.0
    @AppStorage("micBoostLevel") private var micBoostLevel = 10.0
    @AppStorage("debugSavesSeparateAudio") private var debugSavesSeparateAudio = false

    @ObservedObject private var audioDeviceManager = AudioDeviceManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            // Header
            SettingsSectionHeader(
                title: "Recording",
                subtitle: "Audio input, meeting detection, and optimization"
            )

            // Audio Input
            SettingsGroup(title: "Audio Input") {
                VStack(alignment: .leading, spacing: 16) {
                    // Microphone selector
                    HStack {
                        Text("Microphone")
                            .font(.system(size: 13))
                        Spacer()
                        Picker("", selection: Binding(
                            get: { audioDeviceManager.selectedDeviceUID },
                            set: { audioDeviceManager.selectDevice(uid: $0) }
                        )) {
                            Text("System Default").tag("")
                            ForEach(audioDeviceManager.inputDevices) { device in
                                Text(device.name).tag(device.uid)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 200)

                        BrandIconButton(icon: "arrow.clockwise", size: 28, action: {
                            audioDeviceManager.refreshDevices()
                        })
                        .help("Refresh device list")
                    }

                    // Mic boost
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Mic boost level")
                                .font(.system(size: 13))
                            Spacer()
                            Text("\(Int(micBoostLevel))x")
                                .font(.brandMono(13))
                                .foregroundColor(.brandTextSecondary)
                        }
                        HStack(spacing: 8) {
                            Text("1x")
                                .font(.caption)
                                .foregroundColor(.brandTextSecondary)
                            Slider(value: $micBoostLevel, in: 1...20, step: 1)
                                .tint(.brandViolet)
                            Text("20x")
                                .font(.caption)
                                .foregroundColor(.brandTextSecondary)
                        }
                        Text("Increase if your voice is too quiet relative to system audio")
                            .font(.caption)
                            .foregroundColor(.brandTextSecondary)
                    }

                    BrandToggleRow(
                        title: "Save separate audio files",
                        subtitle: "Creates _MIC.m4a and _SYSTEM.m4a for debugging",
                        isOn: $debugSavesSeparateAudio
                    )
                }
            }

            // Shortcuts
            SettingsGroup(title: "Shortcuts") {
                HStack {
                    Text("Start recording")
                        .font(.system(size: 13))
                    Spacer()
                    BrandShortcutDisplay(shortcut: recordingShortcut)
                }
            }

            // Automation
            SettingsGroup(title: "Automation") {
                VStack(alignment: .leading, spacing: 12) {
                    BrandToggleRow(
                        title: "Auto-detect meetings",
                        subtitle: nil,
                        isOn: $autoDetectMeetings
                    )

                    if autoDetectMeetings {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Auto-record these apps:")
                                .font(.caption)
                                .foregroundColor(.brandTextSecondary)
                                .padding(.bottom, 4)

                            // App grid (2 columns)
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 8) {
                                AutoRecordToggle(title: "Zoom", isOn: $autoRecordZoom, app: .zoom)
                                AutoRecordToggle(title: "Google Meet", isOn: $autoRecordMeet, app: .googleMeet)
                                AutoRecordToggle(title: "Teams", isOn: $autoRecordTeams, app: .teams)
                                AutoRecordToggle(title: "Slack", isOn: $autoRecordSlack, app: .slack)
                                AutoRecordToggle(title: "FaceTime", isOn: $autoRecordFaceTime, app: .faceTime)
                                AutoRecordToggle(title: "WhatsApp", isOn: $autoRecordWhatsApp, app: .whatsApp)
                            }
                        }
                        .padding(.leading, 4)
                    }
                }
            }

            // Optimization
            SettingsGroup(title: "Optimization") {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        BrandToggleRow(
                            title: "Crop long silences",
                            subtitle: "Reduces file size and transcription costs",
                            isOn: $cropLongSilences
                        )

                        if cropLongSilences {
                            HStack {
                                Text("Remove silences longer than")
                                    .font(.caption)
                                    .foregroundColor(.brandTextSecondary)
                                TextField("", value: $silenceCropThreshold, format: .number)
                                    .textFieldStyle(.plain)
                                    .font(.brandMono(13))
                                    .frame(width: 60)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.brandSurface)
                                    .cornerRadius(BrandRadius.small)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: BrandRadius.small)
                                            .stroke(Color.brandBorder, lineWidth: 1)
                                    )
                                Text("seconds")
                                    .font(.caption)
                                    .foregroundColor(.brandTextSecondary)
                            }
                            .padding(.leading, 4)
                        }
                    }

                    BrandDivider()

                    VStack(alignment: .leading, spacing: 8) {
                        BrandToggleRow(
                            title: "Auto-stop on silence",
                            subtitle: "Prevents recordings from running forever",
                            isOn: $autoStopOnSilence
                        )

                        if autoStopOnSilence {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Show warning after")
                                        .font(.caption)
                                        .foregroundColor(.brandTextSecondary)
                                    TextField("", value: $silenceWarningThreshold, format: .number)
                                        .textFieldStyle(.plain)
                                        .font(.brandMono(13))
                                        .frame(width: 60)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.brandSurface)
                                        .cornerRadius(BrandRadius.small)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: BrandRadius.small)
                                                .stroke(Color.brandBorder, lineWidth: 1)
                                        )
                                    Text("seconds")
                                        .font(.caption)
                                        .foregroundColor(.brandTextSecondary)
                                }

                                HStack {
                                    Text("Auto-stop after")
                                        .font(.caption)
                                        .foregroundColor(.brandTextSecondary)
                                    TextField("", value: $silenceAutoStopThreshold, format: .number)
                                        .textFieldStyle(.plain)
                                        .font(.brandMono(13))
                                        .frame(width: 60)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.brandSurface)
                                        .cornerRadius(BrandRadius.small)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: BrandRadius.small)
                                                .stroke(Color.brandBorder, lineWidth: 1)
                                        )
                                    Text("seconds")
                                        .font(.caption)
                                        .foregroundColor(.brandTextSecondary)
                                }
                            }
                            .padding(.leading, 4)
                        }
                    }
                }
            }

            Spacer()
        }
    }
}

// MARK: - Dictation Settings Content

struct DictationSettingsContent: View {
    @AppStorage("dictationShortcut") private var dictationShortcut = "^⌘D"
    @AppStorage("aiCleanupEnabled") private var aiCleanupEnabled = false
    @AppStorage("dictationStyleConfigured") private var dictationStyleConfigured = false
    @AppStorage("dictationAddPunctuation") private var dictationAddPunctuation = true
    @AppStorage("dictationAddParagraphs") private var dictationAddParagraphs = true
    @AppStorage("dictationWritingStyle") private var dictationWritingStyle = "natural"
    @AppStorage("dictationCustomPrompt") private var dictationCustomPrompt = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            // Header
            SettingsSectionHeader(
                title: "Dictation",
                subtitle: "Hold-to-speak and AI cleanup settings"
            )

            // Shortcut
            SettingsGroup(title: "Shortcut") {
                HStack {
                    Text("Hold to dictate")
                        .font(.system(size: 13))
                    Spacer()
                    BrandShortcutDisplay(shortcut: dictationShortcut)
                }
            }

            // AI Cleanup
            SettingsGroup(title: "AI Cleanup") {
                VStack(alignment: .leading, spacing: 16) {
                    BrandToggleRow(
                        title: "Enable AI cleanup",
                        subtitle: "Fix grammar, remove filler words",
                        isOn: Binding(
                            get: { aiCleanupEnabled },
                            set: { newValue in
                                aiCleanupEnabled = newValue
                                if newValue { dictationStyleConfigured = true }
                            }
                        )
                    )

                    if aiCleanupEnabled {
                        VStack(alignment: .leading, spacing: 12) {
                            BrandDivider()

                            BrandToggleRow(
                                title: "Add punctuation",
                                subtitle: "Periods, commas, etc.",
                                isOn: $dictationAddPunctuation
                            )

                            BrandToggleRow(
                                title: "Auto-detect paragraphs",
                                subtitle: nil,
                                isOn: $dictationAddParagraphs
                            )

                            BrandDivider()

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Writing style")
                                    .font(.system(size: 13))
                                    .foregroundColor(.brandTextPrimary)

                                Picker("", selection: $dictationWritingStyle) {
                                    Text("Natural (as spoken)").tag("natural")
                                    Text("Professional").tag("professional")
                                    Text("Casual").tag("casual")
                                    Text("Technical").tag("technical")
                                }
                                .labelsHidden()
                                .pickerStyle(.radioGroup)
                            }

                            BrandDivider()

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Custom instructions")
                                    .font(.system(size: 13))
                                    .foregroundColor(.brandTextPrimary)

                                TextField("e.g., Always use British spelling", text: $dictationCustomPrompt)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 13))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color.brandSurface)
                                    .cornerRadius(BrandRadius.small)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: BrandRadius.small)
                                            .stroke(Color.brandBorder, lineWidth: 1)
                                    )
                            }
                        }
                    }
                }
            }

            Spacer()
        }
    }
}

// MARK: - AI Providers Settings Content (Combined API + Models)

struct AIProvidersSettingsContent: View {
    @AppStorage("selectedTranscriptionModel") private var selectedModelId = "openai:gpt-4o-mini-transcribe"

    @State private var expandedProvider: TranscriptionProvider? = nil
    @State private var providerKeys: [TranscriptionProvider: String] = [:]
    @State private var providerStatuses: [TranscriptionProvider: KeyStatus] = [:]
    @State private var showKeys: [TranscriptionProvider: Bool] = [:]

    // Anthropic (for chat)
    @State private var anthropicKey: String = ""
    @State private var showAnthropicKey = false
    @State private var anthropicStatus: KeyStatus = .unknown
    @State private var anthropicExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            // Header
            SettingsSectionHeader(
                title: "AI Providers",
                subtitle: "Configure API keys and select transcription model"
            )

            // Transcription providers
            SettingsGroup(title: "Transcription") {
                VStack(spacing: 0) {
                    ForEach(TranscriptionProvider.allCases) { provider in
                        ProviderConfigRow(
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
                            selectedModelId: $selectedModelId,
                            onToggleExpand: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    expandedProvider = expandedProvider == provider ? nil : provider
                                }
                            },
                            onSave: { saveKey(for: provider) },
                            onDelete: { deleteKey(for: provider) }
                        )

                        if provider != TranscriptionProvider.allCases.last {
                            BrandDivider()
                                .padding(.leading, 44)
                        }
                    }
                }
                .background(Color.brandSurface.opacity(0.5))
                .cornerRadius(BrandRadius.medium)
                .overlay(
                    RoundedRectangle(cornerRadius: BrandRadius.medium)
                        .stroke(Color.brandBorder, lineWidth: 1)
                )
            }

            // Chat provider (Anthropic)
            SettingsGroup(title: "Chat") {
                VStack(spacing: 0) {
                    AnthropicConfigRow(
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
                .background(Color.brandSurface.opacity(0.5))
                .cornerRadius(BrandRadius.medium)
                .overlay(
                    RoundedRectangle(cornerRadius: BrandRadius.medium)
                        .stroke(Color.brandBorder, lineWidth: 1)
                )
            }

            // Security note
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(.brandMint)
                    .font(.system(size: 16))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your API keys are stored securely")
                        .font(.caption)
                        .foregroundColor(.brandTextPrimary)
                    Text("Encrypted in macOS Keychain. Never sent anywhere except the provider.")
                        .font(.caption)
                        .foregroundColor(.brandTextSecondary)
                }
            }
            .padding(14)
            .background(Color.brandMint.opacity(0.08))
            .cornerRadius(BrandRadius.small)

            Spacer()
        }
        .onAppear {
            loadAllKeys()
        }
    }

    private func loadAllKeys() {
        for provider in TranscriptionProvider.allCases {
            if let key = KeychainHelper.readKey(for: provider), !key.isEmpty {
                providerKeys[provider] = key
                providerStatuses[provider] = .valid
            } else {
                providerStatuses[provider] = .notSet
            }
            showKeys[provider] = false
        }

        if let key = KeychainHelper.readAnthropicKey(), !key.isEmpty {
            anthropicKey = key
            anthropicStatus = .valid
        } else {
            anthropicStatus = .notSet
        }
    }

    private func saveKey(for provider: TranscriptionProvider) {
        guard let key = providerKeys[provider], !key.isEmpty else { return }
        // Optimistic update
        providerStatuses[provider] = .valid

        Task {
            let success = KeychainHelper.saveKey(for: provider, key: key)
            if !success {
                await MainActor.run {
                    providerStatuses[provider] = .notSet
                }
            }
        }
    }

    private func deleteKey(for provider: TranscriptionProvider) {
        // Optimistic update
        let previousKey = providerKeys[provider]
        providerKeys[provider] = ""
        providerStatuses[provider] = .notSet

        Task {
            let success = KeychainHelper.deleteKey(for: provider)
            if !success {
                await MainActor.run {
                    providerKeys[provider] = previousKey ?? ""
                    providerStatuses[provider] = .valid
                }
            }
        }
    }

    private func saveAnthropicKey() {
        // Optimistic update
        anthropicStatus = .valid

        Task {
            let success = KeychainHelper.saveAnthropicKey(anthropicKey)
            if !success {
                await MainActor.run {
                    anthropicStatus = .notSet
                }
            }
        }
    }

    private func deleteAnthropicKey() {
        // Optimistic update
        let previousKey = anthropicKey
        anthropicKey = ""
        anthropicStatus = .notSet

        Task {
            let success = KeychainHelper.deleteAnthropicKey()
            if !success {
                await MainActor.run {
                    anthropicKey = previousKey
                    anthropicStatus = .valid
                }
            }
        }
    }
}

// MARK: - Provider Config Row (Combined Key + Model)

struct ProviderConfigRow: View {
    let provider: TranscriptionProvider
    let isExpanded: Bool
    @Binding var apiKey: String
    @Binding var showKey: Bool
    let status: KeyStatus
    @Binding var selectedModelId: String
    let onToggleExpand: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            Button(action: onToggleExpand) {
                HStack(spacing: 12) {
                    // Provider icon
                    ZStack {
                        Circle()
                            .fill(provider.isRecommended ? Color.brandViolet.opacity(0.1) : Color.brandSurface)
                            .frame(width: 32, height: 32)
                        Image(systemName: provider.icon)
                            .font(.system(size: 14))
                            .foregroundColor(provider.isRecommended ? .brandViolet : .brandTextSecondary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(provider.displayName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.brandTextPrimary)
                            if provider.isRecommended {
                                BrandBadge(text: "Recommended", color: .brandViolet, size: .small)
                            }
                        }
                        Text(provider.description)
                            .font(.caption)
                            .foregroundColor(.brandTextSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    ProviderStatusIndicator(status: status)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.brandTextSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovered = hovering
            }
            .background(isHovered && !isExpanded ? Color.brandViolet.opacity(0.03) : Color.clear)

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    // API key field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("API Key")
                            .font(.caption)
                            .foregroundColor(.brandTextSecondary)

                        HStack(spacing: 8) {
                            Group {
                                if showKey {
                                    TextField("Enter API key...", text: $apiKey)
                                } else {
                                    SecureField("Enter API key...", text: $apiKey)
                                }
                            }
                            .textFieldStyle(.plain)
                            .font(.brandMono(13))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.brandSurface)
                            .cornerRadius(BrandRadius.small)
                            .overlay(
                                RoundedRectangle(cornerRadius: BrandRadius.small)
                                    .stroke(Color.brandBorder, lineWidth: 1)
                            )

                            BrandIconButton(
                                icon: showKey ? "eye.slash" : "eye",
                                size: 28,
                                action: { showKey.toggle() }
                            )
                            .help(showKey ? "Hide API key" : "Show API key")
                        }
                    }

                    // Actions
                    HStack(spacing: 10) {
                        BrandPrimaryButton(title: "Save", size: .small, action: onSave)
                            .opacity(apiKey.isEmpty ? 0.5 : 1)
                            .disabled(apiKey.isEmpty)

                        if status == .valid {
                            BrandDestructiveButton(title: "Remove", size: .small, action: onDelete)
                        }

                        Spacer()

                        if let url = provider.apiKeyURL {
                            Link(destination: url) {
                                HStack(spacing: 4) {
                                    Text("Get API key")
                                    Image(systemName: "arrow.up.right")
                                        .font(.caption2)
                                }
                                .font(.caption)
                                .foregroundColor(.brandViolet)
                            }
                        }
                    }

                    // Model selection (only if configured)
                    if status == .valid {
                        BrandDivider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Select model")
                                .font(.caption)
                                .foregroundColor(.brandTextSecondary)

                            ForEach(provider.models) { model in
                                ModelRadioRow(
                                    model: model,
                                    isSelected: selectedModelId == model.fullId,
                                    isEnabled: true,
                                    onSelect: { selectedModelId = model.fullId }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
                .padding(.leading, 32)
            }
        }
    }
}

// MARK: - Anthropic Config Row

struct AnthropicConfigRow: View {
    let isExpanded: Bool
    @Binding var apiKey: String
    @Binding var showKey: Bool
    let status: KeyStatus
    let onToggleExpand: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
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
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.brandTextPrimary)
                        Text("Powers AI chat for meeting Q&A")
                            .font(.caption)
                            .foregroundColor(.brandTextSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    ProviderStatusIndicator(status: status)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.brandTextSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHovered = hovering
            }
            .background(isHovered && !isExpanded ? Color.brandViolet.opacity(0.03) : Color.clear)

            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("API Key")
                            .font(.caption)
                            .foregroundColor(.brandTextSecondary)

                        HStack(spacing: 8) {
                            Group {
                                if showKey {
                                    TextField("sk-ant-...", text: $apiKey)
                                } else {
                                    SecureField("sk-ant-...", text: $apiKey)
                                }
                            }
                            .textFieldStyle(.plain)
                            .font(.brandMono(13))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.brandSurface)
                            .cornerRadius(BrandRadius.small)
                            .overlay(
                                RoundedRectangle(cornerRadius: BrandRadius.small)
                                    .stroke(Color.brandBorder, lineWidth: 1)
                            )

                            BrandIconButton(
                                icon: showKey ? "eye.slash" : "eye",
                                size: 28,
                                action: { showKey.toggle() }
                            )
                        }
                    }

                    HStack(spacing: 10) {
                        BrandPrimaryButton(title: "Save", size: .small, action: onSave)
                            .opacity(apiKey.isEmpty ? 0.5 : 1)
                            .disabled(apiKey.isEmpty)

                        if status == .valid {
                            BrandDestructiveButton(title: "Remove", size: .small, action: onDelete)
                        }

                        Spacer()

                        Link(destination: URL(string: "https://console.anthropic.com/settings/keys")!) {
                            HStack(spacing: 4) {
                                Text("Get API key")
                                Image(systemName: "arrow.up.right")
                                    .font(.caption2)
                            }
                            .font(.caption)
                            .foregroundColor(.brandViolet)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 16)
                .padding(.leading, 32)
            }
        }
    }
}

// MARK: - Provider Status Indicator

enum KeyStatus {
    case unknown
    case valid
    case invalid
    case notSet
}

struct ProviderStatusIndicator: View {
    let status: KeyStatus

    var body: some View {
        HStack(spacing: 5) {
            switch status {
            case .valid:
                BrandStatusDot(status: .success, size: 8)
                Text("Configured")
                    .font(.caption)
                    .foregroundColor(.brandMint)
            case .invalid:
                BrandStatusDot(status: .error, size: 8)
                Text("Invalid")
                    .font(.caption)
                    .foregroundColor(.brandCoral)
            case .notSet:
                BrandStatusDot(status: .inactive, size: 8)
                Text("Not set")
                    .font(.caption)
                    .foregroundColor(.brandTextSecondary)
            case .unknown:
                BrandStatusDot(status: .inactive, size: 8)
            }
        }
    }
}

// MARK: - Model Radio Row

struct ModelRadioRow: View {
    let model: TranscriptionModelOption
    let isSelected: Bool
    let isEnabled: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: {
            if isEnabled { onSelect() }
        }) {
            HStack(spacing: 10) {
                // Radio button
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.brandViolet : Color.brandBorder, lineWidth: 1.5)
                        .frame(width: 16, height: 16)

                    if isSelected {
                        Circle()
                            .fill(Color.brandViolet)
                            .frame(width: 8, height: 8)
                    }
                }

                Text(model.displayName)
                    .font(.system(size: 13))
                    .foregroundColor(.brandTextPrimary)

                Spacer()

                Text(model.formattedCost)
                    .font(.brandMono(12))
                    .foregroundColor(.brandTextSecondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isHovered ? Color.brandViolet.opacity(0.05) : Color.clear)
            .cornerRadius(BrandRadius.small)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Usage Settings Content (Combined Costs + Logs)

struct UsageSettingsContent: View {
    @AppStorage("monthlySpendingAlert") private var monthlySpendingAlert: Double = 10.0
    @AppStorage("spendingAlertEnabled") private var spendingAlertEnabled = true

    @State private var logs: [APICallLog] = []
    @State private var statistics: APICallStatistics = APICallStatistics()
    @State private var selectedTimeRange: TimeRange = .month
    @State private var isLoading = true
    @State private var selectedLog: APICallLog? = nil

    enum TimeRange: String, CaseIterable {
        case today = "Today"
        case week = "Week"
        case month = "Month"
        case all = "All"

        var dateRange: (start: Date, end: Date) {
            let now = Date()
            let calendar = Calendar.current
            switch self {
            case .today:
                return (calendar.startOfDay(for: now), now)
            case .week:
                return (calendar.date(byAdding: .day, value: -7, to: now)!, now)
            case .month:
                return (calendar.date(byAdding: .month, value: -1, to: now)!, now)
            case .all:
                return (Date.distantPast, now)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            // Header
            SettingsSectionHeader(
                title: "Usage",
                subtitle: "Spending, API calls, and usage statistics"
            )

            // Time range picker
            HStack(spacing: 4) {
                ForEach(TimeRange.allCases, id: \.self) { range in
                    BrandTabButton(
                        title: range.rawValue,
                        isSelected: selectedTimeRange == range,
                        action: {
                            selectedTimeRange = range
                            Task { await loadData() }
                        }
                    )
                }
                Spacer()
            }

            // Spending summary
            if statistics.totalCalls > 0 {
                SettingsGroup(title: "Summary") {
                    HStack(spacing: 24) {
                        UsageStatCard(
                            title: "Total Spent",
                            value: statistics.formattedTotalCost,
                            icon: "dollarsign.circle.fill",
                            color: .brandMint
                        )
                        UsageStatCard(
                            title: "API Calls",
                            value: "\(statistics.totalCalls)",
                            icon: "arrow.up.arrow.down.circle.fill",
                            color: .brandViolet
                        )
                        UsageStatCard(
                            title: "Success Rate",
                            value: String(format: "%.0f%%", statistics.successRate),
                            icon: "checkmark.circle.fill",
                            color: statistics.successRate >= 95 ? .brandMint : .brandAmber
                        )
                    }
                }
            }

            // Budget alert
            SettingsGroup(title: "Budget") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Monthly spending alert")
                            .font(.system(size: 13))
                        Spacer()
                        TextField("", value: $monthlySpendingAlert, format: .currency(code: "USD"))
                            .textFieldStyle(.plain)
                            .font(.brandMono(13))
                            .frame(width: 80)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.brandSurface)
                            .cornerRadius(BrandRadius.small)
                            .overlay(
                                RoundedRectangle(cornerRadius: BrandRadius.small)
                                    .stroke(Color.brandBorder, lineWidth: 1)
                            )
                    }

                    BrandToggleRow(
                        title: "Notify when reached",
                        subtitle: nil,
                        isOn: $spendingAlertEnabled
                    )
                }
            }

            // Logs
            SettingsGroup(title: "API Logs") {
                if isLoading {
                    HStack {
                        Spacer()
                        BrandLoadingIndicator(size: .medium)
                        Spacer()
                    }
                    .padding(.vertical, 32)
                } else if logs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundColor(.brandTextSecondary.opacity(0.5))
                        Text("No API calls yet")
                            .font(.caption)
                            .foregroundColor(.brandTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                } else {
                    CompactLogsTable(logs: logs, selectedLog: $selectedLog)
                }
            }

            Spacer()
        }
        .task {
            await loadData()
        }
        .sheet(item: $selectedLog) { log in
            LogDetailSheet(log: log)
        }
    }

    private func loadData() async {
        isLoading = true
        let range = selectedTimeRange.dateRange
        async let fetchedLogs = APICallLogManager.shared.getLogs(from: range.start, to: range.end)
        async let fetchedStats = APICallLogManager.shared.getStatistics(from: range.start, to: range.end)
        logs = await fetchedLogs
        statistics = await fetchedStats
        isLoading = false
    }
}

struct UsageStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
            Text(value)
                .font(.brandDisplay(18, weight: .semibold))
                .foregroundColor(.brandTextPrimary)
            Text(title)
                .font(.caption)
                .foregroundColor(.brandTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.brandSurface)
        .cornerRadius(BrandRadius.small)
    }
}

struct CompactLogsTable: View {
    let logs: [APICallLog]
    @Binding var selectedLog: APICallLog?

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Time").frame(width: 60, alignment: .leading)
                Text("Type").frame(width: 80, alignment: .leading)
                Text("Provider").frame(maxWidth: .infinity, alignment: .leading)
                Text("Cost").frame(width: 50, alignment: .trailing)
            }
            .font(.caption)
            .foregroundColor(.brandTextSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.brandSurface)

            BrandDivider()

            // Rows (max 10)
            ForEach(logs.prefix(10)) { log in
                Button(action: { selectedLog = log }) {
                    HStack {
                        Text(timeFormatter.string(from: log.timestamp))
                            .font(.brandMono(11))
                            .frame(width: 60, alignment: .leading)

                        Text(log.callType.displayName)
                            .font(.caption)
                            .frame(width: 80, alignment: .leading)

                        Text(log.provider)
                            .font(.caption)
                            .foregroundColor(.brandTextSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text(log.formattedCost)
                            .font(.brandMono(11))
                            .frame(width: 50, alignment: .trailing)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if log.id != logs.prefix(10).last?.id {
                    BrandDivider()
                }
            }

            if logs.count > 10 {
                Text("\(logs.count - 10) more...")
                    .font(.caption)
                    .foregroundColor(.brandTextSecondary)
                    .padding(.vertical, 8)
            }
        }
        .background(Color.brandSurface.opacity(0.3))
        .cornerRadius(BrandRadius.small)
        .overlay(
            RoundedRectangle(cornerRadius: BrandRadius.small)
                .stroke(Color.brandBorder, lineWidth: 1)
        )
    }
}

// MARK: - Log Detail Sheet

struct LogDetailSheet: View {
    let log: APICallLog
    @Environment(\.dismiss) private var dismiss

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .long
        return f
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: log.callType.icon)
                            .foregroundColor(.brandViolet)
                        Text(log.callType.displayName)
                            .font(.headline)
                    }
                    Text(dateFormatter.string(from: log.timestamp))
                        .font(.caption)
                        .foregroundColor(.brandTextSecondary)
                }

                Spacer()

                BrandSecondaryButton(title: "Done", size: .small) {
                    dismiss()
                }
            }

            BrandDivider()

            // Details
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Text("Provider").foregroundColor(.brandTextSecondary)
                    Text(log.provider).fontWeight(.medium)
                }
                GridRow {
                    Text("Model").foregroundColor(.brandTextSecondary)
                    Text(log.model).font(.brandMono(13))
                }
                GridRow {
                    Text("Duration").foregroundColor(.brandTextSecondary)
                    Text(log.formattedDuration)
                }
                GridRow {
                    Text("Cost").foregroundColor(.brandTextSecondary)
                    Text(log.formattedCost)
                }
            }
            .font(.system(size: 13))

            if let errorMessage = log.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Error")
                        .font(.caption)
                        .foregroundColor(.brandCoral)
                    Text(errorMessage)
                        .font(.brandMono(11))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.brandCoral.opacity(0.1))
                        .cornerRadius(BrandRadius.small)
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 400, height: 350)
        .background(Color.brandBackground)
    }
}

// MARK: - About Settings Content

struct AboutSettingsContent: View {
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"

    var body: some View {
        VStack(spacing: 32) {
            // App info
            VStack(spacing: 12) {
                BrandLogo(size: 48, showText: false)

                Text("Ambient")
                    .font(.brandDisplay(20, weight: .bold))
                    .foregroundColor(.brandTextPrimary)

                Text("Version \(appVersion) (\(buildNumber))")
                    .font(.caption)
                    .foregroundColor(.brandTextSecondary)
            }
            .padding(.top, 20)

            BrandDivider()

            // Links
            VStack(spacing: 8) {
                AboutLinkRow(icon: "globe", title: "Website", url: "https://ambient.app")
                AboutLinkRow(icon: "doc.text", title: "Documentation", url: "https://ambient.app/docs")
                AboutLinkRow(icon: "envelope", title: "Contact Support", url: "mailto:support@ambient.app")
                AboutLinkRow(icon: "star", title: "Rate on App Store", url: "macappstore://")
            }

            BrandDivider()

            // Credits
            VStack(spacing: 4) {
                Text("Built with Swift & SwiftUI")
                    .font(.caption)
                    .foregroundColor(.brandTextSecondary)
                Text("Transcription powered by OpenAI")
                    .font(.caption)
                    .foregroundColor(.brandTextSecondary)
            }

            Spacer()

            Text("© 2025 Ambient. All rights reserved.")
                .font(.caption2)
                .foregroundColor(.brandTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct AboutLinkRow: View {
    let icon: String
    let title: String
    let url: String

    @State private var isHovered = false

    var body: some View {
        Link(destination: URL(string: url)!) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.brandViolet)
                    .frame(width: 24)
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(.brandTextPrimary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundColor(.brandTextSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isHovered ? Color.brandViolet.opacity(0.05) : Color.brandSurface)
            .cornerRadius(BrandRadius.small)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Reusable Components

struct SettingsSectionHeader: View {
    let title: String
    let subtitle: String?

    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.brandDisplay(20, weight: .bold))
                .foregroundColor(.brandTextPrimary)
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.brandTextSecondary)
            }
        }
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.brandTextSecondary)
                .textCase(.uppercase)

            content()
        }
    }
}

struct BrandToggleRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(.brandTextPrimary)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.brandTextSecondary)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(.brandViolet)
    }
}

struct BrandShortcutDisplay: View {
    let shortcut: String

    var body: some View {
        Text(shortcut)
            .font(.brandMono(13))
            .foregroundColor(.brandTextPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.brandSurface)
            .cornerRadius(BrandRadius.small)
            .overlay(
                RoundedRectangle(cornerRadius: BrandRadius.small)
                    .stroke(Color.brandBorder, lineWidth: 1)
            )
    }
}

struct BrandThemeButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .foregroundColor(isSelected ? .white : .brandTextPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.brandViolet : (isHovered ? Color.brandViolet.opacity(0.1) : Color.brandSurface))
                .cornerRadius(BrandRadius.small)
                .overlay(
                    RoundedRectangle(cornerRadius: BrandRadius.small)
                        .stroke(isSelected ? Color.clear : Color.brandBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Auto-Record Toggle with Discard Stats

struct AutoRecordToggle: View {
    let title: String
    @Binding var isOn: Bool
    let app: MeetingApp

    @ObservedObject private var statsManager = AutoRuleStatsManager.shared

    private var stat: AutoRuleStat? {
        statsManager.getStat(for: app)
    }

    private var wasAutoDisabled: Bool {
        stat?.isAutoDisabled == true
    }

    private var discardCount: Int {
        stat?.consecutiveDiscards ?? 0
    }

    var body: some View {
        HStack {
            Toggle(isOn: Binding(
                get: { isOn },
                set: { newValue in
                    // Optimistic update
                    isOn = newValue
                    if newValue && wasAutoDisabled {
                        statsManager.reEnableRule(for: app)
                    }
                }
            )) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(.brandTextPrimary)
            }
            .toggleStyle(.checkbox)

            Spacer()

            if wasAutoDisabled {
                Button(action: {
                    isOn = true
                    statsManager.reEnableRule(for: app)
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                        Text("Auto-off")
                            .font(.caption2)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.brandAmber)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Auto-disabled after 5 discards. Click to re-enable.")
            } else if discardCount >= 3 {
                HStack(spacing: 3) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                    Text("\(5 - discardCount) left")
                        .font(.caption2)
                }
                .foregroundColor(.brandTextSecondary)
                .help("Discarded \(discardCount) times. \(5 - discardCount) more will auto-disable.")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.brandSurface.opacity(0.5))
        .cornerRadius(BrandRadius.small)
    }
}

// MARK: - Notification for switching tabs

extension Notification.Name {
    static let switchToAPITab = Notification.Name("switchToAPITab")
}

// MARK: - Previews

#Preview("Full Settings") {
    FullSettingsView()
        .frame(width: 720, height: 560)
}

#Preview("General") {
    GeneralSettingsContent()
        .frame(width: 500)
        .padding()
        .background(Color.brandBackground)
}

#Preview("Recording") {
    RecordingSettingsContent()
        .frame(width: 500)
        .padding()
        .background(Color.brandBackground)
}

#Preview("AI Providers") {
    AIProvidersSettingsContent()
        .frame(width: 500)
        .padding()
        .background(Color.brandBackground)
}
