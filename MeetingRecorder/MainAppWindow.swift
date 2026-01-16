//
//  MainAppWindow.swift
//  MeetingRecorder
//
//  Main application window with sidebar navigation
//  Meetings, Transcriptions, Calendar, Settings
//

import SwiftUI
import AppKit

// MARK: - Notification Names

extension Notification.Name {
    static let navigateToSettings = Notification.Name("navigateToSettings")
    static let navigateToMeeting = Notification.Name("navigateToMeeting")
    static let meetingsDidChange = Notification.Name("meetingsDidChange")
}

// MARK: - Main App Window Controller

class MainAppWindowController {
    static let shared = MainAppWindowController()

    private var windowController: NSWindowController?

    /// Published meeting ID to select when window opens
    @Published var pendingMeetingSelection: UUID?

    private init() {}

    func showWindow() {
        if let existingWindow = windowController?.window, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let mainView = MainAppView()
        let hostingController = NSHostingController(rootView: mainView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "MeetingRecorder"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.setContentSize(NSSize(width: 1100, height: 750)) // Slightly larger default
        window.minSize = NSSize(width: 900, height: 600)
        window.center()
        window.isReleasedWhenClosed = false
        window.toolbar = NSToolbar() // Empty toolbar to extend content to top
        window.toolbarStyle = .unified

        windowController = NSWindowController(window: window)
        windowController?.showWindow(nil)

        NSApp.activate(ignoringOtherApps: true)
    }

    func closeWindow() {
        windowController?.close()
    }

    /// Show the window and navigate to a specific meeting
    func showMeeting(id: UUID) {
        pendingMeetingSelection = id
        showWindow()
        // Post notification to navigate (works even if window already open)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .navigateToMeeting, object: id)
        }
    }
    
    func openSettings() {
        showWindow()
        // Post notification to switch to settings tab
        NotificationCenter.default.post(name: .navigateToSettings, object: nil)
    }
}

// MARK: - Navigation

enum NavigationItem: String, CaseIterable, Identifiable {
    case home = "Home"
    case calendar = "Calendar"
    case meetings = "Meetings"
    case dictations = "Dictations"
    case templates = "Templates"
    case analytics = "Analytics"
    case settings = "Settings"

    var id: String { rawValue }
}

// MARK: - Main App View

struct MainAppView: View {
    @State private var selectedItem: NavigationItem = .home
    @State private var searchText = ""
    @StateObject private var viewModel = MainAppViewModel()

    /// Selected meeting ID passed from window controller
    @State private var selectedMeetingId: UUID?

    var body: some View {
        HStack(spacing: 0) {
            // New 60px Sidebar
            SidebarView(
                selectedItem: $selectedItem,
                viewModel: viewModel,
                onRecord: { viewModel.toggleRecording() },
                onSettings: { selectedItem = .settings }
            )

            // Content
            DetailView(selectedItem: $selectedItem, viewModel: viewModel, searchText: $searchText, selectedMeetingId: $selectedMeetingId)
        }
        .ignoresSafeArea()
        .frame(minWidth: 900, minHeight: 600)
        .background(Color.brandBackground.ignoresSafeArea())
        .task {
            await viewModel.loadData()
        }
        .onAppear {
            // Check for pending meeting selection
            if let pendingId = MainAppWindowController.shared.pendingMeetingSelection {
                selectedItem = .meetings
                selectedMeetingId = pendingId
                MainAppWindowController.shared.pendingMeetingSelection = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToSettings)) { _ in
            selectedItem = .settings
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToMeeting)) { notification in
            if let meetingId = notification.object as? UUID {
                selectedItem = .meetings
                selectedMeetingId = meetingId
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .meetingsDidChange)) { _ in
            Task {
                await viewModel.loadData()
            }
        }
    }
}

// MARK: - Detail View

