//
//  MeetingGroupsView.swift
//  MeetingRecorder
//
//  UI for managing meeting groups: list, create, edit, and view group details
//

import SwiftUI

// MARK: - Groups List View

/// Main view showing all meeting groups
struct MeetingGroupsListView: View {
    @StateObject private var viewModel = MeetingGroupsViewModel()
    @State private var selectedGroup: MeetingGroup?
    @State private var isCreatingGroup = false
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header with title and add button
            HStack {
                Text("Groups")
                    .font(.brandDisplay(18, weight: .bold))
                    .foregroundColor(.brandTextPrimary)

                Spacer()

                BrandIconButton(icon: "plus", size: 32) {
                    isCreatingGroup = true
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Search bar
            BrandSearchField(placeholder: "Search groups...", text: $searchText)
                .padding(.horizontal, 12)

            if viewModel.isLoading {
                VStack(spacing: 12) {
                    BrandLoadingIndicator(size: .large)
                    Text("Loading groups...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredGroups.isEmpty {
                EmptyGroupsView(hasSearchQuery: !searchText.isEmpty) {
                    isCreatingGroup = true
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredGroups) { group in
                            GroupRowView(group: group)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedGroup = group
                                }
                                .contextMenu {
                                    GroupContextMenu(group: group, viewModel: viewModel)
                                }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .sheet(item: $selectedGroup) { group in
            GroupDetailView(group: group)
        }
        .sheet(isPresented: $isCreatingGroup) {
            CreateGroupSheet(viewModel: viewModel)
        }
        .task {
            await viewModel.loadGroups()
        }
    }

    private var filteredGroups: [MeetingGroup] {
        if searchText.isEmpty {
            return viewModel.groups
        }
        return viewModel.groups.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.description?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
}

// MARK: - Group Row View

struct GroupRowView: View {
    let group: MeetingGroup

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Emoji or folder icon
            ZStack {
                RoundedRectangle(cornerRadius: BrandRadius.small)
                    .fill(groupColor.opacity(0.15))
                    .frame(width: 40, height: 40)

                if let emoji = group.emoji {
                    Text(emoji)
                        .font(.system(size: 20))
                } else {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 16))
                        .foregroundColor(groupColor)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.brandDisplay(14, weight: .semibold))
                    .foregroundColor(.brandTextPrimary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text("\(group.meetingCount) meetings")
                        .font(.brandDisplay(12, weight: .regular))
                        .foregroundColor(.brandTextSecondary)

                    if group.totalDuration > 0 {
                        Text("·")
                            .foregroundColor(.brandTextSecondary)
                        Text(group.formattedDuration)
                            .font(.brandDisplay(12, weight: .regular))
                            .foregroundColor(.brandTextSecondary)
                    }
                }
            }

            Spacer()

            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.brandTextSecondary)
                .opacity(isHovered ? 1 : 0.5)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: BrandRadius.small)
                .fill(isHovered ? Color.brandViolet.opacity(0.05) : Color.brandSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BrandRadius.small)
                .stroke(isHovered ? Color.brandViolet.opacity(0.2) : Color.brandBorder, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var groupColor: Color {
        guard let colorName = group.color,
              let groupColor = MeetingGroup.GroupColor(rawValue: colorName) else {
            return .brandViolet
        }
        switch groupColor {
        case .violet: return .brandViolet
        case .coral: return .brandCoral
        case .mint: return .brandMint
        case .amber: return .brandAmber
        case .blue: return Color.blue
        case .rose: return Color.pink
        case .emerald: return Color.green
        case .orange: return .brandAmber
        }
    }
}

// MARK: - Group Detail View

struct GroupDetailView: View {
    let group: MeetingGroup

    @StateObject private var viewModel = GroupDetailViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var isAddingMeetings = false
    @State private var selectedMeeting: Meeting?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.brandTextSecondary)
                }
                .buttonStyle(.plain)

                Spacer()

                if let emoji = group.emoji {
                    Text(emoji)
                        .font(.system(size: 24))
                }

                Text(group.name)
                    .font(.brandDisplay(18, weight: .bold))
                    .foregroundColor(.brandTextPrimary)

                Spacer()

