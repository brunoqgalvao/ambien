//
//  RecordingIsland.swift
//  MeetingRecorder
//
//  Recording indicator that wraps around the notch on supported Macs,
//  or shows a floating pill on non-notch displays.
//
//  Design principles:
//  - Single continuous shape that hugs the notch (not two separate blobs)
//  - Generous padding below notch for click safety
//  - Graceful fallback to centered pill on external monitors / older Macs
//

import SwiftUI
import AppKit
import Combine

// MARK: - Notch Detection & Geometry

struct NotchInfo {
    /// Reliably detect if current screen has a notch
    /// Checks both safeAreaInsets AND auxiliaryTopLeftArea to be safe
    static var hasNotch: Bool {
        guard let screen = NSScreen.main else { return false }

        // Must have safe area insets at top
        guard screen.safeAreaInsets.top > 0 else { return false }

        // Must also have auxiliary areas defined (rules out weird edge cases)
        guard let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea,
              leftArea.width > 0 && rightArea.width > 0 else {
            return false
        }

        // Sanity check: notch should be roughly 180-220px wide on current MacBooks
        let computedNotchWidth = screen.frame.width - leftArea.width - rightArea.width
        return computedNotchWidth > 150 && computedNotchWidth < 300
    }

    /// Notch width calculated from auxiliary areas
    static var notchWidth: CGFloat {
        guard let screen = NSScreen.main,
              let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea else {
            return 200
        }
        return screen.frame.width - leftArea.width - rightArea.width
    }

    /// Notch height from safeAreaInsets
    static var notchHeight: CGFloat {
        guard let screen = NSScreen.main else { return 38 }
        return max(screen.safeAreaInsets.top, 38)
    }

    /// Corner radius matching macOS notch aesthetic
    static var cornerRadius: CGFloat { 12 }

    /// Extra padding below the notch area for our UI
    static var bottomPadding: CGFloat { 8 }

    static var screenFrame: CGRect {
        NSScreen.main?.frame ?? .zero
    }
}

// MARK: - Recording Island Controller

class RecordingIslandController {
    static let shared = RecordingIslandController()

    private var window: NSPanel?
    private var audioManager: AudioCaptureManager?
    private var hoverState: IslandHoverState?
    private var recordingObserver: AnyCancellable?

    private init() {}

    @MainActor
    func show(audioManager: AudioCaptureManager) {
        self.audioManager = audioManager

        // Observe recording state - auto-hide when recording stops
        recordingObserver?.cancel()
        recordingObserver = audioManager.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecording in
                if !isRecording {
                    self?.hide()
                }
            }

        guard window == nil else {
            window?.orderFront(nil)
            return
        }

        let newHoverState = IslandHoverState()
        self.hoverState = newHoverState

        let hasNotch = NotchInfo.hasNotch

        let content = RecordingIslandView(
            audioManager: audioManager,
            hoverState: newHoverState,
            hasNotch: hasNotch
        ) { [weak self] in
            self?.hide()
        }

        let hostingView = NSHostingView(rootView: content)

        // Size depends on whether we have a notch
        let windowSize: NSSize
        if hasNotch {
            // Notch mode: notch width + content on each side + corner radius padding
            // Use expanded width (110) so window doesn't need to resize on hover
            let topCornerRadius: CGFloat = 6
            let contentWidth: CGFloat = 50 + 110  // left (50) + right expanded (110)
            let totalWidth = NotchInfo.notchWidth + contentWidth + (topCornerRadius * 2)
            let totalHeight = NotchInfo.notchHeight
            windowSize = NSSize(width: totalWidth, height: totalHeight)
        } else {
            // Pill mode: compact floating pill
            windowSize = NSSize(width: 180, height: 36)
        }

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = !hasNotch  // Shadow only for floating pill
        // statusBar level is high enough without blocking system UI
        panel.level = .statusBar + 1
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.hidesOnDeactivate = false

        hostingView.frame = NSRect(origin: .zero, size: windowSize)
        panel.contentView = hostingView

        positionWindow(panel, hasNotch: hasNotch)

        self.window = panel
        self.hoverState = newHoverState

        // Animate in
        panel.alphaValue = 0
        panel.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel = window else { return }

