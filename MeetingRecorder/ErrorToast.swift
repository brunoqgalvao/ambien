//
//  ErrorToast.swift
//  MeetingRecorder
//
//  Floating toast notification that slides in from the left
//  Used for transcription errors and other app-wide notifications
//

import SwiftUI
import AppKit

// MARK: - Toast Types

enum ToastType {
    case error
    case warning
    case success
    case info

    var icon: String {
        switch self {
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .error: return .red
        case .warning: return .orange
        case .success: return .green
        case .info: return .blue
        }
    }
}

// MARK: - Toast Action

struct ToastAction {
    let title: String
    let action: () -> Void
}

// MARK: - Toast Model

struct ToastData: Identifiable, Equatable {
    let id = UUID()
    let type: ToastType
    let title: String
    let message: String?
    let duration: TimeInterval
    let action: ToastAction?

    static func == (lhs: ToastData, rhs: ToastData) -> Bool {
        lhs.id == rhs.id
    }

    static func error(_ title: String, message: String? = nil, duration: TimeInterval = 4.0, action: ToastAction? = nil) -> ToastData {
        ToastData(type: .error, title: title, message: message, duration: duration, action: action)
    }

    static func warning(_ title: String, message: String? = nil, duration: TimeInterval = 3.0, action: ToastAction? = nil) -> ToastData {
        ToastData(type: .warning, title: title, message: message, duration: duration, action: action)
    }

    static func success(_ title: String, message: String? = nil, duration: TimeInterval = 2.0, action: ToastAction? = nil) -> ToastData {
        ToastData(type: .success, title: title, message: message, duration: duration, action: action)
    }

    static func info(_ title: String, message: String? = nil, duration: TimeInterval = 3.0, action: ToastAction? = nil) -> ToastData {
        ToastData(type: .info, title: title, message: message, duration: duration, action: action)
    }
}

// MARK: - Toast Controller

@MainActor
class ToastController: ObservableObject {
    static let shared = ToastController()

    private var window: NSWindow?
    private var hostingView: NSHostingView<ToastView>?
    private var dismissTask: Task<Void, Never>?

    @Published private(set) var currentToast: ToastData?

    private init() {}

    func show(_ toast: ToastData) {
        // Cancel any existing dismiss task
        dismissTask?.cancel()

        currentToast = toast

        if window == nil {
            createWindow()
        }

        // Animate in
        animateIn()

        // Schedule auto-dismiss
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(toast.duration * 1_000_000_000))
            if !Task.isCancelled {
                dismiss()
            }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        animateOut()
    }

    private func createWindow() {
        let toastView = ToastView(
            toast: Binding(
                get: { self.currentToast },
                set: { _ in }
            ),
            onDismiss: { [weak self] in
                self?.dismiss()
            },
            onAction: { [weak self] in
                self?.currentToast?.action?.action()
                self?.dismiss()
            }
        )

        let hostingView = NSHostingView(rootView: toastView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 360, height: 72)
        self.hostingView = hostingView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 72),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false

        // Position off-screen to the left
        positionWindow(window, offscreen: true)

        self.window = window
        window.orderFront(nil)
    }

    private func positionWindow(_ window: NSWindow, offscreen: Bool) {
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame

        // Position at bottom-right corner
        let padding: CGFloat = 20
        let x = visibleFrame.maxX - window.frame.width - padding
        let y = offscreen ? visibleFrame.origin.y - window.frame.height : visibleFrame.origin.y + padding

        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func animateIn() {
        guard let window = window else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            positionWindow(window.animator(), offscreen: false)
            window.animator().alphaValue = 1
        }
    }

    private func animateOut() {
        guard let window = window else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            positionWindow(window.animator(), offscreen: true)
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.window?.orderOut(nil)
            self?.window = nil
            self?.hostingView = nil
            self?.currentToast = nil
        })
    }
}

// MARK: - Toast View

struct ToastView: View {
    @Binding var toast: ToastData?
    let onDismiss: () -> Void
    var onAction: (() -> Void)?

    var body: some View {
        if let toast = toast {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: toast.type.icon)
                    .font(.system(size: 20))
                    .foregroundColor(toast.type.iconColor)

                // Text content
                VStack(alignment: .leading, spacing: 2) {
                    Text(toast.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    if let message = toast.message {
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                // Action button (if present)
                if let action = toast.action {
                    Button(action: { onAction?() }) {
                        Text(action.title)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                // Dismiss button
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(6)
                .contentShape(Rectangle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(minWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
        }
    }
}

// MARK: - Convenience Extensions

extension ToastController {
    func showError(_ title: String, message: String? = nil, duration: TimeInterval = 4.0, action: ToastAction? = nil) {
        show(.error(title, message: message, duration: duration, action: action))
    }

    func showWarning(_ title: String, message: String? = nil, duration: TimeInterval = 3.0, action: ToastAction? = nil) {
        show(.warning(title, message: message, duration: duration, action: action))
    }

    func showSuccess(_ title: String, message: String? = nil, duration: TimeInterval = 2.0, action: ToastAction? = nil) {
        show(.success(title, message: message, duration: duration, action: action))
    }

    func showInfo(_ title: String, message: String? = nil, duration: TimeInterval = 3.0, action: ToastAction? = nil) {
        show(.info(title, message: message, duration: duration, action: action))
    }
}

// MARK: - Previews

#Preview("Error Toast") {
    ToastView(
        toast: .constant(.error("Transcription failed", message: "Invalid audio format")),
        onDismiss: {},
        onAction: nil
    )
    .padding(40)
    .background(Color.gray.opacity(0.3))
}

#Preview("Error Toast with Retry") {
    ToastView(
        toast: .constant(.error(
            "Transcription failed",
            message: "Network timeout",
            action: ToastAction(title: "Retry", action: {})
        )),
        onDismiss: {},
        onAction: {}
    )
    .padding(40)
    .background(Color.gray.opacity(0.3))
}

#Preview("Warning Toast") {
    ToastView(
        toast: .constant(.warning("You're offline", message: "Transcriptions will queue")),
        onDismiss: {},
        onAction: nil
    )
    .padding(40)
    .background(Color.gray.opacity(0.3))
}

#Preview("Success Toast") {
    ToastView(
        toast: .constant(.success("Copied to clipboard")),
        onDismiss: {},
        onAction: nil
    )
    .padding(40)
    .background(Color.gray.opacity(0.3))
}
