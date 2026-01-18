//
//  AudioImportManager.swift
//  MeetingRecorder
//
//  Imports audio files as meetings and triggers the transcription pipeline
//

import Foundation
import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// Manages importing external audio files as meetings
@MainActor
class AudioImportManager: ObservableObject {
    // MARK: - Shared Instance
    static let shared = AudioImportManager()

    // MARK: - Published Properties
    @Published var isImporting = false
    @Published var importProgress: String?
    @Published var errorMessage: String?

    // MARK: - Supported Formats
    private let supportedExtensions = ["m4a", "mp3", "wav", "aac", "aiff", "mp4", "mov", "caf", "flac", "ogg"]

    private init() {}

    // MARK: - Public Methods

    /// Shows file picker and imports selected audio file
    func showImportDialog() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Select an audio file to import"
        panel.prompt = "Import"

        // Build allowed content types
        var allowedTypes: [UTType] = [.audio, .movie]
        for ext in supportedExtensions {
            if let type = UTType(filenameExtension: ext) {
                allowedTypes.append(type)
            }
        }
        panel.allowedContentTypes = allowedTypes

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in
                await self?.importAudioFile(from: url)
            }
        }
    }

    /// Imports an audio file from a URL
    func importAudioFile(from sourceURL: URL) async {
        isImporting = true
        importProgress = "Preparing import..."
        errorMessage = nil

        do {
            // Validate file exists and is readable
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                throw ImportError.fileNotFound
            }

            // Get audio duration
            importProgress = "Analyzing audio..."
            let duration = try await getAudioDuration(from: sourceURL)

            // Initialize database
            try await DatabaseManager.shared.initialize()

            // Create recordings folder
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let recordingsFolder = documentsPath.appendingPathComponent("MeetingRecorder/recordings", isDirectory: true)
            try FileManager.default.createDirectory(at: recordingsFolder, withIntermediateDirectories: true)

            // Generate destination filename
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let timestamp = formatter.string(from: Date())
            let originalName = sourceURL.deletingPathExtension().lastPathComponent
            let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
            let destURL = recordingsFolder.appendingPathComponent("imported_\(timestamp)_\(originalName).\(ext)")

            // Copy file to recordings folder
            importProgress = "Copying audio file..."
            try FileManager.default.copyItem(at: sourceURL, to: destURL)

            print("[AudioImportManager] Imported file to: \(destURL.path)")

            // Create meeting record
            let meeting = Meeting(
                title: "Imported: \(originalName)",
                startTime: Date(),
                endTime: Date(),
                duration: duration,
                sourceApp: "Imported",
                audioPath: destURL.path,
                status: .pendingTranscription
            )

            try await DatabaseManager.shared.insert(meeting)
            NotificationCenter.default.post(name: .meetingsDidChange, object: nil)

            print("[AudioImportManager] Created meeting: \(meeting.id)")

            // Start transcription
            importProgress = "Starting transcription..."
            await transcribeMeeting(meeting)

            isImporting = false
            importProgress = nil

        } catch {
            isImporting = false
            importProgress = nil
            errorMessage = error.localizedDescription
            print("[AudioImportManager] Import error: \(error)")

            ToastController.shared.showError(
                "Import failed",
                message: error.localizedDescription
            )
        }
    }

    // MARK: - Private Methods

    private func getAudioDuration(from url: URL) async throws -> TimeInterval {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return CMTimeGetSeconds(duration)
    }

    private func transcribeMeeting(_ meeting: Meeting) async {
        var updatedMeeting = meeting
        updatedMeeting.status = .transcribing
        updatedMeeting.errorMessage = nil
        let meetingId = meeting.id

        do {
            try await DatabaseManager.shared.update(updatedMeeting)
            NotificationCenter.default.post(name: .meetingsDidChange, object: nil)

            // Check for API key
            guard KeychainHelper.readOpenAIKey() != nil else {
                errorMessage = "No OpenAI API key. Add in Settings."
                updatedMeeting.status = .failed
                updatedMeeting.errorMessage = "No API key configured"
                try? await DatabaseManager.shared.update(updatedMeeting)
                NotificationCenter.default.post(name: .meetingsDidChange, object: nil)

                ToastController.shared.showError(
                    "No API key",
                    message: "Add your OpenAI API key in Settings",
                    action: ToastAction(title: "Settings") {
                        SettingsWindowController.shared.showWindow()
                    }
                )
                return
            }

            // Show transcribing island
            TranscribingIslandController.shared.show(
                meetingTitle: meeting.title,
                meetingId: meetingId
            )

            // Perform transcription
            let result = try await TranscriptionService.shared.transcribe(
                audioPath: meeting.audioPath,
                meetingId: meetingId
            )

            // Update meeting with transcript
            updatedMeeting.transcript = result.text
            updatedMeeting.apiCostCents = result.costCents
            updatedMeeting.duration = result.duration
            updatedMeeting.status = .ready
            updatedMeeting.errorMessage = nil

            // Use generated title if available
            if let generatedTitle = result.title {
                updatedMeeting.title = generatedTitle
                print("[AudioImportManager] Auto-generated title: \(generatedTitle)")
            }

            // Apply diarization segments if available (already in correct format from TranscriptionService)
            if let diarizationSegments = result.diarizationSegments {
                updatedMeeting.diarizationSegments = diarizationSegments
            }

            // Apply inferred speaker labels if available (already in correct format)
            if let inferredLabels = result.inferredSpeakerLabels {
                updatedMeeting.speakerLabels = inferredLabels
            }

            try await DatabaseManager.shared.update(updatedMeeting)

            print("[AudioImportManager] Transcription complete. Cost: \(result.costCents) cents")

            // Hide transcribing island
            TranscribingIslandController.shared.hide()

            // Show success notification
            ToastController.shared.showSuccess(
                "Transcript ready",
                message: updatedMeeting.title,
                duration: 4.0,
                action: ToastAction(title: "View") {
                    MainAppWindowController.shared.showMeeting(id: meetingId)
                },
                onTap: {
                    MainAppWindowController.shared.showMeeting(id: meetingId)
                }
            )

            NotificationCenter.default.post(name: .meetingsDidChange, object: nil)

            // Export to agent API
            Task {
                do {
                    try await AgentAPIManager.shared.exportMeeting(updatedMeeting)
                } catch {
                    print("[AudioImportManager] Agent API export failed: \(error)")
                }
            }

        } catch {
            print("[AudioImportManager] Transcription error: \(error)")

            updatedMeeting.status = .failed
            updatedMeeting.errorMessage = error.localizedDescription
            try? await DatabaseManager.shared.update(updatedMeeting)
            NotificationCenter.default.post(name: .meetingsDidChange, object: nil)

            TranscribingIslandController.shared.hide()

            ToastController.shared.showError(
                "Transcription failed",
                message: error.localizedDescription
            )
        }
    }
}

// MARK: - Import Errors

enum ImportError: LocalizedError {
    case fileNotFound
    case invalidAudioFile
    case copyFailed
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Audio file not found"
        case .invalidAudioFile:
            return "Could not read audio file"
        case .copyFailed:
            return "Failed to copy audio file"
        case .unsupportedFormat:
            return "Unsupported audio format"
        }
    }
}
