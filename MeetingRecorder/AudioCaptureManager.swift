//
//  AudioCaptureManager.swift
//  MeetingRecorder
//
//  Captures system audio via ScreenCaptureKit and microphone via AVAudioEngine
//  Saves to AAC .m4a file (compressed for OpenAI's 25MB limit)
//

import Foundation
import ScreenCaptureKit
import AVFoundation
import Combine
import CoreGraphics
import CoreAudio
import AudioToolbox

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

/// Silence warning states for auto-stop feature
enum SilenceWarning: Equatable {
    case approaching(secondsRemaining: Int)  // Warning at threshold (default 5 min)
    case imminent(secondsRemaining: Int)     // Countdown before auto-stop

    static func == (lhs: SilenceWarning, rhs: SilenceWarning) -> Bool {
        switch (lhs, rhs) {
        case let (.approaching(s1), .approaching(s2)):
            return s1 == s2
        case let (.imminent(s1), .imminent(s2)):
            return s1 == s2
        default:
            return false
        }
    }
}

/// Main audio capture manager - handles system audio + mic recording
@MainActor
class AudioCaptureManager: NSObject, ObservableObject {
    // MARK: - Shared Instance
    static let shared = AudioCaptureManager()

    // MARK: - Published Properties

    @Published var state: RecordingState = .idle
    @Published var isRecording: Bool = false
    @Published var currentDuration: TimeInterval = 0
    @Published var lastRecordingURL: URL?
    @Published var errorMessage: String?
    @Published var currentMeeting: Meeting?
    @Published var transcriptionProgress: String?
    @Published var silenceWarning: SilenceWarning?

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

    // Audio format settings - record at good quality, downscale for API if needed
    // 44.1kHz mono AAC at 96kbps = ~12KB/sec = ~0.7MB/min (good speech quality)
    // Downscaling to 16kHz/32kbps happens in TranscriptionService before API call
    private let targetSampleRate: Double = 44100
    private let targetChannels: UInt32 = 1
    private let targetBitRate: Int = 96000  // 96kbps for good quality recording

    // Audio mixing - we'll mix mic into system audio
    private var micMixer: AVAudioMixerNode?
    private var micConverter: AVAudioConverter?
    private var pendingMicSamples: [Float] = []
    private let micSamplesLock = NSLock()

    // Target format for mixing (matches system audio output)
    private var mixFormat: AVAudioFormat?

    // Track first sample timestamp for proper session timing
    private var firstSampleTime: CMTime?
    private var sessionStarted: Bool = false

    // Activity to prevent App Nap
    private var backgroundActivity: NSObjectProtocol?

    // Silence monitoring for auto-stop
    private var silenceStartTime: Date?
    private var silenceMonitorTimer: Timer?
    private var currentSilenceDuration: TimeInterval = 0
    private var silenceWarningDismissedForThisRecording: Bool = false
    private let silenceThresholdDb: Float = -40.0  // Below this is considered silence

    // Debug mode - saves separate mic and system audio files for analysis
    private var debugSavesSeparateAudio: Bool {
        UserDefaults.standard.bool(forKey: "debugSavesSeparateAudio")
    }
    private var debugMicWriter: AVAssetWriter?
    private var debugMicInput: AVAssetWriterInput?
    private var debugSystemWriter: AVAssetWriter?
    private var debugSystemInput: AVAssetWriterInput?
    private var debugMicSessionStarted: Bool = false
    private var debugSystemSessionStarted: Bool = false

    // Settings from UserDefaults
    private var autoStopOnSilence: Bool {
        let value = UserDefaults.standard.object(forKey: "autoStopOnSilence")
        return value as? Bool ?? true  // Default to true
    }
    private var silenceWarningThreshold: TimeInterval {
        let value = UserDefaults.standard.double(forKey: "silenceWarningThreshold")
        return value > 0 ? value : 300  // Default 5 minutes (300 seconds)
    }
    private var silenceAutoStopThreshold: TimeInterval {
        let value = UserDefaults.standard.double(forKey: "silenceAutoStopThreshold")
        return value > 0 ? value : 600  // Default 10 minutes (600 seconds)
    }

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

            // Reset silence tracking for new recording
            resetSilenceTracking()

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

            // Notify UI of new meeting
            NotificationCenter.default.post(name: .meetingsDidChange, object: nil)

            // Start duration timer
            startDurationTimer()

            logInfo("[AudioCapture] Recording started: \(outputURL.path)")

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

        // Finish debug writers if active
        if debugSavesSeparateAudio {
            await finishDebugWriters()
        }

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
            NotificationCenter.default.post(name: .meetingsDidChange, object: nil)

