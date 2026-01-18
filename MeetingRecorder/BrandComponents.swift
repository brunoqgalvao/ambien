//
//  BrandComponents.swift
//  MeetingRecorder
//
//  Reusable UI components following the Playful Pop brand guidelines
//

import SwiftUI

// MARK: - Brand Button Styles

/// Primary action button - filled violet, used for main CTAs
struct BrandPrimaryButton: View {
    let title: String
    var icon: String? = nil
    var isDisabled: Bool = false
    var size: ButtonSize = .medium
    let action: () -> Void

    enum ButtonSize {
        case small, medium, large

        var verticalPadding: CGFloat {
            switch self {
            case .small: return 8
            case .medium: return 12
            case .large: return 16
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .small: return 14
            case .medium: return 20
            case .large: return 28
            }
        }

        var fontSize: CGFloat {
            switch self {
            case .small: return 12
            case .medium: return 14
            case .large: return 16
            }
        }

        var iconSize: CGFloat {
            switch self {
            case .small: return 11
            case .medium: return 13
            case .large: return 15
            }
        }
    }

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: size.iconSize, weight: .semibold))
                }
                Text(title)
                    .font(.brandDisplay(size.fontSize, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: BrandRadius.small)
                    .fill(backgroundColor)
            )
            .shadow(color: Color.brandViolet.opacity(isHovered && !isDisabled ? 0.3 : 0), radius: 8, y: 4)
            .scaleEffect(isPressed ? 0.97 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }

    private var backgroundColor: Color {
        if isDisabled {
            return .brandViolet.opacity(0.5)
        } else if isPressed {
            return .brandVioletDeep
        } else if isHovered {
            return .brandVioletBright
        } else {
            return .brandViolet
        }
    }
}

/// Secondary action button - outlined/ghost, used for secondary actions
struct BrandSecondaryButton: View {
    let title: String
    var icon: String? = nil
    var size: BrandPrimaryButton.ButtonSize = .medium
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: size.iconSize, weight: .medium))
                }
                Text(title)
                    .font(.brandDisplay(size.fontSize, weight: .medium))
            }
            .foregroundColor(isHovered ? .brandViolet : .brandTextPrimary)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: BrandRadius.small)
                    .fill(isHovered ? Color.brandViolet.opacity(0.08) : Color.brandSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BrandRadius.small)
                    .stroke(isHovered ? Color.brandViolet.opacity(0.3) : Color.brandBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

/// Ghost button - minimal, text-only feel
struct BrandGhostButton: View {
    let title: String
    var icon: String? = nil
    var size: BrandPrimaryButton.ButtonSize = .medium
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: size.iconSize, weight: .medium))
                }
                Text(title)
                    .font(.brandDisplay(size.fontSize, weight: .medium))
            }
            .foregroundColor(isHovered ? .brandViolet : .brandTextSecondary)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: BrandRadius.small)
                    .fill(isHovered ? Color.brandViolet.opacity(0.05) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

/// Destructive button - coral/red for dangerous actions
struct BrandDestructiveButton: View {
    let title: String
    var icon: String? = nil
    var size: BrandPrimaryButton.ButtonSize = .medium
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: size.iconSize, weight: .semibold))
                }
                Text(title)
                    .font(.brandDisplay(size.fontSize, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: BrandRadius.small)
                    .fill(isHovered ? Color.brandCoralPop : Color.brandCoral)
            )
            .shadow(color: Color.brandCoral.opacity(isHovered ? 0.3 : 0), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

/// Icon-only button - circular, for toolbar actions
struct BrandIconButton: View {
    let icon: String
    var size: CGFloat = 32
    var color: Color = .brandTextSecondary
    var hoverColor: Color = .brandViolet
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.45, weight: .medium))
                .foregroundColor(isHovered ? hoverColor : color)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(isHovered ? hoverColor.opacity(0.1) : Color.clear)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Brand Card

struct BrandCard<Content: View>: View {
    var padding: CGFloat = 20
    var showBorder: Bool = true
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(Color.brandSurface)
            .cornerRadius(BrandRadius.medium)
            .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: BrandRadius.medium)
                    .stroke(showBorder ? Color.brandBorder : Color.clear, lineWidth: 1)
            )
    }
}

