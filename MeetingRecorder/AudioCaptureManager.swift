//
//  AudioCaptureManager.swift
//  MeetingRecorder
//
//  Captures system audio via ScreenCaptureKit and microphone via AVAudioEngine
//  Mixes both streams and saves to AAC .m4a file
//

import Foundation
import ScreenCaptureKit
import AVFoundation
import Combine
import CoreGraphics

/// Errors that can occur during audio capture
enum AudioCaptureError: LocalizedError {
    case noPermission
    case streamFailed(Error)
    case writerFailed(Error)
    case noAudioSources
    case recordingInProgress
    case notRecording

    var errorDescription: String? {
        switch self {
        case .noPermission:
            return "Screen recording permission required"
        case .streamFailed(let error):
            return "Stream failed: \(error.localizedDescription)"
        case .writerFailed(let error):
            return "Writer failed: \(error.localizedDescription)"
        case .noAudioSources:
            return "No audio sources available"
        case .recordingInProgress:
            return "Recording already in progress"
        case .notRecording:
            return "Not currently recording"
        }
    }
}

/// Recording state for UI updates
enum RecordingState: Equatable {
    case idle
    case preparing
    case recording(duration: TimeInterval)
    case stopping
    case error(String)

    static func == (lhs: RecordingState, rhs: RecordingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.preparing, .preparing), (.stopping, .stopping):
            return true
        case let (.recording(d1), .recording(d2)):
            return d1 == d2
        case let (.error(e1), .error(e2)):
            return e1 == e2
        default:
            return false
        }
    }
}

/// Main audio capture manager - handles system audio + mic recording
@MainActor
class AudioCaptureManager: NSObject, ObservableObject {
    // MARK: - Published Properties

    @Published var state: RecordingState = .idle
    @Published var isRecording: Bool = false
    @Published var currentDuration: TimeInterval = 0
    @Published var lastRecordingURL: URL?
    @Published var errorMessage: String?
    @Published var currentMeeting: Meeting?
    @Published var transcriptionProgress: String?

    // MARK: - Private Properties

    private var stream: SCStream?
    private var audioEngine: AVAudioEngine?
    private var assetWriter: AVAssetWriter?
    private var systemAudioInput: AVAssetWriterInput?
    private var micAudioInput: AVAssetWriterInput?
    private var streamOutput: SystemAudioOutputHandler?
    private var streamDelegate: StreamDelegate?
    private var streamConfiguration: SCStreamConfiguration?
    private var streamContentFilter: SCContentFilter?
    private var streamOutputQueue: DispatchQueue?
    private var shareableContent: SCShareableContent?

    private var recordingStartTime: Date?
    private var durationTimer: Timer?
    private var meetingTitle: String = "Meeting"
    private var sourceApp: String?

    // Audio format settings
    private let targetSampleRate: Double = 16000
    private let targetChannels: UInt32 = 1
    private let targetBitRate: Int = 64000

    // Buffers for mixing
    private var systemAudioBuffer: [CMSampleBuffer] = []
    private var micAudioBuffer: [CMSampleBuffer] = []

    // Track first sample timestamp for proper session timing
    private var firstSampleTime: CMTime?
    private var sessionStarted: Bool = false

    // Activity to prevent App Nap
    private var backgroundActivity: NSObjectProtocol?

    // MARK: - Initialization

    override init() {
        super.init()
    }

    // MARK: - Public Methods

    /// Start recording system audio and microphone
    /// - Parameters:
    ///   - title: Optional meeting title (defaults to timestamp)
    ///   - sourceApp: Optional source app name (Zoom, Meet, etc.)
    func startRecording(title: String? = nil, sourceApp: String? = nil) async throws {
        guard !isRecording else {
            throw AudioCaptureError.recordingInProgress
        }

        state = .preparing
        errorMessage = nil

        // Set meeting metadata
        self.sourceApp = sourceApp
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let timeString = formatter.string(from: Date())
        self.meetingTitle = title ?? "Meeting at \(timeString)"

        do {
            // Initialize database if needed
            try await DatabaseManager.shared.initialize()

            // Prevent App Nap during recording
            backgroundActivity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleSystemSleepDisabled],
                reason: "Recording meeting audio"
            )

            // Set up the asset writer
            let outputURL = createOutputURL()
            try setupAssetWriter(url: outputURL)

