//
//  DictationManager.swift
//  MeetingRecorder
//
//  Core dictation logic - hold hotkey to record, release to transcribe, paste at cursor
//  Uses AVAudioEngine for mic capture (NOT system audio)
//

import Foundation
import AVFoundation
import AppKit
import Combine

/// State of the dictation system
enum DictationState: Equatable {
    case idle
    case listening
    case transcribing
    case done(String)
    case error(String)

    var displayText: String {
        switch self {
        case .idle: return "Ready"
        case .listening: return "Listening..."
        case .transcribing: return "Transcribing..."
        case .done(let text): return text.isEmpty ? "No speech detected" : "Done"
        case .error(let msg): return msg
        }
    }

    var icon: String {
        switch self {
        case .idle: return "mic"
        case .listening: return "waveform"
        case .transcribing: return "ellipsis.circle"
        case .done: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}

/// Manager for system-wide dictation
/// Hold hotkey → record mic → release → transcribe → paste at cursor
@MainActor
class DictationManager: ObservableObject {
    // MARK: - Published Properties

    @Published var state: DictationState = .idle
    @Published var isActive: Bool = false
    @Published var audioLevel: Float = 0.0
    @Published var errorMessage: String?
    @Published var lastTranscription: String?

    // MARK: - Audio Properties

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var tempAudioURL: URL?
    private var levelTimer: Timer?

    // Audio format for recording (16kHz mono - optimal for Whisper)
    private let targetSampleRate: Double = 16000
    private let targetChannels: AVAudioChannelCount = 1

    // MARK: - Window Controller

    private var overlayWindow: DictationOverlayWindow?

    // MARK: - Singleton

    static let shared = DictationManager()

    private init() {
        setupHotkeyCallbacks()
    }

    // MARK: - Setup

    private func setupHotkeyCallbacks() {
        HotkeyManager.shared.onKeyDown = { [weak self] in
            Task { @MainActor in
                self?.startDictation()
            }
        }

        HotkeyManager.shared.onKeyUp = { [weak self] in
            Task { @MainActor in
                await self?.stopDictation()
            }
        }
    }

    /// Initialize and register the hotkey
    func initialize() {
        do {
            try HotkeyManager.shared.register()
            print("[DictationManager] Initialized with hotkey: \(HotkeyManager.shared.currentHotkey)")
        } catch {
            errorMessage = error.localizedDescription
            print("[DictationManager] Failed to register hotkey: \(error)")
        }
    }

    // MARK: - Dictation Flow

    /// Start recording when hotkey is pressed
    func startDictation() {
        guard state == .idle else { return }

        // Check for API key first
        guard KeychainHelper.readOpenAIKey() != nil else {
            state = .error("No API key")
            showOverlay()
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    self.hideOverlay()
                    self.state = .idle
                }
            }
            return
        }

        state = .listening
        isActive = true
        showOverlay()

        do {
            try startMicrophoneCapture()
            startLevelMetering()
            print("[DictationManager] Started listening")
        } catch {
            state = .error(error.localizedDescription)
            errorMessage = error.localizedDescription
            print("[DictationManager] Failed to start: \(error)")
        }
    }

    /// Stop recording and transcribe when hotkey is released
    func stopDictation() async {
        guard state == .listening else { return }

        stopMicrophoneCapture()
        stopLevelMetering()

        state = .transcribing
        print("[DictationManager] Stopped listening, transcribing...")

        // Transcribe the audio
        guard let audioURL = tempAudioURL else {
            state = .error("No audio")
            await autoDismiss()
            return
        }

        do {
            // Use whisper-1 for lower latency in dictation
            let result = try await TranscriptionService.shared.transcribeDictation(audioPath: audioURL.path)

            if result.text.isEmpty {
                state = .done("")
                lastTranscription = nil
            } else {
                state = .done(result.text)
                lastTranscription = result.text

                // Paste at cursor
                pasteTextAtCursor(result.text)

                print("[DictationManager] Transcribed: \"\(result.text)\"")
                print("[DictationManager] Latency: \(String(format: "%.2f", result.latency))s")
            }
        } catch {
            state = .error("Transcription failed")
            errorMessage = error.localizedDescription
            print("[DictationManager] Transcription failed: \(error)")
        }

        // Clean up temp file
        cleanupTempFile()

        await autoDismiss()
    }

    /// Cancel dictation without transcribing
    func cancelDictation() {
        stopMicrophoneCapture()
        stopLevelMetering()
        cleanupTempFile()
        hideOverlay()
        state = .idle
        isActive = false
        print("[DictationManager] Cancelled")
    }

