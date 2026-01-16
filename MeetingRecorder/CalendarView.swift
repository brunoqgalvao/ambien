//
//  CalendarView.swift
//  MeetingRecorder
//
//  Main calendar window with date picker, filters, and meeting list
//  Opens in separate window from menu bar
//

import SwiftUI

/// Filter options for meeting list
enum MeetingFilter: String, CaseIterable {
    case all = "All"
    case thisWeek = "This Week"
    case recorded = "Recorded"
}

/// Main calendar view - opens in separate window
struct CalendarView: View {
    @StateObject private var viewModel = CalendarViewModel()
    @State private var selectedFilter: MeetingFilter = .all
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                // Date picker header
                DatePickerHeader(
                    selectedDate: $viewModel.selectedDate,
                    onTodayTapped: { viewModel.goToToday() }
                )

                Divider()

                // Filter pills and search bar
                FilterBar(
                    selectedFilter: $selectedFilter,
                    searchText: $searchText,
                    isSearching: $isSearching
                )

                Divider()

                // Content area
                if isSearching && !searchText.isEmpty {
                    SearchResultsView(
                        searchText: searchText,
                        results: viewModel.searchResults,
                        onSelect: { meeting in
                            navigationPath.append(meeting)
                            isSearching = false
                            searchText = ""
                        },
                        onClose: {
                            isSearching = false
                            searchText = ""
                        }
                    )
                } else {
                    // Meeting list
                    MeetingListContent(
                        meetings: filteredMeetings,
                        navigationPath: $navigationPath,
                        viewModel: viewModel
                    )
                }

                Divider()

                // Keyboard shortcuts footer
                KeyboardShortcutsFooter()
            }
            .background(Color(.windowBackgroundColor))
            .navigationDestination(for: Meeting.self) { meeting in
                MeetingDetailView(meeting: meeting, showBackButton: false)
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            Button(action: { navigationPath.removeLast() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                    Text("Back")
                                }
                            }
                        }
                    }
            }
        }
        .frame(minWidth: 500, idealWidth: 600, minHeight: 500, idealHeight: 700)
        .task {
            await viewModel.loadMeetings()
        }
        .onChange(of: searchText) { _, newValue in
            Task {
                await viewModel.search(query: newValue)
            }
        }
        .onChange(of: viewModel.selectedDate) { _, _ in
            Task {
                await viewModel.loadMeetings()
            }
        }
        // Keyboard navigation
        .onKeyPress(.leftArrow) {
            if navigationPath.isEmpty {
                viewModel.previousDay()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.rightArrow) {
            if navigationPath.isEmpty {
                viewModel.nextDay()
                return .handled
            }
            return .ignored
        }
        .onKeyPress("t") {
            if navigationPath.isEmpty {
                viewModel.goToToday()
                return .handled
            }
            return .ignored
        }
        .onKeyPress("/") {
            if navigationPath.isEmpty {
                isSearching = true
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.escape) {
            if !navigationPath.isEmpty {
                navigationPath.removeLast()
                return .handled
            }
            if isSearching {
                isSearching = false
                searchText = ""
                return .handled
            }
            return .ignored
        }
    }

    private var filteredMeetings: [Meeting] {
        switch selectedFilter {
        case .all:
            return viewModel.meetings
        case .thisWeek:
            let calendar = Calendar.current
            let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
            let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)!
            return viewModel.meetings.filter { $0.startTime >= weekStart && $0.startTime < weekEnd }
        case .recorded:
            return viewModel.meetings.filter { $0.status == .ready || $0.transcript != nil }
        }
    }
}

// MARK: - Date Picker Header

struct DatePickerHeader: View {
    @Binding var selectedDate: Date
    let onTodayTapped: () -> Void

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        return formatter
    }()

    var body: some View {
        HStack(spacing: 16) {
            // Previous day button
            Button(action: previousDay) {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.medium))
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
            .help("Previous day (←)")

            // Date display
            Text(dateFormatter.string(from: selectedDate))
                .font(.title2.weight(.semibold))
                .frame(minWidth: 250)

            // Next day button
            Button(action: nextDay) {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.medium))
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
            .help("Next day (→)")

            Spacer()

            // Today button
            Button("Today") {
                onTodayTapped()
            }
            .buttonStyle(.bordered)
            .help("Jump to today (T)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func previousDay() {
        selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
    }

    private func nextDay() {
        selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
    }
}

// MARK: - Filter Bar

struct FilterBar: View {
    @Binding var selectedFilter: MeetingFilter
    @Binding var searchText: String
    @Binding var isSearching: Bool
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Filter pills
            HStack(spacing: 8) {
                ForEach(MeetingFilter.allCases, id: \.self) { filter in
                    FilterPill(
                        title: filter.rawValue,
                        isSelected: selectedFilter == filter
                    ) {
                        selectedFilter = filter
                    }
                }
            }

            Spacer()

            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 150)
                    .focused($searchFieldFocused)
                    .onSubmit {
                        if !searchText.isEmpty {
                            isSearching = true
                        }
                    }

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        isSearching = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Text("⌘F")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(4)
            }
            .padding(8)
            .background(Color(.textBackgroundColor).opacity(0.5))
            .cornerRadius(8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Filter Pill

struct FilterPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.textBackgroundColor))
                .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Meeting List Content

