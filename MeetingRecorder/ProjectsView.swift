//
//  ProjectsView.swift
//  MeetingRecorder
//
//  UI for managing meeting projects: list, create, edit, and view project details
//  Includes auto-classification features and project learning
//

import SwiftUI

// MARK: - Projects List View

/// Main view showing all meeting projects
struct ProjectsListView: View {
    @StateObject private var viewModel = ProjectsViewModel()
    @State private var selectedProject: Project?
    @State private var isCreatingProject = false
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header with title and add button
            HStack {
                Text("Projects")
                    .font(.brandDisplay(18, weight: .bold))
                    .foregroundColor(.brandTextPrimary)

                Spacer()

                BrandIconButton(icon: "plus", size: 32) {
                    isCreatingProject = true
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Search bar
            BrandSearchField(placeholder: "Search projects...", text: $searchText)
                .padding(.horizontal, 12)

            if viewModel.isLoading {
                VStack(spacing: 12) {
                    BrandLoadingIndicator(size: .large)
                    Text("Loading projects...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredProjects.isEmpty {
                EmptyProjectsView(hasSearchQuery: !searchText.isEmpty) {
                    isCreatingProject = true
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredProjects) { project in
                            ProjectRowView(project: project)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedProject = project
                                }
                                .contextMenu {
                                    ProjectContextMenu(project: project, viewModel: viewModel)
                                }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }
        }
        .sheet(item: $selectedProject) { project in
            ProjectDashboardView(project: project)
        }
        .sheet(isPresented: $isCreatingProject) {
            CreateProjectSheet(viewModel: viewModel)
        }
        .task {
            await viewModel.loadProjects()
        }
    }

    private var filteredProjects: [Project] {
        if searchText.isEmpty {
            return viewModel.projects
        }
        return viewModel.projects.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.description?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
}

// MARK: - Project Row View

struct ProjectRowView: View {
    let project: Project

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Emoji or folder icon
            ZStack {
                RoundedRectangle(cornerRadius: BrandRadius.small)
                    .fill(projectColor.opacity(0.15))
                    .frame(width: 40, height: 40)

                if let emoji = project.emoji {
                    Text(emoji)
                        .font(.system(size: 20))
                } else {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 16))
                        .foregroundColor(projectColor)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.brandDisplay(14, weight: .semibold))
                    .foregroundColor(.brandTextPrimary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text("\(project.meetingCount) meetings")
                        .font(.brandDisplay(12, weight: .regular))
                        .foregroundColor(.brandTextSecondary)

                    if project.totalDuration > 0 {
                        Text("·")
                            .foregroundColor(.brandTextSecondary)
                        Text(project.formattedDuration)
                            .font(.brandDisplay(12, weight: .regular))
                            .foregroundColor(.brandTextSecondary)
                    }

                    // Auto-classify indicator
                    if project.autoClassifyEnabled {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10))
                            .foregroundColor(.brandViolet)
                            .help("Auto-classification enabled")
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

    private var projectColor: Color {
        guard let colorName = project.color,
              let projectColor = Project.ProjectColor(rawValue: colorName) else {
            return .brandViolet
        }
        switch projectColor {
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

// MARK: - Project Detail View

struct ProjectDetailView: View {
    let project: Project

    @StateObject private var viewModel = ProjectDetailViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var isAddingMeetings = false
    @State private var selectedMeeting: Meeting?
    @State private var isEditingDescription = false
    @State private var showLearnPatterns = false

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

                if let emoji = project.emoji {
                    Text(emoji)
                        .font(.system(size: 24))
                }

                Text(project.name)
                    .font(.brandDisplay(18, weight: .bold))
                    .foregroundColor(.brandTextPrimary)

                Spacer()

                HStack(spacing: 8) {
                    // Learn patterns button
                    Button(action: { showLearnPatterns = true }) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.brandViolet)
                    }
                    .buttonStyle(.plain)
                    .help("Learn patterns from meetings")

                    BrandIconButton(icon: "plus", size: 28) {
                        isAddingMeetings = true
                    }
                }
            }
            .padding(16)

            // Description (if exists)
            if let description = project.description {
                Text(description)
                    .font(.brandDisplay(13, weight: .regular))
                    .foregroundColor(.brandTextSecondary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

            // Stats bar
            HStack(spacing: 16) {
                StatPill(label: "Meetings", value: "\(viewModel.meetings.count)")
                StatPill(label: "Duration", value: project.formattedDuration)
                if project.totalCostCents > 0 {
                    StatPill(label: "Cost", value: project.formattedCost)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            // Classification patterns summary
            if project.speakerPatterns?.isEmpty == false || project.themeKeywords?.isEmpty == false {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11))
                        .foregroundColor(.brandViolet)

                    if let patterns = project.speakerPatterns, !patterns.isEmpty {
                        Text("Speakers: \(patterns.prefix(3).joined(separator: ", "))")
                            .font(.brandDisplay(11, weight: .regular))
                            .foregroundColor(.brandTextSecondary)
                            .lineLimit(1)
                    }

                    if let keywords = project.themeKeywords, !keywords.isEmpty {
                        Text("Keywords: \(keywords.prefix(3).joined(separator: ", "))")
                            .font(.brandDisplay(11, weight: .regular))
                            .foregroundColor(.brandTextSecondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

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

                    Text("No meetings in this project")
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
                            ProjectMeetingRowView(meeting: meeting) {
                                Task {
                                    await viewModel.removeMeeting(meeting.id, from: project.id)
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
                            await viewModel.copyCombinedTranscript(for: project.id)
                        }
                    }

                    BrandSecondaryButton(title: "Export for Agent", icon: "square.and.arrow.up", size: .small) {
                        Task {
                            await viewModel.exportProject(project.id)
                        }
                    }
                }
                .padding(12)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(Color.brandBackground)
        .sheet(isPresented: $isAddingMeetings) {
            AddMeetingsToProjectSheet(project: project, viewModel: viewModel)
        }
        .sheet(item: $selectedMeeting) { meeting in
            MeetingDetailView(meeting: meeting)
        }
        .sheet(isPresented: $showLearnPatterns) {
            LearnPatternsSheet(project: project, viewModel: viewModel)
        }
        .task {
            await viewModel.loadMeetings(for: project.id)
        }
    }
}

// MARK: - Learn Patterns Sheet

struct LearnPatternsSheet: View {
    let project: Project
    @ObservedObject var viewModel: ProjectDetailViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var learnedSpeakers: [String] = []
    @State private var learnedKeywords: [String] = []
    @State private var selectedSpeakers: Set<String> = []
    @State private var selectedKeywords: Set<String> = []
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Learn Patterns")
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

            Divider()

            if isLoading {
                VStack(spacing: 12) {
                    BrandLoadingIndicator(size: .large)
                    Text("Analyzing meetings...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Speakers section
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "person.2")
                                    .foregroundColor(.brandViolet)
                                Text("Speakers")
                                    .font(.brandDisplay(14, weight: .semibold))
                            }

                            if learnedSpeakers.isEmpty {
                                Text("No recurring speakers found")
                                    .font(.brandDisplay(13, weight: .regular))
                                    .foregroundColor(.brandTextSecondary)
                                    .padding(.vertical, 8)
                            } else {
                                PatternFlowLayout(spacing: 8) {
                                    ForEach(learnedSpeakers, id: \.self) { speaker in
                                        PatternChip(
                                            text: speaker,
                                            isSelected: selectedSpeakers.contains(speaker),
                                            onToggle: {
                                                if selectedSpeakers.contains(speaker) {
                                                    selectedSpeakers.remove(speaker)
                                                } else {
                                                    selectedSpeakers.insert(speaker)
                                                }
                                            }
                                        )
                                    }
                                }
                            }
                        }

                        // Keywords section
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "tag")
                                    .foregroundColor(.brandViolet)
                                Text("Keywords")
                                    .font(.brandDisplay(14, weight: .semibold))
                            }

                            if learnedKeywords.isEmpty {
                                Text("No recurring keywords found")
                                    .font(.brandDisplay(13, weight: .regular))
                                    .foregroundColor(.brandTextSecondary)
                                    .padding(.vertical, 8)
                            } else {
                                PatternFlowLayout(spacing: 8) {
                                    ForEach(learnedKeywords, id: \.self) { keyword in
                                        PatternChip(
                                            text: keyword,
                                            isSelected: selectedKeywords.contains(keyword),
                                            onToggle: {
                                                if selectedKeywords.contains(keyword) {
                                                    selectedKeywords.remove(keyword)
                                                } else {
                                                    selectedKeywords.insert(keyword)
                                                }
                                            }
                                        )
                                    }
                                }
                            }
                        }

                        Text("Selected patterns will be used to auto-classify future meetings into this project.")
                            .font(.brandDisplay(12, weight: .regular))
                            .foregroundColor(.brandTextSecondary)
                    }
                    .padding(16)
                }
            }

            Divider()

            HStack {
                BrandSecondaryButton(title: "Cancel") {
                    dismiss()
                }

                Spacer()

                BrandPrimaryButton(
                    title: "Save Patterns",
                    icon: "sparkles",
                    isDisabled: selectedSpeakers.isEmpty && selectedKeywords.isEmpty
                ) {
                    Task {
                        await viewModel.updateProjectPatterns(
                            project.id,
                            speakers: Array(selectedSpeakers),
                            keywords: Array(selectedKeywords)
                        )
                        dismiss()
                    }
                }
            }
            .padding(16)
        }
        .frame(width: 400, height: 450)
        .background(Color.brandBackground)
        .task {
            await loadPatterns()
        }
    }

    private func loadPatterns() async {
        isLoading = true
        defer { isLoading = false }

        do {
            learnedSpeakers = try await ProjectManager.shared.learnSpeakerPatterns(for: project.id)
            learnedKeywords = try await ProjectManager.shared.learnThemeKeywords(for: project.id)

            // Pre-select existing patterns
            if let existing = project.speakerPatterns {
                selectedSpeakers = Set(existing)
            }
            if let existing = project.themeKeywords {
                selectedKeywords = Set(existing)
            }
        } catch {
            print("[LearnPatterns] Error: \(error)")
        }
    }
}