// MARK: - Brand Badge

struct BrandBadge: View {
    let text: String
    var color: Color = .brandViolet
    var size: BadgeSize = .medium

    enum BadgeSize {
        case small, medium

        var fontSize: CGFloat {
            switch self {
            case .small: return 10
            case .medium: return 11
            }
        }

        var padding: CGFloat {
            switch self {
            case .small: return 4
            case .medium: return 6
            }
        }
    }

    var body: some View {
        Text(text)
            .font(.brandMono(size.fontSize, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, size.padding * 1.5)
            .padding(.vertical, size.padding)
            .background(
                Capsule()
                    .fill(color.opacity(0.12))
            )
    }
}

// MARK: - Brand Status Dot

struct BrandStatusDot: View {
    let status: Status
    var size: CGFloat = 8
    var animated: Bool = false

    enum Status {
        case active, warning, error, success, inactive

        var color: Color {
            switch self {
            case .active: return .brandViolet
            case .warning: return .brandAmber
            case .error: return .brandCoral
            case .success: return .brandMint
            case .inactive: return .brandTextSecondary.opacity(0.5)
            }
        }
    }

    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(status.color.opacity(0.3), lineWidth: animated && isPulsing ? 3 : 0)
                    .scaleEffect(animated && isPulsing ? 1.8 : 1)
            )
            .onAppear {
                if animated {
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                }
            }
    }
}

// MARK: - Brand Divider

struct BrandDivider: View {
    var vertical: Bool = false
    var color: Color = .brandBorder

    var body: some View {
        if vertical {
            Rectangle()
                .fill(color)
                .frame(width: 1)
        } else {
            Rectangle()
                .fill(color)
                .frame(height: 1)
        }
    }
}

// MARK: - Brand Text Field

struct BrandTextField: View {
    let placeholder: String
    @Binding var text: String
    var icon: String? = nil

