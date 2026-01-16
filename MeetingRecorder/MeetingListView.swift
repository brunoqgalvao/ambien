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

            if viewModel.isLoading {
                // Loading state
                VStack(spacing: 12) {
                    ProgressView()
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
                                    MeetingRowView(meeting: meeting)
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

    func loadMeetings() async {
        isLoading = true
        defer { isLoading = false }

        do {
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
            try await DatabaseManager.shared.delete(meeting.id)
            meetings.removeAll { $0.id == meeting.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func retryTranscription(_ meeting: Meeting) async {
        var updatedMeeting = meeting
        updatedMeeting.status = .pendingTranscription
        updatedMeeting.errorMessage = nil

        do {
            try await DatabaseManager.shared.update(updatedMeeting)
            if let index = meetings.firstIndex(where: { $0.id == meeting.id }) {
                meetings[index] = updatedMeeting
            }
            // Trigger transcription
            // Note: In full implementation, this would kick off TranscriptionService
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Search Bar

struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search meetings...", text: $text)
                .textFieldStyle(.plain)

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color(.textBackgroundColor).opacity(0.5))
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

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            MeetingStatusBadge(status: meeting.status)

            // Meeting info
            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

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

            // Cost badge (if transcribed)
            if let cost = meeting.formattedCost {
                Text(cost)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(4)
            }

            // Chevron
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

// MARK: - Status Badge

struct MeetingStatusBadge: View {
    let status: MeetingStatus

    var body: some View {
        Image(systemName: status.icon)
            .font(.caption)
            .foregroundColor(statusColor)
            .frame(width: 20, height: 20)
    }

    private var statusColor: Color {
        switch status {
        case .recording: return .red
        case .pendingTranscription: return .orange
        case .transcribing: return .blue
        case .ready: return .green
        case .failed: return .red
        }
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

#Preview("Meeting Row - Ready") {
    MeetingRowView(meeting: Meeting.sampleMeetings[0])
        .frame(width: 350)
}

#Preview("Meeting Row - Transcribing") {
    MeetingRowView(meeting: Meeting.sampleMeetings[1])
        .frame(width: 350)
}

#Preview("Meeting Row - Failed") {
    MeetingRowView(meeting: Meeting.sampleMeetings[3])
        .frame(width: 350)
}

#Preview("Empty State") {
    EmptyMeetingListView(hasSearchQuery: false)
        .frame(width: 350, height: 300)
}

#Preview("Empty Search") {
    EmptyMeetingListView(hasSearchQuery: true)
        .frame(width: 350, height: 300)
}

#Preview("Status Badges") {
    HStack(spacing: 16) {
        ForEach(MeetingStatus.allCases, id: \.self) { status in
            VStack {
                MeetingStatusBadge(status: status)
                Text(status.displayName)
                    .font(.caption2)
            }
        }
    }
    .padding()
}
