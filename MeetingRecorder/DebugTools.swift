//
//  DebugTools.swift
//  MeetingRecorder
//
//  Debug overlay system for SwiftUI view inspection
//  Toggle with Cmd+Shift+D in debug builds
//

import SwiftUI
import Combine

// MARK: - Debug Settings

class DebugSettings: ObservableObject {
    static let shared = DebugSettings()

    @Published var showFrames: Bool = false
    @Published var showHierarchy: Bool = false
    @Published var showSizes: Bool = false
    @Published var highlightColor: Color = .red

    private init() {}

    #if DEBUG
    var isDebugBuild: Bool { true }
    #else
    var isDebugBuild: Bool { false }
    #endif
}

// MARK: - Debug Frame Overlay

struct DebugFrameModifier: ViewModifier {
    @ObservedObject private var settings = DebugSettings.shared
    let label: String?
    let color: Color

    init(label: String? = nil, color: Color = .red) {
        self.label = label
        self.color = color
    }

    func body(content: Content) -> some View {
        #if DEBUG
        if settings.showFrames {
            content
                .overlay(
                    GeometryReader { geo in
                        ZStack(alignment: .topLeading) {
                            // Border
                            Rectangle()
                                .stroke(color, lineWidth: 1)

                            // Size label
                            if settings.showSizes {
                                VStack(alignment: .leading, spacing: 0) {
                                    if let label = label {
                                        Text(label)
                                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                                            .foregroundColor(.white)
                                    }
                                    Text("\(Int(geo.size.width))×\(Int(geo.size.height))")
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundColor(.white)
                                }
                                .padding(2)
                                .background(color.opacity(0.85))
                                .cornerRadius(2)
                            }
                        }
                    }
                )
        } else {
            content
        }
        #else
        content
        #endif
    }
}

// MARK: - Debug Size Overlay

struct DebugSizeModifier: ViewModifier {
    @ObservedObject private var settings = DebugSettings.shared
    let alignment: Alignment

    func body(content: Content) -> some View {
        #if DEBUG
        if settings.showSizes {
            content
                .overlay(
                    GeometryReader { geo in
                        Text("\(Int(geo.size.width))×\(Int(geo.size.height))")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .padding(3)
                            .background(Color.black.opacity(0.75))
                            .foregroundColor(.white)
                            .cornerRadius(3)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                    }
                )
        } else {
            content
        }
        #else
        content
        #endif
    }
}

// MARK: - Debug Hierarchy View

struct DebugHierarchyModifier: ViewModifier {
    @ObservedObject private var settings = DebugSettings.shared
    let name: String
    let depth: Int

    private var indentColor: Color {
        let colors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink]
        return colors[depth % colors.length]
    }

    func body(content: Content) -> some View {
        #if DEBUG
        if settings.showHierarchy {
            content
                .border(indentColor.opacity(0.5), width: 1)
                .overlay(
                    Text(name)
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(indentColor.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(2)
                        .offset(x: CGFloat(depth * 2), y: CGFloat(depth * 2)),
                    alignment: .topLeading
                )
        } else {
            content
        }
        #else
        content
        #endif
    }
}

// MARK: - Debug Tap Logger

struct DebugTapModifier: ViewModifier {
    let label: String

    func body(content: Content) -> some View {
        #if DEBUG
        content
            .simultaneousGesture(
                TapGesture().onEnded {
                    print("[Debug Tap] \(label)")
                }
            )
        #else
        content
        #endif
    }
}

// MARK: - View Extensions

extension View {
    /// Shows a colored border with size info when debug mode is on
    /// Toggle with Cmd+Shift+D
    func debugFrame(_ label: String? = nil, color: Color = .red) -> some View {
        modifier(DebugFrameModifier(label: label, color: color))
    }

    /// Shows size overlay in corner
    func debugSize(alignment: Alignment = .bottomTrailing) -> some View {
        modifier(DebugSizeModifier(alignment: alignment))
    }

    /// Shows hierarchy depth with color coding
    func debugHierarchy(_ name: String, depth: Int = 0) -> some View {
        modifier(DebugHierarchyModifier(name: name, depth: depth))
    }

    /// Logs taps to console
    func debugTap(_ label: String) -> some View {
        modifier(DebugTapModifier(label: label))
    }

