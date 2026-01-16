//
//  QuickDictationPill.swift
//  MeetingRecorder
//
//  Persistent floating pill at bottom center of screen
//  Press fn → record, release → transcribe → copy to clipboard
//  Minimal design: just shows "fn" hint when idle, waveform when recording
//

import SwiftUI
import AppKit
import AVFoundation

// MARK: - Quick Recording Pill Window Controller

@MainActor
class QuickRecordingPillController {
    static let shared = QuickRecordingPillController()

    private var window: NSWindow?
    private var hostingView: NSHostingView<QuickRecordingPillView>?
    private var manager: QuickRecordingManager?

    /// User preference: show pill when idle
    @AppStorage("showQuickPillWhenIdle") var showWhenIdle: Bool = true

    /// Track if we're force-showing due to recording/transcribing
    private var isForceShowing: Bool = false

    private init() {}

    func show(manager: QuickRecordingManager, force: Bool = false) {
        print("[QuickPill] show() called, force: \(force), showWhenIdle: \(showWhenIdle)")
        self.manager = manager
        self.isForceShowing = force

        // If not forced and user prefers hidden, don't show
        if !force && !showWhenIdle {
            print("[QuickPill] Hidden by user preference")
            return
        }

        guard window == nil else {
            print("[QuickPill] Window already exists, bringing to front")
            window?.orderFront(nil)
            return
        }

        let pillView = QuickRecordingPillView(manager: manager, onRightClick: { [weak self] in
            self?.showContextMenu()
        })
        let hostingView = NSHostingView(rootView: pillView)
        // Larger frame to accommodate hint pill above when in continuous mode
        hostingView.frame = NSRect(x: 0, y: 0, width: 200, height: 80)
        self.hostingView = hostingView

        // Create borderless floating window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 80),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .statusBar  // Above most windows but below alerts
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true  // Allow dragging
        window.ignoresMouseEvents = false

        // Position at bottom center of screen
        positionWindow(window)

        self.window = window
        window.orderFront(nil)
        print("[QuickPill] Window created and ordered front")

        // Fade in
        window.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }
    }

    /// Force show (for recording/transcribing states)
    func forceShow() {
        guard let manager = manager else { return }
        if window == nil {
            show(manager: manager, force: true)
        }
    }

    /// Hide only if not force-showing
    func hideIfAllowed() {
        if !isForceShowing {
            hide()
        }
    }

    /// Toggle visibility preference
    @MainActor
    func toggleVisibility() {
        showWhenIdle.toggle()
        if showWhenIdle {
            if let manager = manager {
                show(manager: manager)
            }
        } else {
            // Only hide if idle
            if manager?.state == .idle {
                hide()
            }
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let hideItem = NSMenuItem(
            title: showWhenIdle ? "Hide when idle" : "Show when idle",
            action: #selector(toggleVisibilityAction),
            keyEquivalent: ""
        )
        hideItem.target = self
        menu.addItem(hideItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        // Show menu at mouse location
        if let window = window {
            let mouseLocation = NSEvent.mouseLocation
            let windowLocation = window.convertPoint(fromScreen: mouseLocation)
            menu.popUp(positioning: nil, at: windowLocation, in: window.contentView)
        }
    }

    @objc private func toggleVisibilityAction() {
        Task { @MainActor in
            toggleVisibility()
        }
    }

    @objc private func openSettings() {
        Task { @MainActor in
            SettingsWindowController.shared.showWindow()
        }
    }

    func hide() {
        guard let window = window else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
            self.window = nil
            self.hostingView = nil
        })
    }

    private func positionWindow(_ window: NSWindow) {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame  // Excludes dock and menu bar

        // Position centered horizontally, 80px from bottom of visible area (above dock)
        let x = visibleFrame.midX - window.frame.width / 2
        let y = visibleFrame.origin.y + 80
        window.setFrameOrigin(NSPoint(x: x, y: y))

        print("[QuickPill] Positioned at x:\(x), y:\(y)")
    }

}

// MARK: - Quick Recording State

enum QuickRecordingState: Equatable {
    case idle
    case recording
    case continuousRecording  // Double-click mode - keeps recording until Escape
    case transcribing
    case done(String)
    case error(String)