struct DetailView: View {
    @Binding var selectedItem: NavigationItem
    @ObservedObject var viewModel: MainAppViewModel
    @Binding var searchText: String
    @Binding var selectedMeetingId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // Content
            switch selectedItem {
            case .home:
                HomeView(viewModel: viewModel, selectedTab: $selectedItem)
            
            case .calendar:
                VStack(spacing: 0) {
                    DetailToolbar(title: "Calendar", searchText: $searchText)
                    CalendarContentView(viewModel: viewModel) { meeting in
                        // Navigate to Meetings tab with this meeting selected
                        selectedMeetingId = meeting.id
                        selectedItem = .meetings
                    }
                }
                
            case .meetings:
                VStack(spacing: 0) {
                    DetailToolbar(title: "Meetings", searchText: $searchText)
                    MeetingsListView(viewModel: viewModel, searchText: searchText, initialMeetingId: $selectedMeetingId)
                }
                
            case .dictations:
                VStack(spacing: 0) {
                    DetailToolbar(title: "Dictations", searchText: $searchText)
                    DictationsListView(viewModel: viewModel, searchText: searchText)
                }

            case .templates:
                TemplatesView()

            case .analytics:
                AnalyticsView(viewModel: viewModel)

            case .settings:
                FullSettingsView()
            }
        }
    }
}

// MARK: - Detail Toolbar

struct DetailToolbar: View {
    let title: String
    @Binding var searchText: String
    
    var body: some View {
        HStack(spacing: 16) {
            // Title
            Text(title)
                .font(.brandDisplay(20, weight: .semibold))
                .foregroundColor(.brandTextPrimary)

            Spacer()

            // Search
            BrandSearchField(placeholder: "Search...", text: $searchText)
                .frame(width: 220)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color.brandBackground)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.brandBorder),
            alignment: .bottom
        )
    }
}

// MARK: - Legacy Views Support (MeetingsListView, etc.)

// MARK: - Dictations List View

struct DictationsListView: View {
    @ObservedObject var viewModel: MainAppViewModel
    let searchText: String
    @StateObject private var storage = QuickRecordingStorage.shared
    @State private var selectedDictation: QuickRecording?

    private var filteredDictations: [QuickRecording] {
        if searchText.isEmpty {
            return storage.recordings
        }
        return storage.recordings.filter { dictation in
            dictation.text.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        HSplitView {
            // List
            ScrollView {
                if filteredDictations.isEmpty {
                    EmptyDetailView(
                        icon: "mic",
                        title: "No dictations yet",
                        subtitle: "Press ⌃⌘D to start a quick dictation"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredDictations) { dictation in
                            DictationRow(
                                dictation: dictation,
                                isSelected: selectedDictation?.id == dictation.id,
                                onSelect: {
                                    selectedDictation = dictation
                                }
                            )
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .frame(minWidth: 300, idealWidth: 350)
            .background(Color.white)

            // Detail
            if let dictation = selectedDictation {
                DictationDetailView(dictation: dictation)
            } else {
                EmptyDetailView(
                    icon: "mic",
                    title: "Select a dictation",
                    subtitle: "Choose a dictation from the list to view details"
                )
            }
        }
        .onAppear {
            storage.loadRecordings()
        }
    }
}

// MARK: - Dictation Row

struct DictationRow: View {
    let dictation: QuickRecording
    let isSelected: Bool
    var onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: "mic.fill")
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .white : .brandViolet)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(isSelected ? Color.brandViolet : Color.brandViolet.opacity(0.1))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(dictation.text)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(2)
                        .foregroundColor(isSelected ? .white : .primary)

                    HStack(spacing: 8) {
                        Text(dictation.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 11))
                            .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)

                        if dictation.durationSeconds > 0 {
                            Text(String(format: "%.1fs", dictation.durationSeconds))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                        }
                    }
                }

                Spacer()

                // Chevron
                if isHovered || isSelected {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary.opacity(0.5))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.brandViolet : (isHovered ? Color.brandViolet.opacity(0.05) : Color.clear))
            )
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(dictation.text, forType: .string)
            } label: {
                Label("Copy Text", systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive) {
                QuickRecordingStorage.shared.delete(dictation)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Dictation Detail View

struct DictationDetailView: View {
    let dictation: QuickRecording

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.brandViolet)

                        Text("Dictation")
                            .font(.brandDisplay(24, weight: .bold))

                        Spacer()

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(dictation.text, forType: .string)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.system(size: 13))
                        }
                        .buttonStyle(.bordered)
                    }

                    HStack(spacing: 16) {
                        Label(dictation.createdAt.formatted(date: .long, time: .shortened), systemImage: "calendar")
                        if dictation.durationSeconds > 0 {
                            Label(String(format: "%.1f seconds", dictation.durationSeconds), systemImage: "clock")
                        }
                    }
                    .font(.brandMono(13))
                    .foregroundColor(.secondary)
                }

                Divider()

                // Content
                VStack(alignment: .leading, spacing: 12) {
                    Text("Transcription")
                        .font(.brandDisplay(16, weight: .semibold))

                    Text(dictation.text)
                        .font(.brandSerif(16))
                        .lineSpacing(6)
                        .textSelection(.enabled)
                }
            }
            .padding(32)
        }
        .background(Color.brandBackground)
    }
}

