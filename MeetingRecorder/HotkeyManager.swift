//
//  HotkeyManager.swift
//  MeetingRecorder
//
//  Global hotkey registration for system-wide dictation
//  Default: Ctrl+Cmd+D (avoids conflicts with system shortcuts)
//

import Foundation
import Carbon
import AppKit

/// Errors that can occur during hotkey registration
enum HotkeyError: LocalizedError {
    case failedToCreateEventTap
    case failedToRunLoop
    case accessibilityNotGranted

    var errorDescription: String? {
        switch self {
        case .failedToCreateEventTap:
            return "Failed to create event tap. Check Accessibility permissions."
        case .failedToRunLoop:
            return "Failed to add event tap to run loop."
        case .accessibilityNotGranted:
            return "Accessibility permission required for global hotkeys."
        }
    }
}

/// Key event type for hotkey callbacks
enum HotkeyEvent {
    case keyDown
    case keyUp
}

/// Key code for the fn key
let kVK_Function: CGKeyCode = 63

/// Manager for global hotkey registration
/// Uses CGEvent tap to capture key events even when app is not focused
@MainActor
class HotkeyManager: ObservableObject {
    // MARK: - Published Properties

    @Published var isRegistered: Bool = false
    @Published var currentHotkey: String = "^⌘D"
    @Published var errorMessage: String?

    // MARK: - Configuration

    /// Hotkey modifiers (default: Ctrl+Cmd)
    var hotkeyModifiers: CGEventFlags = [.maskControl, .maskCommand]

    /// Hotkey key code (default: D = 2)
    var hotkeyKeyCode: CGKeyCode = 2  // 'D' key

    // MARK: - Callbacks

    /// Called when hotkey is pressed down
    var onKeyDown: (() -> Void)?

    /// Called when hotkey is released
    var onKeyUp: (() -> Void)?

    /// Called when fn key is pressed down (for quick recording)
    var onFnKeyDown: (() -> Void)?

    /// Called when fn key is released (for quick recording)
    var onFnKeyUp: (() -> Void)?

    /// Called when fn key is double-clicked (for continuous recording)
    var onFnDoubleClick: (() -> Void)?

    /// Called when Escape key is pressed (to cancel continuous recording)
    var onEscapePressed: (() -> Void)?

    // MARK: - Private Properties

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isKeyCurrentlyDown: Bool = false
    private var isFnKeyDown: Bool = false
    private var lastFnPressTime: Date?
    private let doubleClickThreshold: TimeInterval = 0.4  // 400ms for double-click
    private var pendingFnReleaseWorkItem: DispatchWorkItem?  // Debounce fn release

    // MARK: - Singleton

    static let shared = HotkeyManager()

    private init() {}

    // MARK: - Public Methods