    static func == (lhs: QuickRecordingState, rhs: QuickRecordingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.recording, .recording), (.continuousRecording, .continuousRecording), (.transcribing, .transcribing):
            return true
        case (.done(let a), .done(let b)):
            return a == b
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }

    /// Whether the state is any kind of recording
    var isRecording: Bool {
        switch self {
        case .recording, .continuousRecording:
            return true
        default:
            return false
        }
    }
}

// MARK: - Quick Recording Manager

@MainActor
class QuickRecordingManager: ObservableObject {
    static let shared = QuickRecordingManager()

    @Published var state: QuickRecordingState = .idle
    @Published var audioLevel: Float = 0.0
    @Published var duration: TimeInterval = 0.0

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var tempAudioURL: URL?
    private var durationTimer: Timer?

    // Audio format (16kHz mono - optimal for Whisper)
    private let targetSampleRate: Double = 16000
    private let targetChannels: AVAudioChannelCount = 1

    private init() {
        setupFnKeyCallbacks()
    }

    private func setupFnKeyCallbacks() {
        HotkeyManager.shared.onFnKeyDown = { [weak self] in
            Task { @MainActor in
                self?.startRecording()
            }
        }

        HotkeyManager.shared.onFnKeyUp = { [weak self] in
            Task { @MainActor in
                // Don't stop if in continuous mode
                guard let self = self, self.state == .recording else { return }
                await self.stopRecording()
            }
        }

        HotkeyManager.shared.onFnDoubleClick = { [weak self] in
            Task { @MainActor in
                self?.startContinuousRecording()
            }
        }

        HotkeyManager.shared.onEscapePressed = { [weak self] in
            Task { @MainActor in
                // Only respond if in continuous recording mode
                guard let self = self, self.state == .continuousRecording else { return }
                await self.stopRecording()
            }
        }
    }

    func initialize() {
        // Ensure hotkey manager is registered
        if !HotkeyManager.shared.isRegistered {
            try? HotkeyManager.shared.register()
        }
        print("[QuickRecording] Initialized with fn key trigger")
    }

    func startRecording() {
        guard state == .idle else { return }
        startRecordingInternal(continuous: false)
    }

    func startContinuousRecording() {
        // If already recording normally, switch to continuous
        if state == .recording {
            state = .continuousRecording
            print("[QuickRecording] Switched to continuous mode")
            return
        }

        guard state == .idle else { return }
        startRecordingInternal(continuous: true)
    }

    private func startRecordingInternal(continuous: Bool) {
        // Check API key
        guard KeychainHelper.readOpenAIKey() != nil else {
            state = .error("No API key")
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run { self.state = .idle }
            }
            return
        }

        state = continuous ? .continuousRecording : .recording
        duration = 0

        // Force show pill when recording
        QuickRecordingPillController.shared.forceShow()

