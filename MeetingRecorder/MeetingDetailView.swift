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
    let meeting: Meeting
    var showBackButton: Bool = true
    @Environment(\.dismiss) private var dismiss
    @StateObject private var audioPlayer = AudioPlayerManager()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            DetailHeader(meeting: meeting, showBackButton: showBackButton, onDismiss: { dismiss() })

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Meeting info card
                    MeetingInfoCard(meeting: meeting)

                    // Audio player (if file exists)
                    if FileManager.default.fileExists(atPath: meeting.audioPath) {
                        AudioPlayerCard(
                            audioPath: meeting.audioPath,
                            player: audioPlayer
                        )
                    }

                    // Transcript
                    TranscriptSection(meeting: meeting)

                    // Action items (if any)
                    if let items = meeting.actionItems, !items.isEmpty {
                        ActionItemsSection(items: items)
                    }

                    // Error message (if failed)
                    if let error = meeting.errorMessage {
                        ErrorSection(message: error)
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
            dismiss()
            return .handled
        }
    }

    private func copyTranscript() {
        guard let transcript = meeting.transcript else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
    }
}

// MARK: - Header

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

            MeetingStatusBadge(status: meeting.status)
        }
        .padding()
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

    var body: some View {
        VStack(spacing: 12) {
            // Progress bar
            ProgressView(value: player.progress)
                .progressViewStyle(.linear)

            HStack {
                // Time display
                Text(formatTime(player.currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)

                Spacer()

                // Controls
                HStack(spacing: 16) {
                    Button(action: { player.skip(seconds: -15) }) {
                        Image(systemName: "gobackward.15")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .disabled(!player.isReady)

                    Button(action: {
                        if player.isPlaying {
                            player.pause()
                        } else {
                            player.play(url: URL(fileURLWithPath: audioPath))
                        }
                    }) {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.title)
                    }
                    .buttonStyle(.plain)

                    Button(action: { player.skip(seconds: 15) }) {
                        Image(systemName: "goforward.15")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .disabled(!player.isReady)
                }

                Spacer()

                // Duration
                Text(formatTime(player.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.textBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .onAppear {
            player.prepare(url: URL(fileURLWithPath: audioPath))
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Transcript Section

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

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.red)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1))
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

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func prepare(url: URL) {
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
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
