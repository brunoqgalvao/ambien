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
        case .error: return .brandCoral
        case .warning: return .brandAmber
        case .success: return .brandMint
        case .info: return .brandViolet
        }
    }

    var accentColor: Color {
        switch self {
        case .error: return .brandCoral
        case .warning: return .brandAmber
        case .success: return .brandMint
        case .info: return .brandViolet
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
    /// Called when the toast body is tapped (not just the action button)
    let onTap: (() -> Void)?

    static func == (lhs: ToastData, rhs: ToastData) -> Bool {
        lhs.id == rhs.id
    }

    static func error(_ title: String, message: String? = nil, duration: TimeInterval = 4.0, action: ToastAction? = nil, onTap: (() -> Void)? = nil) -> ToastData {
        ToastData(type: .error, title: title, message: message, duration: duration, action: action, onTap: onTap)
    }

    static func warning(_ title: String, message: String? = nil, duration: TimeInterval = 3.0, action: ToastAction? = nil, onTap: (() -> Void)? = nil) -> ToastData {
        ToastData(type: .warning, title: title, message: message, duration: duration, action: action, onTap: onTap)
    }

    static func success(_ title: String, message: String? = nil, duration: TimeInterval = 2.0, action: ToastAction? = nil, onTap: (() -> Void)? = nil) -> ToastData {
        ToastData(type: .success, title: title, message: message, duration: duration, action: action, onTap: onTap)
    }

    static func info(_ title: String, message: String? = nil, duration: TimeInterval = 3.0, action: ToastAction? = nil, onTap: (() -> Void)? = nil) -> ToastData {
        ToastData(type: .info, title: title, message: message, duration: duration, action: action, onTap: onTap)
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
            },
            onTap: { [weak self] in
                self?.currentToast?.onTap?()
                self?.dismiss()
            }
        )

        let hostingView = NSHostingView(rootView: toastView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 80)
        self.hostingView = hostingView

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 80),
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
    var onTap: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        if let toast = toast {
            HStack(spacing: 14) {
                // Accent bar on left edge
                RoundedRectangle(cornerRadius: 2)
                    .fill(toast.type.accentColor)
                    .frame(width: 4)
                    .padding(.vertical, 4)

                // Icon in colored circle
                ZStack {
                    Circle()
                        .fill(toast.type.iconColor.opacity(0.12))
                        .frame(width: 36, height: 36)

                    Image(systemName: toast.type.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(toast.type.iconColor)
                }

                // Text content
                VStack(alignment: .leading, spacing: 3) {
                    Text(toast.title)
                        .font(.brandDisplay(14, weight: .semibold))
                        .foregroundColor(.brandTextPrimary)

                    if let message = toast.message {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundColor(.brandTextSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                // Action button (on-brand style)
                if let action = toast.action {
                    Button(action: { onAction?() }) {
                        Text(action.title)
                            .font(.brandDisplay(12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: BrandRadius.small)
                                    .fill(toast.type.accentColor)
                            )
                    }
                    .buttonStyle(.plain)
                }

                // Dismiss button
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.brandTextSecondary)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(Color.brandInk.opacity(isHovered ? 0.08 : 0.04))
                        )
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
            }
            .padding(.leading, 4)
            .padding(.trailing, 16)
            .padding(.vertical, 14)
            .frame(minWidth: 340)
            .background(
                RoundedRectangle(cornerRadius: BrandRadius.medium)
                    .fill(Color.brandSurface)
                    .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 8)
                    .shadow(color: toast.type.accentColor.opacity(0.15), radius: 24, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BrandRadius.medium)
                    .stroke(
                        isHovered && toast.onTap != nil
                            ? toast.type.accentColor.opacity(0.4)
                            : Color.brandBorder,
                        lineWidth: isHovered && toast.onTap != nil ? 1.5 : 1
                    )
            )
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) {
                    isHovered = hovering
                }
                if toast.onTap != nil {
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
            .onTapGesture {
                onTap?()
            }
        }
    }
}

// MARK: - Convenience Extensions

extension ToastController {
    func showError(_ title: String, message: String? = nil, duration: TimeInterval = 4.0, action: ToastAction? = nil, onTap: (() -> Void)? = nil) {
        show(.error(title, message: message, duration: duration, action: action, onTap: onTap))
    }

    func showWarning(_ title: String, message: String? = nil, duration: TimeInterval = 3.0, action: ToastAction? = nil, onTap: (() -> Void)? = nil) {
        show(.warning(title, message: message, duration: duration, action: action, onTap: onTap))
    }

    func showSuccess(_ title: String, message: String? = nil, duration: TimeInterval = 2.0, action: ToastAction? = nil, onTap: (() -> Void)? = nil) {
        show(.success(title, message: message, duration: duration, action: action, onTap: onTap))
    }

    func showInfo(_ title: String, message: String? = nil, duration: TimeInterval = 3.0, action: ToastAction? = nil, onTap: (() -> Void)? = nil) {
        show(.info(title, message: message, duration: duration, action: action, onTap: onTap))
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
    .background(Color.brandCreamDark)
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
    .background(Color.brandCreamDark)
}

#Preview("Warning Toast") {
    ToastView(
        toast: .constant(.warning("You're offline", message: "Transcriptions will queue")),
        onDismiss: {},
        onAction: nil
    )
    .padding(40)
    .background(Color.brandCreamDark)
}

#Preview("Success Toast") {
    ToastView(
        toast: .constant(.success("Transcript ready", message: "Team Standup Meeting")),
        onDismiss: {},
        onAction: nil,
        onTap: {}
    )
    .padding(40)
    .background(Color.brandCreamDark)
}

#Preview("Success Toast with Action") {
    ToastView(
        toast: .constant(.success(
            "Transcript ready",
            message: "Weekly Planning Session",
            action: ToastAction(title: "View", action: {})
        )),
        onDismiss: {},
        onAction: {},
        onTap: {}
    )
    .padding(40)
    .background(Color.brandCreamDark)
}

#Preview("Info Toast") {
    ToastView(
        toast: .constant(.info("Recording started", message: "Capturing mic + system audio")),
        onDismiss: {},
        onAction: nil
    )
    .padding(40)
    .background(Color.brandCreamDark)
}

#Preview("All Toast Types") {
    VStack(spacing: 16) {
        ToastView(toast: .constant(.success("Transcript ready", message: "Meeting notes")), onDismiss: {})
        ToastView(toast: .constant(.info("Processing...", message: "Transcribing audio")), onDismiss: {})
        ToastView(toast: .constant(.warning("Low storage", message: "5GB remaining")), onDismiss: {})
        ToastView(toast: .constant(.error("Upload failed", message: "Check connection")), onDismiss: {})
    }
    .padding(40)
    .background(Color.brandCreamDark)
}
