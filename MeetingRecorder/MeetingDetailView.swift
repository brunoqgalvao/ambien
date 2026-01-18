//
//  MeetingDetailView.swift
//  MeetingRecorder
//
//  Shows transcript, audio player, and meeting details
//

import SwiftUI
import AVFoundation

/// Detail view for a single meeting
struct MeetingDetailView: View {
    @State var meeting: Meeting
    var showBackButton: Bool = true
    var onRetry: ((Meeting) -> Void)?
    var onDeleted: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var audioPlayer = AudioPlayerManager()
    @State private var selectedContentTab: TranscriptSummarySection.ContentTab = .summary
    @State private var isProcessing = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                // Rich Amie-style header with editable title/description
                MeetingHeaderSection(
                    meeting: $meeting,
                    showBackButton: showBackButton,
                    onDismiss: { dismiss() },
                    onDelete: { deleteMeeting() }
                )

                Divider()

                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Audio player - show immediately once recording is done
                        // User can listen while transcription happens in background
                        AudioPlayerCard(
                            audioPath: meeting.audioPath,
                            player: audioPlayer
                        )

                        // Share bar (Amie-style export/share buttons)
                        MeetingShareBar(meeting: meeting)

                        // Processing indicator
                        if isProcessing {
                            HStack(spacing: 8) {
                                BrandLoadingIndicator(size: .small)
                                Text("Generating summary...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }

                        // Speakers section (above tabs, outside the tabbed section)
                        SpeakersBar(meeting: $meeting)

                        // New tabbed transcript/summary section
                        TranscriptSummarySection(
                            meeting: $meeting,
                            selectedTab: $selectedContentTab,
                            onReprocess: {
                                await processMeeting()
                            },
                            onRetryTranscription: meeting.status == .failed ? {
                                Task {
                                    await retryTranscription()
                                }
                            } : nil,
                            onReprocessTranscription: {
                                Task {
                                    await reprocessTranscription()
                                }
                            }
                        )
                        .frame(minHeight: 300)

                        // Error message (if failed)
                        if let error = meeting.errorMessage {
                            ErrorSection(message: error, status: meeting.status, onRetry: meeting.status == .failed ? {
                                Task {
                                    await retryTranscription()
                                }
                            } : nil)
                        }
                    }
                    .padding()
                }
            }

            // Bottom-right transcribing indicator
            if meeting.status == .transcribing {
                TranscribingIndicator()
                    .padding(16)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(minWidth: 450, idealWidth: 550, minHeight: 550, idealHeight: 700)
        .background(Color.brandBackground)
        .onDisappear {
            audioPlayer.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: .meetingsDidChange)) { _ in
            Task {
                if let updatedMeeting = try? await DatabaseManager.shared.getMeeting(id: meeting.id) {
                    meeting = updatedMeeting
                }
            }
        }
        // Keyboard shortcuts
        .onKeyPress(.space) {
            if audioPlayer.isReady {
                if audioPlayer.isPlaying {
                    audioPlayer.pause()
                } else {
                    audioPlayer.play(url: URL(fileURLWithPath: meeting.audioPath))
                }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.leftArrow) {
            audioPlayer.skip(seconds: -10)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            audioPlayer.skip(seconds: 10)
            return .handled
        }
        .onKeyPress("c") {
            copyTranscript()
            return .handled
        }
        .onKeyPress(.escape) {
            // Only handle escape if we're showing our own back button
            // Otherwise, let the parent NavigationStack handle it
            if showBackButton {
                dismiss()
                return .handled
            }
            return .ignored
        }
    }

    private func copyTranscript() {
        guard let transcript = meeting.transcript else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
    }

    private func deleteMeeting() {
        audioPlayer.stop()  // Stop playback before deleting

        Task {
            // Delete audio file
            try? FileManager.default.removeItem(atPath: meeting.audioPath)

            // Delete from database
            try? await DatabaseManager.shared.delete(meeting.id)

            // Remove from Agent API exports
            try? await AgentAPIManager.shared.deleteMeeting(meeting.id)

            // Notify UI
            NotificationCenter.default.post(name: .meetingsDidChange, object: nil)

            // Dismiss and notify parent
            await MainActor.run {
                onDeleted?()
                dismiss()
            }
        }
    }

    private func retryTranscription() async {
        meeting.status = .transcribing
        meeting.errorMessage = nil

        // Use AudioCaptureManager's retryTranscription which handles UI feedback properly
        // (shows transcribing island, toast notifications, etc.)
        await AudioCaptureManager.shared.retryTranscription(meetingId: meeting.id)

        // Refresh meeting from database to get updated state
        if let updatedMeeting = try? await DatabaseManager.shared.getMeeting(id: meeting.id) {
            meeting = updatedMeeting
        }

        // Also call the parent callback if provided
        onRetry?(meeting)
    }

    /// Reprocess transcription for an already-transcribed meeting
    private func reprocessTranscription() async {
        // Clear existing transcript and summary data
        meeting.transcript = nil
        meeting.summary = nil
        meeting.actionItems = nil
        meeting.diarizedTranscript = nil
        meeting.diarizationSegments = nil
        meeting.processedSummaries = nil
        meeting.processedAt = nil
        meeting.status = .transcribing
        meeting.errorMessage = nil

        // Save the cleared state
        try? await DatabaseManager.shared.update(meeting)

        // Use AudioCaptureManager's retryTranscription which handles UI feedback properly
        await AudioCaptureManager.shared.retryTranscription(meetingId: meeting.id)

        // Refresh meeting from database to get updated state
        if let updatedMeeting = try? await DatabaseManager.shared.getMeeting(id: meeting.id) {
            meeting = updatedMeeting
        }

        // Also call the parent callback if provided
        onRetry?(meeting)
    }

    /// Process the meeting transcript with AI to generate summary, action items, and diarization
    private func processMeeting() async {
        guard let transcript = meeting.transcript else { return }

        isProcessing = true
        defer { isProcessing = false }

        do {
            // Get the selected template and any other enabled ones
            let selectedTemplate = SummaryTemplateManager.shared.selectedTemplate
            var templatesToRun = [selectedTemplate]

            // Also run action items and speaker transcript if enabled
            let enabledTemplates = SummaryTemplateManager.shared.enabledTemplates
            for template in enabledTemplates {
                if template.id != selectedTemplate.id &&
                   (template.outputFormat == .actionItems || template.outputFormat == .diarizedTranscript) {
                    templatesToRun.append(template)
                }
            }

            // Process with selected templates
            let summaries = try await PostProcessingService.shared.processMultiple(
                transcript: transcript,
                templates: templatesToRun
            )

            // Update meeting with results
            meeting.processedSummaries = summaries
            meeting.processedAt = Date()
            meeting.summaryTemplateId = selectedTemplate.id

            // Extract the main summary
            if let mainSummary = summaries.first(where: { $0.templateId == selectedTemplate.id }) {
                meeting.summary = mainSummary.content
            }

            // Extract action items if we ran that template
            if let actionItemsSummary = summaries.first(where: { $0.outputFormat == .actionItems }) {
                meeting.actionItems = extractActionItems(from: actionItemsSummary.content)
            }

            // Extract diarized transcript if we ran that template
            if let diarizedSummary = summaries.first(where: { $0.outputFormat == .diarizedTranscript }) {
                meeting.diarizedTranscript = diarizedSummary.content
            }

            // Save to database
            try await DatabaseManager.shared.update(meeting)

            print("[MeetingDetailView] Successfully processed meeting with \(summaries.count) templates")

        } catch {
            print("[MeetingDetailView] Failed to process meeting: \(error)")
            // Don't update error message - this is optional post-processing
        }
    }

    /// Extract action items from processed content
    private func extractActionItems(from content: String) -> [String] {
        var items: [String] = []
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- [ ]") || trimmed.hasPrefix("- [x]") {
                let item = trimmed
                    .replacingOccurrences(of: "- [ ]", with: "")
                    .replacingOccurrences(of: "- [x]", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !item.isEmpty {
                    items.append(item)
                }
            }
        }

        return items
    }
}

// MARK: - Header (Legacy - kept for compatibility)