                BrandIconButton(icon: "plus", size: 28) {
                    isAddingMeetings = true
                }
            }
            .padding(16)

            // Stats bar
            HStack(spacing: 16) {
                StatPill(label: "Meetings", value: "\(viewModel.meetings.count)")
                StatPill(label: "Duration", value: group.formattedDuration)
                // Cost stat - only visible for beta testers
                if FeatureFlags.shared.showCosts && group.totalCostCents > 0 {
                    StatPill(label: "Cost", value: group.formattedCost)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()

            if viewModel.isLoading {
                VStack(spacing: 12) {
                    BrandLoadingIndicator(size: .large)
                    Text("Loading meetings...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.meetings.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.brandTextSecondary)

                    Text("No meetings in this group")
                        .font(.brandDisplay(14, weight: .medium))
                        .foregroundColor(.brandTextSecondary)

                    BrandPrimaryButton(title: "Add Meetings", icon: "plus", size: .small) {
                        isAddingMeetings = true
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Meeting list
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.meetings) { meeting in
                            GroupMeetingRowView(meeting: meeting) {
                                Task {
                                    await viewModel.removeMeeting(meeting.id, from: group.id)
                                }
                            }
                            .onTapGesture {
                                selectedMeeting = meeting
                            }
                        }
                    }
                    .padding(12)
                }
            }

            // Combined transcript action
            if !viewModel.meetings.isEmpty {
                Divider()

                HStack {
                    BrandSecondaryButton(title: "Copy Combined Transcript", icon: "doc.on.doc", size: .small) {
                        Task {
                            await viewModel.copyCombinedTranscript(for: group.id)
                        }
                    }

                    BrandSecondaryButton(title: "Export for Agent", icon: "square.and.arrow.up", size: .small) {
                        Task {
                            await viewModel.exportGroup(group.id)
                        }
                    }
                }
                .padding(12)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(Color.brandBackground)
        .sheet(isPresented: $isAddingMeetings) {
            AddMeetingsToGroupSheet(group: group, viewModel: viewModel)
        }
        .sheet(item: $selectedMeeting) { meeting in
            MeetingDetailView(meeting: meeting)
        }
        .task {
            await viewModel.loadMeetings(for: group.id)
        }
    }
}

// MARK: - Group Meeting Row

struct GroupMeetingRowView: View {
    let meeting: Meeting
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title)
                    .font(.brandDisplay(13, weight: .medium))
                    .foregroundColor(.brandTextPrimary)
                    .lineLimit(1)

                Text(meeting.formattedTime + " · " + meeting.formattedDuration)
                    .font(.brandDisplay(11, weight: .regular))
                    .foregroundColor(.brandTextSecondary)
            }

            Spacer()

            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.brandCoral)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: BrandRadius.small)
                .fill(isHovered ? Color.brandViolet.opacity(0.05) : Color.brandSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BrandRadius.small)
                .stroke(Color.brandBorder, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var statusColor: Color {
        switch meeting.status {
        case .ready: return .brandMint
        case .transcribing: return .brandViolet
        case .failed: return .brandCoral
        default: return .brandAmber
        }
    }
}

// MARK: - Create Group Sheet

struct CreateGroupSheet: View {
    @ObservedObject var viewModel: MeetingGroupsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var selectedEmoji: String?
    @State private var selectedColor: MeetingGroup.GroupColor = .violet

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Group")
                    .font(.brandDisplay(18, weight: .bold))
                    .foregroundColor(.brandTextPrimary)

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.brandTextSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Name
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name")
                            .font(.brandDisplay(12, weight: .medium))
                            .foregroundColor(.brandTextSecondary)