    /// Quick border for debugging layout
    func debugBorder(_ color: Color = .red) -> some View {
        #if DEBUG
        self.border(color, width: 1)
        #else
        self
        #endif
    }

    /// Print geometry to console
    func debugGeometry(_ label: String = "") -> some View {
        #if DEBUG
        self.background(
            GeometryReader { geo in
                Color.clear.onAppear {
                    print("[Debug Geometry] \(label): \(geo.size) at \(geo.frame(in: .global).origin)")
                }
            }
        )
        #else
        self
        #endif
    }
}

// Extension to fix the Array.length issue
private extension Array {
    var length: Int { count }
}

// MARK: - Debug Toolbar

struct DebugToolbar: View {
    @ObservedObject private var settings = DebugSettings.shared
    @State private var isExpanded = false

    var body: some View {
        #if DEBUG
        VStack(alignment: .trailing, spacing: 8) {
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text("DEBUG TOOLS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))

                    Divider()
                        .background(Color.white.opacity(0.3))

                    DebugToggleRow(label: "Show Frames", isOn: $settings.showFrames)
                    DebugToggleRow(label: "Show Sizes", isOn: $settings.showSizes)
                    DebugToggleRow(label: "Show Hierarchy", isOn: $settings.showHierarchy)

                    Divider()
                        .background(Color.white.opacity(0.3))

                    HStack(spacing: 6) {
                        Text("Color:")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))

                        ForEach([Color.red, .orange, .green, .blue, .purple], id: \.self) { color in
                            Circle()
                                .fill(color)
                                .frame(width: 14, height: 14)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: settings.highlightColor == color ? 2 : 0)
                                )
                                .onTapGesture {
                                    settings.highlightColor = color
                                }
                        }
                    }

                    Text("⌘⇧D to toggle")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.top, 4)
                }
                .padding(10)
                .background(Color.black.opacity(0.85))
                .cornerRadius(8)
                .shadow(radius: 10)
            }

            Button(action: { isExpanded.toggle() }) {
                Image(systemName: isExpanded ? "xmark.circle.fill" : "ant.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.black.opacity(0.7))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        #else
        EmptyView()
        #endif
    }
}

struct DebugToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white)

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .scaleEffect(0.6)
                .frame(width: 40)
        }
    }
}

// MARK: - Debug Overlay Container

struct DebugOverlay<Content: View>: View {
    @ObservedObject private var settings = DebugSettings.shared
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            content

            #if DEBUG
            DebugToolbar()
            #endif
        }
    }
}

// MARK: - Keyboard Shortcut Handler

class DebugKeyboardHandler {
    static let shared = DebugKeyboardHandler()

    private var monitor: Any?

    private init() {}

    func setup() {
        #if DEBUG
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Cmd+Shift+D toggles debug frames
            if event.modifierFlags.contains([.command, .shift]) && event.charactersIgnoringModifiers == "d" {
                DebugSettings.shared.showFrames.toggle()
                DebugSettings.shared.showSizes = DebugSettings.shared.showFrames
                print("[Debug] Frame overlay: \(DebugSettings.shared.showFrames ? "ON" : "OFF")")
                return nil // consume the event
            }
            // Cmd+Shift+H toggles hierarchy
            if event.modifierFlags.contains([.command, .shift]) && event.charactersIgnoringModifiers == "h" {
                DebugSettings.shared.showHierarchy.toggle()
                print("[Debug] Hierarchy overlay: \(DebugSettings.shared.showHierarchy ? "ON" : "OFF")")
                return nil
            }
            return event
        }
        print("[Debug] Keyboard shortcuts registered: Cmd+Shift+D (frames), Cmd+Shift+H (hierarchy)")
        #endif
    }

    func teardown() {
        #if DEBUG
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
        #endif
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Debug Toolbar") {
    DebugOverlay {
        VStack(spacing: 20) {
            Text("Parent Container")
                .debugFrame("Parent", color: .blue)
                .padding()

            HStack(spacing: 10) {
                Text("Child 1")
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .debugFrame("Child1", color: .green)

                Text("Child 2")
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .debugFrame("Child2", color: .orange)
            }
            .debugFrame("HStack", color: .purple)
        }
        .padding()
        .debugFrame("Root", color: .red)
    }
    .frame(width: 400, height: 300)
    .onAppear {
        DebugSettings.shared.showFrames = true
        DebugSettings.shared.showSizes = true
    }
}
#endif