struct DetailHeader: View {
    let meeting: Meeting
    var showBackButton: Bool = true
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            if showBackButton {
                Button(action: onDismiss) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.medium))
                        Text("Back")
                            .font(.subheadline)
                    }
                }
                .buttonStyle(.plain)
                .help("Back (Esc)")
            }

            Spacer()

            Text(meeting.title)
                .font(.headline)
                .lineLimit(1)

            Spacer()

            // Status indicator - only show for non-ready states
            if meeting.status == .failed {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.red)
                    .help(meeting.errorMessage ?? "Transcription failed")
            } else if meeting.status == .transcribing {
                BrandLoadingIndicator(size: .small)
            } else if meeting.status == .recording {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
            } else if meeting.status == .pendingTranscription {
                Image(systemName: "clock")
                    .foregroundColor(.orange)
            }
            // .ready = no indicator
        }
        .padding()
    }
}

// MARK: - Meeting Header Section (Amie-style)

/// Rich header section with editable title, description, and metadata (Amie-inspired design)
struct MeetingHeaderSection: View {
    @Binding var meeting: Meeting
    var showBackButton: Bool = true
    var onDismiss: (() -> Void)?
    var onDelete: (() -> Void)?

    @State private var isEditingTitle = false
    @State private var isEditingDescription = false
    @State private var editedTitle: String = ""
    @State private var editedDescription: String = ""
    @State private var showDeleteConfirmation = false
    @FocusState private var titleFieldFocused: Bool
    @FocusState private var descriptionFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top row: Back button + Updated indicator + Actions menu
            HStack {
                if showBackButton {
                    Button(action: { onDismiss?() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.body.weight(.medium))
                            Text("Back")
                                .font(.subheadline)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Back (Esc)")
                }

                Spacer()

                // Status indicator for non-ready states
                if meeting.status == .failed {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.red)
                        Text("Failed")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                } else if meeting.status == .pendingTranscription {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .foregroundColor(.orange)
                        Text("Pending transcription")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if meeting.status == .transcribing {
                    HStack(spacing: 4) {
                        BrandLoadingIndicator(size: .tiny)
                        Text("Transcribing...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if meeting.status == .recording {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text("Recording")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                } else {
                    // "Updated X ago" indicator
                    if let lastUpdatedText = meeting.formattedLastUpdated {
                        Text("Updated \(lastUpdatedText)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Actions menu (three dots)
                Menu {
                    Button(action: {
                        // Show in Finder
                        if let url = URL(string: "file://\(meeting.audioPath)") {
                            NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                        }
                    }) {
                        Label("Show in Finder", systemImage: "folder")
                    }

                    Divider()

                    Button(role: .destructive, action: {
                        showDeleteConfirmation = true
                    }) {
                        Label("Delete Meeting", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 28)
                .help("More options")
            }
            .alert("Delete Meeting?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    onDelete?()
                }
            } message: {
                Text("This will permanently delete \"\(meeting.title)\" and its audio file. This action cannot be undone.")
            }

            // Editable Title
            if isEditingTitle {
                TextField("Meeting title", text: $editedTitle)
                    .font(.brandDisplay(22, weight: .bold))
                    .textFieldStyle(.plain)
                    .focused($titleFieldFocused)
                    .onSubmit { saveTitle() }
                    .onChange(of: titleFieldFocused) { _, focused in
                        if !focused { saveTitle() }
                    }
            } else {
                Text(meeting.title)
                    .font(.brandDisplay(22, weight: .bold))
                    .foregroundColor(.brandTextPrimary)
                    .lineLimit(2)
                    .onTapGesture {
                        editedTitle = meeting.title
                        isEditingTitle = true
                        titleFieldFocused = true
                    }
                    .help("Click to edit title")
            }

            // Editable Description
            if isEditingDescription {
                TextField("Add a description...", text: $editedDescription)
                    .font(.brandDisplay(14))
                    .foregroundColor(.brandTextSecondary)
                    .textFieldStyle(.plain)
                    .focused($descriptionFieldFocused)
                    .onSubmit { saveDescription() }
                    .onChange(of: descriptionFieldFocused) { _, focused in
                        if !focused { saveDescription() }
                    }
            } else {
                let descriptionText = meeting.description ?? ""
                Text(descriptionText.isEmpty ? "Add a description..." : descriptionText)
                    .font(.brandDisplay(14))
                    .foregroundColor(descriptionText.isEmpty ? .brandTextSecondary.opacity(0.6) : .brandTextSecondary)
                    .lineLimit(3)
                    .onTapGesture {
                        editedDescription = meeting.description ?? ""
                        isEditingDescription = true
                        descriptionFieldFocused = true
                    }
                    .help("Click to edit description")
            }

            // Metadata row
            MeetingMetadataRow(meeting: meeting)
        }
        .padding()
    }

    private func saveTitle() {
        guard isEditingTitle else { return }
        isEditingTitle = false

        let newTitle = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newTitle.isEmpty, newTitle != meeting.title else { return }

        meeting.title = newTitle
        meeting.touch()

        Task {
            do {
                try await DatabaseManager.shared.update(meeting)
            } catch {
                print("[MeetingHeaderSection] Failed to save title: \(error)")
            }
        }
    }

    private func saveDescription() {
        guard isEditingDescription else { return }
        isEditingDescription = false

        let newDescription = editedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldDescription = meeting.description ?? ""
        guard newDescription != oldDescription else { return }

        meeting.description = newDescription.isEmpty ? nil : newDescription
        meeting.touch()

        Task {
            do {
                try await DatabaseManager.shared.update(meeting)
            } catch {
                print("[MeetingHeaderSection] Failed to save description: \(error)")
            }
        }
    }
}

// MARK: - Meeting Metadata Row

/// Displays created date/time and meeting source with colored indicator
struct MeetingMetadataRow: View {
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Created date/time row
            HStack(spacing: 8) {
                Text("Created")
                    .font(.brandDisplay(11, weight: .medium))
                    .foregroundColor(.brandTextSecondary)
                    .frame(width: 60, alignment: .leading)

                Text(formattedDateTimeRange)
                    .font(.brandMono(11, weight: .medium))
                    .foregroundColor(.brandTextPrimary)
            }

            // Meeting source row
            if let sourceApp = meeting.sourceApp {
                HStack(spacing: 8) {
                    Text("Meeting")
                        .font(.brandDisplay(11, weight: .medium))
                        .foregroundColor(.brandTextSecondary)
                        .frame(width: 60, alignment: .leading)

                    HStack(spacing: 6) {
                        // Colored dot indicator
                        Circle()
                            .fill(sourceColor(for: sourceApp))
                            .frame(width: 6, height: 6)

                        Text(meeting.windowTitle ?? sourceApp)
                            .font(.brandDisplay(12, weight: .medium))
                            .foregroundColor(.brandTextPrimary)
                            .lineLimit(1)

                        Spacer()

                        // Change button (placeholder)
                        Button(action: {}) {
                            HStack(spacing: 2) {
                                Text("Change")
                                    .font(.brandDisplay(11))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9))
                            }
                            .foregroundColor(.brandViolet)
                        }
                        .buttonStyle(.plain)
                        .help("Link to calendar event (coming soon)")
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    /// Formats the date and time range like "Tue, 13 Jan, 16:41 → 16:44"
    private var formattedDateTimeRange: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE, d MMM"

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        let dateStr = dateFormatter.string(from: meeting.startTime)
        let startTimeStr = timeFormatter.string(from: meeting.startTime)

        if let endTime = meeting.endTime {
            let endTimeStr = timeFormatter.string(from: endTime)
            return "\(dateStr), \(startTimeStr) → \(endTimeStr)"
        } else if meeting.duration > 0 {
            let endDate = meeting.startTime.addingTimeInterval(meeting.duration)
            let endTimeStr = timeFormatter.string(from: endDate)
            return "\(dateStr), \(startTimeStr) → \(endTimeStr)"
        } else {
            return "\(dateStr), \(startTimeStr)"
        }
    }

    /// Returns the brand color for different meeting apps
    private func sourceColor(for app: String) -> Color {
        let lowercased = app.lowercased()
        if lowercased.contains("zoom") {
            return .blue
        } else if lowercased.contains("meet") || lowercased.contains("google") {
            return .green
        } else if lowercased.contains("teams") || lowercased.contains("microsoft") {
            return .purple
        } else if lowercased.contains("slack") {
            return .pink
        } else if lowercased.contains("discord") {
            return .indigo
        } else {
            return .gray
        }
    }
}

// MARK: - Meeting Share Bar

struct MeetingShareBar: View {
    let meeting: Meeting
    @State private var showingExportOptions = false
    @State private var copiedFeedback: String? = nil
    @State private var showingComingSoon = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Email
                ShareButton(
                    icon: "envelope",
                    label: "Email",
                    action: openEmailClient
                )

                // Copy link
                ShareButton(
                    icon: "link",
                    label: copiedFeedback == "link" ? "Copied!" : "Copy link",
                    action: copyLink
                )

                // Copy summary
                ShareButton(
                    icon: "doc.on.doc",
                    label: copiedFeedback == "summary" ? "Copied!" : "Copy summary",
                    action: copySummary
                )
                .disabled(meeting.summary == nil && meeting.transcript == nil)

                // Export PDF
                ShareButton(
                    icon: "arrow.down.doc",
                    label: "Export PDF",
                    action: { showingComingSoon = true }
                )

                // Export Markdown
                ShareButton(
                    icon: "doc.text",
                    label: "Export MD",
                    action: exportMarkdown
                )
            }
            .padding(.horizontal, 4)
        }
        .padding(.vertical, 8)
        .alert("Coming Soon", isPresented: $showingComingSoon) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("PDF export will be available in a future update.")
        }
    }

    // MARK: - Actions

    private func openEmailClient() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        let dateStr = dateFormatter.string(from: meeting.startTime)

        let subject = "Meeting Notes: \(meeting.title)"
        var body = "Meeting: \(meeting.title)\nDate: \(dateStr)\nDuration: \(meeting.formattedDuration)\n\n"

        if let summary = meeting.summary {
            body += "Summary:\n\(summary)\n\n"
        }

        if let transcript = meeting.transcript {
            let preview = String(transcript.prefix(500))
            body += "Transcript Preview:\n\(preview)..."
        }

        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        if let url = URL(string: "mailto:?subject=\(encodedSubject)&body=\(encodedBody)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func copyLink() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: meeting.startTime)

        let reference = "meeting://\(meeting.id.uuidString)\n\(meeting.title) - \(dateStr)"

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(reference, forType: .string)

        withAnimation {
            copiedFeedback = "link"
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                if copiedFeedback == "link" {
                    copiedFeedback = nil
                }
            }
        }
    }