                        BrandTextField(placeholder: "e.g., Project Phoenix", text: $name)
                    }

                    // Description
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Description (optional)")
                            .font(.brandDisplay(12, weight: .medium))
                            .foregroundColor(.brandTextSecondary)

                        BrandTextField(placeholder: "What are these meetings about?", text: $description)
                    }

                    // Emoji picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Icon")
                            .font(.brandDisplay(12, weight: .medium))
                            .foregroundColor(.brandTextSecondary)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 8) {
                            ForEach(MeetingGroup.suggestedEmojis, id: \.self) { emoji in
                                Button(action: { selectedEmoji = emoji }) {
                                    Text(emoji)
                                        .font(.system(size: 24))
                                        .padding(6)
                                        .background(
                                            RoundedRectangle(cornerRadius: BrandRadius.small)
                                                .fill(selectedEmoji == emoji ? Color.brandViolet.opacity(0.2) : Color.clear)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: BrandRadius.small)
                                                .stroke(selectedEmoji == emoji ? Color.brandViolet : Color.clear, lineWidth: 2)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Color picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Color")
                            .font(.brandDisplay(12, weight: .medium))
                            .foregroundColor(.brandTextSecondary)

                        HStack(spacing: 8) {
                            ForEach(MeetingGroup.GroupColor.allCases, id: \.self) { color in
                                Button(action: { selectedColor = color }) {
                                    Circle()
                                        .fill(colorForGroupColor(color))
                                        .frame(width: 28, height: 28)
                                        .overlay(
                                            Circle()
                                                .stroke(selectedColor == color ? Color.brandInk : Color.clear, lineWidth: 2)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(16)
            }

            Divider()

            // Actions
            HStack {
                BrandSecondaryButton(title: "Cancel") {
                    dismiss()
                }

                Spacer()

                BrandPrimaryButton(title: "Create Group", icon: "folder.badge.plus", isDisabled: name.isEmpty) {
                    Task {
                        await viewModel.createGroup(
                            name: name,
                            description: description.isEmpty ? nil : description,
                            emoji: selectedEmoji,
                            color: selectedColor.rawValue
                        )
                        dismiss()
                    }
                }
            }
            .padding(16)
        }
        .frame(width: 400, height: 500)
        .background(Color.brandBackground)
    }

    private func colorForGroupColor(_ color: MeetingGroup.GroupColor) -> Color {
        switch color {
        case .violet: return .brandViolet
        case .coral: return .brandCoral
        case .mint: return .brandMint
        case .amber: return .brandAmber
        case .blue: return Color.blue
        case .rose: return Color.pink
        case .emerald: return Color.green
        case .orange: return Color.orange
        }
    }
}

// MARK: - Add Meetings Sheet

struct AddMeetingsToGroupSheet: View {
    let group: MeetingGroup
    @ObservedObject var viewModel: GroupDetailViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var availableMeetings: [Meeting] = []
    @State private var selectedMeetings: Set<UUID> = []
    @State private var searchText = ""
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Meetings to \(group.name)")
                    .font(.brandDisplay(16, weight: .bold))
                    .foregroundColor(.brandTextPrimary)

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.brandTextSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(16)

            BrandSearchField(placeholder: "Search meetings...", text: $searchText)
                .padding(.horizontal, 12)

            Divider()
                .padding(.top, 8)

            if isLoading {
                VStack(spacing: 12) {
                    BrandLoadingIndicator(size: .large)
                    Text("Loading meetings...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredMeetings) { meeting in
                            MeetingSelectionRow(
                                meeting: meeting,
                                isSelected: selectedMeetings.contains(meeting.id)
                            ) {
                                if selectedMeetings.contains(meeting.id) {
                                    selectedMeetings.remove(meeting.id)
                                } else {
                                    selectedMeetings.insert(meeting.id)
                                }
                            }
                        }
                    }
                    .padding(12)
                }
            }

            Divider()

            // Actions
            HStack {
                Text("\(selectedMeetings.count) selected")
                    .font(.brandDisplay(12, weight: .medium))
                    .foregroundColor(.brandTextSecondary)

                Spacer()

                BrandSecondaryButton(title: "Cancel") {
                    dismiss()
                }

                BrandPrimaryButton(
                    title: "Add \(selectedMeetings.count) Meeting\(selectedMeetings.count == 1 ? "" : "s")",
                    icon: "plus",
                    isDisabled: selectedMeetings.isEmpty
                ) {
                    Task {
                        await viewModel.addMeetings(Array(selectedMeetings), to: group.id)
                        dismiss()
                    }
                }
            }
            .padding(16)
        }
        .frame(width: 450, height: 500)
        .background(Color.brandBackground)
        .task {
            await loadAvailableMeetings()
        }
    }

    private var filteredMeetings: [Meeting] {
        if searchText.isEmpty {
            return availableMeetings
        }
        return availableMeetings.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            ($0.transcript?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private func loadAvailableMeetings() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let allMeetings = try await DatabaseManager.shared.getAllMeetings()
            let existingMeetingIds = Set(viewModel.meetings.map { $0.id })
            availableMeetings = allMeetings.filter { !existingMeetingIds.contains($0.id) }
        } catch {
            print("[AddMeetingsSheet] Error loading meetings: \(error)")
        }
    }
}

// MARK: - Meeting Selection Row

struct MeetingSelectionRow: View {
    let meeting: Meeting
    let isSelected: Bool
    let onToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18))
                .foregroundColor(isSelected ? .brandViolet : .brandTextSecondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title)
                    .font(.brandDisplay(13, weight: .medium))
                    .foregroundColor(.brandTextPrimary)
                    .lineLimit(1)

                Text(meeting.dateGroupKey + " · " + meeting.formattedTime)
                    .font(.brandDisplay(11, weight: .regular))
                    .foregroundColor(.brandTextSecondary)
            }

            Spacer()

            // Status badge
            BrandStatusBadge(status: meetingToBadgeStatus(meeting.status))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: BrandRadius.small)
                .fill(isSelected ? Color.brandViolet.opacity(0.08) : (isHovered ? Color.brandViolet.opacity(0.03) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle()
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Supporting Views

struct StatPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.brandDisplay(14, weight: .semibold))
                .foregroundColor(.brandTextPrimary)

            Text(label)
                .font(.brandDisplay(10, weight: .regular))
                .foregroundColor(.brandTextSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: BrandRadius.small)
                .fill(Color.brandSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BrandRadius.small)
                .stroke(Color.brandBorder, lineWidth: 1)
        )
    }
}