            // Start system audio capture
            try await startSystemAudioCapture()

            // Start microphone capture
            try startMicrophoneCapture()

            // Start the asset writer (session will be started on first sample)
            guard let writer = assetWriter else {
                throw AudioCaptureError.writerFailed(NSError(domain: "AudioCapture", code: -1))
            }
            writer.startWriting()
            // Don't start session yet - we'll start it when we get the first sample
            // to ensure proper timestamp alignment
            firstSampleTime = nil
            sessionStarted = false

            recordingStartTime = Date()
            isRecording = true
            state = .recording(duration: 0)
            lastRecordingURL = outputURL

            // Capture meeting context (screenshot + window title + participants)
            let (screenshotPath, windowTitle, participants) = await ParticipantService.shared.captureMeetingContext(
                bundleIdentifier: self.getSourceAppBundleId()
            )

            // Create Meeting record with context
            var meeting = Meeting(
                title: self.meetingTitle,
                startTime: recordingStartTime!,
                sourceApp: self.sourceApp,
                audioPath: outputURL.path,
                status: .recording,
                windowTitle: windowTitle,
                screenshotPath: screenshotPath,
                participants: participants.isEmpty ? nil : participants
            )

            // If we got a window title, use it as the meeting title if it's better
            if let capturedTitle = windowTitle, capturedTitle.count > 3 {
                meeting.title = capturedTitle
                self.meetingTitle = capturedTitle
            }

            currentMeeting = meeting
            try await DatabaseManager.shared.insert(meeting)

            // Start duration timer
            startDurationTimer()