    private func copySummary() {
        let content = meeting.summary ?? meeting.transcript ?? ""
        guard !content.isEmpty else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)

        withAnimation {
            copiedFeedback = "summary"
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                if copiedFeedback == "summary" {
                    copiedFeedback = nil
                }
            }
        }
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "\(meeting.title.replacingOccurrences(of: " ", with: "_")).md"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }

            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .full
            dateFormatter.timeStyle = .short
            let dateStr = dateFormatter.string(from: meeting.startTime)

            var markdown = """
            # \(meeting.title)

            **Date:** \(dateStr)
            **Duration:** \(meeting.formattedDuration)
            """

            if let app = meeting.sourceApp {
                markdown += "\n**Source:** \(app)"
            }

            markdown += "\n\n---\n\n"

            if let summary = meeting.summary {
                markdown += "## Summary\n\n\(summary)\n\n"
            }

            if let actionItems = meeting.actionItems, !actionItems.isEmpty {
                markdown += "## Action Items\n\n"
                for item in actionItems {
                    markdown += "- [ ] \(item)\n"
                }
                markdown += "\n"
            }

            if let transcript = meeting.transcript {
                markdown += "## Transcript\n\n\(transcript)\n"
            }

            try? markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Share Button

struct ShareButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    var isDisabled: Bool = false

    var body: some View {
        BrandSecondaryButton(
            title: label,
            icon: icon,
            size: .small,
            action: action
        )
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
    }
}

// MARK: - Meeting Info Card

struct MeetingInfoCard: View {
    let meeting: Meeting

    var body: some View {
        BrandCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    InfoItem(icon: "calendar", label: "Date", value: formattedDate)
                    InfoItem(icon: "clock", label: "Time", value: meeting.formattedTime)
                    InfoItem(icon: "timer", label: "Duration", value: meeting.formattedDuration)
                }

                HStack(spacing: 16) {
                    if let app = meeting.sourceApp {
                        InfoItem(icon: "app", label: "Source", value: app)
                    }
                    // Cost info - only visible for beta testers
                    if FeatureFlags.shared.showCosts, let cost = meeting.formattedCost {
                        InfoItem(icon: "dollarsign.circle", label: "Cost", value: cost)
                    }
                }
            }
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: meeting.startTime)
    }
}

struct InfoItem: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.caption.weight(.medium))
            }
        }
    }
}

// MARK: - Audio Player Card

struct AudioPlayerCard: View {
    let audioPath: String
    @ObservedObject var player: AudioPlayerManager
    @State private var isDragging = false
    @State private var showVolumeSlider = false
    @State private var tick = 0  // Forces re-evaluation

    /// Check if audio file exists (re-evaluated on tick changes)
    private var audioFileExists: Bool {
        FileManager.default.fileExists(atPath: audioPath)
    }

