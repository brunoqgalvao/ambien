//
//  DictationIndicatorView.swift
//  MeetingRecorder
//
//  Floating pill UI for dictation state
//  Three states: Listening (with waveform), Transcribing, Done
//  Dockable/movable, semi-transparent, auto-dismiss
//

import SwiftUI

/// Animated waveform view for listening state
struct WaveformView: View {
    let level: Float
    let barCount: Int = 5

    @State private var animationPhases: [Double] = []

    init(level: Float) {
        self.level = level
        _animationPhases = State(initialValue: (0..<5).map { _ in Double.random(in: 0...1) })
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                WaveformBar(
                    level: level,
                    phase: animationPhases[index]
                )
            }
        }
        .onAppear {
            // Start animation
            withAnimation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true)) {
                animationPhases = (0..<barCount).map { _ in Double.random(in: 0...1) }
            }
        }
    }
}

struct WaveformBar: View {
    let level: Float
    let phase: Double

    var body: some View {
        let baseHeight: CGFloat = 4
        let maxHeight: CGFloat = 16
        let animatedLevel = CGFloat(level) * phase

        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.white)
            .frame(width: 3, height: baseHeight + (maxHeight - baseHeight) * animatedLevel)
            .animation(.easeInOut(duration: 0.15), value: level)
    }
}

/// Main dictation indicator pill
struct DictationIndicatorView: View {
    @ObservedObject var manager: DictationManager

    var body: some View {
        HStack(spacing: 10) {
            // State indicator
            stateIcon
                .frame(width: 20, height: 20)

            // Waveform (only in listening state)
            if case .listening = manager.state {
                WaveformView(level: manager.audioLevel)
                    .frame(width: 30, height: 20)
            }

            // Status text
            Text(manager.state.displayText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(backgroundGradient)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 4)
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch manager.state {
        case .idle:
            Image(systemName: "mic")
                .foregroundColor(.white)

        case .listening:
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.5), lineWidth: 2)
                        .scaleEffect(1.3)
                        .opacity(0.8)
                )

        case .transcribing:
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(0.8)

        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)

        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
        }
    }

    private var backgroundGradient: some ShapeStyle {
        switch manager.state {
        case .idle:
            return AnyShapeStyle(Color.gray.opacity(0.9))
        case .listening:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.red.opacity(0.9), Color.red.opacity(0.7)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        case .transcribing:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.blue.opacity(0.9), Color.blue.opacity(0.7)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        case .done:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.green.opacity(0.9), Color.green.opacity(0.7)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        case .error:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [Color.orange.opacity(0.9), Color.orange.opacity(0.7)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
    }
}

/// Compact indicator for docked state
struct DictationIndicatorCompactView: View {
    @ObservedObject var manager: DictationManager

    var body: some View {
        HStack(spacing: 6) {
            // Pulsing dot when listening
            if case .listening = manager.state {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.5), lineWidth: 1)
                            .scaleEffect(1.5)
                    )

                // Mini waveform
                HStack(spacing: 1) {
                    ForEach(0..<3, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white)
                            .frame(width: 2, height: CGFloat(4 + Int(manager.audioLevel * 8)))
                    }
                }
            } else {
                Image(systemName: manager.state.icon)
                    .font(.system(size: 10))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.7))
        .clipShape(Capsule())
    }
}

// MARK: - Preview

#Preview("Idle") {
    DictationIndicatorView(manager: DictationManager.preview)
        .padding()
        .background(Color.gray.opacity(0.3))
}

#Preview("Listening") {
    DictationIndicatorView(manager: DictationManager.previewListening)
        .padding()
        .background(Color.gray.opacity(0.3))
}

#Preview("Transcribing") {
    DictationIndicatorView(manager: DictationManager.previewTranscribing)
        .padding()
        .background(Color.gray.opacity(0.3))
}

#Preview("Done") {
    DictationIndicatorView(manager: DictationManager.previewDone)
        .padding()
        .background(Color.gray.opacity(0.3))
}

#Preview("All States") {
    VStack(spacing: 20) {
        DictationIndicatorView(manager: DictationManager.preview)
        DictationIndicatorView(manager: DictationManager.previewListening)
        DictationIndicatorView(manager: DictationManager.previewTranscribing)
        DictationIndicatorView(manager: DictationManager.previewDone)
    }
    .padding(40)
    .background(Color.gray.opacity(0.3))
}