        recordingObserver?.cancel()
        recordingObserver = nil

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            self?.window = nil
            self?.audioManager = nil
            self?.hoverState?.isHovered = false
            self?.hoverState = nil
        })
    }

    private func positionWindow(_ panel: NSPanel, hasNotch: Bool) {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.frame
        let windowHeight = panel.frame.height

        if hasNotch {
            // Notch mode: position so the notch gap is centered on screen
            // Window layout: [left 50] [notch] [right 110] [padding]
            // We want the notch center to align with screen center
            let topCornerRadius: CGFloat = 6
            let leftContentWidth: CGFloat = 50 + topCornerRadius
            let notchCenter = screenFrame.midX
            let x = notchCenter - leftContentWidth - (NotchInfo.notchWidth / 2)
            let y = screenFrame.maxY - windowHeight
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            // Pill mode: centered horizontally, below menu bar
            let windowWidth = panel.frame.width
            let x = screenFrame.midX - windowWidth / 2
            let y = screenFrame.maxY - 60  // 60px from top (below menu bar)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
}

// MARK: - Hover State

class IslandHoverState: ObservableObject {
    @Published var isHovered = false
}

// MARK: - Recording Island View
// Unified view that handles both notch-wrapping and floating pill modes

struct RecordingIslandView: View {
    @ObservedObject var audioManager: AudioCaptureManager
    @ObservedObject var hoverState: IslandHoverState
    let hasNotch: Bool
    let onStop: () -> Void

    @State private var isHovering = false

    var body: some View {
        Group {
            if hasNotch {
                NotchWrapperView(
                    audioManager: audioManager,
                    isHovered: $isHovering,
                    onStop: onStop
                )
            } else {
                FloatingPillView(
                    audioManager: audioManager,
                    isHovered: $isHovering,
                    onStop: onStop
                )
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Notch Wrapper View
// DynamicNotchKit-style: a single shape that extends from the notch
// The notch is black, our shape is black, they merge visually

struct NotchWrapperView: View {
    @ObservedObject var audioManager: AudioCaptureManager
    @Binding var isHovered: Bool
    let onStop: () -> Void

    // Match DynamicNotchKit's corner radii
    private let topCornerRadius: CGFloat = 6
    private let bottomCornerRadius: CGFloat = 14

    // Sizing
    private let leftWidth: CGFloat = 50
    private let rightWidthCompact: CGFloat = 70
    private let rightWidthExpanded: CGFloat = 110

    private var rightWidth: CGFloat {
        isHovered ? rightWidthExpanded : rightWidthCompact
    }

    var body: some View {
        // Content + mask width animates together
        HStack(spacing: 0) {
            // Left: red recording dot
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .frame(width: leftWidth)

            // Center: notch spacer
            Spacer()
                .frame(width: NotchInfo.notchWidth)

            // Right: timer + stop button
            HStack(spacing: 8) {
                Text(formatDuration(audioManager.currentDuration))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))

                // Stop button appears on hover
                Button(action: stopRecording) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.red))
                }
                .buttonStyle(.plain)
                .opacity(isHovered ? 1 : 0)
                .scaleEffect(isHovered ? 1 : 0.5)
            }
            .frame(width: rightWidth, alignment: .leading)
        }
        .frame(height: NotchInfo.notchHeight)
        .padding(.horizontal, topCornerRadius)
        .background {
            Rectangle()
                .fill(Color.black)
                .padding(-50)
        }
        .mask {
            NotchShape(
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: bottomCornerRadius
            )
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)
    }

    private func stopRecording() {
        Task { @MainActor in
            defer { onStop() }
            do {
                _ = try await audioManager.stopRecording()
            } catch {
                print("[RecordingIsland] Stop error: \(error)")
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Notch Shape (DynamicNotchKit-style)
// A rounded rectangle with different top and bottom corner radii
// This shape IS the content area - not a wrapper around the notch

struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Start at top-left
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Top-left corner curve (curves inward)
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY + topCornerRadius),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY)
        )

        // Left edge down
        path.addLine(to: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY - bottomCornerRadius))

        // Bottom-left corner curve
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topCornerRadius + bottomCornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topCornerRadius, y: rect.maxY)
        )

        // Bottom edge
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius - bottomCornerRadius, y: rect.maxY))

        // Bottom-right corner curve
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY - bottomCornerRadius),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.maxY)
        )

        // Right edge up
        path.addLine(to: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY + topCornerRadius))

        // Top-right corner curve (curves inward)
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topCornerRadius, y: rect.minY)
        )

        // Top edge back to start
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))

        return path
    }
}