    var body: some View {
        Group {
            if audioFileExists {
                playerContent
            } else {
                // Audio file not ready yet (still recording or processing)
                BrandCard(padding: 16) {
                    HStack(spacing: 12) {
                        BrandLoadingIndicator(size: .medium)
                        Text("Preparing audio...")
                            .font(.brandDisplay(14))
                            .foregroundColor(.brandTextSecondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear {
            if audioFileExists {
                player.prepare(url: URL(fileURLWithPath: audioPath))
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            // Increment tick to force view re-evaluation if file doesn't exist yet
            if !audioFileExists {
                tick += 1
            } else if !player.isReady {
                // File exists but player not ready - prepare it
                player.prepare(url: URL(fileURLWithPath: audioPath))
            }
        }
    }

    @ViewBuilder
    private var playerContent: some View {
        BrandCard(padding: 16) {
            VStack(spacing: 12) {
                // Row 1: Play controls + Scrubber + Time
                HStack(spacing: 12) {
                    // Play/Pause button
                    Button(action: {
                        if player.isPlaying {
                            player.pause()
                        } else {
                            player.play(url: URL(fileURLWithPath: audioPath))
                        }
                    }) {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.brandViolet)
                    }
                    .buttonStyle(.plain)

                    // Skip backward
                    BrandIconButton(
                        icon: "gobackward.15",
                        size: 28,
                        action: { player.skip(seconds: -15) }
                    )
                    .disabled(!player.isReady)

                    // Current time
                    Text(formatTime(player.currentTime))
                        .font(.brandMono(11))
                        .foregroundColor(.brandTextSecondary)
                        .frame(width: 40, alignment: .trailing)

                    // Interactive scrubber
                    Slider(
                        value: Binding(
                            get: { player.progress },
                            set: { newValue in
                                player.seek(to: newValue)
                            }
                        ),
                        in: 0...1
                    )
                    .tint(.brandViolet)
                    .controlSize(.small)

                    // Duration
                    Text(formatTime(player.duration))
                        .font(.brandMono(11))
                        .foregroundColor(.brandTextSecondary)
                        .frame(width: 40, alignment: .leading)

                    // Skip forward
                    BrandIconButton(
                        icon: "goforward.15",
                        size: 28,
                        action: { player.skip(seconds: 15) }
                    )
                    .disabled(!player.isReady)
                }

                // Row 2: Volume + Speed controls
                HStack(spacing: 16) {
                    // Volume control
                    HStack(spacing: 6) {
                        Image(systemName: player.volumeIconName)
                            .font(.system(size: 11))
                            .foregroundColor(.brandTextSecondary)
                            .frame(width: 16)

                        Slider(
                            value: Binding(
                                get: { Double(player.volume) },
                                set: { player.setVolume(Float($0)) }
                            ),
                            in: 0...1
                        )
                        .tint(.brandViolet)
                        .controlSize(.mini)
                        .frame(width: 80)
                    }

                    Spacer()

                    // Playback speed selector
                    Menu {
                        ForEach(AudioPlayerManager.playbackRates, id: \.self) { rate in
                            Button(action: { player.setPlaybackRate(rate) }) {
                                HStack {
                                    Text(formatRate(rate))
                                    if rate == player.playbackRate {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(player.playbackRateText)
                                .font(.brandMono(11, weight: .semibold))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9))
                        }
                        .foregroundColor(.brandViolet)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.brandViolet.opacity(0.1))
                        .cornerRadius(BrandRadius.small)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formatRate(_ rate: Float) -> String {
        if rate == floor(rate) {
            return "\(Int(rate))x"
        } else {
            return String(format: "%.2gx", rate)
        }
    }
}

// MARK: - Transcript & Summary Section with Tabs

struct TranscriptSummarySection: View {
    @Binding var meeting: Meeting
    @Binding var selectedTab: ContentTab
    var onReprocess: (() async -> Void)?
    var onRetryTranscription: (() -> Void)?
    var onReprocessTranscription: (() -> Void)?

    // Reordered: Summary and Action Items on top (generated together), then Transcript, then Private Notes
    // Speakers is removed from tabs - shown separately above
    enum ContentTab: String, CaseIterable {
        case summary = "Summary"
        case actionItems = "Action Items"
        case transcript = "Transcript"
        case privateNotes = "Private notes"

        var icon: String {
            switch self {
            case .summary: return "doc.text"
            case .actionItems: return "checklist"
            case .transcript: return "text.alignleft"
            case .privateNotes: return "note.text"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tab bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(ContentTab.allCases, id: \.self) { tab in
                        BrandTabButton(
                            title: tab.rawValue,
                            icon: tab.icon,
                            isSelected: selectedTab == tab,
                            action: { selectedTab = tab }
                        )
                    }

                    Spacer()

                    // Copy button
                    BrandIconButton(
                        icon: "doc.on.doc",
                        size: 28,
                        action: copyContent
                    )
                    .help("Copy content")
                    .disabled(currentContent == nil)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(Color.brandBackground)

            Divider()

            // Content
            ScrollView {
                Group {
                    switch selectedTab {
                    case .summary:
                        SummaryContentView(meeting: meeting, onReprocess: onReprocess)
                    case .actionItems:
                        ActionItemsContentView(meeting: meeting, onReprocess: onReprocess)
                    case .transcript:
                        TranscriptContentView(meeting: meeting, onRetry: onRetryTranscription, onReprocess: onReprocessTranscription)
                    case .privateNotes:
                        PrivateNotesContentView(meeting: $meeting)
                    }
                }
                .padding()
            }
        }
        .background(Color.brandSurface)
        .cornerRadius(BrandRadius.medium)
        .overlay(
            RoundedRectangle(cornerRadius: BrandRadius.medium)
                .stroke(Color.brandBorder, lineWidth: 1)
        )
    }

    private var currentContent: String? {
        switch selectedTab {
        case .summary: return meeting.summary ?? meeting.processedSummaries?.first?.content
        case .actionItems: return meeting.actionItems?.joined(separator: "\n")
        case .transcript: return meeting.transcript
        case .privateNotes: return meeting.privateNotes
        }
    }

    private func copyContent() {
        guard let content = currentContent else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
    }
}

// MARK: - Summary Content View

struct SummaryContentView: View {
    let meeting: Meeting
    var onReprocess: (() async -> Void)?
    @ObservedObject private var templateManager = SummaryTemplateManager.shared
    @State private var selectedSummaryId: UUID?
    @State private var isProcessing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // If we have processed summaries, show a picker
            if let summaries = meeting.processedSummaries, summaries.count > 1 {
                HStack {
                    Text("View:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("", selection: $selectedSummaryId) {
                        ForEach(summaries) { summary in
                            Text(summary.templateName).tag(summary.id as UUID?)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180)

                    Spacer()
                }
            }

            // Show the selected summary
            if let summaries = meeting.processedSummaries,
               let selectedId = selectedSummaryId ?? summaries.first?.id,
               let summary = summaries.first(where: { $0.id == selectedId }) {
                ProcessedSummaryView(summary: summary)
            } else if let summary = meeting.summary {
                // Fallback to raw summary string
                MarkdownTextView(text: summary)
            } else {
                // No summary yet - show centered Summarize button
                VStack(spacing: 16) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 48))
                        .foregroundColor(.brandViolet.opacity(0.4))

                    Text("No summary yet")
                        .font(.brandDisplay(16, weight: .medium))
                        .foregroundColor(.brandTextSecondary)

                    if meeting.transcript != nil {
                        if isProcessing {
                            HStack(spacing: 8) {
                                BrandLoadingIndicator(size: .medium)
                                Text("Generating summary...")
                                    .font(.brandDisplay(13))
                                    .foregroundColor(.brandTextSecondary)
                            }
                        } else if let onReprocess = onReprocess {
                            BrandPrimaryButton(
                                title: "Summarize",
                                icon: "sparkles",
                                size: .medium,
                                action: {
                                    isProcessing = true
                                    Task {
                                        await onReprocess()
                                        isProcessing = false
                                    }
                                }
                            )
                            .help("Generate AI summary and action items")
                        }

                        Text("AI will generate a summary and extract action items")
                            .font(.brandDisplay(12))
                            .foregroundColor(.brandTextSecondary.opacity(0.7))
                    } else {
                        Text("Transcript must be ready before summarizing")
                            .font(.brandDisplay(12))
                            .foregroundColor(.brandTextSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            }
        }
    }
}

// MARK: - Processed Summary View

struct ProcessedSummaryView: View {
    let summary: ProcessedSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with metadata
            HStack {
                Label(summary.templateName, systemImage: iconForFormat(summary.outputFormat))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("Generated \(formattedDate)")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if summary.costCents > 0 {
                    Text("• \(String(format: "$%.2f", Double(summary.costCents) / 100))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 4)

            // Content based on format
            switch summary.outputFormat {
            case .markdown, .custom:
                MarkdownTextView(text: summary.content)

            case .actionItems:
                ActionItemsListView(content: summary.content)

            case .diarizedTranscript:
                SummarySpeakerView(content: summary.content)

            case .keyPoints:
                KeyPointsView(content: summary.content)
            }
        }
    }

    private var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: summary.processedAt, relativeTo: Date())
    }

    private func iconForFormat(_ format: SummaryTemplate.OutputFormat) -> String {
        switch format {
        case .markdown: return "doc.richtext"
        case .actionItems: return "checklist"
        case .diarizedTranscript: return "person.2"
        case .keyPoints: return "list.bullet"
        case .custom: return "doc.text"
        }
    }
}

// MARK: - Markdown Text View

struct MarkdownTextView: View {
    let text: String

    var body: some View {
        Text(LocalizedStringKey(text))
            .font(.body)
            .lineSpacing(4)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Action Items List View

struct ActionItemsListView: View {
    let content: String
    @State private var completedItems: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(parseActionItems(), id: \.self) { item in
                HStack(alignment: .top, spacing: 10) {
                    Button(action: { toggleItem(item) }) {
                        Image(systemName: completedItems.contains(item) ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(completedItems.contains(item) ? .green : .secondary)
                    }
                    .buttonStyle(.plain)

                    Text(item)
                        .font(.body)
                        .strikethrough(completedItems.contains(item))
                        .foregroundColor(completedItems.contains(item) ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func parseActionItems() -> [String] {
        let lines = content.components(separatedBy: .newlines)
        var items: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- [ ]") || trimmed.hasPrefix("- [x]") || trimmed.hasPrefix("- [X]") {
                let item = trimmed
                    .replacingOccurrences(of: "- [ ]", with: "")
                    .replacingOccurrences(of: "- [x]", with: "")
                    .replacingOccurrences(of: "- [X]", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !item.isEmpty {
                    items.append(item)
                }
            } else if trimmed.hasPrefix("•") || trimmed.hasPrefix("-") {
                let item = trimmed
                    .replacingOccurrences(of: "•", with: "")
                    .replacingOccurrences(of: "-", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !item.isEmpty && !item.hasPrefix("#") {
                    items.append(item)
                }
            }
        }

        return items
    }

    private func toggleItem(_ item: String) {
        if completedItems.contains(item) {
            completedItems.remove(item)
        } else {
            completedItems.insert(item)
        }
    }
}

// MARK: - Summary Speaker View (parses speaker patterns from summary text)

struct SummarySpeakerView: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(parseSpeakerSegments(), id: \.id) { segment in
                HStack(alignment: .top, spacing: 12) {
                    // Speaker avatar
                    Circle()
                        .fill(colorForSpeaker(segment.speaker))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text(segment.speaker.prefix(1).uppercased())
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(segment.speaker)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(colorForSpeaker(segment.speaker))

                        Text(segment.text)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private struct SpeakerSegment: Identifiable {
        let id = UUID()
        let speaker: String
        let text: String
    }

    private func parseSpeakerSegments() -> [SpeakerSegment] {
        var segments: [SpeakerSegment] = []
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            // Try to match **Speaker:** pattern
            if let match = trimmed.range(of: #"\*\*([^*]+)\*\*:\s*(.+)"#, options: .regularExpression) {
                let fullMatch = String(trimmed[match])
                if let speakerEnd = fullMatch.range(of: "**:", options: .literal) {
                    let speaker = fullMatch[fullMatch.index(fullMatch.startIndex, offsetBy: 2)..<speakerEnd.lowerBound]
                        .trimmingCharacters(in: .whitespaces)
                    let text = String(fullMatch[speakerEnd.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                    segments.append(SpeakerSegment(speaker: String(speaker), text: text))
                    continue
                }
            }

            // Try Speaker: pattern (no bold)
            if let colonIndex = trimmed.firstIndex(of: ":"),
               colonIndex != trimmed.startIndex {
                let speaker = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let text = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                if !speaker.isEmpty && !text.isEmpty && speaker.count < 30 {
                    segments.append(SpeakerSegment(speaker: speaker, text: text))
                    continue
                }
            }

            // Fallback: append to last segment or create new "Unknown"
            if !segments.isEmpty {
                let last = segments.removeLast()
                segments.append(SpeakerSegment(speaker: last.speaker, text: last.text + " " + trimmed))
            } else {
                segments.append(SpeakerSegment(speaker: "Unknown", text: trimmed))
            }
        }

        return segments
    }

    private func colorForSpeaker(_ speaker: String) -> Color {
        let colors: [Color] = [.blue, .purple, .orange, .green, .pink, .teal]
        let hash = abs(speaker.hashValue)
        return colors[hash % colors.count]
    }
}

// MARK: - Key Points View

struct KeyPointsView: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(parseKeyPoints(), id: \.self) { point in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "diamond.fill")
                        .font(.caption2)
                        .foregroundColor(.brandViolet)
                        .padding(.top, 4)

                    Text(point)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func parseKeyPoints() -> [String] {
        let lines = content.components(separatedBy: .newlines)
        var points: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("•") || trimmed.hasPrefix("-") || trimmed.hasPrefix("*") {
                let point = trimmed
                    .replacingOccurrences(of: "•", with: "")
                    .replacingOccurrences(of: "-", with: "")
                    .replacingOccurrences(of: "*", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !point.isEmpty {
                    points.append(point)
                }
            }
        }

        return points
    }
}

// MARK: - Private Notes Content View

struct PrivateNotesContentView: View {
    @Binding var meeting: Meeting
    @State private var notesText: String = ""
    @State private var saveTask: Task<Void, Never>?

    private let placeholderText = "Add your private notes here. These won't be shared or sent to AI."

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                // Placeholder when empty
                if notesText.isEmpty {
                    Text(placeholderText)
                        .font(.body)
                        .foregroundColor(.secondary.opacity(0.6))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $notesText)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(minHeight: 200)
            }
            .padding(8)
            .background(Color.brandBackground)
            .cornerRadius(BrandRadius.small)
            .overlay(
                RoundedRectangle(cornerRadius: BrandRadius.small)
                    .stroke(Color.brandBorder, lineWidth: 1)
            )

            // Footer with character count
            HStack {
                Spacer()
                Text("\(notesText.count) characters")
                    .font(.brandMono(10))
                    .foregroundColor(.brandTextSecondary)
            }
        }
        .onAppear {
            notesText = meeting.privateNotes ?? ""
        }
        .onChange(of: notesText) { _, newValue in
            // Debounced auto-save
            saveTask?.cancel()
            saveTask = Task {
                try? await Task.sleep(for: .milliseconds(500))
                if !Task.isCancelled {
                    await saveNotes(newValue)
                }
            }
        }
        .onDisappear {
            // Save immediately on disappear
            saveTask?.cancel()
            if notesText != (meeting.privateNotes ?? "") {
                Task {
                    await saveNotes(notesText)
                }
            }
        }
    }

    @MainActor
    private func saveNotes(_ text: String) async {
        meeting.privateNotes = text.isEmpty ? nil : text
        do {
            try await DatabaseManager.shared.update(meeting)
            print("[PrivateNotes] Saved notes (\(text.count) chars)")
        } catch {
            print("[PrivateNotes] Failed to save: \(error)")
        }
    }
}

// MARK: - Action Items Content View (Standalone Tab)

struct ActionItemsContentView: View {
    let meeting: Meeting
    var onReprocess: (() async -> Void)?
    @State private var completedItems: Set<String> = []
    @State private var isProcessing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let items = meeting.actionItems, !items.isEmpty {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Button(action: { toggleItem(item) }) {
                            Image(systemName: completedItems.contains(item) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(completedItems.contains(item) ? .green : .secondary)
                        }
                        .buttonStyle(.plain)

                        Text(item)
                            .font(.body)
                            .strikethrough(completedItems.contains(item))
                            .foregroundColor(completedItems.contains(item) ? .secondary : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                }
            } else if let summaries = meeting.processedSummaries,
                      let actionSummary = summaries.first(where: { $0.outputFormat == .actionItems }) {
                // Parse action items from processed summary
                ActionItemsListView(content: actionSummary.content)
            } else {
                // No action items - show centered Summarize button
                VStack(spacing: 16) {
                    Image(systemName: "checklist")
                        .font(.system(size: 48))
                        .foregroundColor(.brandViolet.opacity(0.4))

                    Text("No action items yet")
                        .font(.brandDisplay(16, weight: .medium))
                        .foregroundColor(.brandTextSecondary)

                    if meeting.transcript != nil && !meeting.isProcessed {
                        if isProcessing {
                            HStack(spacing: 8) {
                                BrandLoadingIndicator(size: .medium)
                                Text("Extracting action items...")
                                    .font(.brandDisplay(13))
                                    .foregroundColor(.brandTextSecondary)
                            }
                        } else if let onReprocess = onReprocess {
                            BrandPrimaryButton(
                                title: "Summarize",
                                icon: "sparkles",
                                size: .medium,
                                action: {
                                    isProcessing = true
                                    Task {
                                        await onReprocess()
                                        isProcessing = false
                                    }
                                }
                            )
                            .help("Generate AI summary and action items")
                        }

                        Text("AI will extract action items from the transcript")
                            .font(.brandDisplay(12))
                            .foregroundColor(.brandTextSecondary.opacity(0.7))
                    } else if meeting.transcript == nil {
                        Text("Transcript must be ready before extracting action items")
                            .font(.brandDisplay(12))
                            .foregroundColor(.brandTextSecondary)
                    } else if meeting.isProcessed {
                        Text("No action items were found in this meeting")
                            .font(.brandDisplay(12))
                            .foregroundColor(.brandTextSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            }
        }
    }

    private func toggleItem(_ item: String) {
        if completedItems.contains(item) {
            completedItems.remove(item)
        } else {
            completedItems.insert(item)
        }
    }
}

// MARK: - Transcript Content View (Raw)

struct TranscriptContentView: View {
    let meeting: Meeting
    var onRetry: (() -> Void)?
    var onReprocess: (() -> Void)?
    @State private var isReprocessing = false
    @State private var showReprocessConfirmation = false
    @State private var viewMode: TranscriptViewMode = .diarized

    enum TranscriptViewMode: String, CaseIterable {
        case diarized = "Speakers"
        case plain = "Plain Text"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let transcript = meeting.transcript {
                // Header row with view toggle and reprocess button
                HStack(spacing: 12) {
                    // View mode toggle (only if we have diarization)
                    if hasDiarization {
                        Picker("", selection: $viewMode) {
                            ForEach(TranscriptViewMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }

                    Spacer()

                    Button(action: { showReprocessConfirmation = true }) {
                        HStack(spacing: 6) {
                            if isReprocessing {
                                BrandLoadingIndicator(size: .tiny)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11))
                            }
                            Text(isReprocessing ? "Reprocessing..." : "Re-transcribe")
                                .font(.brandDisplay(11, weight: .medium))
                        }
                        .foregroundColor(.brandViolet)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.brandViolet.opacity(0.1))
                        .cornerRadius(BrandRadius.small)
                    }
                    .buttonStyle(.plain)
                    .disabled(isReprocessing || meeting.status == .transcribing)
                    .help("Re-run transcription on this audio file")
                    .alert("Re-transcribe Audio?", isPresented: $showReprocessConfirmation) {
                        Button("Cancel", role: .cancel) { }
                        Button("Re-transcribe") {
                            isReprocessing = true
                            onReprocess?()
                        }
                    } message: {
                        Text("This will re-transcribe the audio file and replace the current transcript. This action will incur API costs.")
                    }
                }

                // Content based on view mode
                if viewMode == .diarized && hasDiarization {
                    DiarizedTranscriptView(meeting: meeting)
                } else {
                    Text(transcript)
                        .font(.body)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                TranscriptPlaceholder(status: meeting.status, onRetry: onRetry)
            }
        }
        .onChange(of: meeting.status) { _, newStatus in
            if newStatus != .transcribing {
                isReprocessing = false
            }
        }
    }

    private var hasDiarization: Bool {
        meeting.diarizationSegments?.isEmpty == false
    }
}

// MARK: - Diarized Transcript View

/// Chat-like view showing transcript with speaker labels and timestamps
struct DiarizedTranscriptView: View {
    let meeting: Meeting

    private var segments: [DiarizationSegment] {
        meeting.diarizationSegments ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                DiarizationSegmentRow(
                    segment: segment,
                    speakerName: meeting.speakerName(for: segment.speakerId),
                    speakerIndex: speakerIndex(for: segment.speakerId),
                    isNewSpeaker: isNewSpeaker(at: index)
                )
            }
        }
    }

    private func speakerIndex(for speakerId: String) -> Int {
        let uniqueSpeakers = meeting.uniqueSpeakers
        return uniqueSpeakers.firstIndex(of: speakerId) ?? 0
    }

    private func isNewSpeaker(at index: Int) -> Bool {
        guard index > 0 else { return true }
        return segments[index].speakerId != segments[index - 1].speakerId
    }
}

// MARK: - Diarization Segment Row

/// A single speaker segment with avatar, name, timestamp, and text
struct DiarizationSegmentRow: View {
    let segment: DiarizationSegment
    let speakerName: String
    let speakerIndex: Int
    let isNewSpeaker: Bool

    private static let speakerColors: [Color] = [
        .brandViolet,
        .brandCoral,
        Color(red: 0.2, green: 0.7, blue: 0.5),  // Teal
        Color(red: 0.9, green: 0.6, blue: 0.2),  // Orange
        Color(red: 0.5, green: 0.4, blue: 0.8),  // Purple
        Color(red: 0.3, green: 0.6, blue: 0.9),  // Blue
    ]

    private var speakerColor: Color {
        Self.speakerColors[speakerIndex % Self.speakerColors.count]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Speaker avatar (only show on first message from this speaker in a row)
            if isNewSpeaker {
                Circle()
                    .fill(speakerColor)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(speakerName.prefix(1).uppercased())
                            .font(.brandDisplay(13, weight: .semibold))
                            .foregroundColor(.white)
                    )
            } else {
                // Placeholder for alignment
                Color.clear
                    .frame(width: 32, height: 32)
            }

            VStack(alignment: .leading, spacing: 4) {
                // Speaker name and timestamp (only on first message)
                if isNewSpeaker {
                    HStack(spacing: 8) {
                        Text(speakerName)
                            .font(.brandDisplay(13, weight: .semibold))
                            .foregroundColor(speakerColor)

                        Text(formatTimestamp(segment.start))
                            .font(.brandMono(11))
                            .foregroundColor(.brandTextSecondary)
                    }
                }

                // Message text
                Text(segment.text)
                    .font(.brandDisplay(14))
                    .foregroundColor(.brandTextPrimary)
                    .textSelection(.enabled)
                    .lineSpacing(3)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, isNewSpeaker ? 8 : 2)
        .padding(.horizontal, 4)
    }

    private func formatTimestamp(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

// MARK: - Speakers Bar (Compact, Above Tabs)

/// Compact speakers display shown above the tabbed section
struct SpeakersBar: View {
    @Binding var meeting: Meeting
    @State private var isExpanded = false

    private var speakerCount: Int {
        if let segments = meeting.diarizationSegments {
            return Set(segments.map { $0.speakerId }).count
        } else if let participants = meeting.participants {
            return participants.count
        }
        return 0
    }

    private var speakerNames: [String] {
        if let segments = meeting.diarizationSegments {
            let uniqueIds = Set(segments.map { $0.speakerId })
            return uniqueIds.sorted().map { meeting.speakerName(for: $0) }
        } else if let participants = meeting.participants {
            return participants.map { $0.name }
        }
        return []
    }

    var body: some View {
        if speakerCount > 0 || meeting.hasSpeakerData {
            BrandCard(padding: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    // Header row
                    Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                        HStack(spacing: 8) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.brandViolet)

                            Text("Speakers")
                                .font(.brandDisplay(12, weight: .semibold))
                                .foregroundColor(.brandTextPrimary)

                            if speakerCount > 0 {
                                Text("(\(speakerCount))")
                                    .font(.brandDisplay(11))
                                    .foregroundColor(.brandTextSecondary)
                            }

                            Spacer()

                            // Collapsed preview: show speaker avatars
                            if !isExpanded && speakerCount > 0 {
                                HStack(spacing: -6) {
                                    ForEach(Array(speakerNames.prefix(4).enumerated()), id: \.offset) { index, name in
                                        Circle()
                                            .fill(colorForIndex(index))
                                            .frame(width: 24, height: 24)
                                            .overlay(
                                                Text(name.prefix(1).uppercased())
                                                    .font(.brandDisplay(10, weight: .semibold))
                                                    .foregroundColor(.white)
                                            )
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.brandSurface, lineWidth: 2)
                                            )
                                    }

                                    if speakerCount > 4 {
                                        Circle()
                                            .fill(Color.brandTextSecondary.opacity(0.3))
                                            .frame(width: 24, height: 24)
                                            .overlay(
                                                Text("+\(speakerCount - 4)")
                                                    .font(.brandMono(9, weight: .semibold))
                                                    .foregroundColor(.brandTextSecondary)
                                            )
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.brandSurface, lineWidth: 2)
                                            )
                                    }
                                }
                            }

                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.brandTextSecondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // Expanded content
                    if isExpanded {
                        VStack(alignment: .leading, spacing: 12) {
                            // Speaker pills/chips
                            FlowLayout(spacing: 6) {
                                ForEach(Array(speakerNames.enumerated()), id: \.offset) { index, name in
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(colorForIndex(index))
                                            .frame(width: 20, height: 20)
                                            .overlay(
                                                Text(name.prefix(1).uppercased())
                                                    .font(.brandDisplay(9, weight: .semibold))
                                                    .foregroundColor(.white)
                                            )

                                        Text(name)
                                            .font(.brandDisplay(12))
                                            .foregroundColor(.brandTextPrimary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.brandBackground)
                                    .cornerRadius(BrandRadius.small)
                                }
                            }

                            // Participants from screenshot (if any)
                            if let participants = meeting.participants, !participants.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Detected from meeting")
                                        .font(.brandDisplay(10, weight: .medium))
                                        .foregroundColor(.brandTextSecondary)

                                    FlowLayout(spacing: 4) {
                                        ForEach(participants) { participant in
                                            HStack(spacing: 4) {
                                                Image(systemName: sourceIcon(participant.source))
                                                    .font(.system(size: 9))
                                                Text(participant.name)
                                                    .font(.brandDisplay(11))
                                            }
                                            .foregroundColor(.brandTextSecondary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.brandBackground.opacity(0.5))
                                            .cornerRadius(BrandRadius.small)
                                        }
                                    }
                                }
                            }

                            // Edit speakers link
                            if meeting.hasSpeakerData {
                                SpeakerLabelingView(meeting: $meeting)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
    }

    private func colorForIndex(_ index: Int) -> Color {
        let colors: [Color] = [.blue, .purple, .orange, .green, .pink, .teal, .indigo, .mint]
        return colors[index % colors.count]
    }

    private func sourceIcon(_ source: MeetingParticipant.ParticipantSource) -> String {
        switch source {
        case .screenshot: return "camera.viewfinder"
        case .calendar: return "calendar"
        case .manual: return "pencil"
        case .speakerLabel: return "waveform"
        }
    }
}

// MARK: - Speakers Content View (Legacy - kept for reference)

struct SpeakersContentView: View {
    @Binding var meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Speaker labeling section (if we have diarization data)
            if meeting.hasSpeakerData {
                SpeakerLabelingView(meeting: $meeting)
            }

            // Participants from screenshot
            if let participants = meeting.participants, !participants.isEmpty {
                ParticipantsSection(participants: participants)
            }

            // Screenshot preview
            if let screenshotPath = meeting.screenshotPath,
               FileManager.default.fileExists(atPath: screenshotPath) {
                ScreenshotPreviewSection(path: screenshotPath)
            }

            // Diarized transcript
            if let segments = meeting.diarizationSegments, !segments.isEmpty {
                Divider()
                DiarizedSegmentsView(segments: segments, meeting: meeting)
            } else if let diarized = meeting.diarizedTranscript {
                Divider()
                SummarySpeakerView(content: diarized)
            } else if let summaries = meeting.processedSummaries,
                      let speakerSummary = summaries.first(where: { $0.outputFormat == .diarizedTranscript }) {
                Divider()
                SummarySpeakerView(content: speakerSummary.content)
            } else if !meeting.hasSpeakerData {
                // No speaker data at all
                VStack(spacing: 12) {
                    Image(systemName: "person.2")
                        .font(.largeTitle)
                        .foregroundColor(.secondary.opacity(0.5))

                    Text("Speaker identification not available")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("Speakers will be detected automatically during transcription")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }
        }
    }
}

// MARK: - Participants Section

struct ParticipantsSection: View {
    let participants: [MeetingParticipant]
    @State private var isExpanded = true

    var body: some View {
        BrandCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    HStack {
                        Image(systemName: "person.crop.rectangle.stack")
                            .foregroundColor(.brandTextSecondary)
                        Text("Detected Participants (\(participants.count))")
                            .font(.brandDisplay(12, weight: .medium))
                            .foregroundColor(.brandTextSecondary)
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.brandTextSecondary)
                    }
                }
                .buttonStyle(.plain)

                if isExpanded {
                    FlowLayout(spacing: 6) {
                        ForEach(participants) { participant in
                            HStack(spacing: 4) {
                                Image(systemName: sourceIcon(participant.source))
                                    .font(.system(size: 10))
                                Text(participant.name)
                                    .font(.brandDisplay(11))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.brandBackground)
                            .cornerRadius(BrandRadius.small)
                        }
                    }
                }
            }
        }
    }

    private func sourceIcon(_ source: MeetingParticipant.ParticipantSource) -> String {
        switch source {
        case .screenshot: return "camera.viewfinder"
        case .calendar: return "calendar"
        case .manual: return "pencil"
        case .speakerLabel: return "waveform"
        }
    }
}

// MARK: - Screenshot Preview Section

struct ScreenshotPreviewSection: View {
    let path: String
    @State private var isExpanded = false

    var body: some View {
        BrandCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    HStack {
                        Image(systemName: "photo")
                            .foregroundColor(.brandTextSecondary)
                        Text("Meeting Screenshot")
                            .font(.brandDisplay(12, weight: .medium))
                            .foregroundColor(.brandTextSecondary)
                        Spacer()
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.brandTextSecondary)
                    }
                }
                .buttonStyle(.plain)

                if isExpanded {
                    if let image = NSImage(contentsOfFile: path) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 300)
                            .cornerRadius(BrandRadius.small)
                            .onTapGesture {
                                // Open in Preview
                                NSWorkspace.shared.open(URL(fileURLWithPath: path))
                            }
                    }
                }
            }
        }
    }
}