    // MARK: - Microphone Capture

    private func startMicrophoneCapture() throws {
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else {
            throw NSError(domain: "DictationManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio engine"])
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Create temp file for recording
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "dictation_\(UUID().uuidString.prefix(8)).wav"
        tempAudioURL = tempDir.appendingPathComponent(filename)

        guard let url = tempAudioURL else {
            throw NSError(domain: "DictationManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to create temp file"])
        }

        // Create output format (16kHz mono)
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: targetChannels,
            interleaved: true
        ) else {
            throw NSError(domain: "DictationManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio format"])
        }

        // Create audio file
        audioFile = try AVAudioFile(
            forWriting: url,
            settings: outputFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )

        // Create format converter if needed
        let converter = AVAudioConverter(from: inputFormat, to: outputFormat)

        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
            guard let self = self, let file = self.audioFile else { return }

            if let converter = converter {
                // Convert to target format
                let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * self.targetSampleRate / inputFormat.sampleRate)
                guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount) else { return }

                var error: NSError?
                let status = converter.convert(to: convertedBuffer, error: &error) { inNumPackets, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }

                if status == .haveData {
                    do {
                        try file.write(from: convertedBuffer)
                    } catch {
                        print("[DictationManager] Write error: \(error)")
                    }
                }
            }

            // Update audio level for waveform
            self.updateAudioLevel(buffer)
        }

        try engine.start()
    }

    private func stopMicrophoneCapture() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
        isActive = false
    }

    private func updateAudioLevel(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let channelDataValue = channelData.pointee
        let channelDataValueArray = stride(from: 0, to: Int(buffer.frameLength), by: buffer.stride).map { channelDataValue[$0] }

        let rms = sqrt(channelDataValueArray.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
        let avgPower = 20 * log10(max(rms, 0.000001))

        // Normalize to 0-1 range (assuming -60dB to 0dB range)
        let normalizedLevel = max(0, min(1, (avgPower + 60) / 60))

        Task { @MainActor in
            self.audioLevel = normalizedLevel
        }
    }

    // MARK: - Level Metering (for UI animation)

    private func startLevelMetering() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            // Audio level is updated in the tap callback
            // This timer is just to ensure smooth animation
        }
    }

    private func stopLevelMetering() {
        levelTimer?.invalidate()
        levelTimer = nil
        audioLevel = 0
    }

    // MARK: - Paste at Cursor

    /// Paste text at the current cursor position
    /// Uses clipboard + Cmd+V simulation (most reliable method)
    private func pasteTextAtCursor(_ text: String) {
        // Save current clipboard content
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)

        // Set new content
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V
        simulatePaste()

        // Restore original clipboard after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let old = oldContents {
                pasteboard.clearContents()
                pasteboard.setString(old, forType: .string)
            }
        }
    }

    /// Simulate Cmd+V keystroke
    private func simulatePaste() {
        // Create key down event for Cmd+V
        let source = CGEventSource(stateID: .hidSystemState)

        // Key code for 'V' is 9
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true) {
            keyDown.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
        }

        // Key up
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) {
            keyUp.flags = .maskCommand
            keyUp.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Overlay Window

    private func showOverlay() {
        if overlayWindow == nil {
            overlayWindow = DictationOverlayWindow(manager: self)
        }
        overlayWindow?.show()
    }

    private func hideOverlay() {
        overlayWindow?.hide()
    }

    private func autoDismiss() async {
        // Show "Done" state briefly
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        await MainActor.run {
            self.hideOverlay()
            self.state = .idle
        }
    }

    // MARK: - Cleanup

    private func cleanupTempFile() {
        if let url = tempAudioURL {
            try? FileManager.default.removeItem(at: url)
            tempAudioURL = nil
        }
    }

    deinit {
        // Note: unregister() is called on MainActor
        Task { @MainActor in
            HotkeyManager.shared.unregister()
        }
    }
}

// MARK: - Preview Helpers

extension DictationManager {
    static var preview: DictationManager {
        let manager = DictationManager()
        return manager
    }

    static var previewListening: DictationManager {
        let manager = DictationManager()
        manager.state = .listening
        manager.isActive = true
        manager.audioLevel = 0.5
        return manager
    }

    static var previewTranscribing: DictationManager {
        let manager = DictationManager()
        manager.state = .transcribing
        return manager
    }

    static var previewDone: DictationManager {
        let manager = DictationManager()
        manager.state = .done("Hello, this is a test transcription.")
        return manager
    }
}