            print("[AudioCapture] Recording started: \(outputURL.path)")

        } catch {
            await cleanupResources()
            state = .error(error.localizedDescription)
            errorMessage = error.localizedDescription
            throw error
        }
    }

    /// Stop recording and save the file
    /// - Parameter autoTranscribe: Whether to automatically start transcription (default: true)
    func stopRecording(autoTranscribe: Bool = true) async throws -> URL {
        guard isRecording, let outputURL = lastRecordingURL else {
            throw AudioCaptureError.notRecording
        }

        state = .stopping
        durationTimer?.invalidate()
        durationTimer = nil

        // Stop system audio capture
        if let stream = stream {
            try? await stream.stopCapture()
        }

        // Stop microphone capture
        audioEngine?.stop()

        // Finish writing
        systemAudioInput?.markAsFinished()
        micAudioInput?.markAsFinished()

        await withCheckedContinuation { continuation in
            assetWriter?.finishWriting {
                continuation.resume()
            }
        }

        await cleanupResources()

        let duration = currentDuration
        isRecording = false
        state = .idle

        // Update meeting record
        if var meeting = currentMeeting {
            meeting.endTime = Date()
            meeting.duration = duration
            meeting.status = autoTranscribe ? .pendingTranscription : .ready

            try await DatabaseManager.shared.update(meeting)
            currentMeeting = meeting

            print("[AudioCapture] Recording stopped. Duration: \(String(format: "%.1f", duration))s")
            print("[AudioCapture] Saved to: \(outputURL.path)")

            // Trigger transcription automatically
            if autoTranscribe {
                Task {
                    await transcribeMeeting(meeting)
                }
            }
        }

        currentDuration = 0

        return outputURL
    }

    /// Transcribe a meeting using OpenAI API
    /// - Parameter meeting: The meeting to transcribe
    func transcribeMeeting(_ meeting: Meeting) async {
        var updatedMeeting = meeting
        updatedMeeting.status = .transcribing
        let meetingId = meeting.id

        do {
            try await DatabaseManager.shared.update(updatedMeeting)
            currentMeeting = updatedMeeting
            transcriptionProgress = "Transcribing..."

            // Show transcribing state in the notch island
            TranscribingIslandController.shared.show(
                meetingTitle: meeting.title,
                meetingId: meetingId,
                onCancel: { [weak self] in
                    self?.cancelTranscription(meetingId: meetingId)
                }
            )

            // Perform transcription
            let result = try await TranscriptionService.shared.transcribe(audioPath: meeting.audioPath)

            // Update meeting with transcript
            updatedMeeting.transcript = result.text
            updatedMeeting.apiCostCents = result.costCents
            updatedMeeting.duration = result.duration
            updatedMeeting.status = .ready
            updatedMeeting.errorMessage = nil

            // Update with diarization results
            updatedMeeting.speakerCount = result.speakerCount
            updatedMeeting.diarizationSegments = result.diarizationSegments

            try await DatabaseManager.shared.update(updatedMeeting)
            currentMeeting = updatedMeeting
            transcriptionProgress = nil

            print("[AudioCapture] Transcription complete. Cost: \(result.costCents) cents")
            if let speakers = result.speakerCount, speakers > 0 {
                print("[AudioCapture] Detected \(speakers) speakers")
            }

            // Hide transcribing island
            TranscribingIslandController.shared.hide()

            // Show success notification with View action
            ToastController.shared.showSuccess(
                "Transcript ready",
                message: meeting.title,
                duration: 4.0,
                action: ToastAction(title: "View") {
                    MainAppWindowController.shared.showMeeting(id: meetingId)
                }
            )

            // Export to agent-accessible JSON
            Task {
                try? await AgentAPIManager.shared.exportMeeting(updatedMeeting)
            }

        } catch {
            print("[AudioCapture] Transcription failed: \(error)")

            updatedMeeting.status = .failed
            updatedMeeting.errorMessage = error.localizedDescription

            try? await DatabaseManager.shared.update(updatedMeeting)
            currentMeeting = updatedMeeting
            transcriptionProgress = nil
            errorMessage = error.localizedDescription

            // Hide transcribing island
            TranscribingIslandController.shared.hide()

            // Show error notification with Retry action
            ToastController.shared.showError(
                "Transcription failed",
                message: error.localizedDescription,
                action: ToastAction(title: "Retry") { [weak self] in
                    Task { @MainActor in
                        await self?.retryTranscription(meetingId: meetingId)
                    }
                }
            )
        }
    }

    /// Cancel an in-progress transcription
    func cancelTranscription(meetingId: UUID) {
        // For now, we just mark it as failed since we can't truly cancel the API call
        Task {
            guard var meeting = try? await DatabaseManager.shared.getMeeting(id: meetingId) else {
                return
            }
            meeting.status = .failed
            meeting.errorMessage = "Transcription cancelled"
            try? await DatabaseManager.shared.update(meeting)
            currentMeeting = meeting
            transcriptionProgress = nil

            ToastController.shared.showWarning(
                "Transcription cancelled",
                message: meeting.title
            )
        }
    }

    /// Retry transcription for a failed meeting
    func retryTranscription(meetingId: UUID) async {
        guard let meeting = try? await DatabaseManager.shared.getMeeting(id: meetingId) else {
            return
        }
        await transcribeMeeting(meeting)
    }

    /// Check if screen recording permission is available
    func checkPermission() async -> Bool {
        do {
            // Preflight first; in macOS 14+, content listing can succeed even without permission.
            if !CGPreflightScreenCaptureAccess() {
                _ = CGRequestScreenCaptureAccess()
            }
            _ = try await SCShareableContent.current
            return CGPreflightScreenCaptureAccess()
        } catch {
            return false
        }
    }

    // MARK: - Private Methods

    private func createOutputURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let recordingsFolder = documentsPath.appendingPathComponent("MeetingRecorder/recordings", isDirectory: true)

        try? FileManager.default.createDirectory(at: recordingsFolder, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())

        return recordingsFolder.appendingPathComponent("meeting_\(timestamp).wav")
    }

    private func setupAssetWriter(url: URL) throws {
        // Remove existing file if present
        try? FileManager.default.removeItem(at: url)

        // Use WAV format - simpler, no codec issues, OpenAI accepts it
        assetWriter = try AVAssetWriter(outputURL: url, fileType: .wav)

        // Linear PCM settings matching ScreenCaptureKit output (48kHz stereo)
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48000.0,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        // Single audio input (we'll mix system + mic)
        systemAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        systemAudioInput?.expectsMediaDataInRealTime = true

        if let input = systemAudioInput, assetWriter?.canAdd(input) == true {
            assetWriter?.add(input)
        }
    }

    private func startSystemAudioCapture() async throws {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw AudioCaptureError.noPermission
        }

        let content = try await SCShareableContent.current
        shareableContent = content

        // Use display capture with audio only
        guard let display = content.displays.first else {
            throw AudioCaptureError.noAudioSources
        }

        print("[AudioCapture] Found display: \(display.width)x\(display.height)")

        // Exclude the current app to avoid capturing its own audio.
        let excludedApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let displayFilter = SCContentFilter(display: display, excludingApplications: excludedApps, exceptingWindows: [])
        streamContentFilter = displayFilter

        // Configure stream for audio-only capture.
        // Note: On macOS 14, we must still capture video (minimum size) to get audio
        let config = SCStreamConfiguration()
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1) // 1 fps
        config.queueDepth = 5
        config.showsCursor = false
        config.capturesAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        config.excludesCurrentProcessAudio = true
        streamConfiguration = config

        // Create stream with delegate for error handling (keep strong reference)
        streamDelegate = StreamDelegate()
        self.stream = SCStream(filter: displayFilter, configuration: config, delegate: streamDelegate)

        guard self.stream != nil else {
            throw AudioCaptureError.streamFailed(NSError(domain: "AudioCapture", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create stream"]))
        }

        // Create and store output handler (must keep strong reference)
        self.streamOutput = SystemAudioOutputHandler { [weak self] sampleBuffer in
            Task { @MainActor in
                self?.handleSystemAudioBuffer(sampleBuffer)
            }
        }

        guard let output = self.streamOutput, let currentStream = self.stream else {
            throw AudioCaptureError.streamFailed(NSError(domain: "AudioCapture", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create output handler"]))
        }

        let outputQueue = DispatchQueue(label: "com.meetingrecorder.audio")
        streamOutputQueue = outputQueue
        try currentStream.addStreamOutput(output, type: .audio, sampleHandlerQueue: outputQueue)

        do {
            try await currentStream.startCapture()
            print("[AudioCapture] System audio capture started successfully")
        } catch {
            print("[AudioCapture] startCapture failed: \(error)")
            throw AudioCaptureError.streamFailed(error)
        }
    }

    private func startMicrophoneCapture() throws {
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { return }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Install tap for mic audio
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
            Task { @MainActor in
                self?.handleMicBuffer(buffer, time: time)
            }
        }

        try engine.start()
    }

    private func handleSystemAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording,
              let writer = assetWriter,
              let input = systemAudioInput else {
            return
        }

        // Start the session on the first valid sample
        if !sessionStarted {
            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if presentationTime.isValid {
                writer.startSession(atSourceTime: presentationTime)
                firstSampleTime = presentationTime
                sessionStarted = true
                print("[AudioCapture] Session started at time: \(presentationTime.seconds)")
            }
        }

        guard sessionStarted, input.isReadyForMoreMediaData else {
            return
        }

        // Append the sample buffer
        if !input.append(sampleBuffer) {
            print("[AudioCapture] Failed to append sample buffer, writer status: \(writer.status.rawValue)")
            if let error = writer.error {
                print("[AudioCapture] Writer error: \(error)")
            }
        }
    }

    private func handleMicBuffer(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        // For now, we're only writing system audio to keep the implementation simple
        // In a full implementation, we'd mix mic + system audio
        // The mic tap is here for validation and future mixing
    }

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            Task { @MainActor [weak self] in
                self?.updateDuration()
            }
        }
    }

    private func updateDuration() {
        guard let startTime = recordingStartTime else { return }
        currentDuration = Date().timeIntervalSince(startTime)
        state = .recording(duration: currentDuration)
    }

    private func cleanupResources() async {
        stream = nil
        streamOutput = nil
        streamDelegate = nil
        streamConfiguration = nil
        streamContentFilter = nil
        streamOutputQueue = nil
        shareableContent = nil
        audioEngine?.stop()
        audioEngine = nil
        assetWriter = nil
        systemAudioInput = nil
        micAudioInput = nil
        firstSampleTime = nil
        sessionStarted = false

        if let activity = backgroundActivity {
            ProcessInfo.processInfo.endActivity(activity)
            backgroundActivity = nil
        }
    }

    /// Get the bundle identifier for the source app
    private func getSourceAppBundleId() -> String? {
        guard let app = sourceApp?.lowercased() else { return nil }

        switch app {
        case "zoom":
            return "us.zoom.xos"
        case "google meet":
            return "com.google.Chrome"  // Usually in browser
        case "microsoft teams":
            return "com.microsoft.teams"
        case "slack":
            return "com.tinyspeck.slackmacgap"
        case "facetime":
            return "com.apple.FaceTime"
        default:
            return nil
        }
    }
}