// MARK: - Diarized Segments View (from DiarizationSegment)

struct DiarizedSegmentsView: View {
    let segments: [DiarizationSegment]
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conversation")
                .font(.brandDisplay(14, weight: .semibold))
                .padding(.bottom, 4)

            ForEach(segments) { segment in
                HStack(alignment: .top, spacing: 12) {
                    // Speaker avatar
                    Circle()
                        .fill(colorForSpeaker(segment.speakerId))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text(meeting.speakerName(for: segment.speakerId).prefix(1).uppercased())
                                .font(.brandDisplay(12, weight: .semibold))
                                .foregroundColor(.white)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(meeting.speakerName(for: segment.speakerId))
                            .font(.brandDisplay(12, weight: .semibold))
                            .foregroundColor(colorForSpeaker(segment.speakerId))

                        Text(segment.text)
                            .font(.brandDisplay(13))
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func colorForSpeaker(_ speakerId: String) -> Color {
        let colors: [Color] = [.blue, .purple, .orange, .green, .pink, .teal, .indigo, .mint]
        if let numStr = speakerId.split(separator: "_").last,
           let num = Int(numStr) {
            return colors[num % colors.count]
        }
        return colors[abs(speakerId.hashValue) % colors.count]
    }
}

// MARK: - Flow Layout Helper

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    struct FlowResult {
        var positions: [CGPoint] = []
        var size: CGSize = .zero

        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > width && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: width, height: y + lineHeight)
        }
    }
}

