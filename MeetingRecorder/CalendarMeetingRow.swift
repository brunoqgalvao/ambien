//
//  CalendarMeetingRow.swift
//  MeetingRecorder
//
//  Single meeting row for CalendarView with hover actions and context menu
//

import SwiftUI

/// Meeting row for calendar view with hover state and quick actions
struct CalendarMeetingRow: View {
    let meeting: Meeting
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onRetry: () -> Void

    @State private var isHovered = false
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            CalendarStatusBadge(status: meeting.status)

            // Meeting info
            VStack(alignment: .leading, spacing: 4) {
                Text(meeting.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    // Time
                    Text(meeting.formattedTime)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Duration
                    Text(formatDuration(meeting.duration))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Source app
                    if let app = meeting.sourceApp {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(app)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Hover actions
            if isHovered {
                HStack(spacing: 8) {
                    // Play button
                    if meeting.status == .ready && FileManager.default.fileExists(atPath: meeting.audioPath) {
                        QuickActionButton(icon: "play.fill", tooltip: "Play audio") {
                            playAudio()
                        }
                    }

                    // Copy transcript
                    if meeting.transcript != nil {
                        QuickActionButton(icon: "doc.on.doc", tooltip: "Copy transcript") {
                            copyTranscript()
                        }
                    }

                    // Delete
                    QuickActionButton(icon: "trash", tooltip: "Delete", isDestructive: true) {
                        showDeleteConfirm = true
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                // Cost badge (when not hovering)
                if let cost = meeting.formattedCost {
                    Text(cost)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.brandCreamDark)
                        .cornerRadius(BrandRadius.small)
                }

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            CalendarMeetingContextMenu(
                meeting: meeting,
                onPlay: playAudio,
                onCopy: copyTranscript,
                onRetry: onRetry,
                onDelete: { showDeleteConfirm = true }
            )
        }
        .alert("Delete Meeting?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("The recording and transcript for \"\(meeting.title)\" will be permanently deleted.")
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.brandViolet.opacity(0.1)
        } else if isHovered {
            return Color.brandCreamDark.opacity(0.5)
        }
        return Color.clear
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = minutes / 60
            let remainingMins = minutes % 60
            if remainingMins == 0 {
                return "\(hours)h"
            }
            return "\(hours)h \(remainingMins)m"
        }
    }

    private func playAudio() {
        let url = URL(fileURLWithPath: meeting.audioPath)
        NSWorkspace.shared.open(url)
    }

    private func copyTranscript() {
        guard let transcript = meeting.transcript else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
    }
}

// MARK: - Quick Action Button

struct QuickActionButton: View {
    let icon: String
    let tooltip: String
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.caption.weight(.medium))
                .foregroundColor(isDestructive ? .red : .primary)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(isHovered ? Color.brandCreamDark : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Status Badge for Calendar

/// Only shows an indicator for errors or in-progress states
/// Ready meetings show nothing (clean, minimal)
struct CalendarStatusBadge: View {
    let status: MeetingStatus

    var body: some View {
        Group {
            switch status {
            case .recording:
                // Recording pulse indicator
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                }
            case .transcribing:
                // Simple spinner for transcribing
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 32, height: 32)
            case .failed:
                // Error ribbon/alert - the ONLY colored indicator for completed meetings
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.12))
                        .frame(width: 32, height: 32)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.red)
                }
            case .pendingTranscription, .ready:
                // No indicator - clean and minimal
                Color.clear
                    .frame(width: 32, height: 32)
            }
        }
    }
}

// MARK: - Context Menu

struct CalendarMeetingContextMenu: View {
    let meeting: Meeting
    let onPlay: () -> Void
    let onCopy: () -> Void
    let onRetry: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Group {
            // Play audio
            if meeting.status == .ready && FileManager.default.fileExists(atPath: meeting.audioPath) {
                Button(action: onPlay) {
                    Label("Play audio", systemImage: "play.fill")
                }
            }

            // Edit title (placeholder)
            Button(action: {}) {
                Label("Edit title...", systemImage: "pencil")
            }
            .disabled(true)

            // Copy transcript
            if meeting.transcript != nil {
                Button(action: onCopy) {
                    Label("Copy transcript", systemImage: "doc.on.doc")
                }
            }

            // Export as Markdown
            if meeting.transcript != nil {
                Button(action: { exportAsMarkdown() }) {
                    Label("Export as Markdown", systemImage: "arrow.up.doc")
                }
            }

            Divider()

            // Re-transcribe
            if meeting.status == .failed || meeting.status == .ready {
                Button(action: onRetry) {
                    Label("Re-transcribe", systemImage: "arrow.clockwise")
                }
            }

            // Show in Finder
            Button(action: showInFinder) {
                Label("Show in Finder", systemImage: "folder")
            }

            Divider()

            // Delete
            Button(role: .destructive, action: onDelete) {
                Label("Delete...", systemImage: "trash")
            }
        }
    }

    private func showInFinder() {
        let url = URL(fileURLWithPath: meeting.audioPath)
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
    }

    private func exportAsMarkdown() {
        guard let transcript = meeting.transcript else { return }

        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short

        var markdown = "# \(meeting.title)\n\n"
        markdown += "**Date:** \(formatter.string(from: meeting.startTime))\n"
        markdown += "**Duration:** \(Int(meeting.duration / 60)) minutes\n"
        if let app = meeting.sourceApp {
            markdown += "**Source:** \(app)\n"
        }
        markdown += "\n---\n\n"
        markdown += "## Transcript\n\n"
        markdown += transcript
        markdown += "\n"

        if let items = meeting.actionItems, !items.isEmpty {
            markdown += "\n## Action Items\n\n"
            for item in items {
                markdown += "- [ ] \(item)\n"
            }
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }
}

// MARK: - Previews

#Preview("Meeting Row - Ready") {
    CalendarMeetingRow(
        meeting: Meeting.sampleMeetings[0],
        isSelected: false,
        onSelect: {},
        onDelete: {},
        onRetry: {}
    )
    .frame(width: 500)
    .padding()
}

#Preview("Meeting Row - Selected") {
    CalendarMeetingRow(
        meeting: Meeting.sampleMeetings[0],
        isSelected: true,
        onSelect: {},
        onDelete: {},
        onRetry: {}
    )
    .frame(width: 500)
    .padding()
}

#Preview("Meeting Row - Transcribing") {
    CalendarMeetingRow(
        meeting: Meeting.sampleMeetings[1],
        isSelected: false,
        onSelect: {},
        onDelete: {},
        onRetry: {}
    )
    .frame(width: 500)
    .padding()
}

#Preview("Meeting Row - Failed") {
    CalendarMeetingRow(
        meeting: Meeting.sampleMeetings[3],
        isSelected: false,
        onSelect: {},
        onDelete: {},
        onRetry: {}
    )
    .frame(width: 500)
    .padding()
}

#Preview("Status Badges") {
    HStack(spacing: 20) {
        ForEach(MeetingStatus.allCases, id: \.self) { status in
            VStack {
                CalendarStatusBadge(status: status)
                Text(status.displayName)
                    .font(.caption2)
            }
        }
    }
    .padding()
}

#Preview("Quick Action Buttons") {
    HStack(spacing: 16) {
        QuickActionButton(icon: "play.fill", tooltip: "Play") {}
        QuickActionButton(icon: "doc.on.doc", tooltip: "Copy") {}
        QuickActionButton(icon: "trash", tooltip: "Delete", isDestructive: true) {}
    }
    .padding()
}