// MARK: - Stream Output Handler

/// Handler for ScreenCaptureKit audio output
private class SystemAudioOutputHandler: NSObject, SCStreamOutput {
    private let handler: (CMSampleBuffer) -> Void

    init(handler: @escaping (CMSampleBuffer) -> Void) {
        self.handler = handler
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        handler(sampleBuffer)
    }
}

/// Delegate for stream error handling
private class StreamDelegate: NSObject, SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[StreamDelegate] Stream stopped with error: \(error)")
    }
}

// MARK: - Simplified Recording Manager (Alternative Implementation)

/// Simpler audio capture using just microphone (for testing)
@MainActor
class SimpleMicRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var currentDuration: TimeInterval = 0
    @Published var lastRecordingURL: URL?

    private var audioRecorder: AVAudioRecorder?
    private var durationTimer: Timer?
    private var recordingStartTime: Date?

    func startRecording() throws {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let recordingsFolder = documentsPath.appendingPathComponent("MeetingRecorder/recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: recordingsFolder, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let url = recordingsFolder.appendingPathComponent("mic_\(timestamp).m4a")

        // Use 44.1kHz which is more compatible with AAC encoder
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        audioRecorder = try AVAudioRecorder(url: url, settings: settings)
        guard audioRecorder?.prepareToRecord() == true else {
            throw NSError(domain: "SimpleMicRecorder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare recorder"])
        }
        audioRecorder?.record()

        lastRecordingURL = url
        isRecording = true
        recordingStartTime = Date()

        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard self != nil else {
                timer.invalidate()
                return
            }
            Task { @MainActor [weak self] in
                guard let self = self, let start = self.recordingStartTime else { return }
                self.currentDuration = Date().timeIntervalSince(start)
            }
        }

        print("[SimpleMicRecorder] Recording started: \(url.path)")
    }

    func stopRecording() -> URL? {
        durationTimer?.invalidate()
        durationTimer = nil
        audioRecorder?.stop()
        isRecording = false
        currentDuration = 0

        let url = lastRecordingURL
        print("[SimpleMicRecorder] Recording stopped: \(url?.path ?? "none")")
        return url
    }
}