// MARK: - Meetings List View

struct MeetingsListView: View {
    @ObservedObject var viewModel: MainAppViewModel
    let searchText: String
    @Binding var initialMeetingId: UUID?
    @State private var selectedMeeting: Meeting?
    @State private var meetingToRename: Meeting?
    @State private var newTitle: String = ""

    private var filteredMeetings: [Meeting] {
        let meetings = viewModel.meetings.filter { meeting in
            return meeting.sourceApp != "Dictation"
        }
        if searchText.isEmpty {
            return meetings
        }
        return meetings.filter { meeting in
            meeting.title.localizedCaseInsensitiveContains(searchText) ||
            (meeting.transcript?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        HSplitView {
            // List
            ScrollView {
                if filteredMeetings.isEmpty {
                    EmptyDetailView(
                        icon: "waveform",
                        title: searchText.isEmpty ? "No meetings yet" : "No matches",
                        subtitle: searchText.isEmpty ? "Start recording to capture your meetings" : "Try a different search term"
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredMeetings) { meeting in
                            MainWindowMeetingRow(
                                meeting: meeting,
                                isSelected: selectedMeeting?.id == meeting.id,
                                onSelect: {
                                    selectedMeeting = meeting
                                },
                                onRename: {
                                    meetingToRename = meeting
                                    newTitle = meeting.title
                                }
                            )
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .frame(minWidth: 300, idealWidth: 350)
            .background(Color.white)

            // Detail - use MeetingDetailView with full Amie-style features
            if let meeting = selectedMeeting {
                MeetingDetailView(
                    meeting: meeting,
                    showBackButton: false
                )
                .id(meeting.id) // Force view recreation on selection change
            } else {
                EmptyDetailView(
                    icon: "waveform",
                    title: "Select a meeting",
                    subtitle: "Choose a meeting from the list to view details"
                )
            }
        }
        .sheet(item: $meetingToRename) { meeting in
            RenameMeetingSheet(
                meeting: meeting,
                newTitle: $newTitle,
                onSave: { updatedTitle in
                    Task {
                        await renameMeeting(meeting, to: updatedTitle)
                    }
                },
                onCancel: {
                    meetingToRename = nil
                }
            )
        }
        .onChange(of: initialMeetingId) { _, newId in
            if let id = newId, let meeting = filteredMeetings.first(where: { $0.id == id }) {
                selectedMeeting = meeting
                initialMeetingId = nil
            }
        }
        .onAppear {
            if let id = initialMeetingId, let meeting = filteredMeetings.first(where: { $0.id == id }) {
                selectedMeeting = meeting
                initialMeetingId = nil
            }
        }
        // Refresh selectedMeeting when viewModel.meetings changes (e.g., after transcription)
        .onChange(of: viewModel.meetings) { _, newMeetings in
            if let currentId = selectedMeeting?.id,
               let updated = newMeetings.first(where: { $0.id == currentId }) {
                selectedMeeting = updated
            }
        }
    }

    private func renameMeeting(_ meeting: Meeting, to newTitle: String) async {
        var updated = meeting
        updated.title = newTitle
        do {
            try await DatabaseManager.shared.update(updated)
            if selectedMeeting?.id == meeting.id {
                selectedMeeting = updated
            }
            await viewModel.loadData()
        } catch {
            print("[MeetingsListView] Failed to rename: \(error)")
        }
        meetingToRename = nil
    }
}

// MARK: - Rename Meeting Sheet

struct RenameMeetingSheet: View {
    let meeting: Meeting
    @Binding var newTitle: String
    let onSave: (String) -> Void
    let onCancel: () -> Void
    @FocusState private var isFocused: Bool

    private var isValidTitle: Bool {
        !newTitle.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Rename Meeting")
                .font(.headline)

            TextField("Meeting title", text: $newTitle)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit {
                    if isValidTitle {
                        onSave(newTitle)
                    }
                }

            HStack(spacing: 12) {
                SecondaryActionButton(title: "Cancel", action: onCancel)
                    .keyboardShortcut(.escape)

                PrimaryActionButton(
                    title: "Save",
                    isDisabled: !isValidTitle,
                    action: { onSave(newTitle) }
                )
                .keyboardShortcut(.return)
            }
        }
        .padding(24)
        .frame(width: 350)
        .onAppear {
            isFocused = true
        }
    }
}

// MARK: - Custom Action Buttons (On-Brand)

/// Primary action button - filled accent color, used for Save/Confirm actions
struct PrimaryActionButton: View {
    let title: String
    var icon: String? = nil
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.subheadline.weight(.medium))
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(backgroundColor)
            )
            .opacity(isDisabled ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .scaleEffect(isPressed ? 0.97 : 1)
    }

    private var backgroundColor: Color {
        if isDisabled {
            return Color.brandViolet.opacity(0.6)
        } else if isHovered {
            return Color.brandViolet.opacity(0.85)
        } else {
            return Color.brandViolet
        }
    }
}

/// Secondary action button - outlined/subtle, used for Cancel/Back actions
struct SecondaryActionButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.subheadline.weight(.medium))
                }
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            .foregroundColor(.primary.opacity(0.8))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.brandCreamDark : Color.brandCreamDark.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