    @FocusState private var isFocused: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(isFocused ? .brandViolet : .brandTextSecondary)
            }

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($isFocused)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.brandSurface)
        .cornerRadius(BrandRadius.small)
        .overlay(
            RoundedRectangle(cornerRadius: BrandRadius.small)
                .stroke(isFocused ? Color.brandViolet : (isHovered ? Color.brandViolet.opacity(0.3) : Color.brandBorder), lineWidth: isFocused ? 2 : 1)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Brand Menu Button

/// Menu item button - for dropdown menus and sidebars
struct BrandMenuButton: View {
    let icon: String
    let title: String
    var shortcut: String? = nil
    var isSelected: Bool = false
    var badge: String? = nil
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .brandViolet : .brandTextSecondary)
                    .frame(width: 20)

                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .brandViolet : .brandTextPrimary)

                Spacer()

                if let badge = badge {
                    BrandBadge(text: badge, color: .brandViolet, size: .small)
                }

                if let shortcut = shortcut {
                    Text("⌘\(shortcut)")
                        .font(.system(size: 11))
                        .foregroundColor(.brandTextSecondary.opacity(0.7))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: BrandRadius.small)
                    .fill(isSelected ? Color.brandViolet.opacity(0.1) : (isHovered ? Color.brandViolet.opacity(0.05) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Brand Tab Button

/// Tab/segment selector button
struct BrandTabButton: View {
    let title: String
    var icon: String? = nil
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                }
                Text(title)
                    .font(.brandDisplay(13, weight: isSelected ? .semibold : .medium))
            }
            .foregroundColor(isSelected ? .white : (isHovered ? .brandViolet : .brandTextPrimary))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: BrandRadius.small)
                    .fill(isSelected ? Color.brandViolet : (isHovered ? Color.brandViolet.opacity(0.08) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Brand List Row

/// Selectable list row with icon, title, subtitle, and optional accessories
struct BrandListRow: View {
    var icon: String? = nil
    var iconColor: Color = .brandViolet
    let title: String
    var subtitle: String? = nil
    var accessory: String? = nil
    var isSelected: Bool = false
    var showChevron: Bool = true
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Icon
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundColor(isSelected ? .white : iconColor)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(isSelected ? iconColor : iconColor.opacity(0.1))
                        )
                }

                // Content
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isSelected ? .white : .brandTextPrimary)
                        .lineLimit(1)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(isSelected ? .white.opacity(0.8) : .brandTextSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Accessory text
                if let accessory = accessory {
                    Text(accessory)
                        .font(.brandMono(11))
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .brandTextSecondary)
                }

                // Chevron
                if showChevron && (isHovered || isSelected) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .brandTextSecondary.opacity(0.5))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: BrandRadius.small)
                    .fill(isSelected ? Color.brandViolet : (isHovered ? Color.brandViolet.opacity(0.05) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Brand Status Badge

/// Minimal status indicator - only shows for errors or in-progress states
/// Ready/completed meetings show nothing (clean, minimal design)
struct BrandStatusBadge: View {
    let status: Status
    var size: CGFloat = 32

    enum Status {
        case recording
        case transcribing
        case pending
        case ready
        case failed
    }

    var body: some View {
        Group {
            switch status {
            case .recording:
                // Recording pulse indicator
                ZStack {
                    Circle()
                        .fill(Color.brandCoral.opacity(0.12))
                        .frame(width: size, height: size)
                    Circle()
                        .fill(Color.brandCoral)
                        .frame(width: size * 0.25, height: size * 0.25)
                }
            case .transcribing:
                // Simple spinner using brand loading
                BrandLoadingIndicator(size: .custom(size), style: .spinner)
            case .failed:
                // Error alert - the ONLY indicator for completed meetings with issues
                ZStack {
                    Circle()
                        .fill(Color.brandCoral.opacity(0.12))
                        .frame(width: size, height: size)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundColor(.brandCoral)
                }
            case .pending, .ready:
                // No indicator - clean and minimal
                Color.clear
                    .frame(width: size, height: size)
            }
        }
    }
}

// MARK: - Brand Search Field

/// Search-specific text field with clear button
struct BrandSearchField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: (() -> Void)? = nil

    @FocusState private var isFocused: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundColor(isFocused ? .brandViolet : .brandTextSecondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isFocused)
                .onSubmit {
                    onSubmit?()
                }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.brandTextSecondary.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.brandSurface)
        .cornerRadius(BrandRadius.small)
        .overlay(
            RoundedRectangle(cornerRadius: BrandRadius.small)
                .stroke(isFocused ? Color.brandViolet : (isHovered ? Color.brandViolet.opacity(0.3) : Color.brandBorder), lineWidth: isFocused ? 2 : 1)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Previews

#Preview("Primary Buttons") {
    VStack(spacing: 16) {
        BrandPrimaryButton(title: "Get Started", icon: "arrow.right", size: .large) {}
        BrandPrimaryButton(title: "Save Changes", size: .medium) {}
        BrandPrimaryButton(title: "Add", icon: "plus", size: .small) {}
        BrandPrimaryButton(title: "Disabled", isDisabled: true) {}
    }
    .padding(40)
    .background(Color.brandBackground)
}

#Preview("Secondary Buttons") {
    VStack(spacing: 16) {
        BrandSecondaryButton(title: "Cancel", size: .large) {}
        BrandSecondaryButton(title: "Learn More", icon: "arrow.up.right", size: .medium) {}
        BrandSecondaryButton(title: "Edit", icon: "pencil", size: .small) {}
    }
    .padding(40)
    .background(Color.brandBackground)
}

#Preview("Button Variants") {
    HStack(spacing: 16) {
        BrandGhostButton(title: "Skip", size: .medium) {}
        BrandSecondaryButton(title: "Cancel", size: .medium) {}
        BrandPrimaryButton(title: "Continue", icon: "arrow.right", size: .medium) {}
    }
    .padding(40)
    .background(Color.brandBackground)
}

#Preview("Destructive") {
    HStack(spacing: 16) {
        BrandSecondaryButton(title: "Keep", size: .medium) {}
        BrandDestructiveButton(title: "Delete", icon: "trash", size: .medium) {}
    }
    .padding(40)
    .background(Color.brandBackground)
}