        // Start duration timer
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor [weak self] in
                self?.duration += 0.1
            }
        }

        do {
            try startMicrophoneCapture()
            print("[QuickRecording] Started \(continuous ? "(continuous)" : "(hold)")")
        } catch {
            state = .error("Mic error")
            print("[QuickRecording] Start failed: \(error)")
        }
    }

    func stopRecording() async {
        guard state.isRecording else { return }

        durationTimer?.invalidate()
        durationTimer = nil
        stopMicrophoneCapture()

        state = .transcribing

        // Force show pill when transcribing
        QuickRecordingPillController.shared.forceShow()

        // Transcribe
        guard let audioURL = tempAudioURL else {
            state = .error("No audio")
            await autoReset()
            return
        }

        do {
            let result = try await TranscriptionService.shared.transcribeDictation(audioPath: audioURL.path)

            if result.text.isEmpty {
                state = .done("")
                print("[QuickRecording] No speech detected")
            } else {
                // Check if AI cleanup is enabled
                let aiCleanupEnabled = UserDefaults.standard.bool(forKey: "aiCleanupEnabled")

                var finalText = result.text
                if aiCleanupEnabled {
                    print("[QuickRecording] AI cleanup enabled, processing...")
                    do {
                        let cleanupResult = try await PostProcessingService.shared.cleanupDictation(result.text)
                        finalText = cleanupResult.content
                        print("[QuickRecording] AI cleanup done, cost: \(cleanupResult.costCents)¢")
                    } catch {
                        // If cleanup fails, fall back to raw transcription
                        print("[QuickRecording] AI cleanup failed, using raw: \(error)")
                    }
                }

                state = .done(finalText)

                // Auto-paste at cursor
                pasteTextAtCursor(finalText)

                // Save dictation to storage
                saveDictation(text: finalText, duration: duration)

                print("[QuickRecording] Done & pasted: \"\(finalText)\"")
            }
        } catch {
            state = .error("Failed")
            print("[QuickRecording] Transcription failed: \(error)")

            // Extract user-friendly error message
            let errorMessage: String
            if let transcriptionError = error as? TranscriptionError {
                errorMessage = transcriptionError.errorDescription ?? "Unknown error"
            } else {
                errorMessage = error.localizedDescription
            }

            // Wait 2 seconds showing X, then close pill and show toast
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            state = .idle

            // Hide pill
            if !QuickRecordingPillController.shared.showWhenIdle {
                QuickRecordingPillController.shared.hide()
            }

            // Show error toast with retry button
            ToastController.shared.showError(
                "Transcription failed",
                message: errorMessage,
                action: ToastAction(title: "Retry", action: { [weak self] in
                    Task { @MainActor in
                        self?.startRecording()
                    }
                })
            )

            cleanupTempFile()
            return
        }

        cleanupTempFile()
        await autoReset()
    }

    func cancelRecording() {
        durationTimer?.invalidate()
        durationTimer = nil
        stopMicrophoneCapture()
        cleanupTempFile()
        state = .idle
        print("[QuickRecording] Cancelled")
    }

    // MARK: - Microphone Capture

    private func startMicrophoneCapture() throws {
        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else {
            throw NSError(domain: "QuickRecording", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create audio engine"])
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Create temp file - use .m4a (AAC) which OpenAI definitely accepts
        // Write at native mic sample rate to avoid conversion issues
        let tempDir = FileManager.default.temporaryDirectory
        let filename = "quick_\(UUID().uuidString.prefix(8)).m4a"
        tempAudioURL = tempDir.appendingPathComponent(filename)

        guard let url = tempAudioURL else {
            throw NSError(domain: "QuickRecording", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to create temp file"])
        }

        // AAC settings - use native mic sample rate to avoid conversion issues
        // OpenAI accepts various sample rates (8kHz-48kHz)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: inputFormat.sampleRate,  // Use native rate
            AVNumberOfChannelsKey: 1,  // Mono is fine
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 64000
        ]

        audioFile = try AVAudioFile(
            forWriting: url,
            settings: outputSettings
        )

        // If mic is stereo, convert to mono; if sample rate differs, we'll need conversion
        let fileFormat = audioFile!.processingFormat

        // Check if we need to convert
        let needsConversion = inputFormat.sampleRate != fileFormat.sampleRate ||
                              inputFormat.channelCount != fileFormat.channelCount

        var converter: AVAudioConverter?
        if needsConversion {
            converter = AVAudioConverter(from: inputFormat, to: fileFormat)
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self, let file = self.audioFile else { return }

            do {
                if let converter = converter {
                    // Convert buffer to file format
                    let frameCapacity = AVAudioFrameCount(
                        Double(buffer.frameLength) * fileFormat.sampleRate / inputFormat.sampleRate
                    )
                    guard let convertedBuffer = AVAudioPCMBuffer(
                        pcmFormat: fileFormat,
                        frameCapacity: frameCapacity
                    ) else { return }

                    var error: NSError?
                    converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                        outStatus.pointee = .haveData
                        return buffer
                    }
                    if error == nil {
                        try file.write(from: convertedBuffer)
                    }
                } else {
                    // Direct write - formats match
                    try file.write(from: buffer)
                }
            } catch {
                print("[QuickRecording] Write error: \(error)")
            }

            self.updateAudioLevel(buffer)
        }

        try engine.start()
    }

    private func stopMicrophoneCapture() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioFile = nil
    }

    private func updateAudioLevel(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let channelDataValue = channelData.pointee
        let channelDataValueArray = stride(from: 0, to: Int(buffer.frameLength), by: buffer.stride).map { channelDataValue[$0] }

        let rms = sqrt(channelDataValueArray.map { $0 * $0 }.reduce(0, +) / Float(buffer.frameLength))
        let avgPower = 20 * log10(max(rms, 0.000001))
        let normalizedLevel = max(0, min(1, (avgPower + 60) / 60))

        Task { @MainActor in
            self.audioLevel = normalizedLevel
        }
    }

    // MARK: - Helpers

    /// Save dictation to QuickRecordingStorage
    private func saveDictation(text: String, duration: TimeInterval) {
        let recording = QuickRecording(
            text: text,
            createdAt: Date(),
            durationSeconds: duration,
            copiedToClipboard: true
        )

        QuickRecordingStorage.shared.save(recording)
        print("[QuickRecording] Dictation saved: \(text.prefix(30))...")
    }

    /// Paste text at the current cursor position
    private func pasteTextAtCursor(_ text: String) {
        // Save current clipboard
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)

        // Set new content
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V
        simulatePaste()

        // Restore original clipboard after short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let old = oldContents {
                pasteboard.clearContents()
                pasteboard.setString(old, forType: .string)
            }
        }
    }

    /// Simulate Cmd+V keystroke
    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)

        // Key code for 'V' is 9
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true) {
            keyDown.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
        }

        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) {
            keyUp.flags = .maskCommand
            keyUp.post(tap: .cghidEventTap)
        }
    }

    private func cleanupTempFile() {
        if let url = tempAudioURL {
            try? FileManager.default.removeItem(at: url)
            tempAudioURL = nil
        }
    }

    private func autoReset() async {
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        state = .idle

        // Hide pill if user prefers it hidden when idle
        if !QuickRecordingPillController.shared.showWhenIdle {
            QuickRecordingPillController.shared.hide()
        }
    }
}