// MARK: - Mic Recorder with Transcription

/// Microphone recorder that integrates with the transcription pipeline
@MainActor
class MicRecorderWithTranscription: ObservableObject {
    @Published var isRecording = false
    @Published var currentDuration: TimeInterval = 0
    @Published var lastRecordingURL: URL?
    @Published var status: String?
    @Published var errorMessage: String?
    @Published var currentMeeting: Meeting?

    private var audioRecorder: AVAudioRecorder?
    private var durationTimer: Timer?
    private var recordingStartTime: Date?

    func startRecording() async {
        do {
            // Initialize database
            try await DatabaseManager.shared.initialize()

            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let recordingsFolder = documentsPath.appendingPathComponent("MeetingRecorder/recordings", isDirectory: true)
            try FileManager.default.createDirectory(at: recordingsFolder, withIntermediateDirectories: true)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let timestamp = formatter.string(from: Date())
            // Use .wav format - always supported and OpenAI accepts it
            let url = recordingsFolder.appendingPathComponent("mic_\(timestamp).wav")

            // Linear PCM (WAV) - universally supported, no codec issues
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16000.0,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ]

            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            guard audioRecorder?.prepareToRecord() == true else {
                throw NSError(domain: "MicRecorder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare recorder"])
            }
            audioRecorder?.record()
            print("[MicRecorderWithTranscription] Recording to WAV: \(url.path)")

            lastRecordingURL = url
            isRecording = true
            recordingStartTime = Date()
            status = nil
            errorMessage = nil

            // Create meeting record
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "h:mm a"
            let meeting = Meeting(
                title: "Recording at \(timeFormatter.string(from: Date()))",
                startTime: Date(),
                sourceApp: "Microphone",
                audioPath: url.path,
                status: .recording
            )
            currentMeeting = meeting
            try await DatabaseManager.shared.insert(meeting)