#Preview("Icon Buttons") {
    HStack(spacing: 12) {
        BrandIconButton(icon: "gear", size: 36) {}
        BrandIconButton(icon: "bell", size: 36) {}
        BrandIconButton(icon: "square.and.arrow.up", size: 36) {}
        BrandIconButton(icon: "trash", size: 36, hoverColor: .brandCoral) {}
    }
    .padding(40)
    .background(Color.brandBackground)
}

#Preview("Badges") {
    HStack(spacing: 12) {
        BrandBadge(text: "NEW", color: .brandViolet)
        BrandBadge(text: "3 min", color: .brandMint)
        BrandBadge(text: "LIVE", color: .brandCoral)
        BrandBadge(text: "PRO", color: .brandAmber, size: .small)
    }
    .padding(40)
    .background(Color.brandBackground)
}

#Preview("Status Dots") {
    HStack(spacing: 20) {
        HStack(spacing: 8) {
            BrandStatusDot(status: .active)
            Text("Active")
        }
        HStack(spacing: 8) {
            BrandStatusDot(status: .success)
            Text("Success")
        }
        HStack(spacing: 8) {
            BrandStatusDot(status: .warning)
            Text("Warning")
        }
        HStack(spacing: 8) {
            BrandStatusDot(status: .error, animated: true)
            Text("Recording")
        }
    }
    .font(.system(size: 13))
    .padding(40)
    .background(Color.brandBackground)
}

#Preview("Card") {
    BrandCard {
        VStack(alignment: .leading, spacing: 12) {
            Text("Meeting Title")
                .font(.brandDisplay(16, weight: .semibold))
            Text("Today at 2:30 PM • 45 minutes")
                .font(.system(size: 13))
                .foregroundColor(.brandTextSecondary)
        }
        .frame(width: 280, alignment: .leading)
    }
    .padding(40)
    .background(Color.brandBackground)
}

#Preview("Text Field") {
    VStack(spacing: 16) {
        BrandTextField(placeholder: "Search meetings...", text: .constant(""), icon: "magnifyingglass")
        BrandTextField(placeholder: "Enter API key", text: .constant("sk-..."), icon: "key")
    }
    .frame(width: 300)
    .padding(40)
    .background(Color.brandBackground)
}

#Preview("Menu Buttons") {
    VStack(spacing: 2) {
        BrandMenuButton(icon: "rectangle.stack", title: "Open App", shortcut: "O") {}
        BrandMenuButton(icon: "magnifyingglass", title: "Search", shortcut: "F") {}
        BrandMenuButton(icon: "gear", title: "Settings", shortcut: ",", isSelected: true) {}
        BrandMenuButton(icon: "bell", title: "Notifications", badge: "3") {}
    }
    .frame(width: 260)
    .padding(20)
    .background(Color.brandBackground)
}

#Preview("Tab Buttons") {
    HStack(spacing: 4) {
        BrandTabButton(title: "All", isSelected: true) {}
        BrandTabButton(title: "Meetings", icon: "waveform", isSelected: false) {}
        BrandTabButton(title: "Dictations", icon: "mic", isSelected: false) {}
    }
    .padding(20)
    .background(Color.brandBackground)
}

#Preview("List Rows") {
    VStack(spacing: 2) {
        BrandListRow(
            icon: "waveform",
            title: "Team Standup",
            subtitle: "Today at 9:00 AM",
            accessory: "45m",
            isSelected: true
        ) {}
        BrandListRow(
            icon: "waveform",
            title: "Product Review",
            subtitle: "Yesterday at 2:30 PM",
            accessory: "1h 12m"
        ) {}
        BrandListRow(
            icon: "mic.fill",
            iconColor: .brandMint,
            title: "Quick Note",
            subtitle: "Just now",
            accessory: "0:32"
        ) {}
    }
    .frame(width: 320)
    .padding(20)
    .background(Color.brandBackground)
}