// MARK: - Floating Pill View (Non-notch fallback)
// Minimal: logo + timer, stop on hover

struct FloatingPillView: View {
    @ObservedObject var audioManager: AudioCaptureManager
    @Binding var isHovered: Bool
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Logo
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.9))

            // Timer
            Text(formatDuration(audioManager.currentDuration))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))

            if isHovered {
                Button(action: stopRecording) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.red))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(Color(white: 0.08))
        )
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    private func stopRecording() {
        Task { @MainActor in
            defer { onStop() }
            do {
                _ = try await audioManager.stopRecording()
            } catch {
                print("[RecordingIsland] Stop error: \(error)")
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Pulsing Loader (reusable across app)

struct PulsingLoader: View {
    let size: CGFloat
    var color: Color = .white

    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(color.opacity(0.8))
            .frame(width: size, height: size)
            .scaleEffect(isAnimating ? 1.0 : 0.6)
            .opacity(isAnimating ? 0.6 : 1.0)
            .animation(
                .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear { isAnimating = true }
    }
}

// MARK: - Live Waveform Icon (Amie-style animated bars)

struct LiveWaveformIcon: View {
    var color: Color = .red
    @State private var animating = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 3)
                    .scaleEffect(y: animating ? CGFloat.random(in: 0.4...1.0) : 0.5, anchor: .center)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.15).repeatForever(autoreverses: true)) {
                animating = true
            }
        }
    }
}

// MARK: - Recording Dot

struct RecordingDot: View {
    var size: CGFloat = 8
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.4))
                .frame(width: size, height: size)
                .scaleEffect(isPulsing ? 2.0 : 1.0)
                .opacity(isPulsing ? 0 : 0.5)

            Circle()
                .fill(Color.red)
                .frame(width: size, height: size)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.0).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}

// MARK: - Mini Waveform

struct MiniWaveform: View {
    @StateObject private var animator = MiniWaveformAnimator()

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.8))
                    .frame(width: 2, height: max(3, 12 * animator.levels[index]))
            }
        }
        .frame(height: 12, alignment: .center)
        .onAppear { animator.start() }
        .onDisappear { animator.stop() }
    }
}

class MiniWaveformAnimator: ObservableObject {
    @Published var levels: [CGFloat] = [0.5, 0.7, 0.4, 0.6]
    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.1)) {
                    self?.levels = (0..<4).map { _ in CGFloat.random(in: 0.3...1.0) }
                }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit { timer?.invalidate() }
}

// MARK: - Previews

#Preview("NotchShape") {
    NotchShape(topCornerRadius: 6, bottomCornerRadius: 14)
        .fill(Color.black)
        .frame(width: 300, height: 38)
        .padding(20)
        .background(Color.gray)
}

#Preview("Recording - Notch") {
    ZStack {
        Color(white: 0.2)

        VStack(spacing: 0) {
            // Simulated notch content
            HStack(spacing: 0) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(width: 50)

                Spacer().frame(width: 200) // notch

                HStack(spacing: 8) {
                    Text("01:23")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                }
                .frame(width: 80)
            }
            .frame(height: 38)
            .padding(.horizontal, 6)
            .background {
                Rectangle().fill(Color.black).padding(-50)
            }
            .mask {
                NotchShape(topCornerRadius: 6, bottomCornerRadius: 14)
            }

            Spacer()
        }
    }
    .frame(width: 450, height: 100)
}

#Preview("Recording - Pill (No Notch)") {
    ZStack {
        Color(white: 0.3)

        VStack {
            Spacer().frame(height: 30)

            HStack(spacing: 10) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.9))

                Text("01:23")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.black))

            Spacer()
        }
    }
    .frame(width: 250, height: 100)
}

// MARK: - Transcribing Island Controller
// Minimal: just a pulsing loader, no text

class TranscribingIslandController {
    static let shared = TranscribingIslandController()

    private var window: NSPanel?
    private var cancelAction: (() -> Void)?