// MARK: - Quick Recording Pill View

struct QuickRecordingPillView: View {
    @ObservedObject var manager: QuickRecordingManager
    var onRightClick: (() -> Void)?

    // Sleek pill dimensions
    private let pillHeight: CGFloat = 28
    private let idleWidth: CGFloat = 56
    private let recordingWidth: CGFloat = 72
    private let transcribingWidth: CGFloat = 64

    private var pillWidth: CGFloat {
        switch manager.state {
        case .idle: return idleWidth
        case .recording, .continuousRecording: return recordingWidth
        case .transcribing, .done, .error: return transcribingWidth
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            // Hint pill for continuous recording
            if manager.state == .continuousRecording {
                ContinuousRecordingHintPill()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Main pill
            HStack(spacing: 6) {
                switch manager.state {
                case .idle:
                    idleContent
                case .recording, .continuousRecording:
                    recordingContent
                case .transcribing:
                    transcribingContent
                case .done:
                    doneContent
                case .error:
                    errorContent
                }
            }
            .frame(width: pillWidth, height: pillHeight)
            .background(
                Capsule()
                    .fill(backgroundColor)
                    .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 2)
            )
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: manager.state)
        .overlay(
            RightClickOverlay(onRightClick: onRightClick)
        )
    }

    // MARK: - State Contents

    private var idleContent: some View {
        HStack(spacing: 4) {
            // Custom waveform icon
            MiniWaveformIcon()
                .frame(width: 16, height: 12)

            // fn hint
            Text("fn")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
        }
    }

    private var recordingContent: some View {
        HStack(spacing: 6) {
            // Pulsing red dot
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .modifier(PulseDotModifier())

            // Live waveform
            LiveWaveform(level: manager.audioLevel)
                .frame(width: 28, height: 14)
        }
    }

    private var transcribingContent: some View {
        HStack(spacing: 4) {
            ProgressView()
                .scaleEffect(0.5)
                .tint(.white.opacity(0.8))

            Text("...")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    private var doneContent: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.green)
    }