            logInfo("[AudioCapture] Recording stopped. Duration: \(String(format: "%.1f", duration))s")
            logInfo("[AudioCapture] Saved to: \(outputURL.path)")

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

    /// Check if current recording is short (< 1 minute) - useful for discard prompts
    var isShortRecording: Bool {
        return currentDuration < 60
    }

    /// Discard the current recording without saving/transcribing
    /// Deletes the audio file and removes the meeting from the database
    func discardRecording() async {
        guard isRecording, let outputURL = lastRecordingURL else {
            return
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

        // Cancel writing (don't finish cleanly since we're discarding)
        assetWriter?.cancelWriting()

        await cleanupResources()

        // Delete the audio file
        try? FileManager.default.removeItem(at: outputURL)

        // Delete from database
        if let meeting = currentMeeting {
            try? await DatabaseManager.shared.delete(meeting.id)
            NotificationCenter.default.post(name: .meetingsDidChange, object: nil)
            logInfo("[AudioCapture] Recording discarded: \(meeting.title)")
        }

        isRecording = false
        state = .idle
        currentDuration = 0
        currentMeeting = nil
        lastRecordingURL = nil
    }

    /// Transcribe a meeting using OpenAI API
    /// - Parameter meeting: The meeting to transcribe
    func transcribeMeeting(_ meeting: Meeting) async {
        var updatedMeeting = meeting
        updatedMeeting.status = .transcribing
        updatedMeeting.errorMessage = nil
        let meetingId = meeting.id

        do {
            try await DatabaseManager.shared.update(updatedMeeting)
            currentMeeting = updatedMeeting
            NotificationCenter.default.post(name: .meetingsDidChange, object: nil)
            transcriptionProgress = "Transcribing..."

            // Show transcribing state in the notch island
            TranscribingIslandController.shared.show(
                meetingTitle: meeting.title,
                meetingId: meetingId,
                onCancel: { [weak self] in
                    self?.cancelTranscription(meetingId: meetingId)
                }
            )

            // Perform transcription (pass meeting ID for voice embedding extraction)
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

            // Update with diarization results
            updatedMeeting.speakerCount = result.speakerCount
            updatedMeeting.diarizationSegments = result.diarizationSegments

            // Update with AI-inferred speaker names
            if let inferredLabels = result.inferredSpeakerLabels, !inferredLabels.isEmpty {
                updatedMeeting.speakerLabels = inferredLabels
                logInfo("[AudioCapture] AI identified speakers: \(inferredLabels.map { "\($0.speakerId)=\($0.name)" }.joined(separator: ", "))")
            }

            // Use title from transcription process (generated automatically)
            if let generatedTitle = result.title {
                updatedMeeting.title = generatedTitle
                logInfo("[AudioCapture] Auto-generated title: \(generatedTitle)")
            }

            try await DatabaseManager.shared.update(updatedMeeting)
            currentMeeting = updatedMeeting
            transcriptionProgress = nil

            logInfo("[AudioCapture] Transcription complete. Cost: \(result.costCents) cents")
            if let speakers = result.speakerCount, speakers > 0 {
                logInfo("[AudioCapture] Detected \(speakers) speakers")
            }

            // Hide transcribing island
            TranscribingIslandController.shared.hide()

            // Show success notification - clicking anywhere opens the meeting
            ToastController.shared.showSuccess(
                "Transcript ready",
                message: meeting.title,
                duration: 4.0,
                action: ToastAction(title: "View") {
                    MainAppWindowController.shared.showMeeting(id: meetingId)
                },
                onTap: {
                    MainAppWindowController.shared.showMeeting(id: meetingId)
                }
            )

            // Notify UI to refresh meeting list
            NotificationCenter.default.post(name: .meetingsDidChange, object: nil)

            // Export to agent-accessible JSON
            Task {
                try? await AgentAPIManager.shared.exportMeeting(updatedMeeting)
            }

        } catch {
            logError("[AudioCapture] Transcription failed: \(error)")

            // Get the best error message - prefer errorDescription for LocalizedError
            let errorMsg: String
            if let localizedError = error as? LocalizedError, let desc = localizedError.errorDescription {
                errorMsg = desc
            } else {
                errorMsg = error.localizedDescription
            }

            updatedMeeting.status = .failed
            updatedMeeting.errorMessage = errorMsg

            try? await DatabaseManager.shared.update(updatedMeeting)
            currentMeeting = updatedMeeting
            NotificationCenter.default.post(name: .meetingsDidChange, object: nil)
            transcriptionProgress = nil
            errorMessage = errorMsg

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
            NotificationCenter.default.post(name: .meetingsDidChange, object: nil)
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

        // Use .m4a (AAC) for smaller file sizes - fits more in OpenAI's 25MB limit
        return recordingsFolder.appendingPathComponent("meeting_\(timestamp).m4a")
    }

    private func setupAssetWriter(url: URL) throws {
        // Remove existing file if present
        try? FileManager.default.removeItem(at: url)

        // Use M4A (AAC) format - much smaller files, OpenAI accepts it
        // 16kHz mono at 32kbps = ~4KB/sec = ~104 min fits in 25MB
        assetWriter = try AVAssetWriter(outputURL: url, fileType: .m4a)

        // AAC output settings - optimized for speech transcription
        // Note: We still accept 48kHz stereo input from ScreenCaptureKit,
        // but the AAC encoder will downsample/downmix automatically
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: targetSampleRate,
            AVNumberOfChannelsKey: Int(targetChannels),
            AVEncoderBitRateKey: targetBitRate,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        // Single audio input (we'll mix system + mic)
        systemAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        systemAudioInput?.expectsMediaDataInRealTime = true

        if let input = systemAudioInput, assetWriter?.canAdd(input) == true {
            assetWriter?.add(input)
        }

        // Debug mode: set up separate files for mic and system audio
        if debugSavesSeparateAudio {
            try setupDebugWriters(baseURL: url)
        }
    }

    /// Set up separate writers for mic and system audio (debug mode)
    private func setupDebugWriters(baseURL: URL) throws {
        let baseName = baseURL.deletingPathExtension().lastPathComponent
        let folder = baseURL.deletingLastPathComponent()

        // Mic audio file
        let micURL = folder.appendingPathComponent("\(baseName)_MIC.m4a")
        try? FileManager.default.removeItem(at: micURL)
        debugMicWriter = try AVAssetWriter(outputURL: micURL, fileType: .m4a)

        // Mic settings - 48kHz mono to match what we capture
        let micSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 96000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        debugMicInput = AVAssetWriterInput(mediaType: .audio, outputSettings: micSettings)
        debugMicInput?.expectsMediaDataInRealTime = true
        if let input = debugMicInput, debugMicWriter?.canAdd(input) == true {
            debugMicWriter?.add(input)
        }

        // System audio file
        let sysURL = folder.appendingPathComponent("\(baseName)_SYSTEM.m4a")
        try? FileManager.default.removeItem(at: sysURL)
        debugSystemWriter = try AVAssetWriter(outputURL: sysURL, fileType: .m4a)

        // System settings - preserve original format (48kHz stereo)
        let sysSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000.0,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        debugSystemInput = AVAssetWriterInput(mediaType: .audio, outputSettings: sysSettings)
        debugSystemInput?.expectsMediaDataInRealTime = true
        if let input = debugSystemInput, debugSystemWriter?.canAdd(input) == true {
            debugSystemWriter?.add(input)
        }

        // Start writing
        debugMicWriter?.startWriting()
        debugSystemWriter?.startWriting()
        debugMicSessionStarted = false
        debugSystemSessionStarted = false

        logInfo("[AudioCapture] Debug mode: saving separate audio files")
        logInfo("[AudioCapture]   Mic: \(micURL.lastPathComponent)")
        logInfo("[AudioCapture]   System: \(sysURL.lastPathComponent)")
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

        logDebug("[AudioCapture] Found display: \(display.width)x\(display.height)")

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

        let outputQueue = DispatchQueue(label: "com.ambient.audio")
        streamOutputQueue = outputQueue
        try currentStream.addStreamOutput(output, type: .audio, sampleHandlerQueue: outputQueue)

        do {
            try await currentStream.startCapture()
            logInfo("[AudioCapture] System audio capture started successfully")
        } catch {
            logError("[AudioCapture] startCapture failed: \(error)")
            throw AudioCaptureError.streamFailed(error)
        }
    }

    private func startMicrophoneCapture() throws {
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { return }

        // Set specific microphone if one is selected in settings
        configureSelectedMicrophone(for: engine)

        let inputNode = engine.inputNode
        let outputFormat = inputNode.outputFormat(forBus: 0)

        logInfo("[AudioCapture] Mic format: \(outputFormat.sampleRate)Hz, \(outputFormat.channelCount)ch")

        // We do our own resampling in processMicBuffer (linear interpolation)
        // This avoids AVAudioConverter's stateful issues

        // Install tap using the node's native format
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: outputFormat) { [weak self] buffer, time in
            self?.processMicBuffer(buffer)
        }

        try engine.start()
        logInfo("[AudioCapture] Microphone capture started")
    }

    /// Debug counter for mic buffer logging
    private static var micBufferCount = 0

    /// Process mic buffer and queue samples for mixing
    /// Runs on audio thread - uses simple linear interpolation for resampling
    private func processMicBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isRecording else { return }

        guard let channelData = buffer.floatChannelData else { return }
        let inputFrames = Int(buffer.frameLength)
        guard inputFrames > 0 else { return }

        let inputRate = buffer.format.sampleRate
        let outputRate: Double = 48000  // Target rate to match ScreenCaptureKit

        // Log first few buffers for debugging
        Self.micBufferCount += 1
        if Self.micBufferCount <= 5 {
            logDebug("[AudioCapture] Mic buffer #\(Self.micBufferCount): \(inputFrames) frames @ \(inputRate)Hz")
        }

        // Extract mono samples from input (use first channel)
        // Keep it simple - just copy the samples
        var monoSamples = [Float](repeating: 0, count: inputFrames)
        for i in 0..<inputFrames {
            monoSamples[i] = channelData[0][i]
        }

        // For 48kHz input (which is common), skip resampling entirely
        // Only resample if sample rates actually differ significantly
        var outputSamples: [Float]
        if abs(inputRate - outputRate) < 100 {
            // No resampling needed - rates are close enough
            outputSamples = monoSamples
        } else {
            // Resample using linear interpolation
            let ratio = outputRate / inputRate
            let outputCount = Int(ceil(Double(inputFrames) * ratio))
            outputSamples = [Float](repeating: 0, count: outputCount)

            for i in 0..<outputCount {
                let srcPos = Double(i) / ratio
                let srcIdx = Int(srcPos)
                let frac = Float(srcPos - Double(srcIdx))

                if srcIdx + 1 < inputFrames {
                    outputSamples[i] = monoSamples[srcIdx] * (1.0 - frac) + monoSamples[srcIdx + 1] * frac
                } else if srcIdx < inputFrames {
                    outputSamples[i] = monoSamples[srcIdx]
                }
            }

            if Self.micBufferCount <= 5 {
                logDebug("[AudioCapture] Resampled \(inputFrames) → \(outputCount) samples")
            }
        }

        // Queue mono samples - we'll handle stereo conversion during mixing
        // This way we don't assume interleaved vs non-interleaved storage
        micSamplesLock.lock()
        pendingMicSamples.append(contentsOf: outputSamples)
        // Keep max ~1 second buffer (48000 mono samples)
        let maxSamples = 48000
        if pendingMicSamples.count > maxSamples {
            pendingMicSamples.removeFirst(pendingMicSamples.count - maxSamples)
        }
        micSamplesLock.unlock()

        // Debug mode: write raw mic audio to separate file
        if debugSavesSeparateAudio {
            writeDebugMicAudio(buffer)
        }
    }

