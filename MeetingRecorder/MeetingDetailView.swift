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
    @Environment(\.dismiss) private var dismiss
    @StateObject private var audioPlayer = AudioPlayerManager()
    @State private var selectedContentTab: TranscriptSummarySection.ContentTab = .summary
    @State private var isProcessing = false

    var body: some View {
        VStack(spacing: 0) {
            // Rich Amie-style header with editable title/description
            MeetingHeaderSection(
                meeting: $meeting,
                showBackButton: showBackButton,
                onDismiss: { dismiss() }
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
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Generating summary...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }

                    // New tabbed transcript/summary section
                    TranscriptSummarySection(
                        meeting: $meeting,
                        selectedTab: $selectedContentTab,
                        onReprocess: {
                            await processMeeting()
                        }
                    )
                    .frame(minHeight: 300)

                    // Action items (if any and not already in summary)
                    if let items = meeting.actionItems, !items.isEmpty, selectedContentTab != .summary {
                        ActionItemsSection(items: items)
                    }

                    // Error message (if failed)
                    if let error = meeting.errorMessage {
                        ErrorSection(message: error, onRetry: meeting.status == .failed ? {
                            Task {
                                await retryTranscription()
                            }
                        } : nil)
                    }
                }
                .padding()
            }

            // Keyboard shortcuts footer
            DetailKeyboardFooter()
        }
        .frame(minWidth: 450, idealWidth: 550, minHeight: 550, idealHeight: 700)
        .background(Color(.windowBackgroundColor))
        .onDisappear {
            audioPlayer.stop()
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

    private func retryTranscription() async {
        // Update meeting status to pending
        var updated = meeting
        updated.status = .pendingTranscription
        updated.errorMessage = nil

        do {
            try await DatabaseManager.shared.update(updated)
            meeting = updated

            // Update to transcribing status
            meeting.status = .transcribing
            try await DatabaseManager.shared.update(meeting)

            // Trigger transcription
            let result = try await TranscriptionService.shared.transcribe(audioPath: meeting.audioPath)

            // Update with transcript
            meeting.transcript = result.text
            meeting.apiCostCents = result.costCents
            meeting.status = .ready
            meeting.errorMessage = nil

            // Generate smart title from transcript
            if let smartTitle = await TranscriptionService.shared.generateMeetingTitle(from: result.text) {
                meeting.title = smartTitle
            }

            try await DatabaseManager.shared.update(meeting)
        } catch {
            // Mark as failed
            meeting.status = .failed
            meeting.errorMessage = error.localizedDescription
            try? await DatabaseManager.shared.update(meeting)
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
                ProgressView()
                    .scaleEffect(0.7)
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

    @State private var isEditingTitle = false
    @State private var isEditingDescription = false
    @State private var editedTitle: String = ""
    @State private var editedDescription: String = ""
    @FocusState private var titleFieldFocused: Bool
    @FocusState private var descriptionFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top row: Back button + Updated indicator
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
                } else if meeting.status == .transcribing {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
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
            }

            // Editable Title
            if isEditingTitle {
                TextField("Meeting title", text: $editedTitle)
                    .font(.title2.weight(.bold))
                    .textFieldStyle(.plain)
                    .focused($titleFieldFocused)
                    .onSubmit { saveTitle() }
                    .onChange(of: titleFieldFocused) { _, focused in
                        if !focused { saveTitle() }
                    }
            } else {
                Text(meeting.title)
                    .font(.title2.weight(.bold))
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
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .textFieldStyle(.plain)
                    .focused($descriptionFieldFocused)
                    .onSubmit { saveDescription() }
                    .onChange(of: descriptionFieldFocused) { _, focused in
                        if !focused { saveDescription() }
                    }
            } else {
                let descriptionText = meeting.description ?? ""
                Text(descriptionText.isEmpty ? "Add a description..." : descriptionText)
                    .font(.subheadline)
                    .foregroundColor(descriptionText.isEmpty ? .secondary.opacity(0.6) : .secondary)
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
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .leading)

                Text(formattedDateTimeRange)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.primary)
            }

            // Meeting source row
            if let sourceApp = meeting.sourceApp {
                HStack(spacing: 8) {
                    Text("Meeting")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .leading)

                    HStack(spacing: 6) {
                        // Colored dot indicator
                        Circle()
                            .fill(sourceColor(for: sourceApp))
                            .frame(width: 8, height: 8)

                        Text(meeting.windowTitle ?? sourceApp)
                            .font(.caption.weight(.medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Spacer()

                        // Change button (placeholder)
                        Button(action: {}) {
                            HStack(spacing: 2) {
                                Text("Change")
                                    .font(.caption)
                                Image(systemName: "chevron.down")
                                    .font(.caption2)
                            }
                            .foregroundColor(.secondary)
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
                    icon: "text.document",
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

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(label)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isHovering ? Color(.textBackgroundColor) : Color(.textBackgroundColor).opacity(0.6))
            .foregroundColor(.primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Meeting Info Card

struct MeetingInfoCard: View {
    let meeting: Meeting

    var body: some View {
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
                if let cost = meeting.formattedCost {
                    InfoItem(icon: "dollarsign.circle", label: "Cost", value: cost)
                }
            }
        }
        .padding()
        .background(Color(.textBackgroundColor).opacity(0.5))
        .cornerRadius(8)
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
                HStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Preparing audio...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.textBackgroundColor).opacity(0.5))
                .cornerRadius(8)
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
                        .font(.system(size: 32))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)

                // Skip backward
                Button(action: { player.skip(seconds: -15) }) {
                    Image(systemName: "gobackward.15")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!player.isReady)

                // Current time
                Text(formatTime(player.currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
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
                .controlSize(.small)

                // Duration
                Text(formatTime(player.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 40, alignment: .leading)

                // Skip forward
                Button(action: { player.skip(seconds: 15) }) {
                    Image(systemName: "goforward.15")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!player.isReady)
            }

            // Row 2: Volume + Speed controls
            HStack(spacing: 16) {
                // Volume control
                HStack(spacing: 6) {
                    Button(action: {
                        if player.volume > 0 {
                            player.setVolume(0)
                        } else {
                            player.setVolume(1.0)
                        }
                    }) {
                        Image(systemName: player.volumeIconName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 16)
                    }
                    .buttonStyle(.plain)
                    .help(player.volume > 0 ? "Mute" : "Unmute")

                    Slider(
                        value: Binding(
                            get: { Double(player.volume) },
                            set: { player.setVolume(Float($0)) }
                        ),
                        in: 0...1
                    )
                    .controlSize(.mini)
                    .frame(width: 70)
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
                            .font(.caption.weight(.medium))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.textBackgroundColor))
                    .cornerRadius(4)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding()
        .background(Color(.textBackgroundColor).opacity(0.5))
        .cornerRadius(8)
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

    enum ContentTab: String, CaseIterable {
        case privateNotes = "Private notes"
        case summary = "Summary"
        case actionItems = "Action Items"
        case transcript = "Transcript"
        case speakers = "Speakers"

        var icon: String {
            switch self {
            case .privateNotes: return "note.text"
            case .summary: return "doc.text"
            case .actionItems: return "checklist"
            case .transcript: return "text.alignleft"
            case .speakers: return "person.2"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(ContentTab.allCases, id: \.self) { tab in
                    Button(action: { selectedTab = tab }) {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.caption)
                            Text(tab.rawValue)
                                .font(.subheadline)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(selectedTab == tab ? Color.accentColor.opacity(0.1) : Color.clear)
                        .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Copy button
                Button(action: copyContent) {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Copy content")
                .disabled(currentContent == nil)

                // Reprocess button (if not processed yet)
                if let onReprocess = onReprocess, !meeting.isProcessed && meeting.transcript != nil {
                    Button(action: { Task { await onReprocess() } }) {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.caption)
                            Text("Summarize")
                                .font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help("Generate AI summary")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.textBackgroundColor).opacity(0.5))

            Divider()

            // Content
            ScrollView {
                Group {
                    switch selectedTab {
                    case .privateNotes:
                        PrivateNotesContentView(meeting: $meeting)
                    case .summary:
                        SummaryContentView(meeting: meeting)
                    case .actionItems:
                        ActionItemsContentView(meeting: meeting)
                    case .transcript:
                        TranscriptContentView(meeting: meeting)
                    case .speakers:
                        SpeakersContentView(meeting: $meeting)
                    }
                }
                .padding()
            }
        }
        .background(Color(.textBackgroundColor).opacity(0.3))
        .cornerRadius(8)
    }

    private var currentContent: String? {
        switch selectedTab {
        case .privateNotes: return meeting.privateNotes
        case .summary: return meeting.summary ?? meeting.processedSummaries?.first?.content
        case .actionItems: return meeting.actionItems?.joined(separator: "\n")
        case .transcript: return meeting.transcript
        case .speakers: return meeting.diarizedTranscript ?? meeting.transcript
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
    @StateObject private var templateManager = SummaryTemplateManager.shared
    @State private var selectedSummaryId: UUID?

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
                // No summary yet
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.largeTitle)
                        .foregroundColor(.secondary.opacity(0.5))

                    Text("No summary yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if meeting.transcript != nil {
                        Text("Click \"Summarize\" to generate an AI summary")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Transcript must be ready before summarizing")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
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
                DiarizedTranscriptView(content: summary.content)

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

// MARK: - Diarized Transcript View

struct DiarizedTranscriptView: View {
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
                        .foregroundColor(.accentColor)
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
            .background(Color(.textBackgroundColor).opacity(0.5))
            .cornerRadius(8)

            // Footer with character count
            HStack {
                Spacer()
                Text("\(notesText.count) characters")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
    @State private var completedItems: Set<String> = []

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
                // No action items
                VStack(spacing: 12) {
                    Image(systemName: "checklist")
                        .font(.largeTitle)
                        .foregroundColor(.secondary.opacity(0.5))

                    Text("No action items yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if meeting.transcript != nil && !meeting.isProcessed {
                        Text("Click \"Summarize\" to extract action items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if meeting.transcript == nil {
                        Text("Transcript must be ready before extracting action items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
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

    var body: some View {
        if let transcript = meeting.transcript {
            Text(transcript)
                .font(.body)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            TranscriptPlaceholder(status: meeting.status)
        }
    }
}

// MARK: - Speakers Content View

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
                DiarizedTranscriptView(content: diarized)
            } else if let summaries = meeting.processedSummaries,
                      let speakerSummary = summaries.first(where: { $0.outputFormat == .diarizedTranscript }) {
                Divider()
                DiarizedTranscriptView(content: speakerSummary.content)
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
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: "person.crop.rectangle.stack")
                        .foregroundColor(.secondary)
                    Text("Detected Participants (\(participants.count))")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                FlowLayout(spacing: 6) {
                    ForEach(participants) { participant in
                        HStack(spacing: 4) {
                            Image(systemName: sourceIcon(participant.source))
                                .font(.caption2)
                            Text(participant.name)
                                .font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.textBackgroundColor))
                        .cornerRadius(4)
                    }
                }
            }
        }
        .padding()
        .background(Color(.textBackgroundColor).opacity(0.3))
        .cornerRadius(8)
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
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: "photo")
                        .foregroundColor(.secondary)
                    Text("Meeting Screenshot")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                if let image = NSImage(contentsOfFile: path) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 300)
                        .cornerRadius(8)
                        .onTapGesture {
                            // Open in Preview
                            NSWorkspace.shared.open(URL(fileURLWithPath: path))
                        }
                }
            }
        }
        .padding()
        .background(Color(.textBackgroundColor).opacity(0.3))
        .cornerRadius(8)
    }
}

// MARK: - Diarized Segments View (from DiarizationSegment)

struct DiarizedSegmentsView: View {
    let segments: [DiarizationSegment]
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Conversation")
                .font(.subheadline.weight(.semibold))
                .padding(.bottom, 4)

            ForEach(segments) { segment in
                HStack(alignment: .top, spacing: 12) {
                    // Speaker avatar
                    Circle()
                        .fill(colorForSpeaker(segment.speakerId))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Text(meeting.speakerName(for: segment.speakerId).prefix(1).uppercased())
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(meeting.speakerName(for: segment.speakerId))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(colorForSpeaker(segment.speakerId))

                        Text(segment.text)
                            .font(.body)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Transcript")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                if meeting.transcript != nil {
                    Button(action: copyTranscript) {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Copy transcript")
                }
            }

            if let transcript = meeting.transcript {
                Text(transcript)
                    .font(.body)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TranscriptPlaceholder(status: meeting.status)
            }
        }
        .padding()
        .background(Color(.textBackgroundColor).opacity(0.3))
        .cornerRadius(8)
    }

    private func copyTranscript() {
        guard let transcript = meeting.transcript else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
    }
}

struct TranscriptPlaceholder: View {
    let status: MeetingStatus

    var body: some View {
        HStack(spacing: 12) {
            switch status {
            case .recording:
                ProgressView()
                    .scaleEffect(0.8)
                Text("Recording in progress...")
            case .pendingTranscription:
                Image(systemName: "clock")
                Text("Waiting for transcription...")
            case .transcribing:
                ProgressView()
                    .scaleEffect(0.8)
                Text("Transcribing...")
            case .ready:
                Image(systemName: "doc.text")
                Text("No transcript available")
            case .failed:
                Image(systemName: "exclamationmark.triangle")
                Text("Transcription failed")
            }
        }
        .font(.subheadline)
        .foregroundColor(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - Action Items Section

struct ActionItemsSection: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Action Items")
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                            .padding(.top, 3)

                        Text(item)
                            .font(.body)
                    }
                }
            }
        }
        .padding()
        .background(Color(.textBackgroundColor).opacity(0.3))
        .cornerRadius(8)
    }
}

// MARK: - Error Section

struct ErrorSection: View {
    let message: String
    var onRetry: (() -> Void)?
    @State private var isRetrying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.primary)

                Spacer()
            }

            if let onRetry = onRetry {
                Button(action: {
                    isRetrying = true
                    onRetry()
                }) {
                    HStack(spacing: 6) {
                        if isRetrying {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(isRetrying ? "Retrying..." : "Retry Transcription")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.accentColor)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .disabled(isRetrying)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Keyboard Footer

struct DetailKeyboardFooter: View {
    var body: some View {
        Divider()
        HStack(spacing: 20) {
            DetailShortcutHint(keys: "← →", action: "seek ±10s")
            DetailShortcutHint(keys: "Space", action: "play/pause")
            DetailShortcutHint(keys: "C", action: "copy transcript")
            DetailShortcutHint(keys: "Esc", action: "back")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

struct DetailShortcutHint: View {
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

#Preview("Error Section") {
    ErrorSection(message: "API key invalid. Please check your settings.")
        .frame(width: 400)
        .padding()
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