// MARK: - Legacy Transcript Section (kept for compatibility)

struct TranscriptSection: View {
    let meeting: Meeting
    var onRetry: (() -> Void)?

    var body: some View {
        BrandCard(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Transcript")
                        .font(.brandDisplay(14, weight: .semibold))

                    Spacer()

                    if meeting.transcript != nil {
                        BrandIconButton(
                            icon: "doc.on.doc",
                            size: 24,
                            action: copyTranscript
                        )
                        .help("Copy transcript")
                    }
                }

                if let transcript = meeting.transcript {
                    Text(transcript)
                        .font(.brandDisplay(13))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TranscriptPlaceholder(status: meeting.status, onRetry: onRetry)
                }
            }
        }
    }

    private func copyTranscript() {
        guard let transcript = meeting.transcript else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
    }
}

struct TranscriptPlaceholder: View {
    let status: MeetingStatus
    var onRetry: (() -> Void)?
    @State private var isRetrying = false

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                switch status {
                case .recording:
                    BrandLoadingIndicator(size: .medium, color: .brandCoral, style: .bars)
                    Text("Recording in progress...")
                case .pendingTranscription:
                    BrandLoadingIndicator(size: .medium)
                    Text("Waiting for transcription...")
                case .transcribing:
                    BrandLoadingIndicator(size: .medium)
                    Text("Transcribing...")
                case .ready:
                    Image(systemName: "doc.text")
                    Text("No transcript available")
                case .failed:
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.brandCoral)
                    Text("Transcription failed")
                }
            }
            .font(.brandDisplay(13))
            .foregroundColor(.brandTextSecondary)

            // Show retry button for failed status
            if status == .failed, let onRetry = onRetry {
                BrandPrimaryButton(
                    title: isRetrying ? "Retrying..." : "Retry",
                    icon: isRetrying ? nil : "arrow.clockwise",
                    isDisabled: isRetrying,
                    size: .small,
                    action: {
                        isRetrying = true
                        onRetry()
                    }
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .onChange(of: status) { _, newStatus in
            if newStatus != .failed {
                isRetrying = false
            }
        }
    }
}