#Preview("Status Badges") {
    HStack(spacing: 20) {
        VStack {
            BrandStatusBadge(status: .recording)
            Text("Recording").font(.caption)
        }
        VStack {
            BrandStatusBadge(status: .transcribing)
            Text("Transcribing").font(.caption)
        }
        VStack {
            BrandStatusBadge(status: .pending)
            Text("Pending").font(.caption)
        }
        VStack {
            BrandStatusBadge(status: .ready)
            Text("Ready").font(.caption)
        }
        VStack {
            BrandStatusBadge(status: .failed)
            Text("Failed").font(.caption)
        }
    }
    .padding(40)
    .background(Color.brandBackground)
}

// MARK: - Brand Loading Indicator

/// Animated loading spinner with brand colors
/// Usage:
///   - BrandLoadingIndicator(size: .small)  // 16pt - inline with text
///   - BrandLoadingIndicator(size: .medium) // 24pt - buttons, cards
///   - BrandLoadingIndicator(size: .large)  // 40pt - full screen loading
///   - BrandLoadingIndicator(size: .custom(32)) // exact size
struct BrandLoadingIndicator: View {
    var size: LoadingSize = .medium
    var color: Color = .brandViolet
    var lineWidth: CGFloat? = nil
    var style: LoadingStyle = .spinner

    enum LoadingSize {
        case tiny       // 12pt - very small inline
        case small      // 16pt - inline with text
        case medium     // 24pt - default, buttons, cards
        case large      // 40pt - page loading
        case xlarge     // 56pt - hero loading
        case custom(CGFloat)

        var points: CGFloat {
            switch self {
            case .tiny: return 12
            case .small: return 16
            case .medium: return 24
            case .large: return 40
            case .xlarge: return 56
            case .custom(let value): return value
            }
        }
    }

    enum LoadingStyle {
        case spinner      // Classic rotating spinner
        case dots         // Bouncing dots
        case pulse        // Pulsing circle
        case bars         // Animated bars (audio-like)
    }

    @State private var isAnimating = false
    @State private var dotPhases: [Bool] = [false, false, false]

    private var sizePoints: CGFloat { size.points }

    private var computedLineWidth: CGFloat {
        lineWidth ?? (sizePoints * 0.1)
    }

    var body: some View {
        switch style {
        case .spinner:
            spinnerView
        case .dots:
            dotsView
        case .pulse:
            pulseView
        case .bars:
            barsView
        }
    }

    // MARK: - Spinner Style

    private var spinnerView: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [color.opacity(0.1), color]),
                    center: .center,
                    startAngle: .degrees(0),
                    endAngle: .degrees(360)
                ),
                style: StrokeStyle(lineWidth: computedLineWidth, lineCap: .round)
            )
            .frame(width: sizePoints, height: sizePoints)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }

    // MARK: - Dots Style

    private var dotsView: some View {
        HStack(spacing: sizePoints * 0.2) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: sizePoints * 0.25, height: sizePoints * 0.25)
                    .offset(y: dotPhases[index] ? -sizePoints * 0.2 : 0)
            }
        }
        .frame(height: sizePoints)
        .onAppear {
            for i in 0..<3 {
                withAnimation(
                    .easeInOut(duration: 0.4)
                    .repeatForever(autoreverses: true)
                    .delay(Double(i) * 0.15)
                ) {
                    dotPhases[i] = true
                }
            }
        }
    }

    // MARK: - Pulse Style

    private var pulseView: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.2))
                .frame(width: sizePoints, height: sizePoints)
                .scaleEffect(isAnimating ? 1.3 : 0.8)
                .opacity(isAnimating ? 0 : 0.8)

            Circle()
                .fill(color)
                .frame(width: sizePoints * 0.5, height: sizePoints * 0.5)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: false)) {
                isAnimating = true
            }
        }
    }

    // MARK: - Bars Style (Audio waveform-like)

    @State private var barHeights: [CGFloat] = [0.3, 0.5, 0.7, 0.5, 0.3]

    private var barsView: some View {
        HStack(spacing: sizePoints * 0.08) {
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: sizePoints * 0.05)
                    .fill(color)
                    .frame(width: sizePoints * 0.12, height: sizePoints * barHeights[index])
            }
        }
        .frame(height: sizePoints)
        .onAppear {
            animateBars()
        }
    }

    private func animateBars() {
        Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.15)) {
                barHeights = barHeights.map { _ in CGFloat.random(in: 0.2...1.0) }
            }
        }
    }
}