            // Start duration timer
            durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
                guard self != nil else {
                    timer.invalidate()
                    return
                }
                Task { @MainActor [weak self] in
                    guard let self = self, let start = self.recordingStartTime else { return }
                    self.currentDuration = Date().timeIntervalSince(start)
                }
            }

            print("[MicRecorderWithTranscription] Recording started: \(url.path)")

        } catch {
            errorMessage = error.localizedDescription
            print("[MicRecorderWithTranscription] Start error: \(error)")
        }
    }

    func stopRecording() async {
        durationTimer?.invalidate()
        durationTimer = nil
        audioRecorder?.stop()
        isRecording = false

        let duration = currentDuration
        currentDuration = 0

        guard let url = lastRecordingURL, var meeting = currentMeeting else {
            return
        }

        // Update meeting record
        meeting.endTime = Date()
        meeting.duration = duration
        meeting.status = .pendingTranscription

        do {
            try await DatabaseManager.shared.update(meeting)
            currentMeeting = meeting

            print("[MicRecorderWithTranscription] Recording stopped. Duration: \(String(format: "%.1f", duration))s")

            // Start transcription
            await transcribeMeeting(meeting)

        } catch {
            errorMessage = error.localizedDescription
            print("[MicRecorderWithTranscription] Update error: \(error)")
        }
    }

    private func transcribeMeeting(_ meeting: Meeting) async {
        var updatedMeeting = meeting
        updatedMeeting.status = .transcribing
        status = "Transcribing..."
        let meetingId = meeting.id

        do {
            try await DatabaseManager.shared.update(updatedMeeting)
            currentMeeting = updatedMeeting

            // Check for API key
            guard KeychainHelper.readOpenAIKey() != nil else {
                status = nil
                errorMessage = "No OpenAI API key. Add in Settings."
                updatedMeeting.status = .failed
                updatedMeeting.errorMessage = "No API key configured"
                try? await DatabaseManager.shared.update(updatedMeeting)
                currentMeeting = updatedMeeting

                // Show error notification
                ToastController.shared.showError(
                    "No API key",
                    message: "Add your OpenAI API key in Settings",
                    action: ToastAction(title: "Settings") {
                        SettingsWindowController.shared.showWindow()
                    }
                )
                return
            }

            // Show transcribing state in the notch island (no cancel action for mic recorder)
            TranscribingIslandController.shared.show(
                meetingTitle: meeting.title,
                meetingId: meetingId
            )

            // Perform transcription
            let result = try await TranscriptionService.shared.transcribe(audioPath: meeting.audioPath)

            // Update meeting with transcript
            updatedMeeting.transcript = result.text
            updatedMeeting.apiCostCents = result.costCents
            updatedMeeting.duration = result.duration
            updatedMeeting.status = .ready
            updatedMeeting.errorMessage = nil

            try await DatabaseManager.shared.update(updatedMeeting)
            currentMeeting = updatedMeeting
            status = "Done! Cost: $\(String(format: "%.3f", Double(result.costCents) / 100))"

            print("[MicRecorderWithTranscription] Transcription complete. Cost: \(result.costCents) cents")

            // Hide transcribing island
            TranscribingIslandController.shared.hide()

            // Show success notification with View action
            ToastController.shared.showSuccess(
                "Transcript ready",
                message: meeting.title,
                duration: 4.0,
                action: ToastAction(title: "View") {
                    MainAppWindowController.shared.showMeeting(id: meetingId)
                }
            )

            // Export to agent-accessible JSON
            Task {
                try? await AgentAPIManager.shared.exportMeeting(updatedMeeting)
            }

            // Clear status after a delay
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            status = nil

        } catch {
            print("[MicRecorderWithTranscription] Transcription failed: \(error)")

            updatedMeeting.status = .failed
            updatedMeeting.errorMessage = error.localizedDescription

            try? await DatabaseManager.shared.update(updatedMeeting)
            currentMeeting = updatedMeeting
            status = nil
            errorMessage = error.localizedDescription

            // Hide transcribing island
            TranscribingIslandController.shared.hide()

            // Show error notification with Retry action
            ToastController.shared.showError(
                "Transcription failed",
                message: error.localizedDescription,
                action: ToastAction(title: "Retry") { [weak self] in
                    Task { @MainActor in
                        await self?.retryTranscription(meetingId: meetingId)
                    }
                }
            )
        }
    }

    /// Retry transcription for a failed meeting
    func retryTranscription(meetingId: UUID) async {
        guard let meeting = try? await DatabaseManager.shared.getMeeting(id: meetingId) else {
            return
        }
        await transcribeMeeting(meeting)
    }
}