    /// Write raw mic audio to debug file
    private func writeDebugMicAudio(_ buffer: AVAudioPCMBuffer) {
        guard let writer = debugMicWriter,
              let input = debugMicInput,
              writer.status == .writing,
              input.isReadyForMoreMediaData else {
            return
        }

        // Convert AVAudioPCMBuffer to CMSampleBuffer
        guard let sampleBuffer = createSampleBuffer(from: buffer) else {
            return
        }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if !debugMicSessionStarted && presentationTime.isValid {
            writer.startSession(atSourceTime: presentationTime)
            debugMicSessionStarted = true
        }

        guard debugMicSessionStarted else { return }

        input.append(sampleBuffer)
    }

    /// Convert AVAudioPCMBuffer to CMSampleBuffer
    private func createSampleBuffer(from pcmBuffer: AVAudioPCMBuffer) -> CMSampleBuffer? {
        let format = pcmBuffer.format
        let frameCount = pcmBuffer.frameLength

        var formatDescription: CMAudioFormatDescription?
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: format.streamDescription,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )

        guard status == noErr, let formatDesc = formatDescription else {
            return nil
        }

        // Create block buffer from audio data
        guard let channelData = pcmBuffer.floatChannelData else { return nil }

        let dataSize = Int(frameCount) * MemoryLayout<Float>.size
        var blockBuffer: CMBlockBuffer?

