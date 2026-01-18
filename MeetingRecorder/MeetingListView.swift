//
//  MeetingListView.swift
//  MeetingRecorder
//
//  Shows meetings grouped by day with status indicators
//

import SwiftUI

/// Main meeting list view with day grouping
struct MeetingListView: View {
    @StateObject private var viewModel = MeetingListViewModel()
    @State private var selectedMeeting: Meeting?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            SearchBar(text: $searchText)
                .padding(.horizontal, 12)
                .padding(.top, 8)

            // Failed transcriptions banner
            if viewModel.failedCount > 0 {
                FailedTranscriptionsBanner(
                    failedCount: viewModel.failedCount,
                    isRetrying: viewModel.isRetrying,
                    progress: viewModel.retryProgress,
                    onRetryAll: {
                        Task {
                            await viewModel.retryAllFailed()
                        }
                    }
                )
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }

            if viewModel.isLoading {
                // Loading state
                VStack(spacing: 12) {
                    BrandLoadingIndicator(size: .large)
                    Text("Loading meetings...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredMeetings.isEmpty {
                // Empty state
                EmptyMeetingListView(hasSearchQuery: !searchText.isEmpty)
            } else {
                // Meeting list
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(groupedMeetings, id: \.key) { group in
                            Section {
                                ForEach(group.meetings) { meeting in
                                    MeetingRowView(
                                        meeting: meeting,
                                        onRetry: {
                                            Task {
                                                await viewModel.retryTranscription(meeting)
                                            }
                                        },
                                        onRename: { newTitle in
                                            Task {
                                                await viewModel.renameMeeting(meeting, to: newTitle)
                                            }
                                        },
                                        onDelete: {
                                            Task {
                                                await viewModel.deleteMeeting(meeting)
                                            }
                                        }
                                    )
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            selectedMeeting = meeting
                                        }
                                        .contextMenu {
                                            MeetingContextMenu(meeting: meeting, viewModel: viewModel)
                                        }
                                }
                            } header: {
                                DaySectionHeader(title: group.key)
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .sheet(item: $selectedMeeting) { meeting in
            MeetingDetailView(meeting: meeting)
        }
        .task {
            await viewModel.loadMeetings()
        }
        .onChange(of: searchText) { _, newValue in
            Task {
                await viewModel.search(query: newValue)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .meetingsDidChange)) { _ in
            Task {
                await viewModel.search(query: searchText)
            }
        }
        .onChange(of: viewModel.meetings) { _, newMeetings in
            if let selectedId = selectedMeeting?.id,
               let updatedMeeting = newMeetings.first(where: { $0.id == selectedId }) {
                selectedMeeting = updatedMeeting
            }
        }
    }

    private var filteredMeetings: [Meeting] {
        viewModel.meetings
    }

    private var groupedMeetings: [(key: String, meetings: [Meeting])] {
        let grouped = Dictionary(grouping: filteredMeetings) { $0.dateGroupKey }
        return grouped.map { (key: $0.key, meetings: $0.value) }
            .sorted { meeting1, meeting2 in
                // Sort groups by date (Today first, then Yesterday, then by date)
                let order = ["Today", "Yesterday"]
                let idx1 = order.firstIndex(of: meeting1.key) ?? Int.max
                let idx2 = order.firstIndex(of: meeting2.key) ?? Int.max
                if idx1 != idx2 {
                    return idx1 < idx2
                }
                // Both are dates, sort by first meeting's start time
                guard let m1 = meeting1.meetings.first, let m2 = meeting2.meetings.first else {
                    return meeting1.key < meeting2.key
                }
                return m1.startTime > m2.startTime
            }
    }
}

// MARK: - View Model

@MainActor
class MeetingListViewModel: ObservableObject {
    @Published var meetings: [Meeting] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isRetrying = false
    @Published var retryProgress: String?

    /// Count of failed meetings for UI display
    var failedCount: Int {
        meetings.filter { $0.status == .failed }.count
    }

    func loadMeetings() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Wait for database to be initialized before querying
            try await DatabaseManager.shared.waitForInitialization()
            meetings = try await DatabaseManager.shared.getAllMeetings()
        } catch {
            errorMessage = error.localizedDescription
            print("[MeetingListView] Error loading meetings: \(error)")
        }
    }

    func search(query: String) async {
        do {
            if query.isEmpty {
                meetings = try await DatabaseManager.shared.getAllMeetings()
            } else {
                meetings = try await DatabaseManager.shared.search(query: query)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteMeeting(_ meeting: Meeting) async {
        do {
            // Delete audio file
            try? FileManager.default.removeItem(atPath: meeting.audioPath)

            // Delete from database
            try await DatabaseManager.shared.delete(meeting.id)
            meetings.removeAll { $0.id == meeting.id }

            // Remove from Agent API exports
            try? await AgentAPIManager.shared.deleteMeeting(meeting.id)

            NotificationCenter.default.post(name: .meetingsDidChange, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func renameMeeting(_ meeting: Meeting, to newTitle: String) async {
        var updatedMeeting = meeting
        updatedMeeting.title = newTitle

        do {
            try await DatabaseManager.shared.update(updatedMeeting)
            updateMeetingInList(updatedMeeting)
            NotificationCenter.default.post(name: .meetingsDidChange, object: nil)

            // Update agent API export if meeting is ready
            if meeting.status == .ready {
                Task {
                    try? await AgentAPIManager.shared.exportMeeting(updatedMeeting)
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Retry transcription for a single failed meeting
    func retryTranscription(_ meeting: Meeting) async {
        var updatedMeeting = meeting
        updatedMeeting.status = .transcribing
        updatedMeeting.errorMessage = nil

        do {
            try await DatabaseManager.shared.update(updatedMeeting)
            updateMeetingInList(updatedMeeting)
            NotificationCenter.default.post(name: .meetingsDidChange, object: nil)

            // Perform actual transcription
            let result = try await TranscriptionService.shared.transcribe(audioPath: meeting.audioPath)

            // Update with transcript
            updatedMeeting.transcript = result.text
            updatedMeeting.apiCostCents = result.costCents
            updatedMeeting.duration = result.duration
            updatedMeeting.status = .ready
            updatedMeeting.errorMessage = nil

            // Use title from transcription process
            if let smartTitle = result.title {
                updatedMeeting.title = smartTitle
            }

            try await DatabaseManager.shared.update(updatedMeeting)
            updateMeetingInList(updatedMeeting)

            // Export to agent API
            Task {
                try? await AgentAPIManager.shared.exportMeeting(updatedMeeting)
            }

            print("[MeetingListViewModel] Retry successful for: \(meeting.title)")

        } catch {
            // Mark as failed again
            updatedMeeting.status = .failed
            updatedMeeting.errorMessage = error.localizedDescription
            try? await DatabaseManager.shared.update(updatedMeeting)
            updateMeetingInList(updatedMeeting)
            NotificationCenter.default.post(name: .meetingsDidChange, object: nil)
            errorMessage = error.localizedDescription
            print("[MeetingListViewModel] Retry failed: \(error)")
        }
    }

    /// Retry transcription for all failed meetings
    func retryAllFailed() async {
        let failedMeetings = meetings.filter { $0.status == .failed }
        guard !failedMeetings.isEmpty else { return }

        isRetrying = true
        defer {
            isRetrying = false
            retryProgress = nil
        }

        print("[MeetingListViewModel] Retrying \(failedMeetings.count) failed transcriptions")

        for (index, meeting) in failedMeetings.enumerated() {
            retryProgress = "Retrying \(index + 1) of \(failedMeetings.count)..."
            await retryTranscription(meeting)

            // Small delay between retries to avoid rate limiting
            if index < failedMeetings.count - 1 {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            }
        }

        // Reload to get fresh state
        await loadMeetings()
    }

    private func updateMeetingInList(_ meeting: Meeting) {
        if let index = meetings.firstIndex(where: { $0.id == meeting.id }) {
            meetings[index] = meeting
        }
    }
}

// MARK: - Search Bar

struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        BrandSearchField(placeholder: "Search meetings...", text: $text)
    }
}

// MARK: - Failed Transcriptions Banner

struct FailedTranscriptionsBanner: View {
    let failedCount: Int
    let isRetrying: Bool
    let progress: String?
    let onRetryAll: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(failedCount) failed transcription\(failedCount == 1 ? "" : "s")")
                    .font(.subheadline.weight(.medium))

                if let progress = progress {
                    Text(progress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button(action: onRetryAll) {
                HStack(spacing: 4) {
                    if isRetrying {
                        BrandLoadingIndicator(size: .tiny, color: .white)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    Text(isRetrying ? "Retrying..." : "Retry All")
                        .font(.caption.weight(.medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.brandViolet)
                .foregroundColor(.white)
                .cornerRadius(BrandRadius.small)
            }
            .buttonStyle(.plain)
            .disabled(isRetrying)
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Day Section Header

struct DaySectionHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.windowBackgroundColor))
    }
}

// MARK: - Meeting Row

struct MeetingRowView: View {
    let meeting: Meeting
    var onRetry: (() -> Void)? = nil
    var onRename: ((String) -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var isEditing = false
    @State private var editedTitle = ""
    @State private var isHovered = false
    @State private var showErrorPopover = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            // Dictation icon or status indicator
            // Ready state = no indicator (success is the default/expected)
            if meeting.isDictation {
                Image(systemName: "text.bubble")
                    .font(.caption)
                    .foregroundColor(.purple)
                    .frame(width: 20, height: 20)
            } else if meeting.status == .failed {
                // Failed: show warning icon with popover for details
                Button(action: { showErrorPopover.toggle() }) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .frame(width: 20, height: 20)
                .popover(isPresented: $showErrorPopover, arrowEdge: .trailing) {
                    TranscriptionErrorPopover(
                        errorMessage: meeting.errorMessage ?? "Unknown error",
                        onRetry: {
                            showErrorPopover = false
                            onRetry?()
                        },
                        onDismiss: { showErrorPopover = false }
                    )
                }
                .help("Transcription failed - click for details")
            } else if meeting.status == .transcribing {
                // Transcribing: show spinner
                BrandLoadingIndicator(size: .small)
                    .frame(width: 20, height: 20)
            } else if meeting.status == .recording {
                // Recording: show pulsing red dot
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .frame(width: 20, height: 20)
            } else if meeting.status == .pendingTranscription {
                // Pending: show clock icon
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .frame(width: 20, height: 20)
            }
            // .ready status = no indicator shown (success is default)

            // Meeting info
            VStack(alignment: .leading, spacing: 2) {
                if isEditing {
                    TextField("Meeting title", text: $editedTitle, onCommit: {
                        if !editedTitle.isEmpty && editedTitle != meeting.title {
                            onRename?(editedTitle)
                        }
                        isEditing = false
                    })
                    .textFieldStyle(.plain)
                    .font(.subheadline.weight(.medium))
                    .onExitCommand {
                        isEditing = false
                        editedTitle = meeting.title
                    }
                } else {
                    Text(meeting.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Text(meeting.formattedTime)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(meeting.formattedDuration)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let app = meeting.sourceApp {
                        Text(app)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Cost badge (if transcribed) - only visible for beta testers
            if FeatureFlags.shared.showCosts, let cost = meeting.formattedCost {
                Text(cost)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.brandCreamDark)
                    .cornerRadius(4)
            }

            // Hover actions
            if isHovered {
                HStack(spacing: 6) {
                    // Retry button for failed transcriptions
                    if meeting.status == .failed {
                        Button(action: { onRetry?() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption)
                                Text("Retry")
                                    .font(.caption.weight(.medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.brandViolet)
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }

                    // Delete button (always show on hover)
                    Button(action: { showDeleteConfirmation = true }) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundColor(.red.opacity(0.8))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Delete meeting")
                }
                .transition(.opacity)
            }

            // Chevron (hide when hovered to make room for actions)
            if !isHovered {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture(count: 2) {
            // Double-click to edit
            editedTitle = meeting.title
            isEditing = true
        }
        .alert("Delete Meeting?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete?()
            }
        } message: {
            Text("This will permanently delete \"\(meeting.title)\" and its audio file.")
        }
    }
}

// MARK: - Transcription Error Popover

struct TranscriptionErrorPopover: View {
    let errorMessage: String
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                Text("Transcription Failed")
                    .font(.headline)
                Spacer()
            }

            Divider()

            Text("Error Details")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            Text(errorMessage)
                .font(.caption)
                .foregroundColor(.primary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.brandCreamDark)
                .cornerRadius(BrandRadius.small)

            HStack(spacing: 8) {
                Button(action: onDismiss) {
                    Text("Dismiss")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .background(Color.brandSurface)
                .cornerRadius(BrandRadius.small)

                Button(action: onRetry) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                        Text("Retry")
                            .font(.caption.weight(.medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .background(Color.brandViolet)
                .cornerRadius(BrandRadius.small)
            }
        }
        .padding(12)
        .frame(width: 280)
    }
}

// MARK: - Empty State

struct EmptyMeetingListView: View {
    let hasSearchQuery: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: hasSearchQuery ? "magnifyingglass" : "waveform.circle")
                .font(.system(size: 40))
                .foregroundColor(.secondary)

            Text(hasSearchQuery ? "No results" : "No meetings yet")
                .font(.headline)

            Text(hasSearchQuery ? "Try a different search term" : "Start recording to see your meetings here")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Context Menu

struct MeetingContextMenu: View {
    let meeting: Meeting
    let viewModel: MeetingListViewModel

    var body: some View {
        Button(action: {
            if let url = URL(string: "file://\(meeting.audioPath)") {
                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
            }
        }) {
            Label("Show in Finder", systemImage: "folder")
        }

        if meeting.status == .failed {
            Button(action: {
                Task {
                    await viewModel.retryTranscription(meeting)
                }
            }) {
                Label("Retry Transcription", systemImage: "arrow.clockwise")
            }
        }

        Divider()

        Button(role: .destructive, action: {
            Task {
                await viewModel.deleteMeeting(meeting)
            }
        }) {
            Label("Delete", systemImage: "trash")
        }
    }
}

// MARK: - Previews

#Preview("Meeting List") {
    MeetingListView()
        .frame(width: 350, height: 500)
}

#Preview("Meeting Row - Ready (No Indicator)") {
    VStack(spacing: 0) {
        MeetingRowView(meeting: Meeting.sampleMeetings[0])
        Divider()
        // Show how ready meetings look clean without any badge
        MeetingRowView(meeting: Meeting(
            title: "Product Planning",
            startTime: Date().addingTimeInterval(-7200),
            duration: 2400,
            sourceApp: "Zoom",
            audioPath: "/path/to/audio.m4a",
            transcript: "Meeting notes...",
            apiCostCents: 42,
            status: .ready
        ))
    }
    .frame(width: 350)
}

#Preview("Meeting Row - Transcribing") {
    MeetingRowView(meeting: Meeting.sampleMeetings[1])
        .frame(width: 350)
}

#Preview("Meeting Row - Failed") {
    VStack(spacing: 0) {
        MeetingRowView(
            meeting: Meeting.sampleMeetings[3],
            onRetry: { print("Retry tapped") }
        )
        Divider()
        // Different error message
        MeetingRowView(
            meeting: Meeting(
                title: "Team Sync",
                startTime: Date().addingTimeInterval(-3600),
                duration: 1800,
                audioPath: "/path/to/audio.m4a",
                status: .failed,
                errorMessage: "Network timeout - could not reach OpenAI API"
            ),
            onRetry: { print("Retry tapped") }
        )
    }
    .frame(width: 350)
}

#Preview("Error Popover") {
    TranscriptionErrorPopover(
        errorMessage: "API key invalid or expired. Please check your OpenAI API key in Settings.",
        onRetry: { print("Retry") },
        onDismiss: { print("Dismiss") }
    )
}

#Preview("Empty State") {
    EmptyMeetingListView(hasSearchQuery: false)
        .frame(width: 350, height: 300)
}

#Preview("Empty Search") {
    EmptyMeetingListView(hasSearchQuery: true)
        .frame(width: 350, height: 300)
}

#Preview("Failed Banner") {
    FailedTranscriptionsBanner(
        failedCount: 3,
        isRetrying: false,
        progress: nil,
        onRetryAll: {}
    )
    .frame(width: 350)
    .padding()
}

#Preview("Failed Banner - Retrying") {
    FailedTranscriptionsBanner(
        failedCount: 3,
        isRetrying: true,
        progress: "Retrying 2 of 3...",
        onRetryAll: {}
    )
    .frame(width: 350)
    .padding()
}