// MARK: - Action Items Section

struct ActionItemsSection: View {
    let items: [String]

    var body: some View {
        BrandCard(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Action Items")
                    .font(.brandDisplay(14, weight: .semibold))

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "circle")
                                .font(.system(size: 10))
                                .foregroundColor(.brandViolet)
                                .padding(.top, 3)

                            Text(item)
                                .font(.brandDisplay(13))
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Error Section

struct ErrorSection: View {
    let message: String
    let status: MeetingStatus
    var onRetry: (() -> Void)?
    @State private var isRetrying = false

    var body: some View {
        BrandCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.brandCoral)
                    Text("Error")
                        .font(.brandDisplay(14, weight: .bold))
                }

                Text(message)
                    .font(.brandDisplay(13))
                    .foregroundColor(.brandTextPrimary)

                if let onRetry = onRetry {
                    BrandPrimaryButton(
                        title: isRetrying ? "Retrying..." : "Retry Transcription",
                        icon: isRetrying ? nil : "arrow.clockwise",
                        isDisabled: isRetrying,
                        size: .small,
                        action: {
                            isRetrying = true
                            onRetry()
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.brandCoral.opacity(0.05))
        .cornerRadius(BrandRadius.medium)
        .onChange(of: status) { _, newStatus in
            if newStatus != .failed {
                isRetrying = false
            }
        }
        .onChange(of: message) { _, _ in
            isRetrying = false
        }
    }
}

// MARK: - Keyboard Footer

struct DetailKeyboardFooter: View {
    var body: some View {
        HStack(spacing: 20) {
            Spacer()

            KeyboardHint(keys: "Space", action: "Play/Pause")
            KeyboardHint(keys: "←/→", action: "Seek")
            KeyboardHint(keys: "C", action: "Copy Transcript")
            KeyboardHint(keys: "Esc", action: "Back")

            Spacer()
        }
        .padding(.vertical, 10)
        .background(Color.brandSurface)
    }
}

struct KeyboardHint: View {
    let keys: String
    let action: String

    var body: some View {
        HStack(spacing: 6) {
            Text(keys)
                .font(.brandMono(10, weight: .semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.brandViolet.opacity(0.1))
                .foregroundColor(.brandViolet)
                .cornerRadius(4)

            Text(action)
                .font(.brandDisplay(11))
                .foregroundColor(.brandTextSecondary)
        }
    }
}

// MARK: - Audio Player Manager

@MainActor
class AudioPlayerManager: ObservableObject {
    @Published var isPlaying = false
    @Published var isReady = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var progress: Double = 0
    @Published var volume: Float = 1.0
    @Published var playbackRate: Float = 1.0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    /// Available playback speed options
    static let playbackRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    func prepare(url: URL) {
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.enableRate = true  // Required for playback rate to work
            player?.prepareToPlay()
            player?.volume = volume
            player?.rate = playbackRate
            duration = player?.duration ?? 0
            isReady = true
        } catch {
            print("[AudioPlayer] Failed to prepare: \(error)")
        }
    }

    func play(url: URL) {
        if player == nil {
            prepare(url: url)
        }

        player?.volume = volume
        player?.rate = playbackRate
        player?.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    func stop() {
        player?.stop()
        isPlaying = false
        stopTimer()
        currentTime = 0
        progress = 0
    }

    func skip(seconds: Double) {
        guard let player = player else { return }
        let newTime = max(0, min(player.duration, player.currentTime + seconds))
        player.currentTime = newTime
        updateProgress()
    }

    func seek(to progress: Double) {
        guard let player = player else { return }
        player.currentTime = progress * player.duration
        updateProgress()
    }

    func setVolume(_ newVolume: Float) {
        volume = max(0, min(1, newVolume))
        player?.volume = volume
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        player?.rate = rate
    }

    /// Get SF Symbol name for current volume level
    var volumeIconName: String {
        if volume == 0 {
            return "speaker.slash.fill"
        } else if volume < 0.33 {
            return "speaker.wave.1.fill"
        } else if volume < 0.66 {
            return "speaker.wave.2.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }

    /// Format playback rate for display (e.g., "1x", "1.5x")
    var playbackRateText: String {
        if playbackRate == floor(playbackRate) {
            return "\(Int(playbackRate))x"
        } else {
            return String(format: "%.2gx", playbackRate)
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard self != nil else {
                timer.invalidate()
                return
            }
            Task { @MainActor [weak self] in
                self?.updateProgress()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateProgress() {
        guard let player = player else { return }
        currentTime = player.currentTime
        progress = duration > 0 ? currentTime / duration : 0

        if !player.isPlaying && currentTime >= duration - 0.1 {
            isPlaying = false
            stopTimer()
        }
    }
}

// MARK: - Previews

#Preview("Meeting Detail - Ready") {
    MeetingDetailView(meeting: Meeting.sampleMeetings[0])
        .frame(width: 450, height: 600)
}

#Preview("Meeting Detail - Transcribing") {
    MeetingDetailView(meeting: Meeting.sampleMeetings[1])
        .frame(width: 450, height: 600)
}

#Preview("Meeting Detail - Failed") {
    MeetingDetailView(meeting: Meeting.sampleMeetings[3])
        .frame(width: 450, height: 600)
}

#Preview("Info Card") {
    MeetingInfoCard(meeting: Meeting.sampleMeetings[0])
        .frame(width: 400)
        .padding()
}

#Preview("Share Bar") {
    MeetingShareBar(meeting: Meeting.sampleMeetings[0])
        .frame(width: 450)
        .padding()
}

#Preview("Action Items") {
    ActionItemsSection(items: [
        "Review API documentation",
        "Send proposal to client",
        "Schedule follow-up meeting"
    ])
    .frame(width: 400)
    .padding()
}

#Preview("Transcript Placeholder - Transcribing") {
    TranscriptPlaceholder(status: .transcribing)
        .frame(width: 400)
        .padding()
}

#Preview("Transcript Placeholder - Failed with Retry") {
    TranscriptPlaceholder(status: .failed, onRetry: { print("Retry tapped") })
        .frame(width: 400)
        .padding()
        .background(Color.brandSurface)
}