struct EmptyGroupsView: View {
    let hasSearchQuery: Bool
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: hasSearchQuery ? "magnifyingglass" : "folder.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(.brandTextSecondary)

            Text(hasSearchQuery ? "No groups match your search" : "No groups yet")
                .font(.brandDisplay(16, weight: .semibold))
                .foregroundColor(.brandTextPrimary)

            Text(hasSearchQuery ? "Try a different search term" : "Create a group to organize related meetings together")
                .font(.brandDisplay(13, weight: .regular))
                .foregroundColor(.brandTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if !hasSearchQuery {
                BrandPrimaryButton(title: "Create Group", icon: "folder.badge.plus", size: .medium) {
                    onCreate()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GroupContextMenu: View {
    let group: MeetingGroup
    @ObservedObject var viewModel: MeetingGroupsViewModel

    var body: some View {
        Button(action: {
            Task {
                await viewModel.exportGroup(group.id)
            }
        }) {
            Label("Export for Agent", systemImage: "square.and.arrow.up")
        }

        Divider()

        Button(role: .destructive, action: {
            Task {
                await viewModel.deleteGroup(group.id)
            }
        }) {
            Label("Delete Group", systemImage: "trash")
        }
    }
}

// MARK: - Helpers

/// Convert MeetingStatus to BrandStatusBadge.Status
private func meetingToBadgeStatus(_ status: MeetingStatus) -> BrandStatusBadge.Status {
    switch status {
    case .recording: return .recording
    case .pendingTranscription: return .pending
    case .transcribing: return .transcribing
    case .ready: return .ready
    case .failed: return .failed
    }
}

// MARK: - View Models

@MainActor
class MeetingGroupsViewModel: ObservableObject {
    @Published var groups: [MeetingGroup] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func loadGroups() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Wait for database to be initialized before querying
            try await DatabaseManager.shared.waitForInitialization()
            groups = try await GroupManager.shared.getAllGroups()
        } catch {
            errorMessage = error.localizedDescription
            print("[MeetingGroupsView] Error loading groups: \(error)")
        }
    }

    func createGroup(name: String, description: String?, emoji: String?, color: String?) async {
        do {
            let group = try await GroupManager.shared.createGroup(
                name: name,
                description: description,
                emoji: emoji,
                color: color
            )
            groups.append(group)
            groups.sort { $0.name < $1.name }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteGroup(_ groupId: UUID) async {
        do {
            try await GroupManager.shared.deleteGroup(groupId)
            groups.removeAll { $0.id == groupId }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportGroup(_ groupId: UUID) async {
        do {
            try await GroupManager.shared.exportGroup(groupId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
class GroupDetailViewModel: ObservableObject {
    @Published var meetings: [Meeting] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func loadMeetings(for groupId: UUID) async {
        isLoading = true
        defer { isLoading = false }

        do {
            meetings = try await GroupManager.shared.getMeetings(in: groupId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addMeetings(_ meetingIds: [UUID], to groupId: UUID) async {
        do {
            try await GroupManager.shared.addMeetings(meetingIds, to: groupId)
            await loadMeetings(for: groupId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeMeeting(_ meetingId: UUID, from groupId: UUID) async {
        do {
            try await GroupManager.shared.removeMeeting(meetingId, from: groupId)
            meetings.removeAll { $0.id == meetingId }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func copyCombinedTranscript(for groupId: UUID) async {
        do {
            if let transcript = try await GroupManager.shared.getCombinedTranscript(for: groupId) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(transcript, forType: .string)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportGroup(_ groupId: UUID) async {
        do {
            try await GroupManager.shared.exportGroup(groupId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Previews

#Preview("Groups List") {
    MeetingGroupsListView()
        .frame(width: 350, height: 500)
}

#Preview("Group Row") {
    VStack(spacing: 8) {
        ForEach(MeetingGroup.sampleGroups) { group in
            GroupRowView(group: group)
        }
    }
    .padding()
    .background(Color.brandBackground)
}
