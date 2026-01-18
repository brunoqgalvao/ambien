//
//  SpeakerLabelingView.swift
//  MeetingRecorder
//
//  UI for labeling speakers detected in a meeting transcript
//

import SwiftUI

/// View for labeling speakers in a meeting
struct SpeakerLabelingView: View {
    @Binding var meeting: Meeting
    @State private var editingLabel: SpeakerLabel?
    @State private var isExpanded: Bool = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: "person.2.fill")
                        .foregroundColor(.brandViolet)
                    Text("Speakers (\(meeting.speakerCount ?? meeting.uniqueSpeakers.count))")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(meeting.uniqueSpeakers, id: \.self) { speakerId in
                        SpeakerLabelRow(
                            speakerId: speakerId,
                            currentLabel: meeting.speakerName(for: speakerId),
                            isLabeled: meeting.speakerLabels?.contains(where: { $0.speakerId == speakerId }) ?? false,
                            onLabelChanged: { newName in
                                updateSpeakerLabel(speakerId: speakerId, name: newName)
                            }
                        )
                    }

                    // Add from participants button (if we have OCR-detected participants)
                    if let participants = meeting.participants, !participants.isEmpty {
                        Divider()
                        SuggestedParticipantsView(
                            participants: participants,
                            speakers: meeting.uniqueSpeakers,
                            existingLabels: meeting.speakerLabels ?? [],
                            onAssign: { speakerId, participantName in
                                updateSpeakerLabel(speakerId: speakerId, name: participantName)
                            }
                        )
                    }
                }
            }
        }
        .padding()
        .background(Color.brandCreamDark.opacity(0.5))
        .cornerRadius(8)
    }

    private func updateSpeakerLabel(speakerId: String, name: String) {
        var labels = meeting.speakerLabels ?? []

        // Remove existing label for this speaker
        labels.removeAll { $0.speakerId == speakerId }

        // Add new label if name is not empty
        if !name.isEmpty {
            labels.append(SpeakerLabel(speakerId: speakerId, name: name))
        }

        meeting.speakerLabels = labels

        // Save to database
        Task {
            try? await DatabaseManager.shared.update(meeting)
        }
    }
}

/// Row for a single speaker with editable label
struct SpeakerLabelRow: View {
    let speakerId: String
    let currentLabel: String
    let isLabeled: Bool
    let onLabelChanged: (String) -> Void