#Preview("Error Section") {
    ErrorSection(message: "API key invalid. Please check your settings.", status: .failed)
        .frame(width: 400)
        .padding()
}

// MARK: - Transcribing Indicator (Bottom-right floating pill)

struct TranscribingIndicator: View {
    @State private var dotOffset: CGFloat = 0

    var body: some View {
        HStack(spacing: 8) {
            // Animated loading dots
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.white)
                        .frame(width: 6, height: 6)
                        .offset(y: dotOffset(for: index))
                }
            }

            Text("Transcribing")
                .font(.brandDisplay(12, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.brandViolet)
                .shadow(color: Color.black.opacity(0.15), radius: 8, y: 4)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                dotOffset = 1
            }
        }
    }

    private func dotOffset(for index: Int) -> CGFloat {
        let offset = dotOffset * -4
        let delay = Double(index) * 0.15
        return offset * sin(.pi * (dotOffset + CGFloat(delay)))
    }
}

#Preview("Transcribing Indicator") {
    ZStack {
        Color.brandBackground
        TranscribingIndicator()
    }
    .frame(width: 200, height: 100)
}

#Preview("Meeting Header Section") {
    struct PreviewWrapper: View {
        @State private var meeting = Meeting.sampleMeetings[0]

        var body: some View {
            MeetingHeaderSection(
                meeting: $meeting,
                showBackButton: true,
                onDismiss: {}
            )
        }
    }
    return PreviewWrapper()
        .frame(width: 450)
        .background(Color(.windowBackgroundColor))
}

#Preview("Meeting Header - Recording") {
    struct PreviewWrapper: View {
        @State private var meeting: Meeting = {
            var m = Meeting.sampleMeetings[0]
            m.status = .recording
            return m
        }()

        var body: some View {
            MeetingHeaderSection(
                meeting: $meeting,
                showBackButton: true,
                onDismiss: {}
            )
        }
    }
    return PreviewWrapper()
        .frame(width: 450)
        .background(Color(.windowBackgroundColor))
}

#Preview("Metadata Row") {
    MeetingMetadataRow(meeting: Meeting.sampleMeetings[0])
        .frame(width: 400)
        .padding()
}
