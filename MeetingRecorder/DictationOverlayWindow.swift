//
//  DictationOverlayWindow.swift
//  MeetingRecorder
//
//  Floating window controller for dictation indicator pill
//  NSPanel that floats above other windows, borderless, transparent
//  Stays on top during dictation, draggable
//

import AppKit
import SwiftUI

/// Window controller for the floating dictation indicator
class DictationOverlayWindow {
    // MARK: - Properties

    private var panel: NSPanel?
    private var hostingView: NSHostingView<DictationIndicatorView>?
    private let manager: DictationManager

    /// Current position (for docking)
    private var currentPosition: CGPoint?

    /// Default position (centered horizontally, ~100px from top)
    private var defaultPosition: CGPoint {
        guard let screen = NSScreen.main else {
            return CGPoint(x: 500, y: 100)
        }
        return CGPoint(
            x: screen.frame.width / 2 - 100,  // Centered (pill is ~200px wide)
            y: screen.frame.height - 100       // 100px from top (macOS uses bottom-left origin)
        )
    }

    // MARK: - Initialization

    init(manager: DictationManager) {
        self.manager = manager
        setupPanel()
    }

    // MARK: - Setup

    private func setupPanel() {
        // Create panel with transparent background
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 50),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Configure panel
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false  // We handle shadow in SwiftUI
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true

        // Create hosting view
        let indicatorView = DictationIndicatorView(manager: manager)
        let hostingView = NSHostingView(rootView: indicatorView)
        hostingView.frame = panel.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]

        panel.contentView = hostingView

        self.panel = panel
        self.hostingView = hostingView

        // Set initial position
        let position = currentPosition ?? defaultPosition
        panel.setFrameOrigin(position)
    }

    // MARK: - Public Methods

    /// Show the overlay window
    func show() {
        guard let panel = panel else { return }

        // Ensure we're on main thread
        DispatchQueue.main.async {
            // Position at saved location or default
            let position = self.currentPosition ?? self.defaultPosition
            panel.setFrameOrigin(position)

            // Show panel
            panel.orderFrontRegardless()
            panel.makeKeyAndOrderFront(nil)

            // Start tracking window position for docking
            self.startTrackingPosition()
        }
    }

    /// Hide the overlay window
    func hide() {
        guard let panel = panel else { return }

        DispatchQueue.main.async {
            // Save current position
            self.currentPosition = panel.frame.origin

            // Hide panel
            panel.orderOut(nil)

            // Stop tracking
            self.stopTrackingPosition()
        }
    }

    /// Move to center of screen
    func centerOnScreen() {
        guard let panel = panel else { return }

        let position = defaultPosition
        panel.setFrameOrigin(position)
        currentPosition = position
    }

    /// Dock to corner
    func dockTo(corner: DockCorner) {
        guard let panel = panel, let screen = NSScreen.main else { return }

        let margin: CGFloat = 20
        let frameSize = panel.frame.size

        var position: CGPoint

        switch corner {
        case .topLeft:
            position = CGPoint(
                x: margin,
                y: screen.frame.height - frameSize.height - margin
            )
        case .topRight:
            position = CGPoint(
                x: screen.frame.width - frameSize.width - margin,
                y: screen.frame.height - frameSize.height - margin
            )
        case .bottomLeft:
            position = CGPoint(x: margin, y: margin)
        case .bottomRight:
            position = CGPoint(
                x: screen.frame.width - frameSize.width - margin,
                y: margin
            )
        case .center:
            position = defaultPosition
        }

        // Animate to position
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrameOrigin(position)
        }

        currentPosition = position
    }

    // MARK: - Docking Detection

    enum DockCorner {
        case topLeft, topRight, bottomLeft, bottomRight, center
    }

    private var positionObserver: Any?

    private func startTrackingPosition() {
        // Observe window movement for snap-to-edge behavior
        positionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.checkForDocking()
        }
    }

    private func stopTrackingPosition() {
        if let observer = positionObserver {
            NotificationCenter.default.removeObserver(observer)
            positionObserver = nil
        }
    }

    private func checkForDocking() {
        guard let panel = panel, let screen = NSScreen.main else { return }

        let position = panel.frame.origin
        let frameSize = panel.frame.size
        let snapDistance: CGFloat = 30

        // Check if near edges
        let nearLeft = position.x < snapDistance
        let nearRight = position.x > screen.frame.width - frameSize.width - snapDistance
        let nearTop = position.y > screen.frame.height - frameSize.height - snapDistance
        let nearBottom = position.y < snapDistance

        // Determine dock corner
        if nearLeft && nearTop {
            dockTo(corner: .topLeft)
        } else if nearRight && nearTop {
            dockTo(corner: .topRight)
        } else if nearLeft && nearBottom {
            dockTo(corner: .bottomLeft)
        } else if nearRight && nearBottom {
            dockTo(corner: .bottomRight)
        }
    }

    // MARK: - Cleanup

    deinit {
        stopTrackingPosition()
        panel?.close()
    }
}

// MARK: - SwiftUI Bridge

/// A view modifier to present the dictation overlay
struct DictationOverlayModifier: ViewModifier {
    @ObservedObject var manager: DictationManager

    func body(content: Content) -> some View {
        content
            .onAppear {
                // Overlay is managed by DictationManager directly
            }
    }
}

extension View {
    func withDictationOverlay(manager: DictationManager) -> some View {
        self.modifier(DictationOverlayModifier(manager: manager))
    }
}
