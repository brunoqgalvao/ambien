//
//  ProjectDashboardView.swift
//  MeetingRecorder
//
//  Full-screen project dashboard with meetings list and AI chat panel
//  Provides context-aware chat with all project meetings
//

import SwiftUI

// MARK: - Project Dashboard View

struct ProjectDashboardView: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss

    @StateObject private var viewModel = ProjectDashboardViewModel()
    @State private var selectedMeeting: Meeting?
    @State private var chatInput = ""
    @State private var isAddingMeetings = false
    @State private var showLearnPatterns = false
    @State private var meetingsListWidth: CGFloat = 320
    @State private var selectedRightTab: RightPanelTab = .chat

    enum RightPanelTab: String, CaseIterable {
        case chat = "Chat"
        case speakers = "Speakers"
        case vocabulary = "Vocabulary"

        var icon: String {
            switch self {
            case .chat: return "bubble.left.and.bubble.right"
            case .speakers: return "person.2"
            case .vocabulary: return "textformat.abc"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            dashboardHeader

            Divider()

            // Main content: Meetings + Right Panel
            HStack(spacing: 0) {
                // Left: Meetings list
                meetingsPanel
                    .frame(width: meetingsListWidth)

                // Resize handle
                Rectangle()
                    .fill(Color.brandBorder)
                    .frame(width: 1)
                    .overlay(
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 8)
                            .cursor(.resizeLeftRight)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        let newWidth = meetingsListWidth + value.translation.width
                                        meetingsListWidth = max(250, min(500, newWidth))
                                    }
                            )
                    )

                // Right: Tabbed panel (Chat / Speakers / Vocabulary) or Meeting Detail
                if let meeting = selectedMeeting {
                    // Show meeting detail with back button
                    meetingDetailPanel(meeting)
                } else {
                    // Show tabbed panel
                    rightTabbedPanel
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Color.brandBackground)
        .sheet(isPresented: $isAddingMeetings) {
            AddMeetingsToProjectSheet(project: project, viewModel: viewModel.detailViewModel)
        }
        .sheet(isPresented: $showLearnPatterns) {
            LearnPatternsSheet(project: project, viewModel: viewModel.detailViewModel)
        }
        .task {
            await viewModel.load(project: project)
        }
    }

    // MARK: - Right Tabbed Panel

    private var rightTabbedPanel: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(RightPanelTab.allCases, id: \.self) { tab in
                    RightTabButton(
                        title: tab.rawValue,
                        icon: tab.icon,
                        isSelected: selectedRightTab == tab
                    ) {
                        selectedRightTab = tab
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Divider()
                .padding(.top, 8)

            // Tab content
            switch selectedRightTab {
            case .chat:
                chatPanel
            case .speakers:
                speakersPanel
            case .vocabulary:
                vocabularyPanel
            }
        }
        .background(Color.brandBackground)
    }

    // MARK: - Header

    private var dashboardHeader: some View {
        HStack(spacing: 16) {
            // Back button
            Button(action: { dismiss() }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Projects")
                        .font(.brandDisplay(13, weight: .medium))
                }
                .foregroundColor(.brandTextSecondary)
            }
            .buttonStyle(.plain)

            // Project icon + name
            HStack(spacing: 10) {
                if let emoji = project.emoji {
                    Text(emoji)
                        .font(.system(size: 28))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.brandViolet.opacity(0.1))
                            .frame(width: 36, height: 36)
                        Image(systemName: "folder.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.brandViolet)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.brandDisplay(18, weight: .bold))
                        .foregroundColor(.brandTextPrimary)

                    if let description = project.description {
                        Text(description)
                            .font(.brandDisplay(12, weight: .regular))
                            .foregroundColor(.brandTextSecondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Stats pills
            HStack(spacing: 12) {
                StatPill(label: "Meetings", value: "\(viewModel.meetings.count)")
                StatPill(label: "Duration", value: project.formattedDuration)

                if project.autoClassifyEnabled {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                        Text("Auto-classify")
                            .font(.brandDisplay(11, weight: .medium))
                    }
                    .foregroundColor(.brandViolet)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: BrandRadius.small)
                            .fill(Color.brandViolet.opacity(0.1))
                    )
                }
            }

            // Actions
            HStack(spacing: 8) {
                Button(action: { showLearnPatterns = true }) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundColor(.brandViolet)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: BrandRadius.small)
                                .fill(Color.brandViolet.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
                .help("Learn patterns from meetings")

                BrandIconButton(icon: "plus", size: 32) {
                    isAddingMeetings = true
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.brandBackground)
    }

    // MARK: - Meetings Panel

    private var meetingsPanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Meetings")
                    .font(.brandDisplay(14, weight: .semibold))
                    .foregroundColor(.brandTextPrimary)

                Spacer()

                Text("\(viewModel.meetings.count)")
                    .font(.brandDisplay(12, weight: .medium))
                    .foregroundColor(.brandTextSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.brandSurface)
                    )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

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
                        .font(.system(size: 32))
                        .foregroundColor(.brandTextSecondary)

                    Text("No meetings yet")
                        .font(.brandDisplay(14, weight: .medium))
                        .foregroundColor(.brandTextSecondary)

                    BrandPrimaryButton(title: "Add Meetings", icon: "plus", size: .small) {
                        isAddingMeetings = true
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(viewModel.meetings) { meeting in
                            ProjectMeetingCard(
                                meeting: meeting,
                                isSelected: selectedMeeting?.id == meeting.id,
                                onSelect: { selectedMeeting = meeting },
                                onRemove: {
                                    Task {
                                        await viewModel.removeMeeting(meeting.id)
                                    }
                                }
                            )
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(Color.white)
    }

    // MARK: - Meeting Detail Panel

    private func meetingDetailPanel(_ meeting: Meeting) -> some View {
        VStack(spacing: 0) {
            // Back to chat header
            HStack {
                Button(action: { selectedMeeting = nil }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Back to Chat")
                            .font(.brandDisplay(13, weight: .medium))
                    }
                    .foregroundColor(.brandViolet)
                }
                .buttonStyle(.plain)

                Spacer()

                // Quick actions
                HStack(spacing: 8) {
                    Button(action: {
                        if let transcript = meeting.transcript {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(transcript, forType: .string)
                        }
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                            .foregroundColor(.brandTextSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy transcript")
                    .disabled(meeting.transcript == nil)

                    Button(action: {
                        // Add to chat context
                        viewModel.addMeetingToContext(meeting)
                        selectedMeeting = nil
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "bubble.left.and.text.bubble.right")
                                .font(.system(size: 11))
                            Text("Ask about this")
                                .font(.brandDisplay(12, weight: .medium))
                        }
                        .foregroundColor(.brandViolet)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: BrandRadius.small)
                                .fill(Color.brandViolet.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.brandBackground)

            Divider()

            // Meeting content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title and meta
                    VStack(alignment: .leading, spacing: 8) {
                        Text(meeting.title)
                            .font(.brandDisplay(20, weight: .bold))
                            .foregroundColor(.brandTextPrimary)

                        HStack(spacing: 16) {
                            Label(meeting.startTime.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                            Label(meeting.formattedDuration, systemImage: "clock")
                            if let source = meeting.sourceApp {
                                Label(source, systemImage: "app")
                            }
                        }
                        .font(.brandDisplay(12, weight: .regular))
                        .foregroundColor(.brandTextSecondary)
                    }

                    Divider()

                    // Transcript
                    if let transcript = meeting.transcript {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Transcript")
                                .font(.brandDisplay(14, weight: .semibold))
                                .foregroundColor(.brandTextPrimary)

                            Text(transcript)
                                .font(.brandSerif(15))
                                .lineSpacing(6)
                                .foregroundColor(.brandTextPrimary)
                                .textSelection(.enabled)
                        }
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: statusIcon(for: meeting.status))
                                .foregroundColor(statusColor(for: meeting.status))
                            Text(statusText(for: meeting.status))
                                .font(.brandDisplay(13, weight: .regular))
                                .foregroundColor(.brandTextSecondary)
                        }
                    }
                }
                .padding(24)
            }
            .background(Color.brandBackground)
        }
    }

    // MARK: - Chat Panel

    private var chatPanel: some View {
        VStack(spacing: 0) {
            // Chat header
            HStack {
                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 14))
                    .foregroundColor(.brandViolet)

                Text("Chat with Project")
                    .font(.brandDisplay(14, weight: .semibold))
                    .foregroundColor(.brandTextPrimary)

                Spacer()

                if !viewModel.chatMessages.isEmpty {
                    Button(action: { viewModel.clearChat() }) {
                        Text("Clear")
                            .font(.brandDisplay(12, weight: .medium))
                            .foregroundColor(.brandTextSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.brandBackground)

            Divider()

            // Chat messages
            if viewModel.chatMessages.isEmpty {
                // Empty state with suggestions
                chatEmptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.chatMessages) { message in
                                ChatMessageBubble(message: message)
                                    .id(message.id)
                            }

                            if viewModel.isGenerating {
                                HStack(spacing: 8) {
                                    BrandLoadingIndicator(size: .small)
                                    Text("Thinking...")
                                        .font(.brandDisplay(13, weight: .regular))
                                        .foregroundColor(.brandTextSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                            }
                        }
                        .padding(20)
                    }
                    .onChange(of: viewModel.chatMessages.count) { _, _ in
                        if let lastMessage = viewModel.chatMessages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }

            Divider()

            // Chat input
            chatInputBar
        }
        .background(Color.white)
    }

    private var chatEmptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 40))
                    .foregroundColor(.brandViolet.opacity(0.5))

                Text("Ask anything about this project")
                    .font(.brandDisplay(16, weight: .semibold))
                    .foregroundColor(.brandTextPrimary)

                Text("I have access to all \(viewModel.meetings.count) meetings in this project")
                    .font(.brandDisplay(13, weight: .regular))
                    .foregroundColor(.brandTextSecondary)
            }

            // Suggested prompts
            VStack(spacing: 8) {
                Text("Try asking:")
                    .font(.brandDisplay(12, weight: .medium))
                    .foregroundColor(.brandTextSecondary)

                VStack(spacing: 8) {
                    SuggestedPromptButton(text: "Summarize all meetings in this project") {
                        sendMessage("Summarize all meetings in this project")
                    }

                    SuggestedPromptButton(text: "What are the key decisions made?") {
                        sendMessage("What are the key decisions made across these meetings?")
                    }

                    SuggestedPromptButton(text: "List all action items") {
                        sendMessage("List all action items mentioned in these meetings")
                    }

                    SuggestedPromptButton(text: "Who are the main participants?") {
                        sendMessage("Who are the main participants in this project's meetings?")
                    }
                }
            }

            Spacer()
        }
        .padding(24)
    }

    private var chatInputBar: some View {
        HStack(spacing: 12) {
            TextField("Ask about this project...", text: $chatInput)
                .textFieldStyle(.plain)
                .font(.brandDisplay(14, weight: .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: BrandRadius.medium)
                        .fill(Color.brandSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: BrandRadius.medium)
                        .stroke(Color.brandBorder, lineWidth: 1)
                )
                .onSubmit {
                    sendMessage(chatInput)
                }

            Button(action: { sendMessage(chatInput) }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(chatInput.isEmpty ? .brandTextSecondary : .brandViolet)
            }
            .buttonStyle(.plain)
            .disabled(chatInput.isEmpty || viewModel.isGenerating)
        }
        .padding(16)
        .background(Color.brandBackground)
    }

    // MARK: - Speakers Panel

    private var speakersPanel: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading {
                VStack(spacing: 12) {
                    BrandLoadingIndicator(size: .large)
                    Text("Loading speakers...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.projectSpeakers.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "person.2")
                        .font(.system(size: 40))
                        .foregroundColor(.brandTextSecondary)

                    Text("No speakers identified")
                        .font(.brandDisplay(16, weight: .semibold))
                        .foregroundColor(.brandTextPrimary)

                    Text("Speakers will appear here once meetings have been transcribed with speaker labels")
                        .font(.brandDisplay(13, weight: .regular))
                        .foregroundColor(.brandTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.projectSpeakers, id: \.name) { speaker in
                            SpeakerCard(speaker: speaker)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .background(Color.white)
        .task {
            await viewModel.loadSpeakers()
        }
    }

    // MARK: - Vocabulary Panel

    private var vocabularyPanel: some View {
        VStack(spacing: 0) {
            if viewModel.isLoading {
                VStack(spacing: 12) {
                    BrandLoadingIndicator(size: .large)
                    Text("Analyzing vocabulary...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.projectVocabulary.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "textformat.abc")
                        .font(.system(size: 40))
                        .foregroundColor(.brandTextSecondary)

                    Text("No vocabulary extracted")
                        .font(.brandDisplay(16, weight: .semibold))
                        .foregroundColor(.brandTextPrimary)

                    Text("Key terms and phrases will appear here once meetings have been transcribed")
                        .font(.brandDisplay(13, weight: .regular))
                        .foregroundColor(.brandTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Word cloud style layout
                        Text("Frequently Used Terms")
                            .font(.brandDisplay(14, weight: .semibold))
                            .foregroundColor(.brandTextPrimary)

                        ProjectFlowLayout(spacing: 8) {
                            ForEach(viewModel.projectVocabulary, id: \.term) { vocab in
                                VocabularyChip(vocab: vocab)
                            }
                        }

                        if !viewModel.projectPhrases.isEmpty {
                            Divider()
                                .padding(.vertical, 8)

                            Text("Common Phrases")
                                .font(.brandDisplay(14, weight: .semibold))
                                .foregroundColor(.brandTextPrimary)

                            ForEach(viewModel.projectPhrases, id: \.phrase) { phrase in
                                PhraseRow(phrase: phrase)
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .background(Color.white)
        .task {
            await viewModel.loadVocabulary()
        }
    }

    // MARK: - Helpers

    private func sendMessage(_ text: String) {
        guard !text.isEmpty else { return }
        let messageText = text
        chatInput = ""
        Task {
            await viewModel.sendMessage(messageText)
        }
    }

    private func statusIcon(for status: MeetingStatus) -> String {
        switch status {
        case .recording: return "record.circle"
        case .pendingTranscription: return "clock"
        case .transcribing: return "waveform"
        case .ready: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private func statusColor(for status: MeetingStatus) -> Color {
        switch status {
        case .recording: return .red
        case .pendingTranscription: return .orange
        case .transcribing: return .brandViolet
        case .ready: return .brandMint
        case .failed: return .brandCoral
        }
    }

    private func statusText(for status: MeetingStatus) -> String {
        switch status {
        case .recording: return "Recording in progress..."
        case .pendingTranscription: return "Waiting for transcription..."
        case .transcribing: return "Transcribing..."
        case .ready: return "Ready"
        case .failed: return "Transcription failed"
        }
    }
}

// MARK: - Project Meeting Card

struct ProjectMeetingCard: View {
    let meeting: Meeting
    let isSelected: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Status dot
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 3) {
                    Text(meeting.title)
                        .font(.brandDisplay(13, weight: .medium))
                        .foregroundColor(isSelected ? .white : .brandTextPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(meeting.startTime.formatted(date: .abbreviated, time: .omitted))
                            .font(.brandDisplay(11, weight: .regular))

                        Text("·")

                        Text(meeting.formattedDuration)
                            .font(.brandDisplay(11, weight: .regular))
                    }
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .brandTextSecondary)
                }

                Spacer()

                if isHovered && !isSelected {
                    Button(action: onRemove) {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 14))
                            .foregroundColor(.brandCoral)
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(isSelected ? .white.opacity(0.6) : .brandTextSecondary.opacity(0.5))
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: BrandRadius.small)
                    .fill(isSelected ? Color.brandViolet : (isHovered ? Color.brandViolet.opacity(0.05) : Color.brandSurface))
            )
            .overlay(
                RoundedRectangle(cornerRadius: BrandRadius.small)
                    .stroke(isSelected ? Color.brandViolet : Color.brandBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var statusColor: Color {
        switch meeting.status {
        case .ready: return isSelected ? .white : .brandMint
        case .transcribing: return isSelected ? .white : .brandViolet
        case .failed: return .brandCoral
        default: return isSelected ? .white.opacity(0.6) : .brandAmber
        }
    }
}

// MARK: - Chat Message

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String
    let timestamp: Date

    enum Role {
        case user
        case assistant
    }
}

struct ChatMessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .assistant {
                // AI avatar
                ZStack {
                    Circle()
                        .fill(Color.brandViolet.opacity(0.1))
                        .frame(width: 32, height: 32)

                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundColor(.brandViolet)
                }
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.brandDisplay(14, weight: .regular))
                    .foregroundColor(message.role == .user ? .white : .brandTextPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: BrandRadius.medium)
                            .fill(message.role == .user ? Color.brandViolet : Color.brandSurface)
                    )
                    .textSelection(.enabled)

                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.brandDisplay(10, weight: .regular))
                    .foregroundColor(.brandTextSecondary)
            }
            .frame(maxWidth: 500, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .user {
                // User avatar
                ZStack {
                    Circle()
                        .fill(Color.brandViolet)
                        .frame(width: 32, height: 32)

                    Image(systemName: "person.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

// MARK: - Suggested Prompt Button

struct SuggestedPromptButton: View {
    let text: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "sparkle")
                    .font(.system(size: 11))
                    .foregroundColor(.brandViolet)

                Text(text)
                    .font(.brandDisplay(13, weight: .regular))
                    .foregroundColor(.brandTextPrimary)

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.brandTextSecondary)
                    .opacity(isHovered ? 1 : 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: BrandRadius.small)
                    .fill(isHovered ? Color.brandViolet.opacity(0.05) : Color.brandSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BrandRadius.small)
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

// MARK: - Right Tab Button

struct RightTabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))

                Text(title)
                    .font(.brandDisplay(13, weight: isSelected ? .semibold : .medium))
            }
            .foregroundColor(isSelected ? .brandViolet : .brandTextSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: BrandRadius.small)
                    .fill(isSelected ? Color.brandViolet.opacity(0.1) : (isHovered ? Color.brandViolet.opacity(0.05) : Color.clear))
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

// MARK: - Speaker Card

struct SpeakerCard: View {
    let speaker: ProjectSpeaker

    private let avatarColors: [Color] = [.blue, .purple, .orange, .green, .pink, .teal, .indigo, .mint]

    var body: some View {
        HStack(spacing: 14) {
            // Avatar
            ZStack {
                Circle()
                    .fill(avatarColor)
                    .frame(width: 44, height: 44)

                Text(speaker.name.prefix(1).uppercased())
                    .font(.brandDisplay(18, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(speaker.name)
                    .font(.brandDisplay(14, weight: .semibold))
                    .foregroundColor(.brandTextPrimary)

                HStack(spacing: 12) {
                    Label("\(speaker.meetingCount) meetings", systemImage: "calendar")

                    if speaker.totalSpeakingTime > 0 {
                        Label(formattedTime, systemImage: "clock")
                    }
                }
                .font(.brandDisplay(11, weight: .regular))
                .foregroundColor(.brandTextSecondary)
            }

            Spacer()

            // Last seen
            VStack(alignment: .trailing, spacing: 2) {
                Text("Last seen")
                    .font(.brandDisplay(10, weight: .regular))
                    .foregroundColor(.brandTextSecondary)

                Text(speaker.lastSeen.formatted(date: .abbreviated, time: .omitted))
                    .font(.brandDisplay(11, weight: .medium))
                    .foregroundColor(.brandTextPrimary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: BrandRadius.small)
                .fill(Color.brandSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BrandRadius.small)
                .stroke(Color.brandBorder, lineWidth: 1)
        )
    }

    private var avatarColor: Color {
        let index = abs(speaker.name.hashValue) % avatarColors.count
        return avatarColors[index]
    }

    private var formattedTime: String {
        let hours = Int(speaker.totalSpeakingTime) / 3600
        let minutes = (Int(speaker.totalSpeakingTime) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Vocabulary Chip

struct VocabularyChip: View {
    let vocab: ProjectVocabulary

    var body: some View {
        HStack(spacing: 4) {
            Text(vocab.term)
                .font(.brandDisplay(fontSize, weight: .medium))

            Text("\(vocab.count)")
                .font(.brandDisplay(10, weight: .regular))
                .foregroundColor(.brandViolet)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    Capsule()
                        .fill(Color.brandViolet.opacity(0.15))
                )
        }
        .foregroundColor(.brandTextPrimary)
        .padding(.horizontal, 10)
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

    private var fontSize: CGFloat {
        // Scale font size based on importance (12-16)
        12 + (vocab.importance * 4)
    }
}

// MARK: - Phrase Row

struct PhraseRow: View {
    let phrase: ProjectPhrase

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(phrase.phrase)
                    .font(.brandDisplay(13, weight: .medium))
                    .foregroundColor(.brandTextPrimary)

                Spacer()

                Text("×\(phrase.count)")
                    .font(.brandDisplay(11, weight: .medium))
                    .foregroundColor(.brandViolet)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.brandViolet.opacity(0.1))
                    )

                if phrase.context != nil {
                    Button(action: { isExpanded.toggle() }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.brandTextSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if isExpanded, let context = phrase.context {
                Text("\"\(context.prefix(150))...\"")
                    .font(.brandDisplay(11, weight: .regular))
                    .foregroundColor(.brandTextSecondary)
                    .italic()
                    .padding(.top, 4)
            }
        }
        .padding(12)
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

// MARK: - Flow Layout

private struct ProjectFlowLayout: Layout {
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

// MARK: - View Model

// MARK: - Speaker and Vocabulary Data Types

struct ProjectSpeaker: Identifiable {
    let id = UUID()
    let name: String
    let meetingCount: Int
    let totalSpeakingTime: TimeInterval
    let lastSeen: Date
}

struct ProjectVocabulary {
    let term: String
    let count: Int
    let importance: Double // 0-1 scale based on frequency and uniqueness
}

struct ProjectPhrase {
    let phrase: String
    let count: Int
    let context: String? // Example usage from meetings
}

@MainActor
class ProjectDashboardViewModel: ObservableObject {
    @Published var meetings: [Meeting] = []
    @Published var isLoading = false
    @Published var chatMessages: [ChatMessage] = []
    @Published var isGenerating = false
    @Published var errorMessage: String?

    // Speakers data
    @Published var projectSpeakers: [ProjectSpeaker] = []

    // Vocabulary data
    @Published var projectVocabulary: [ProjectVocabulary] = []
    @Published var projectPhrases: [ProjectPhrase] = []

    private var project: Project?
    let detailViewModel = ProjectDetailViewModel()

    func load(project: Project) async {
        self.project = project
        isLoading = true
        defer { isLoading = false }

        await detailViewModel.loadMeetings(for: project.id)
        meetings = detailViewModel.meetings
    }

    func removeMeeting(_ meetingId: UUID) async {
        guard let project = project else { return }
        await detailViewModel.removeMeeting(meetingId, from: project.id)
        meetings = detailViewModel.meetings
    }

    func addMeetingToContext(_ meeting: Meeting) {
        // Pre-fill with a question about this specific meeting
        let message = "Tell me about the meeting '\(meeting.title)'"
        Task {
            await sendMessage(message)
        }
    }

    func clearChat() {
        chatMessages = []
    }

    // MARK: - Speakers

    func loadSpeakers() async {
        var speakerData: [String: (count: Int, time: TimeInterval, lastSeen: Date)] = [:]

        for meeting in meetings {
            guard let labels = meeting.speakerLabels else { continue }

            for label in labels {
                let name = label.name
                guard !name.isEmpty else { continue }

                // Calculate speaking time from segments if available
                var speakingTime: TimeInterval = 0
                if let segments = meeting.diarizationSegments {
                    for segment in segments where segment.speakerId == label.speakerId {
                        speakingTime += segment.end - segment.start
                    }
                }

                if var existing = speakerData[name] {
                    existing.count += 1
                    existing.time += speakingTime
                    if meeting.startTime > existing.lastSeen {
                        existing.lastSeen = meeting.startTime
                    }
                    speakerData[name] = existing
                } else {
                    speakerData[name] = (count: 1, time: speakingTime, lastSeen: meeting.startTime)
                }
            }
        }

        projectSpeakers = speakerData.map { name, data in
            ProjectSpeaker(
                name: name,
                meetingCount: data.count,
                totalSpeakingTime: data.time,
                lastSeen: data.lastSeen
            )
        }.sorted { $0.meetingCount > $1.meetingCount }
    }

    // MARK: - Vocabulary

    func loadVocabulary() async {
        var wordCounts: [String: Int] = [:]
        let stopWords = Set([
            "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with", "by",
            "is", "are", "was", "were", "be", "been", "being", "have", "has", "had", "do", "does", "did",
            "will", "would", "could", "should", "may", "might", "must", "shall",
            "i", "you", "he", "she", "it", "we", "they", "me", "him", "her", "us", "them",
            "this", "that", "these", "those", "what", "which", "who", "whom", "whose",
            "if", "then", "else", "when", "where", "why", "how", "all", "each", "every",
            "both", "few", "more", "most", "other", "some", "such", "no", "nor", "not", "only",
            "own", "same", "so", "than", "too", "very", "just", "also", "now", "here", "there",
            "yeah", "yes", "no", "okay", "ok", "um", "uh", "like", "know", "think", "going",
            "gonna", "want", "need", "got", "get", "can", "really", "actually", "basically"
        ])

        // Extract words from transcripts
        for meeting in meetings {
            guard let transcript = meeting.transcript else { continue }

            let words = transcript.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 3 && !stopWords.contains($0) }

            for word in words {
                wordCounts[word, default: 0] += 1
            }
        }

        // Calculate total word count for importance scoring
        let totalWords = wordCounts.values.reduce(0, +)

        // Filter to words appearing at least 3 times and sort by frequency
        projectVocabulary = wordCounts
            .filter { $0.value >= 3 }
            .map { word, count in
                let importance = min(1.0, Double(count) / Double(max(totalWords / 100, 1)))
                return ProjectVocabulary(term: word, count: count, importance: importance)
            }
            .sorted { $0.count > $1.count }
            .prefix(50)
            .map { $0 }

        // Extract common phrases (2-3 word combinations)
        var phraseCounts: [String: (count: Int, example: String?)] = [:]

        for meeting in meetings {
            guard let transcript = meeting.transcript else { continue }

            let sentences = transcript.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            for sentence in sentences {
                let words = sentence.lowercased()
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter { !$0.isEmpty }

                // Extract 2-word phrases
                for i in 0..<max(0, words.count - 1) {
                    let phrase = "\(words[i]) \(words[i + 1])"
                    if !stopWords.contains(words[i]) || !stopWords.contains(words[i + 1]) {
                        if phraseCounts[phrase] == nil {
                            phraseCounts[phrase] = (count: 1, example: sentence.trimmingCharacters(in: .whitespaces))
                        } else {
                            phraseCounts[phrase]!.count += 1
                        }
                    }
                }
            }
        }

        projectPhrases = phraseCounts
            .filter { $0.value.count >= 3 }
            .map { phrase, data in
                ProjectPhrase(phrase: phrase, count: data.count, context: data.example)
            }
            .sorted { $0.count > $1.count }
            .prefix(20)
            .map { $0 }
    }

    func sendMessage(_ text: String) async {
        guard project != nil else { return }

        // Add user message
        let userMessage = ChatMessage(role: .user, content: text, timestamp: Date())
        chatMessages.append(userMessage)

        isGenerating = true
        defer { isGenerating = false }

        // Build context from all meetings
        let context = buildProjectContext()

        // Generate response using OpenAI
        do {
            let response = try await generateResponse(userMessage: text, context: context)
            let assistantMessage = ChatMessage(role: .assistant, content: response, timestamp: Date())
            chatMessages.append(assistantMessage)
        } catch {
            let errorResponse = ChatMessage(
                role: .assistant,
                content: "I'm sorry, I encountered an error: \(error.localizedDescription). Please check your API key in Settings.",
                timestamp: Date()
            )
            chatMessages.append(errorResponse)
        }
    }

    private func buildProjectContext() -> String {
        guard let project = project else { return "" }

        var context = "Project: \(project.name)\n"
        if let description = project.description {
            context += "Description: \(description)\n"
        }
        context += "Total meetings: \(meetings.count)\n\n"

        // Add meeting summaries
        context += "=== MEETINGS IN THIS PROJECT ===\n\n"

        for (index, meeting) in meetings.enumerated() {
            context += "--- Meeting \(index + 1): \(meeting.title) ---\n"
            context += "Date: \(meeting.startTime.formatted(date: .long, time: .shortened))\n"
            context += "Duration: \(meeting.formattedDuration)\n"

            if let transcript = meeting.transcript {
                // Truncate very long transcripts
                let maxLength = 3000
                if transcript.count > maxLength {
                    context += "Transcript (truncated):\n\(String(transcript.prefix(maxLength)))...\n\n"
                } else {
                    context += "Transcript:\n\(transcript)\n\n"
                }
            } else {
                context += "(No transcript available)\n\n"
            }
        }

        return context
    }

    private func generateResponse(userMessage: String, context: String) async throws -> String {
        // Get API key from keychain
        guard let apiKey = KeychainHelper.readOpenAIKey() else {
            throw NSError(domain: "ProjectChat", code: 1, userInfo: [NSLocalizedDescriptionKey: "No OpenAI API key found. Please add one in Settings."])
        }

        // Build messages for chat completion
        let systemPrompt = """
        You are a helpful assistant analyzing meeting transcripts for a project.
        You have access to all the meetings in this project and can answer questions about them.
        Be concise but thorough. When quoting from meetings, mention which meeting the quote is from.
        If asked to summarize, provide key points, decisions made, and action items.

        Here is the project context:

        \(context)
        """

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ],
            "max_tokens": 2000,
            "temperature": 0.7
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "ProjectChat", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        guard httpResponse.statusCode == 200 else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw NSError(domain: "ProjectChat", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: message])
            }
            throw NSError(domain: "ProjectChat", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "API error: \(httpResponse.statusCode)"])
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "ProjectChat", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not parse response"])
        }

        return content
    }
}

// MARK: - Preview

#Preview("Project Dashboard") {
    ProjectDashboardView(project: Project.sampleProjects[0])
        .frame(width: 1000, height: 700)
}