    private var errorContent: some View {
        Image(systemName: "xmark")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.orange)
    }

    // MARK: - Background Color

    private var backgroundColor: Color {
        switch manager.state {
        case .idle:
            return Color(white: 0.1).opacity(0.95)
        case .recording, .continuousRecording:
            return Color(red: 0.15, green: 0.05, blue: 0.05).opacity(0.95)
        case .transcribing:
            return Color(white: 0.1).opacity(0.95)
        case .done:
            return Color(white: 0.1).opacity(0.95)
        case .error:
            return Color(white: 0.1).opacity(0.95)
        }
    }
}

// MARK: - Continuous Recording Hint Pill

struct ContinuousRecordingHintPill: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("Press")
                .foregroundColor(.white.opacity(0.7))

            Text("esc")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.15))
                )

            Text("to finish")
                .foregroundColor(.white.opacity(0.7))
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(white: 0.1).opacity(0.95))
                .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 2)
        )
    }
}

// MARK: - Mini Waveform Icon (Static)

struct MiniWaveformIcon: View {
    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.6))
                    .frame(width: 2, height: barHeight(for: i))
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        // Create a wave pattern: short-medium-tall-medium-short
        let heights: [CGFloat] = [4, 7, 10, 7, 4]
        return heights[index]
    }
}

// MARK: - Live Waveform (Animated)

struct LiveWaveform: View {
    let level: Float

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<6, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.red.opacity(0.9))
                    .frame(width: 2.5, height: barHeight(for: i))
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let baseHeight: CGFloat = 3
        let maxHeight: CGFloat = 12
        // Vary each bar slightly for organic look
        let variation = CGFloat(abs(sin(Double(index) * 1.5))) * 0.4 + 0.6
        return baseHeight + (maxHeight - baseHeight) * CGFloat(level) * variation
    }
}

// MARK: - Pulse Dot Modifier

struct PulseDotModifier: ViewModifier {
    @State private var opacity: Double = 1.0

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    opacity = 0.4
                }
            }
    }
}

// MARK: - Right Click Overlay

struct RightClickOverlay: NSViewRepresentable {
    var onRightClick: (() -> Void)?

    func makeNSView(context: Context) -> RightClickView {
        let view = RightClickView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: RightClickView, context: Context) {
        nsView.onRightClick = onRightClick
    }
}

class RightClickView: NSView {
    var onRightClick: (() -> Void)?

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }

    override func mouseDown(with event: NSEvent) {
        // Don't consume - let it pass through
    }
}

// MARK: - Previews

#Preview("Sleek Pill - All States") {
    VStack(spacing: 16) {
        // Idle
        HStack(spacing: 4) {
            MiniWaveformIcon()
                .frame(width: 16, height: 12)
            Text("fn")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(width: 56, height: 28)
        .background(Capsule().fill(Color(white: 0.1).opacity(0.95)))

        // Recording (hold)
        HStack(spacing: 6) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
            LiveWaveform(level: 0.6)
                .frame(width: 28, height: 14)
        }
        .frame(width: 72, height: 28)
        .background(Capsule().fill(Color(red: 0.15, green: 0.05, blue: 0.05).opacity(0.95)))

        // Continuous Recording (double-click) - with hint pill
        VStack(spacing: 8) {
            ContinuousRecordingHintPill()

            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                LiveWaveform(level: 0.6)
                    .frame(width: 28, height: 14)
            }
            .frame(width: 72, height: 28)
            .background(Capsule().fill(Color(red: 0.15, green: 0.05, blue: 0.05).opacity(0.95)))
        }

        // Transcribing
        HStack(spacing: 4) {
            ProgressView()
                .scaleEffect(0.5)
                .tint(.white.opacity(0.8))
            Text("...")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(width: 64, height: 28)
        .background(Capsule().fill(Color(white: 0.1).opacity(0.95)))

        // Done
        Image(systemName: "checkmark")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.green)
            .frame(width: 64, height: 28)
            .background(Capsule().fill(Color(white: 0.1).opacity(0.95)))

        // Error
        Image(systemName: "xmark")
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.orange)
            .frame(width: 64, height: 28)
            .background(Capsule().fill(Color(white: 0.1).opacity(0.95)))
    }
    .padding(30)
    .background(Color.gray.opacity(0.4))
}