/// Destructive action button - red tinted, used for Delete actions
struct DestructiveActionButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.subheadline.weight(.medium))
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.red.opacity(0.85) : Color.red)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Main Window Meeting Row

struct MainWindowMeetingRow: View {
    let meeting: Meeting
    let isSelected: Bool
    var onSelect: () -> Void
    var onRename: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Status indicator
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .foregroundColor(isSelected ? .white : .primary)

                    HStack(spacing: 8) {
                        Text(meeting.startTime.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 11))
                            .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)

                        if meeting.duration > 0 {
                            Text(formatDuration(meeting.duration))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                        }
                    }
                }

                Spacer()

                // Chevron
                if isHovered || isSelected {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary.opacity(0.5))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.brandViolet : (isHovered ? Color.brandViolet.opacity(0.05) : Color.clear))
            )
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button {
                onRename?()
            } label: {
                Label("Rename...", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                // TODO: Delete meeting
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var statusColor: Color {
        switch meeting.status {
        case .ready: return .green
        case .transcribing, .pendingTranscription: return .orange
        case .recording: return .red
        case .failed: return .red.opacity(0.6)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Meeting Detail Content

struct MeetingDetailContentView: View {
    @State var meeting: Meeting
    var onRename: (() -> Void)? = nil
    var onTitleChanged: ((Meeting) -> Void)? = nil

    @State private var isEditingTitle = false
    @State private var editedTitle = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header with editable title
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        if isEditingTitle {
                            TextField("Meeting title", text: $editedTitle)
                                .font(.brandDisplay(24, weight: .bold))
                                .textFieldStyle(.plain)
                                .onSubmit {
                                    saveTitle()
                                }
                                .onExitCommand {
                                    isEditingTitle = false
                                }

                            Button("Save") {
                                saveTitle()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                            Button("Cancel") {
                                isEditingTitle = false
                            }
                            .controlSize(.small)
                        } else {
                            Text(meeting.title)
                                .font(.brandDisplay(24, weight: .bold))

                            Button {
                                editedTitle = meeting.title
                                isEditingTitle = true
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Rename meeting")
                        }

                        Spacer()
                    }

                    HStack(spacing: 16) {
                        Label(meeting.startTime.formatted(date: .long, time: .shortened), systemImage: "calendar")
                        Label(formatDuration(meeting.duration), systemImage: "clock")
                        if let source = meeting.sourceApp {
                            Label(source, systemImage: "app")
                        }
                    }
                    .font(.brandMono(13))
                    .foregroundColor(.secondary)
                }

                Divider()

                // Transcript
                if let transcript = meeting.transcript {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Transcript")
                            .font(.brandDisplay(16, weight: .semibold))

                        Text(transcript)
                            .font(.brandSerif(16))
                            .lineSpacing(6)
                            .textSelection(.enabled)
                    }
                } else if meeting.status == .transcribing || meeting.status == .pendingTranscription {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Transcribing...")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                } else if meeting.status == .failed {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text(meeting.errorMessage ?? "Transcription failed")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(32)
        }
        .background(Color.brandBackground)
    }

    private func saveTitle() {
        let trimmed = editedTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            isEditingTitle = false
            return
        }

        Task {
            var updated = meeting
            updated.title = trimmed
            do {
                try await DatabaseManager.shared.update(updated)
                meeting = updated
                onTitleChanged?(updated)
            } catch {
                print("[MeetingDetailContentView] Failed to save title: \(error)")
            }
        }
        isEditingTitle = false
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Calendar Content View

struct CalendarContentView: View {
    @ObservedObject var viewModel: MainAppViewModel
    var onMeetingSelect: ((Meeting) -> Void)? = nil
    @State private var selectedDate = Date()
    @State private var displayedMonth = Date()

    private var calendar: Calendar { Calendar.current }

    // Get days that have meetings
    private var daysWithMeetings: Set<Date> {
        var days = Set<Date>()
        for meeting in viewModel.meetings {
            let startOfDay = calendar.startOfDay(for: meeting.startTime)
            days.insert(startOfDay)
        }
        return days
    }

    var body: some View {
        HStack(spacing: 0) {
            // Custom Calendar
            VStack(spacing: 0) {
                CustomCalendarView(
                    selectedDate: $selectedDate,
                    displayedMonth: $displayedMonth,
                    daysWithMeetings: daysWithMeetings
                )
                .padding(20)

                Spacer()
            }
            .frame(width: 300)
            .background(Color.white)
            .overlay(
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(Color.brandBorder),
                alignment: .trailing
            )

            // Meetings for selected date
            VStack(alignment: .leading, spacing: 16) {
                Text(selectedDate.formatted(date: .complete, time: .omitted))
                    .font(.brandDisplay(18, weight: .semibold))
                    .padding(.horizontal, 24)
                    .padding(.top, 24)

                let meetingsForDate = viewModel.meetings.filter { Calendar.current.isDate($0.startTime, inSameDayAs: selectedDate) }

                if meetingsForDate.isEmpty {
                    EmptyDetailView(
                        icon: "calendar.badge.exclamationmark",
                        title: "No meetings",
                        subtitle: "No meetings recorded on this date"
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(meetingsForDate) { meeting in
                                CalendarMeetingCard(meeting: meeting) {
                                    onMeetingSelect?(meeting)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
            }
            .background(Color.brandBackground)
        }
    }
}

// MARK: - Custom Calendar View with Activity Dots

struct CustomCalendarView: View {
    @Binding var selectedDate: Date
    @Binding var displayedMonth: Date
    let daysWithMeetings: Set<Date>

    private let calendar = Calendar.current
    private let weekdays = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: displayedMonth)
    }

    private var daysInMonth: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth),
              let firstDayOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: displayedMonth))
        else { return [] }

        let firstWeekday = calendar.component(.weekday, from: firstDayOfMonth)
        var days: [Date?] = Array(repeating: nil, count: firstWeekday - 1)

        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: firstDayOfMonth) {
                days.append(date)
            }
        }

        // Pad to complete last week
        while days.count % 7 != 0 {
            days.append(nil)
        }

        return days
    }

    var body: some View {
        VStack(spacing: 16) {
            // Month navigation
            HStack {
                Text(monthYearString)
                    .font(.brandDisplay(16, weight: .semibold))

                Spacer()

                HStack(spacing: 4) {
                    Button(action: previousMonth) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Color.brandBackground)
                            .cornerRadius(BrandRadius.small)
                    }
                    .buttonStyle(.plain)

                    Button(action: goToToday) {
                        Circle()
                            .fill(Color.brandViolet)
                            .frame(width: 8, height: 8)
                    }
                    .buttonStyle(.plain)
                    .help("Go to today")

                    Button(action: nextMonth) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Color.brandBackground)
                            .cornerRadius(BrandRadius.small)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Weekday headers
            HStack(spacing: 0) {
                ForEach(weekdays, id: \.self) { day in
                    Text(day)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Days grid
            let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(daysInMonth.enumerated()), id: \.offset) { _, date in
                    if let date = date {
                        CalendarDayCell(
                            date: date,
                            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                            isToday: calendar.isDateInToday(date),
                            hasMeetings: daysWithMeetings.contains(calendar.startOfDay(for: date)),
                            onSelect: { selectedDate = date }
                        )
                    } else {
                        Color.clear
                            .frame(height: 36)
                    }
                }
            }
        }
    }

    private func previousMonth() {
        if let newMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) {
            displayedMonth = newMonth
        }
    }

    private func nextMonth() {
        if let newMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) {
            displayedMonth = newMonth
        }
    }

    private func goToToday() {
        displayedMonth = Date()
        selectedDate = Date()
    }
}