    @State private var isEditing = false
    @State private var editedName: String = ""
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Speaker avatar
            Circle()
                .fill(colorForSpeaker(speakerId))
                .frame(width: 32, height: 32)
                .overlay(
                    Text(currentLabel.prefix(1).uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                )

            if isEditing {
                // Edit mode - brand-styled inline text field, left-aligned
                HStack(spacing: 8) {
                    TextField("Enter name", text: $editedName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .focused($isFocused)
                        .onSubmit {
                            commitEdit()
                        }
                        .onExitCommand {
                            cancelEdit()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.brandSurface)
                        .cornerRadius(BrandRadius.small)
                        .overlay(
                            RoundedRectangle(cornerRadius: BrandRadius.small)
                                .stroke(Color.brandViolet, lineWidth: 2)
                        )
                        .frame(maxWidth: 180)

                    // Confirm button
                    BrandIconButton(icon: "checkmark", size: 28, color: .brandMint, hoverColor: .brandMint) {
                        commitEdit()
                    }

                    // Cancel button
                    BrandIconButton(icon: "xmark", size: 28, color: .brandTextSecondary, hoverColor: .brandCoral) {
                        cancelEdit()
                    }

                    Spacer()
                }
                .onAppear {
                    isFocused = true
                }
            } else {
                // Display mode - double-click to edit
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(currentLabel)
                            .font(.subheadline.weight(.medium))

                        if !isLabeled {
                            Text("Double-click to name")
                                .font(.caption2)
                                .foregroundColor(.brandTextSecondary)
                        }
                    }

                    Spacer()

                    // Show pencil on hover
                    if isHovered {
                        Image(systemName: "pencil")
                            .font(.system(size: 11))
                            .foregroundColor(.brandTextSecondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    startEditing()
                }
                .onHover { hovering in
                    isHovered = hovering
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func startEditing() {
        editedName = isLabeled ? currentLabel : ""
        isEditing = true
    }

    private func commitEdit() {
        onLabelChanged(editedName)
        isEditing = false
    }

    private func cancelEdit() {
        isEditing = false
    }

    private func colorForSpeaker(_ speakerId: String) -> Color {
        let colors: [Color] = [.blue, .purple, .orange, .green, .pink, .teal, .indigo, .mint]
        // Extract number from speaker_0, speaker_1, etc.
        if let numStr = speakerId.split(separator: "_").last,
           let num = Int(numStr) {
            return colors[num % colors.count]
        }
        return colors[abs(speakerId.hashValue) % colors.count]
    }
}

/// View showing suggested participants from OCR
struct SuggestedParticipantsView: View {
    let participants: [MeetingParticipant]
    let speakers: [String]
    let existingLabels: [SpeakerLabel]
    let onAssign: (String, String) -> Void

    @State private var selectedSpeaker: String?
    @State private var isExpanded = false

    // Filter out participants that are already assigned
    private var unassignedParticipants: [MeetingParticipant] {
        let assignedNames = Set(existingLabels.map { $0.name.lowercased() })
        return participants.filter { !assignedNames.contains($0.name.lowercased()) }
    }

    // Speakers that don't have custom labels yet
    private var unlabeledSpeakers: [String] {
        let labeledIds = Set(existingLabels.map { $0.speakerId })
        return speakers.filter { !labeledIds.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: "person.crop.rectangle.stack")
                        .foregroundColor(.secondary)
                    Text("Detected from screenshot (\(unassignedParticipants.count))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded && !unassignedParticipants.isEmpty {
                VStack(spacing: 6) {
                    ForEach(unassignedParticipants) { participant in
                        HStack {
                            Text(participant.name)
                                .font(.caption)

                            Spacer()

                            // Quick assign buttons for unlabeled speakers
                            ForEach(unlabeledSpeakers.prefix(3), id: \.self) { speakerId in
                                Button(action: {
                                    onAssign(speakerId, participant.name)
                                }) {
                                    Text(displayName(for: speakerId))
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(colorForSpeaker(speakerId).opacity(0.2))
                                        .foregroundColor(colorForSpeaker(speakerId))
                                        .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                                .help("Assign to \(displayName(for: speakerId))")
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func displayName(for speakerId: String) -> String {
        if let numStr = speakerId.split(separator: "_").last,
           let num = Int(numStr) {
            return "S\(num + 1)"
        }
        return speakerId
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

// MARK: - Speaker Naming Prompt (Dismissable Banner)

/// Dismissable prompt encouraging users to name speakers
/// Shows when speakers are detected but not all have user-assigned names
struct SpeakerNamingPrompt: View {
    @Binding var meeting: Meeting
    @State private var isExpanded = false
    @State private var isHovered = false

    private var unnamedCount: Int {
        let speakers = meeting.uniqueSpeakers
        let userLabeled = meeting.speakerLabels?.filter { $0.isUserAssigned }.count ?? 0
        return max(0, speakers.count - userLabeled)
    }

    var body: some View {
        BrandCard(padding: 0) {
            VStack(spacing: 0) {
                // Main prompt row
                HStack(spacing: 12) {
                    // Icon with pulse animation
                    ZStack {
                        Circle()
                            .fill(Color.brandViolet.opacity(0.15))
                            .frame(width: 36, height: 36)

                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 16))
                            .foregroundColor(.brandViolet)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Name your speakers")
                            .font(.brandDisplay(13, weight: .semibold))
                            .foregroundColor(.brandTextPrimary)

                        Text("\(unnamedCount) speaker\(unnamedCount == 1 ? "" : "s") detected • add names for better transcripts")
                            .font(.brandDisplay(11))
                            .foregroundColor(.brandTextSecondary)
                    }

                    Spacer()

                    // Actions
                    HStack(spacing: 8) {
                        // Name now button
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded.toggle()
                            }
                        }) {
                            Text(isExpanded ? "Collapse" : "Name now")
                                .font(.brandDisplay(12, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.brandViolet)
                                .cornerRadius(BrandRadius.small)
                        }
                        .buttonStyle(.plain)

                        // Dismiss button
                        Button(action: dismissPrompt) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.brandTextSecondary)
                                .frame(width: 24, height: 24)
                                .background(Color.brandBackground)
                                .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        .help("Don't show again for this meeting")
                    }
                }
                .padding(12)

                // Expanded inline labeling
                if isExpanded {
                    Divider()

                    VStack(spacing: 8) {
                        ForEach(meeting.uniqueSpeakers, id: \.self) { speakerId in
                            SpeakerLabelRow(
                                speakerId: speakerId,
                                currentLabel: meeting.speakerName(for: speakerId),
                                isLabeled: meeting.speakerLabels?.contains(where: { $0.speakerId == speakerId && $0.isUserAssigned }) ?? false,
                                onLabelChanged: { newName in
                                    updateSpeakerLabel(speakerId: speakerId, name: newName, isUserAssigned: true)
                                }
                            )
                        }

                        // Done button when all named
                        if unnamedCount == 0 {
                            HStack {
                                Spacer()
                                Button(action: {
                                    withAnimation {
                                        isExpanded = false
                                        dismissPrompt()
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark.circle.fill")
                                        Text("All done!")
                                    }
                                    .font(.brandDisplay(12, weight: .medium))
                                    .foregroundColor(.brandMint)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func dismissPrompt() {
        withAnimation(.easeOut(duration: 0.2)) {
            meeting.speakerNamingDismissed = true
        }

        // Save to database
        Task {
            try? await DatabaseManager.shared.update(meeting)
        }
    }

    private func updateSpeakerLabel(speakerId: String, name: String, isUserAssigned: Bool) {
        var labels = meeting.speakerLabels ?? []

        // Remove existing label for this speaker
        labels.removeAll { $0.speakerId == speakerId }

        // Add new label if name is not empty
        if !name.isEmpty {
            labels.append(SpeakerLabel(
                speakerId: speakerId,
                name: name,
                isUserAssigned: isUserAssigned
            ))
        }

        meeting.speakerLabels = labels

        // Save to database
        Task {
            try? await DatabaseManager.shared.update(meeting)
        }
    }
}

// MARK: - Compact Speaker Labels (for inline use)

/// Compact horizontal display of speaker labels
struct CompactSpeakerLabels: View {
    let meeting: Meeting
    var onTap: (() -> Void)?

    var body: some View {
        if meeting.hasSpeakerData {
            Button(action: { onTap?() }) {
                HStack(spacing: 4) {
                    Image(systemName: "person.2")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text("\(meeting.speakerCount ?? meeting.uniqueSpeakers.count) speakers")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let labels = meeting.speakerLabels, !labels.isEmpty {
                        Text("•")
                            .foregroundColor(.secondary)

                        // Show first few names
                        Text(labels.prefix(2).map { $0.name }.joined(separator: ", "))
                            .font(.caption)
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        if labels.count > 2 {
                            Text("+\(labels.count - 2)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Previews

#Preview("Speaker Naming Prompt") {
    let meeting = Meeting(
        title: "Team Standup",
        startTime: Date(),
        audioPath: "/path/to/audio.m4a",
        transcript: "Hello everyone...",
        status: .ready,
        speakerCount: 3,
        diarizationSegments: [
            DiarizationSegment(speakerId: "speaker_0", start: 0, end: 10, text: "Hello everyone"),
            DiarizationSegment(speakerId: "speaker_1", start: 10, end: 20, text: "Good morning"),
            DiarizationSegment(speakerId: "speaker_2", start: 20, end: 30, text: "Let's get started")
        ]
    )

    return SpeakerNamingPrompt(meeting: .constant(meeting))
        .frame(width: 450)
        .padding()
}

#Preview("Speaker Labeling") {
    let meeting = Meeting(
        title: "Team Standup",
        startTime: Date(),
        audioPath: "/path/to/audio.m4a",
        transcript: "Hello everyone...",
        status: .ready,
        participants: [
            MeetingParticipant(name: "Alice Smith", source: .screenshot),
            MeetingParticipant(name: "Bob Jones", source: .screenshot),
            MeetingParticipant(name: "Carol White", source: .screenshot)
        ],
        speakerCount: 3,
        diarizationSegments: [
            DiarizationSegment(speakerId: "speaker_0", start: 0, end: 10, text: "Hello everyone"),
            DiarizationSegment(speakerId: "speaker_1", start: 10, end: 20, text: "Good morning"),
            DiarizationSegment(speakerId: "speaker_2", start: 20, end: 30, text: "Let's get started")
        ]
    )

    return SpeakerLabelingView(meeting: .constant(meeting))
        .frame(width: 400)
        .padding()
}