// MARK: - Pattern Chip

struct PatternChip: View {
    let text: String
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 4) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                }
                Text(text)
                    .font(.brandDisplay(12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: BrandRadius.small)
                    .fill(isSelected ? Color.brandViolet.opacity(0.15) : Color.brandSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BrandRadius.small)
                    .stroke(isSelected ? Color.brandViolet : Color.brandBorder, lineWidth: 1)
            )
            .foregroundColor(isSelected ? .brandViolet : .brandTextPrimary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow Layout (for chips)

struct PatternFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (subview, point) in zip(subviews, result.points) {
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var maxHeight: CGFloat = 0
        let maxWidth = proposal.width ?? .infinity

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += maxHeight + spacing
                maxHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            maxHeight = max(maxHeight, size.height)
        }

        return (CGSize(width: maxWidth, height: y + maxHeight), points)
    }
}

// MARK: - Project Meeting Row

struct ProjectMeetingRowView: View {
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

// MARK: - Create Project Sheet

struct CreateProjectSheet: View {
    @ObservedObject var viewModel: ProjectsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var selectedEmoji: String?
    @State private var selectedColor: Project.ProjectColor = .violet
    @State private var autoClassify = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Project")
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

                    // Auto-classify toggle
                    HStack {
                        Toggle(isOn: $autoClassify) {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .foregroundColor(.brandViolet)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Auto-classify meetings")
                                        .font(.brandDisplay(13, weight: .medium))
                                    Text("Automatically add meetings that match this project's patterns")
                                        .font(.brandDisplay(11, weight: .regular))
                                        .foregroundColor(.brandTextSecondary)
                                }
                            }
                        }
                        .toggleStyle(.switch)
                    }

                    // Emoji picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Icon")
                            .font(.brandDisplay(12, weight: .medium))
                            .foregroundColor(.brandTextSecondary)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 8) {
                            ForEach(Project.suggestedEmojis, id: \.self) { emoji in
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
                            ForEach(Project.ProjectColor.allCases, id: \.self) { color in
                                Button(action: { selectedColor = color }) {
                                    Circle()
                                        .fill(colorForProjectColor(color))
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

                BrandPrimaryButton(title: "Create Project", icon: "folder.badge.plus", isDisabled: name.isEmpty) {
                    Task {
                        await viewModel.createProject(
                            name: name,
                            description: description.isEmpty ? nil : description,
                            emoji: selectedEmoji,
                            color: selectedColor.rawValue,
                            autoClassifyEnabled: autoClassify
                        )
                        dismiss()
                    }
                }
            }
            .padding(16)
        }
        .frame(width: 400, height: 550)
        .background(Color.brandBackground)
    }

    private func colorForProjectColor(_ color: Project.ProjectColor) -> Color {
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

struct AddMeetingsToProjectSheet: View {
    let project: Project
    @ObservedObject var viewModel: ProjectDetailViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var availableMeetings: [Meeting] = []
    @State private var selectedMeetings: Set<UUID> = []
    @State private var searchText = ""
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Meetings to \(project.name)")
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
                            MeetingSelectionRowForProject(
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
                        await viewModel.addMeetings(Array(selectedMeetings), to: project.id)
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

struct MeetingSelectionRowForProject: View {
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
            BrandStatusBadge(status: meetingToBadgeStatusForProject(meeting.status))
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

struct EmptyProjectsView: View {
    let hasSearchQuery: Bool
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: hasSearchQuery ? "magnifyingglass" : "folder.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(.brandTextSecondary)

            Text(hasSearchQuery ? "No projects match your search" : "No projects yet")
                .font(.brandDisplay(16, weight: .semibold))
                .foregroundColor(.brandTextPrimary)

            Text(hasSearchQuery ? "Try a different search term" : "Create a project to organize related meetings together")
                .font(.brandDisplay(13, weight: .regular))
                .foregroundColor(.brandTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if !hasSearchQuery {
                BrandPrimaryButton(title: "Create Project", icon: "folder.badge.plus", size: .medium) {
                    onCreate()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ProjectContextMenu: View {
    let project: Project
    @ObservedObject var viewModel: ProjectsViewModel

    var body: some View {
        Button(action: {
            Task {
                await viewModel.exportProject(project.id)
            }
        }) {
            Label("Export for Agent", systemImage: "square.and.arrow.up")
        }

        Divider()

        Button(role: .destructive, action: {
            Task {
                await viewModel.deleteProject(project.id)
            }
        }) {
            Label("Delete Project", systemImage: "trash")
        }
    }
}

// MARK: - Helpers

/// Convert MeetingStatus to BrandStatusBadge.Status
private func meetingToBadgeStatusForProject(_ status: MeetingStatus) -> BrandStatusBadge.Status {
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
class ProjectsViewModel: ObservableObject {
    @Published var projects: [Project] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func loadProjects() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Wait for database to be initialized before querying
            try await DatabaseManager.shared.waitForInitialization()
            projects = try await ProjectManager.shared.getAllProjects()
        } catch {
            errorMessage = error.localizedDescription
            print("[ProjectsView] Error loading projects: \(error)")
        }
    }

    func createProject(
        name: String,
        description: String?,
        emoji: String?,
        color: String?,
        autoClassifyEnabled: Bool = true
    ) async {
        do {
            let project = try await ProjectManager.shared.createProject(
                name: name,
                description: description,
                emoji: emoji,
                color: color,
                autoClassifyEnabled: autoClassifyEnabled
            )
            projects.append(project)
            projects.sort { $0.name < $1.name }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteProject(_ projectId: UUID) async {
        do {
            try await ProjectManager.shared.deleteProject(projectId)
            projects.removeAll { $0.id == projectId }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportProject(_ projectId: UUID) async {
        do {
            try await ProjectManager.shared.exportProject(projectId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
class ProjectDetailViewModel: ObservableObject {
    @Published var meetings: [Meeting] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func loadMeetings(for projectId: UUID) async {
        isLoading = true
        defer { isLoading = false }

        do {
            meetings = try await ProjectManager.shared.getMeetings(in: projectId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addMeetings(_ meetingIds: [UUID], to projectId: UUID) async {
        do {
            try await ProjectManager.shared.addMeetings(meetingIds, to: projectId)
            await loadMeetings(for: projectId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeMeeting(_ meetingId: UUID, from projectId: UUID) async {
        do {
            try await ProjectManager.shared.removeMeeting(meetingId, from: projectId)
            meetings.removeAll { $0.id == meetingId }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func copyCombinedTranscript(for projectId: UUID) async {
        do {
            if let transcript = try await ProjectManager.shared.getCombinedTranscript(for: projectId) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(transcript, forType: .string)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportProject(_ projectId: UUID) async {
        do {
            try await ProjectManager.shared.exportProject(projectId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateProjectPatterns(_ projectId: UUID, speakers: [String], keywords: [String]) async {
        do {
            guard var project = try await ProjectManager.shared.getProject(id: projectId) else { return }
            project.speakerPatterns = speakers.isEmpty ? nil : speakers
            project.themeKeywords = keywords.isEmpty ? nil : keywords
            try await ProjectManager.shared.updateProject(project)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// Note: MeetingGroupsListView still exists in MeetingGroupsView.swift
// The navigation now uses ProjectsListView directly

// MARK: - Previews

#Preview("Projects List") {
    ProjectsListView()
        .frame(width: 350, height: 500)
}

#Preview("Project Row") {
    VStack(spacing: 8) {
        ForEach(Project.sampleProjects) { project in
            ProjectRowView(project: project)
        }
    }
    .padding()
    .background(Color.brandBackground)
}