struct CalendarDayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let hasMeetings: Bool
    let onSelect: () -> Void

    private let calendar = Calendar.current

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 13, weight: isSelected || isToday ? .semibold : .regular))
                    .foregroundColor(foregroundColor)

                // Activity dot
                Circle()
                    .fill(hasMeetings ? (isSelected ? Color.white : Color.brandViolet) : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .background(backgroundColor)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private var foregroundColor: Color {
        if isSelected {
            return .white
        } else if isToday {
            return .brandViolet
        } else {
            return .primary
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return .brandViolet
        } else if isToday {
            return .brandViolet.opacity(0.1)
        } else {
            return .clear
        }
    }
}

struct CalendarMeetingCard: View {
    let meeting: Meeting
    var onSelect: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        Button(action: { onSelect?() }) {
        HStack(spacing: 12) {
            // Time
            VStack(alignment: .trailing, spacing: 2) {
                Text(meeting.startTime.formatted(date: .omitted, time: .shortened))
                    .font(.brandMono(12))
                    .fontWeight(.semibold)

                if meeting.duration > 0 {
                    Text("\(Int(meeting.duration / 60))m")
                        .font(.brandMono(11))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 60)

            // Divider line
            Rectangle()
                .fill(Color.brandViolet)
                .frame(width: 3)
                .cornerRadius(1.5)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.title)
                    .font(.system(size: 14, weight: .medium))

                if let source = meeting.sourceApp {
                    Text(source)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Chevron indicator
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary.opacity(isHovered ? 0.8 : 0.3))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(isHovered ? Color.brandViolet.opacity(0.03) : Color.white)
        .cornerRadius(BrandRadius.medium)
        .shadow(color: Color.black.opacity(0.02), radius: 2, y: 1)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isHovered ? Color.brandViolet.opacity(0.3) : Color.brandBorder, lineWidth: 1)
        )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Empty Detail View

struct EmptyDetailView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.brandViolet.opacity(0.3))

            Text(title)
                .font(.brandDisplay(18, weight: .semibold))

            Text(subtitle)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - View Model