    /// Check if Accessibility permission is granted
    func checkAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Request Accessibility permission (shows system dialog)
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Register the global hotkey
    func register() throws {
        guard checkAccessibilityPermission() else {
            requestAccessibilityPermission()
            throw HotkeyError.accessibilityNotGranted
        }

        // Unregister first if already registered
        unregister()

        // Create event tap callback
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passRetained(event) }

            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
            return manager.handleEvent(proxy: proxy, type: type, event: event)
        }

        // Create event tap for key down and key up events
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw HotkeyError.failedToCreateEventTap
        }

        eventTap = tap

        // Create run loop source
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        guard let source = runLoopSource else {
            throw HotkeyError.failedToRunLoop
        }

        // Add to run loop
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        isRegistered = true
        errorMessage = nil

        print("[HotkeyManager] Registered global hotkey: \(currentHotkey)")
    }

    /// Unregister the global hotkey
    func unregister() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        isRegistered = false
        isKeyCurrentlyDown = false

        print("[HotkeyManager] Unregistered global hotkey")
    }

    /// Configure hotkey from string representation
    /// - Parameter hotkey: String like "^⌘D" or "⌃⌘D"
    func configure(hotkey: String) {
        // Parse modifier flags
        var modifiers: CGEventFlags = []

        if hotkey.contains("⌃") || hotkey.contains("^") {
            modifiers.insert(.maskControl)
        }
        if hotkey.contains("⌘") {
            modifiers.insert(.maskCommand)
        }
        if hotkey.contains("⌥") || hotkey.contains("~") {
            modifiers.insert(.maskAlternate)
        }
        if hotkey.contains("⇧") || hotkey.contains("$") {
            modifiers.insert(.maskShift)
        }

        hotkeyModifiers = modifiers

        // Extract key character (last character)
        if let lastChar = hotkey.last?.uppercased().first {
            hotkeyKeyCode = keyCodeForCharacter(lastChar)
        }

        currentHotkey = hotkey

        // Re-register if already registered
        if isRegistered {
            try? register()
        }
    }

    // MARK: - Private Methods

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Check if it's our hotkey
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        // Check if modifiers match (ignore caps lock and other non-modifier flags)
        let relevantFlags: CGEventFlags = [.maskControl, .maskCommand, .maskAlternate, .maskShift]
        let currentModifiers = flags.intersection(relevantFlags)
        let targetModifiers = hotkeyModifiers.intersection(relevantFlags)

        let isOurHotkey = (keyCode == hotkeyKeyCode) && (currentModifiers == targetModifiers)

        // Escape key code is 53
        let escapeKeyCode: CGKeyCode = 53

        switch type {
        case .keyDown:
            // Handle Escape key
            if keyCode == escapeKeyCode {
                Task { @MainActor in
                    self.onEscapePressed?()
                }
                // Don't consume - let Escape work normally
            }

            if isOurHotkey && !isKeyCurrentlyDown {
                isKeyCurrentlyDown = true
                Task { @MainActor in
                    self.onKeyDown?()
                }
                return nil  // Consume the event
            }

        case .keyUp:
            if keyCode == hotkeyKeyCode && isKeyCurrentlyDown {
                isKeyCurrentlyDown = false
                Task { @MainActor in
                    self.onKeyUp?()
                }
                return nil  // Consume the event
            }

        case .flagsChanged:
            // Handle modifier key release
            if isKeyCurrentlyDown {
                let hasRequiredModifiers = currentModifiers.isSuperset(of: targetModifiers)
                if !hasRequiredModifiers {
                    isKeyCurrentlyDown = false
                    Task { @MainActor in
                        self.onKeyUp?()
                    }
                }
            }

            // Handle fn key (it's detected via flagsChanged, not keyDown/keyUp)
            let fnKeyPressed = flags.contains(.maskSecondaryFn)
            if fnKeyPressed && !isFnKeyDown {
                isFnKeyDown = true
                let now = Date()

                // Cancel any pending release - user pressed again
                pendingFnReleaseWorkItem?.cancel()
                pendingFnReleaseWorkItem = nil

                // Check for double-click
                if let lastPress = lastFnPressTime,
                   now.timeIntervalSince(lastPress) < doubleClickThreshold {
                    // Double-click detected - switch to continuous mode
                    lastFnPressTime = nil  // Reset to prevent triple-click
                    Task { @MainActor in
                        self.onFnDoubleClick?()
                    }
                } else {
                    // Single press (might become double-click)
                    lastFnPressTime = now
                    Task { @MainActor in
                        self.onFnKeyDown?()
                    }
                }
                // Don't consume - let fn key work normally for other purposes
            } else if !fnKeyPressed && isFnKeyDown {
                isFnKeyDown = false

                // Debounce the release to allow time for double-click detection
                // If user double-clicks quickly, the second press will cancel this
                let releaseDelay: TimeInterval = 0.15  // 150ms buffer
                let workItem = DispatchWorkItem { [weak self] in
                    Task { @MainActor in
                        self?.onFnKeyUp?()
                    }
                }
                pendingFnReleaseWorkItem = workItem
                DispatchQueue.main.asyncAfter(deadline: .now() + releaseDelay, execute: workItem)
            }

        default:
            break
        }

        return Unmanaged.passRetained(event)
    }

    /// Convert a character to its key code
    private func keyCodeForCharacter(_ char: Character) -> CGKeyCode {
        let keyMap: [Character: CGKeyCode] = [
            "A": 0, "S": 1, "D": 2, "F": 3, "H": 4, "G": 5, "Z": 6, "X": 7,
            "C": 8, "V": 9, "B": 11, "Q": 12, "W": 13, "E": 14, "R": 15,
            "Y": 16, "T": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
            "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
            "]": 30, "O": 31, "U": 32, "[": 33, "I": 34, "P": 35, "L": 37,
            "J": 38, "'": 39, "K": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
            "N": 45, "M": 46, ".": 47, " ": 49
        ]
        return keyMap[char] ?? 2  // Default to 'D'
    }
}

// MARK: - Preview Helpers

extension HotkeyManager {
    static var preview: HotkeyManager {
        let manager = HotkeyManager()
        manager.isRegistered = true
        return manager
    }
}