        // Create block buffer
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: dataSize,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: dataSize,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        guard blockStatus == kCMBlockBufferNoErr, let block = blockBuffer else {
            return nil
        }

        // Copy data
        CMBlockBufferReplaceDataBytes(
            with: channelData[0],
            blockBuffer: block,
            offsetIntoDestination: 0,
            dataLength: dataSize
        )

        // Create sample buffer
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: formatDesc,
            sampleCount: CMItemCount(frameCount),
            presentationTimeStamp: CMTime(value: 0, timescale: CMTimeScale(format.sampleRate)),
            packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        )

        guard sampleStatus == noErr else { return nil }
        return sampleBuffer
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
                logDebug("[AudioCapture] Session started at time: \(presentationTime.seconds)")
            }
        }

        guard sessionStarted, input.isReadyForMoreMediaData else {
            return
        }

        // Debug mode: write raw system audio to separate file BEFORE mixing
        if debugSavesSeparateAudio {
            writeDebugSystemAudio(sampleBuffer)
        }

        // Calculate audio power level for silence detection
        if autoStopOnSilence {
            let powerLevel = calculateAudioPowerLevel(sampleBuffer)
            handleSilenceDetection(powerLevel: powerLevel)
        }

        // Mix mic audio into system audio
        let mixedBuffer = mixMicIntoSystemAudio(sampleBuffer)

        // Append the (possibly mixed) sample buffer
        let bufferToWrite = mixedBuffer ?? sampleBuffer
        if !input.append(bufferToWrite) {
            logError("[AudioCapture] Failed to append sample buffer, writer status: \(writer.status.rawValue)")
            if let error = writer.error {
                logError("[AudioCapture] Writer error: \(error)")
            }
        }
    }

    /// Write raw system audio to debug file (before mixing)
    private func writeDebugSystemAudio(_ sampleBuffer: CMSampleBuffer) {
        guard let writer = debugSystemWriter,
              let input = debugSystemInput,
              writer.status == .writing else {
            return
        }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if !debugSystemSessionStarted && presentationTime.isValid {
            writer.startSession(atSourceTime: presentationTime)
            debugSystemSessionStarted = true
        }

        guard debugSystemSessionStarted, input.isReadyForMoreMediaData else {
            return
        }

        input.append(sampleBuffer)
    }

    /// Log format info once
    private static var hasLoggedFormat = false

    /// Mix pending mic samples into the system audio buffer
    private func mixMicIntoSystemAudio(_ systemBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        // Get format description to understand the audio layout
        guard let formatDesc = CMSampleBufferGetFormatDescription(systemBuffer) else {
            return nil
        }

        // Log format info once at start
        if !Self.hasLoggedFormat {
            Self.hasLoggedFormat = true
            if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee {
                logInfo("[AudioCapture] System audio format:")
                logInfo("  Sample rate: \(asbd.mSampleRate)")
                logInfo("  Channels: \(asbd.mChannelsPerFrame)")
                logInfo("  Bits per channel: \(asbd.mBitsPerChannel)")
                logInfo("  Bytes per frame: \(asbd.mBytesPerFrame)")
                logInfo("  Bytes per packet: \(asbd.mBytesPerPacket)")
                logInfo("  Frames per packet: \(asbd.mFramesPerPacket)")
                logInfo("  Format flags: \(asbd.mFormatFlags)")
                // kAudioFormatFlagIsFloat = 1, kAudioFormatFlagIsNonInterleaved = 32
                let isFloat = (asbd.mFormatFlags & 1) != 0
                let isNonInterleaved = (asbd.mFormatFlags & 32) != 0
                logInfo("  Is Float: \(isFloat), Is Non-Interleaved: \(isNonInterleaved)")
            }
        }

        // Get the audio buffer list from the system sample buffer
        guard let blockBuffer = CMSampleBufferGetDataBuffer(systemBuffer) else {
            return nil
        }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

        guard status == kCMBlockBufferNoErr, let data = dataPointer, length > 0 else {
            return nil
        }

        // Get format info
        guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee else {
            return nil
        }

        let isNonInterleaved = (asbd.mFormatFlags & 32) != 0
        let channels = Int(asbd.mChannelsPerFrame)
        let bytesPerSample = Int(asbd.mBitsPerChannel / 8)

        // Get mic samples to mix
        let frameCount: Int
        if isNonInterleaved {
            // Non-interleaved: each channel's data is separate
            // Total length / channels / bytes per sample = frames
            frameCount = length / channels / bytesPerSample
        } else {
            // Interleaved: samples alternate L,R,L,R
            frameCount = length / (channels * bytesPerSample)
        }

        // Get mic samples (stored as mono)
        micSamplesLock.lock()
        let samplesNeeded = frameCount  // One sample per frame (mono)
        let micSamples: [Float]
        if pendingMicSamples.count >= samplesNeeded {
            micSamples = Array(pendingMicSamples.prefix(samplesNeeded))
            pendingMicSamples.removeFirst(samplesNeeded)
        } else {
            // Pad with zeros if we don't have enough mic samples
            micSamples = pendingMicSamples + Array(repeating: 0.0, count: samplesNeeded - pendingMicSamples.count)
            pendingMicSamples.removeAll()
        }
        micSamplesLock.unlock()

        // Mix: add mic samples to system audio samples
        // Boost mic level significantly - most mics are quiet relative to system audio
        // User-configurable gain (default 10x) + soft limiting to prevent clipping
        let micBoostSetting = UserDefaults.standard.double(forKey: "micBoostLevel")
        let micLevel: Float = Float(micBoostSetting > 0 ? micBoostSetting : 10.0)
        let floatPointer = UnsafeMutableRawPointer(data).assumingMemoryBound(to: Float.self)

        // Soft limiter function - sounds better than hard clipping
        @inline(__always) func softLimit(_ x: Float) -> Float {
            // tanh provides smooth limiting, scale to get close to ±1.0
            return tanh(x)
        }

        if isNonInterleaved && channels == 2 {
            // Non-interleaved stereo: first half is L channel, second half is R channel
            // Buffer layout: [L0, L1, L2, ..., Ln, R0, R1, R2, ..., Rn]
            for i in 0..<frameCount {
                if i < micSamples.count {
                    let micSample = micSamples[i] * micLevel

                    // Left channel (first half of buffer)
                    let mixedL = floatPointer[i] + micSample
                    floatPointer[i] = softLimit(mixedL)

                    // Right channel (second half of buffer)
                    let mixedR = floatPointer[frameCount + i] + micSample
                    floatPointer[frameCount + i] = softLimit(mixedR)
                }
            }
        } else {
            // Interleaved: samples alternate L,R,L,R
            // Buffer layout: [L0, R0, L1, R1, L2, R2, ...]
            for i in 0..<frameCount {
                if i < micSamples.count {
                    let micSample = micSamples[i] * micLevel

                    // Left sample
                    let mixedL = floatPointer[i * 2] + micSample
                    floatPointer[i * 2] = softLimit(mixedL)

                    // Right sample
                    let mixedR = floatPointer[i * 2 + 1] + micSample
                    floatPointer[i * 2 + 1] = softLimit(mixedR)
                }
            }
        }

        // Return nil to indicate we modified the buffer in place
        return nil
    }

    /// Calculate RMS power level from audio sample buffer in dB
    /// Note: ScreenCaptureKit delivers Float32 stereo audio at 48kHz
    private func calculateAudioPowerLevel(_ sampleBuffer: CMSampleBuffer) -> Float {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return -100.0  // Very quiet if we can't read
        }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

        guard let data = dataPointer, length > 0 else {
            return -100.0
        }

        // ScreenCaptureKit delivers Float32 samples (4 bytes per sample)
        let bytesPerSample = 4
        let sampleCount = length / bytesPerSample
        guard sampleCount > 0 else { return -100.0 }

        let samples = UnsafeBufferPointer(
            start: UnsafeRawPointer(data).assumingMemoryBound(to: Float.self),
            count: sampleCount
        )

        // Calculate RMS - Float32 samples are already in -1.0 to 1.0 range
        var sumOfSquares: Float = 0.0
        for sample in samples {
            sumOfSquares += sample * sample
        }

        let rms = sqrt(sumOfSquares / Float(sampleCount))

        // Convert to dB
        let db = 20 * log10(max(rms, 0.00001))
        return db
    }

    /// Handle silence detection and update warning state
    private func handleSilenceDetection(powerLevel: Float) {
        let isSilent = powerLevel < silenceThresholdDb

        if isSilent {
            // Start tracking silence if not already
            if silenceStartTime == nil {
                silenceStartTime = Date()
            }
            currentSilenceDuration = Date().timeIntervalSince(silenceStartTime!)
        } else {
            // Audio detected - reset silence tracking and clear any warnings
            silenceStartTime = nil
            currentSilenceDuration = 0
            if silenceWarning != nil && !silenceWarningDismissedForThisRecording {
                silenceWarning = nil
            }
        }
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

        // Start silence monitor timer (checks every second)
        if autoStopOnSilence {
            startSilenceMonitorTimer()
        }
    }

    private func startSilenceMonitorTimer() {
        silenceMonitorTimer?.invalidate()
        silenceMonitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            Task { @MainActor [weak self] in
                self?.updateSilenceWarning()
            }
        }
    }

    private func updateSilenceWarning() {
        guard isRecording, autoStopOnSilence, !silenceWarningDismissedForThisRecording else { return }

        let warningThreshold = silenceWarningThreshold
        let autoStopThreshold = silenceAutoStopThreshold
        let imminentThreshold = autoStopThreshold - 60  // Start countdown 60s before auto-stop

        if currentSilenceDuration >= autoStopThreshold {
            // Auto-stop the recording
            logWarning("[AudioCapture] Auto-stopping due to \(Int(currentSilenceDuration))s of silence")
            Task { @MainActor in
                do {
                    _ = try await self.stopRecording()
                    ToastController.shared.showWarning(
                        "Recording stopped",
                        message: "No audio detected for \(Int(autoStopThreshold / 60)) minutes"
                    )
                } catch {
                    logError("[AudioCapture] Failed to auto-stop: \(error)")
                }
            }
        } else if currentSilenceDuration >= imminentThreshold {
            // Imminent warning with countdown
            let secondsRemaining = Int(autoStopThreshold - currentSilenceDuration)
            silenceWarning = .imminent(secondsRemaining: secondsRemaining)
        } else if currentSilenceDuration >= warningThreshold {
            // Approaching warning
            let secondsRemaining = Int(autoStopThreshold - currentSilenceDuration)
            silenceWarning = .approaching(secondsRemaining: secondsRemaining)
        } else {
            // Below threshold - clear warning if not dismissed
            if silenceWarning != nil {
                silenceWarning = nil
            }
        }
    }

    private func updateDuration() {
        guard let startTime = recordingStartTime else { return }
        currentDuration = Date().timeIntervalSince(startTime)
        state = .recording(duration: currentDuration)
    }

    /// Dismiss the silence warning and prevent it from showing again this recording session
    func dismissSilenceWarning() {
        silenceWarning = nil
        silenceWarningDismissedForThisRecording = true
        silenceStartTime = nil
        currentSilenceDuration = 0
        logDebug("[AudioCapture] Silence warning dismissed for this recording")
    }

    /// Reset silence tracking (called when recording starts)
    private func resetSilenceTracking() {
        silenceStartTime = nil
        currentSilenceDuration = 0
        silenceWarning = nil
        silenceWarningDismissedForThisRecording = false
        silenceMonitorTimer?.invalidate()
        silenceMonitorTimer = nil
    }

    /// Configure the selected microphone for the audio engine
    private func configureSelectedMicrophone(for engine: AVAudioEngine) {
        let selectedUID = UserDefaults.standard.string(forKey: "selectedMicrophoneUID") ?? ""

        guard !selectedUID.isEmpty else {
            logDebug("[AudioCapture] Using system default microphone")
            return
        }

        // Find the device ID for the selected UID
        guard let deviceID = getAudioDeviceID(forUID: selectedUID) else {
            logWarning("[AudioCapture] Selected microphone not found, using system default")
            return
        }

        // Set the audio unit's input device
        let inputNode = engine.inputNode
        let audioUnit = inputNode.audioUnit

        guard let au = audioUnit else {
            logWarning("[AudioCapture] Could not get audio unit, using system default")
            return
        }

        var deviceIDCopy = deviceID
        let status = AudioUnitSetProperty(
            au,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceIDCopy,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        if status == noErr {
            if let deviceName = getDeviceName(deviceID: deviceID) {
                logInfo("[AudioCapture] Using microphone: \(deviceName)")
            }
        } else {
            logWarning("[AudioCapture] Failed to set microphone (error \(status)), using system default")
        }
    }

    /// Get the AudioDeviceID for a given UID
    private func getAudioDeviceID(forUID uid: String) -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else { return nil }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )

        guard status == noErr else { return nil }

        for deviceID in deviceIDs {
            if let deviceUID = getDeviceUID(deviceID: deviceID), deviceUID == uid {
                return deviceID
            }
        }

        return nil
    }

    /// Get the UID of a device
    private func getDeviceUID(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var uid: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &uid)

        guard status == noErr, let deviceUID = uid else { return nil }
        return deviceUID as String
    }

    /// Get the name of a device
    private func getDeviceName(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &name)

        guard status == noErr, let deviceName = name else { return nil }
        return deviceName as String
    }

    /// Finish debug audio writers
    private func finishDebugWriters() async {
        debugMicInput?.markAsFinished()
        debugSystemInput?.markAsFinished()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let group = DispatchGroup()

            if let micWriter = debugMicWriter, micWriter.status == .writing {
                group.enter()
                micWriter.finishWriting {
                    group.leave()
                }
            }

            if let sysWriter = debugSystemWriter, sysWriter.status == .writing {
                group.enter()
                sysWriter.finishWriting {
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                continuation.resume()
            }
        }

        logInfo("[AudioCapture] Debug audio files saved")
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

        // Clean up debug writers
        debugMicWriter = nil
        debugMicInput = nil
        debugSystemWriter = nil
        debugSystemInput = nil
        debugMicSessionStarted = false
        debugSystemSessionStarted = false

        // Clean up mic mixing resources
        micMixer = nil
        micConverter = nil
        mixFormat = nil
        micSamplesLock.lock()
        pendingMicSamples.removeAll()
        micSamplesLock.unlock()

        // Clean up silence monitoring
        silenceMonitorTimer?.invalidate()
        silenceMonitorTimer = nil
        silenceStartTime = nil
        currentSilenceDuration = 0
        silenceWarning = nil

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
            // Use .m4a (AAC) format - much smaller files for OpenAI's 25MB limit
            let url = recordingsFolder.appendingPathComponent("mic_\(timestamp).m4a")

            // AAC settings optimized for speech transcription
            // 16kHz mono at 32kbps = ~4KB/sec = ~104 min fits in 25MB
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 16000.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 32000,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ]

            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            guard audioRecorder?.prepareToRecord() == true else {
                throw NSError(domain: "MicRecorder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare recorder"])
            }
            audioRecorder?.record()
            print("[MicRecorderWithTranscription] Recording to AAC: \(url.path)")

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

            // Notify UI of new meeting
            NotificationCenter.default.post(name: .meetingsDidChange, object: nil)

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
            NotificationCenter.default.post(name: .meetingsDidChange, object: nil)

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
        updatedMeeting.errorMessage = nil
        status = "Transcribing..."
        let meetingId = meeting.id

        do {
            try await DatabaseManager.shared.update(updatedMeeting)
            currentMeeting = updatedMeeting
            NotificationCenter.default.post(name: .meetingsDidChange, object: nil)

            // Check for API key
            guard KeychainHelper.readOpenAIKey() != nil else {
                status = nil
                errorMessage = "No OpenAI API key. Add in Settings."
                updatedMeeting.status = .failed
                updatedMeeting.errorMessage = "No API key configured"
                try? await DatabaseManager.shared.update(updatedMeeting)
                currentMeeting = updatedMeeting
                NotificationCenter.default.post(name: .meetingsDidChange, object: nil)

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

            // Perform transcription (pass meeting ID for voice embedding extraction)
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

            // Use title from transcription process (generated automatically)
            if let generatedTitle = result.title {
                updatedMeeting.title = generatedTitle
                print("[MicRecorderWithTranscription] Auto-generated title: \(generatedTitle)")
            }

            try await DatabaseManager.shared.update(updatedMeeting)
            currentMeeting = updatedMeeting
            status = "Done! Cost: $\(String(format: "%.3f", Double(result.costCents) / 100))"

            print("[MicRecorderWithTranscription] Transcription complete. Cost: \(result.costCents) cents")

            // Hide transcribing island
            TranscribingIslandController.shared.hide()

            // Show success notification - clicking anywhere opens the meeting
            ToastController.shared.showSuccess(
                "Transcript ready",
                message: meeting.title,
                duration: 4.0,
                action: ToastAction(title: "View") {
                    MainAppWindowController.shared.showMeeting(id: meetingId)
                },
                onTap: {
                    MainAppWindowController.shared.showMeeting(id: meetingId)
                }
            )

            // Notify UI to refresh meeting list
            NotificationCenter.default.post(name: .meetingsDidChange, object: nil)

            // Export to agent-accessible JSON
            Task {
                try? await AgentAPIManager.shared.exportMeeting(updatedMeeting)
            }

            // Clear status after a delay
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            status = nil

        } catch {
            logError("[MicRecorderWithTranscription] Transcription failed: \(error)")

            // Get the best error message - prefer errorDescription for LocalizedError
            let errorMsg: String
            if let localizedError = error as? LocalizedError, let desc = localizedError.errorDescription {
                errorMsg = desc
            } else {
                errorMsg = error.localizedDescription
            }

            updatedMeeting.status = .failed
            updatedMeeting.errorMessage = errorMsg

            try? await DatabaseManager.shared.update(updatedMeeting)
            currentMeeting = updatedMeeting
            NotificationCenter.default.post(name: .meetingsDidChange, object: nil)
            status = nil
            errorMessage = errorMsg

            // Hide transcribing island
            TranscribingIslandController.shared.hide()

            // Show error notification with Retry action
            ToastController.shared.showError(
                "Transcription failed",
                message: errorMsg,
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