// MARK: - Brand Recording Indicator

/// Animated recording indicator with pulsing effect
struct BrandRecordingIndicator: View {
    var size: CGFloat = 48
    var style: RecordingStyle = .waveform
    var isActive: Bool = true

    enum RecordingStyle {
        case dot          // Pulsing red dot
        case waveform     // Audio waveform bars
        case circle       // Concentric circles
        case ring         // Rotating ring with dot
    }

    @State private var isPulsing = false
    @State private var waveHeights: [CGFloat] = [0.3, 0.5, 0.8, 0.6, 0.4, 0.7, 0.5]
    @State private var ringRotation: Double = 0

    var body: some View {
        switch style {
        case .dot:
            dotView
        case .waveform:
            waveformView
        case .circle:
            circleView
        case .ring:
            ringView
        }
    }

    // MARK: - Dot Style

    private var dotView: some View {
        ZStack {
            // Outer pulse rings
            if isActive {
                ForEach(0..<2, id: \.self) { index in
                    Circle()
                        .stroke(Color.brandCoral.opacity(0.3), lineWidth: 2)
                        .frame(width: size, height: size)
                        .scaleEffect(isPulsing ? 1.5 + CGFloat(index) * 0.3 : 1)
                        .opacity(isPulsing ? 0 : 0.6)
                }
            }

            // Core dot
            Circle()
                .fill(Color.brandCoral)
                .frame(width: size * 0.4, height: size * 0.4)
                .shadow(color: Color.brandCoral.opacity(0.4), radius: isPulsing ? 12 : 6)
        }
        .frame(width: size * 2, height: size * 2)
        .onAppear {
            guard isActive else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
        .onChange(of: isActive) { _, newValue in
            if newValue {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                    isPulsing = true
                }
            } else {
                isPulsing = false
            }
        }
    }

    // MARK: - Waveform Style

    private var waveformView: some View {
        HStack(spacing: size * 0.06) {
            ForEach(0..<7, id: \.self) { index in
                RoundedRectangle(cornerRadius: size * 0.04)
                    .fill(
                        LinearGradient(
                            colors: [Color.brandCoral, Color.brandCoralPop],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: size * 0.08, height: size * waveHeights[index])
            }
        }
        .frame(height: size)
        .onAppear {
            guard isActive else { return }
            animateWaveform()
        }
    }

    private func animateWaveform() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            guard isActive else {
                timer.invalidate()
                return
            }
            withAnimation(.easeInOut(duration: 0.1)) {
                waveHeights = waveHeights.map { _ in CGFloat.random(in: 0.2...1.0) }
            }
        }
    }

    // MARK: - Circle Style

    private var circleView: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(
                        Color.brandCoral.opacity(0.3 - Double(index) * 0.1),
                        lineWidth: 2
                    )
                    .frame(width: size * (0.4 + CGFloat(index) * 0.3), height: size * (0.4 + CGFloat(index) * 0.3))
                    .scaleEffect(isPulsing ? 1.2 : 1)
                    .opacity(isPulsing ? 0.3 : 0.8)
                    .animation(
                        .easeInOut(duration: 1)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.2),
                        value: isPulsing
                    )
            }

            // Center icon
            Image(systemName: "mic.fill")
                .font(.system(size: size * 0.3, weight: .semibold))
                .foregroundColor(.brandCoral)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard isActive else { return }
            isPulsing = true
        }
    }

    // MARK: - Ring Style

    private var ringView: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.brandCoral.opacity(0.2), lineWidth: size * 0.08)
                .frame(width: size, height: size)

            // Animated arc
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(
                    LinearGradient(
                        colors: [Color.brandCoral, Color.brandCoralPop],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: size * 0.08, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(ringRotation))

            // Center dot
            Circle()
                .fill(Color.brandCoral)
                .frame(width: size * 0.25, height: size * 0.25)
                .shadow(color: Color.brandCoral.opacity(0.4), radius: 4)
        }
        .onAppear {
            guard isActive else { return }
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
        }
    }
}