struct MeetingListContent: View {
    let meetings: [Meeting]
    @Binding var navigationPath: NavigationPath
    let viewModel: CalendarViewModel

    var body: some View {
        if meetings.isEmpty {
            EmptyCalendarState()
        } else {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    // Group meetings by day
                    ForEach(groupedMeetings, id: \.key) { group in
                        Section {
                            ForEach(group.meetings) { meeting in
                                CalendarMeetingRow(
                                    meeting: meeting,
                                    isSelected: false,
                                    onSelect: { navigationPath.append(meeting) },
                                    onDelete: {
                                        Task { await viewModel.deleteMeeting(meeting) }
                                    },
                                    onRetry: {
                                        Task { await viewModel.retryTranscription(meeting) }
                                    }
                                )
                            }
                        } header: {
                            DayGroupHeader(title: group.key, count: group.meetings.count)
                        }
                    }
                }
                .padding(.bottom, 16)
            }
        }
    }

    private var groupedMeetings: [(key: String, meetings: [Meeting])] {
        let grouped = Dictionary(grouping: meetings) { $0.dateGroupKey }
        return grouped.map { (key: $0.key, meetings: $0.value) }
            .sorted { meeting1, meeting2 in
                let order = ["Today", "Yesterday"]
                let idx1 = order.firstIndex(of: meeting1.key) ?? Int.max
                let idx2 = order.firstIndex(of: meeting2.key) ?? Int.max
                if idx1 != idx2 { return idx1 < idx2 }
                guard let m1 = meeting1.meetings.first, let m2 = meeting2.meetings.first else {
                    return meeting1.key < meeting2.key
                }
                return m1.startTime > m2.startTime
            }
    }
}

// MARK: - Day Group Header

struct DayGroupHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            Text("\(count) meeting\(count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.8))

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(.windowBackgroundColor).opacity(0.95))
    }
}

// MARK: - Empty State

struct EmptyCalendarState: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No meetings recorded yet")
                .font(.headline)

            Text("Start recording to see your meetings here")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack {
                Text("⌘⇧R")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(4)

                Text("Start Recording")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Keyboard Shortcuts Footer

struct KeyboardShortcutsFooter: View {
    var body: some View {
        HStack(spacing: 20) {
            ShortcutHint(keys: "j/k", action: "navigate")
            ShortcutHint(keys: "↵", action: "open")
            ShortcutHint(keys: "/", action: "search")
            ShortcutHint(keys: "T", action: "today")
            ShortcutHint(keys: "← →", action: "days")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

struct ShortcutHint: View {
    let keys: String
    let action: String

    var body: some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.caption.weight(.medium).monospaced())
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color(.textBackgroundColor))
                .cornerRadius(3)

            Text(action)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - View Model

@MainActor
class CalendarViewModel: ObservableObject {
    @Published var meetings: [Meeting] = []
    @Published var searchResults: [Meeting] = []
    @Published var selectedDate: Date = Date()
    @Published var isLoading = false
    @Published var errorMessage: String?

    func loadMeetings() async {
        isLoading = true
        defer { isLoading = false }

        do {
            meetings = try await DatabaseManager.shared.getAllMeetings()
        } catch {
            errorMessage = error.localizedDescription
            print("[CalendarView] Error loading meetings: \(error)")
        }
    }

    func search(query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }

        do {
            searchResults = try await DatabaseManager.shared.search(query: query)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteMeeting(_ meeting: Meeting) async {
        do {
            try await DatabaseManager.shared.delete(meeting.id)
            meetings.removeAll { $0.id == meeting.id }
            searchResults.removeAll { $0.id == meeting.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func retryTranscription(_ meeting: Meeting) async {
        var updated = meeting
        updated.status = .pendingTranscription
        updated.errorMessage = nil

        do {
            try await DatabaseManager.shared.update(updated)
            if let index = meetings.firstIndex(where: { $0.id == meeting.id }) {
                meetings[index] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func goToToday() {
        selectedDate = Date()
    }

    func nextDay() {
        selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
    }

    func previousDay() {
        selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
    }
}

// MARK: - Previews

#Preview("Calendar View") {
    CalendarView()
        .frame(width: 600, height: 700)
}

#Preview("Date Picker Header") {
    DatePickerHeader(selectedDate: .constant(Date()), onTodayTapped: {})
        .frame(width: 600)
}

#Preview("Filter Bar") {
    FilterBar(
        selectedFilter: .constant(.all),
        searchText: .constant(""),
        isSearching: .constant(false)
    )
    .frame(width: 600)
}

#Preview("Filter Pills") {
    HStack {
        FilterPill(title: "All", isSelected: true, action: {})
        FilterPill(title: "This Week", isSelected: false, action: {})
        FilterPill(title: "Recorded", isSelected: false, action: {})
    }
    .padding()
}

#Preview("Empty State") {
    EmptyCalendarState()
        .frame(width: 500, height: 400)
}

#Preview("Keyboard Footer") {
    KeyboardShortcutsFooter()
        .frame(width: 600)
}

#Preview("Day Group Header") {
    DayGroupHeader(title: "Today", count: 3)
        .frame(width: 500)
}
