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