@MainActor
class MainAppViewModel: ObservableObject {
    @Published var meetings: [Meeting] = []
    @Published var isRecording = false
    @Published var totalMeetings = 0
    @Published var totalHours: Double = 0
    @Published var totalCost: Double = 0
    @Published var pendingTranscriptions = 0
    @Published var todayMeetings = 0
    @Published var dictationsCount = 0
    @Published var dictationMinutes: Double = 0
    @Published var dictationCost: Double = 0

    // Monthly stats
    @Published var monthlyMeetings = 0
    @Published var monthlyHours: Double = 0
    @Published var monthlyCost: Double = 0
    @Published var monthlyDictations = 0
    @Published var monthlyDictationMinutes: Double = 0
    @Published var monthlyDictationCost: Double = 0

    // Daily usage for chart (last 14 days)
    @Published var dailyUsage: [(date: Date, minutes: Double)] = []

    func loadData() async {
        do {
            meetings = try await DatabaseManager.shared.getAllMeetings()

            // All time stats
            totalMeetings = meetings.filter { $0.sourceApp != "Dictation" }.count
            totalHours = meetings.filter { $0.sourceApp != "Dictation" }.reduce(0) { $0 + $1.duration } / 3600
            totalCost = Double(meetings.filter { $0.sourceApp != "Dictation" }.compactMap { $0.apiCostCents }.reduce(0, +)) / 100

            let dictations = meetings.filter { $0.sourceApp == "Dictation" }
            dictationsCount = dictations.count
            dictationMinutes = dictations.reduce(0) { $0 + $1.duration } / 60
            dictationCost = Double(dictations.compactMap { $0.apiCostCents }.reduce(0, +)) / 100

            pendingTranscriptions = meetings.filter { $0.status == .pendingTranscription || $0.status == .transcribing }.count
            todayMeetings = meetings.filter { Calendar.current.isDateInToday($0.startTime) }.count

            // Monthly stats
            let calendar = Calendar.current
            let now = Date()
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            let thisMonthMeetings = meetings.filter { $0.startTime >= startOfMonth }

            let monthlyMeetingsOnly = thisMonthMeetings.filter { $0.sourceApp != "Dictation" }
            monthlyMeetings = monthlyMeetingsOnly.count
            monthlyHours = monthlyMeetingsOnly.reduce(0) { $0 + $1.duration } / 3600
            monthlyCost = Double(monthlyMeetingsOnly.compactMap { $0.apiCostCents }.reduce(0, +)) / 100

            let monthlyDictationsOnly = thisMonthMeetings.filter { $0.sourceApp == "Dictation" }
            monthlyDictations = monthlyDictationsOnly.count
            monthlyDictationMinutes = monthlyDictationsOnly.reduce(0) { $0 + $1.duration } / 60
            monthlyDictationCost = Double(monthlyDictationsOnly.compactMap { $0.apiCostCents }.reduce(0, +)) / 100

            // Daily usage for last 14 days
            dailyUsage = (0..<14).reversed().map { daysAgo in
                let date = calendar.date(byAdding: .day, value: -daysAgo, to: now)!
                let dayStart = calendar.startOfDay(for: date)
                let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
                let dayMeetings = meetings.filter { $0.startTime >= dayStart && $0.startTime < dayEnd }
                let minutes = dayMeetings.reduce(0) { $0 + $1.duration } / 60
                return (date: dayStart, minutes: minutes)
            }
        } catch {
            print("[MainApp] Error loading data: \(error)")
        }
    }