// MARK: - Brand Logo

/// Brand logo component with optional animation
struct BrandLogo: View {
    var size: CGFloat = 40
    var showText: Bool = true
    var animated: Bool = false

    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: size * 0.3) {
            // Logo mark - stylized waveform in a circle
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.brandViolet, Color.brandVioletDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                    .shadow(color: Color.brandViolet.opacity(animated && isAnimating ? 0.4 : 0.2), radius: animated && isAnimating ? 12 : 6)

                // Waveform icon
                HStack(spacing: size * 0.05) {
                    ForEach(0..<5, id: \.self) { index in
                        RoundedRectangle(cornerRadius: size * 0.02)
                            .fill(Color.white)
                            .frame(width: size * 0.06, height: waveHeight(for: index))
                    }
                }
            }
            .scaleEffect(animated && isAnimating ? 1.05 : 1)

            if showText {
                Text("ambient")
                    .font(.brandDisplay(size * 0.5, weight: .bold))
                    .foregroundColor(.brandInk)
            }
        }
        .onAppear {
            if animated {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
        }
    }

    private func waveHeight(for index: Int) -> CGFloat {
        let heights: [CGFloat] = [0.2, 0.35, 0.5, 0.35, 0.2]
        return size * heights[index]
    }
}

#Preview("Search Field") {
    VStack(spacing: 16) {
        BrandSearchField(placeholder: "Search meetings...", text: .constant(""))
        BrandSearchField(placeholder: "Search meetings...", text: .constant("team standup"))
    }
    .frame(width: 280)
    .padding(40)
    .background(Color.brandBackground)
}

#Preview("Loading Indicators") {
    HStack(spacing: 40) {
        VStack {
            BrandLoadingIndicator(size: .medium, style: .spinner)
            Text("Spinner").font(.caption)
        }
        VStack {
            BrandLoadingIndicator(size: .medium, style: .dots)
            Text("Dots").font(.caption)
        }
        VStack {
            BrandLoadingIndicator(size: .medium, style: .pulse)
            Text("Pulse").font(.caption)
        }
        VStack {
            BrandLoadingIndicator(size: .medium, style: .bars)
            Text("Bars").font(.caption)
        }
    }
    .padding(40)
    .background(Color.brandBackground)
}

#Preview("Loading Sizes") {
    HStack(spacing: 30) {
        VStack {
            BrandLoadingIndicator(size: .tiny)
            Text("Tiny (12)").font(.caption2)
        }
        VStack {
            BrandLoadingIndicator(size: .small)
            Text("Small (16)").font(.caption2)
        }
        VStack {
            BrandLoadingIndicator(size: .medium)
            Text("Medium (24)").font(.caption2)
        }
        VStack {
            BrandLoadingIndicator(size: .large)
            Text("Large (40)").font(.caption2)
        }
        VStack {
            BrandLoadingIndicator(size: .xlarge, color: .brandCoral)
            Text("XLarge (56)").font(.caption2)
        }
    }
    .padding(40)
    .background(Color.brandBackground)
}

#Preview("Recording Indicators") {
    HStack(spacing: 40) {
        VStack {
            BrandRecordingIndicator(size: 48, style: .dot)
            Text("Dot").font(.caption)
        }
        VStack {
            BrandRecordingIndicator(size: 48, style: .waveform)
            Text("Waveform").font(.caption)
        }
        VStack {
            BrandRecordingIndicator(size: 48, style: .circle)
            Text("Circle").font(.caption)
        }
        VStack {
            BrandRecordingIndicator(size: 48, style: .ring)
            Text("Ring").font(.caption)
        }
    }
    .padding(60)
    .background(Color.brandBackground)
}

#Preview("Brand Logo") {
    VStack(spacing: 30) {
        BrandLogo(size: 40, showText: true)
        BrandLogo(size: 32, showText: true, animated: true)
        BrandLogo(size: 24, showText: false)
    }
    .padding(40)
    .background(Color.brandBackground)
}