    private init() {}

    @MainActor
    func show(meetingTitle: String, meetingId: UUID, onCancel: (() -> Void)? = nil) {
        self.cancelAction = onCancel

        guard window == nil else {
            window?.orderFront(nil)
            return
        }

        let hasNotch = NotchInfo.hasNotch

        let content = TranscribingIslandView(
            hasNotch: hasNotch,
            onCancel: { [weak self] in
                self?.cancel()
            }
        )

        let hostingView = NSHostingView(rootView: content)

        // Minimal size
        let windowSize: NSSize
        if hasNotch {
            let topCornerRadius: CGFloat = 6
            let totalWidth = NotchInfo.notchWidth + 80 + (topCornerRadius * 2)  // 40 each side
            let totalHeight = NotchInfo.notchHeight
            windowSize = NSSize(width: totalWidth, height: totalHeight)
        } else {
            windowSize = NSSize(width: 60, height: 36)
        }

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = !hasNotch
        panel.level = .statusBar + 1
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false

        hostingView.frame = NSRect(origin: .zero, size: windowSize)
        panel.contentView = hostingView

        positionWindow(panel, hasNotch: hasNotch)

        self.window = panel
        panel.alphaValue = 0
        panel.orderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel = window else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            self?.window = nil
            self?.cancelAction = nil
        })
    }

    private func cancel() {
        cancelAction?()
        hide()
    }

    private func positionWindow(_ panel: NSPanel, hasNotch: Bool) {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.frame
        let windowWidth = panel.frame.width
        let windowHeight = panel.frame.height

        if hasNotch {
            let x = screenFrame.midX - windowWidth / 2
            let y = screenFrame.maxY - windowHeight
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            let x = screenFrame.midX - windowWidth / 2
            let y = screenFrame.maxY - 60
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
}

// MARK: - Transcribing Island View

struct TranscribingIslandView: View {
    let hasNotch: Bool
    let onCancel: () -> Void

    var body: some View {
        if hasNotch {
            TranscribingNotchView(onCancel: onCancel)
        } else {
            TranscribingPillView(onCancel: onCancel)
        }
    }
}

// MARK: - Transcribing Notch View
// Just pulsing loader on left side

struct TranscribingNotchView: View {
    let onCancel: () -> Void

    private let topCornerRadius: CGFloat = 6
    private let bottomCornerRadius: CGFloat = 14

    var body: some View {
        HStack(spacing: 0) {
            // Left: pulsing loader
            PulsingLoader(size: 10, color: .white)
                .frame(width: 40)

            // Notch spacer
            Spacer()
                .frame(width: NotchInfo.notchWidth)

            // Right: empty
            Spacer()
                .frame(width: 40)
        }
        .frame(height: NotchInfo.notchHeight)
        .padding(.horizontal, topCornerRadius)
        .background {
            Rectangle()
                .fill(Color.black)
                .padding(-50)
        }
        .mask {
            NotchShape(
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: bottomCornerRadius
            )
        }
    }
}

// MARK: - Transcribing Pill View (Non-notch)
// Just pulsing loader

struct TranscribingPillView: View {
    let onCancel: () -> Void

    var body: some View {
        HStack {
            PulsingLoader(size: 10, color: .white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule().fill(Color(white: 0.08))
        )
    }
}

// MARK: - Transcribing Island Previews

#Preview("Transcribing - Notch") {
    ZStack {
        Color(white: 0.2)

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                PulsingLoader(size: 10, color: .white)
                    .frame(width: 40)
                Spacer().frame(width: 200)
                Spacer().frame(width: 40)
            }
            .frame(height: 38)
            .padding(.horizontal, 6)
            .background {
                Rectangle().fill(Color.black).padding(-50)
            }
            .mask {
                NotchShape(topCornerRadius: 6, bottomCornerRadius: 14)
            }

            Spacer()
        }
    }
    .frame(width: 350, height: 100)
}

#Preview("Transcribing - Pill (No Notch)") {
    ZStack {
        Color(white: 0.3)

        VStack {
            Spacer().frame(height: 30)

            HStack {
                PulsingLoader(size: 10, color: .white)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.black))

            Spacer()
        }
    }
    .frame(width: 150, height: 100)
}