    func toggleRecording() {
        print("[HomeView] toggleRecording called")
        Task { @MainActor in
            guard let appDelegate = NSApp.delegate as? AppDelegate else {
                print("[HomeView] ERROR: Could not get AppDelegate")
                return
            }
            let audioManager = appDelegate.audioManager
            print("[HomeView] Got audioManager, isRecording: \(audioManager.isRecording)")

            if audioManager.isRecording {
                // Stop recording
                print("[HomeView] Stopping recording...")
                _ = try? await audioManager.stopRecording()
                RecordingIslandController.shared.hide()
                isRecording = false
            } else {
                // Start recording and show the Recording Island
                print("[HomeView] Starting recording...")
                do {
                    try await audioManager.startRecording()
                    print("[HomeView] Recording started, showing island")
                    RecordingIslandController.shared.show(audioManager: audioManager)
                    isRecording = true
                } catch {
                    print("[HomeView] ERROR starting recording: \(error)")
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Custom Action Buttons") {
    VStack(spacing: 20) {
        Text("On-Brand Action Buttons")
            .font(.headline)

        HStack(spacing: 12) {
            SecondaryActionButton(title: "Cancel", action: {})
            PrimaryActionButton(title: "Save", action: {})
        }

        HStack(spacing: 12) {
            SecondaryActionButton(title: "Cancel", icon: "xmark") {}
            PrimaryActionButton(title: "Confirm", icon: "checkmark") {}
        }

        HStack(spacing: 12) {
            SecondaryActionButton(title: "Keep") {}
            DestructiveActionButton(title: "Delete", icon: "trash") {}
        }

        PrimaryActionButton(title: "Disabled", isDisabled: true) {}
    }
    .padding(40)
    .frame(width: 400)
    .background(Color(.windowBackgroundColor))
}

#Preview("Rename Meeting Sheet") {
    struct PreviewWrapper: View {
        @State private var title = "Team Standup Meeting"

        var body: some View {
            RenameMeetingSheet(
                meeting: Meeting.sampleMeetings[0],
                newTitle: $title,
                onSave: { _ in },
                onCancel: {}
            )
        }
    }
    return PreviewWrapper()
        .background(Color(.windowBackgroundColor))
}