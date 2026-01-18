//
//  SidebarView.swift
//  MeetingRecorder
//
//  60px icon-only sidebar navigation
//

import SwiftUI

struct SidebarView: View {
    @Binding var selectedItem: NavigationItem
    @ObservedObject var viewModel: MainAppViewModel
    var onRecord: () -> Void
    var onSettings: () -> Void
    @Binding var isMeetingsListCollapsed: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Top Navigation Items
            VStack(spacing: 16) {
                SidebarButton(
                    icon: "house.fill",
                    label: "Home",
                    isSelected: selectedItem == .home,
                    action: { selectedItem = .home }
                )

                SidebarButton(
                    icon: "calendar",
                    label: "Calendar",
                    isSelected: selectedItem == .calendar,
                    action: { selectedItem = .calendar }
                )

                SidebarButton(
                    icon: "checklist",
                    label: "Action Items",
                    isSelected: selectedItem == .actionItems,
                    badge: viewModel.openActionItemsCount > 0 ? viewModel.openActionItemsCount : nil,
                    action: { selectedItem = .actionItems }
                )

                SidebarButton(
                    icon: "doc.text.fill",
                    label: "Meetings",
                    isSelected: selectedItem == .meetings,
                    badge: viewModel.pendingTranscriptions > 0 ? viewModel.pendingTranscriptions : nil,
                    action: { selectedItem = .meetings }
                )

                SidebarButton(
                    icon: "folder.fill",
                    label: "Projects",
                    isSelected: selectedItem == .projects,
                    action: { selectedItem = .projects }
                )

                SidebarButton(
                    icon: "mic.fill",
                    label: "Dictations",
                    isSelected: selectedItem == .dictations,
                    action: { selectedItem = .dictations }
                )

                SidebarButton(
                    icon: "doc.text.magnifyingglass",
                    label: "Templates",
                    isSelected: selectedItem == .templates,
                    action: { selectedItem = .templates }
                )

                // Analytics - only visible for beta testers (shows cost data)
                if FeatureFlags.shared.showCosts {
                    SidebarButton(
                        icon: "chart.bar.fill",
                        label: "Analytics",
                        isSelected: selectedItem == .analytics,
                        action: { selectedItem = .analytics }
                    )
                }
            }
            .padding(.top, 52)

            Spacer()

            // Bottom Action Items
            VStack(spacing: 12) {
                // Settings Button
                SidebarButton(
                    icon: "gear",
                    label: "Settings",
                    isSelected: selectedItem == .settings,
                    action: onSettings
                )
            }
            .padding(.bottom, 20)
        }
        .frame(width: 80)
        .background(
            Color.brandBackground
                .ignoresSafeArea()
        )
        .overlay(alignment: .trailing) {
            ZStack {
                // Border line
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(Color.brandBorder)
                    .ignoresSafeArea()

                // Edge toggle button - only show on Meetings tab
                if selectedItem == .meetings {
                    SidebarEdgeToggle(isCollapsed: $isMeetingsListCollapsed)
                        .offset(x: 12) // Half the button width to center on edge
                }
            }
        }
    }
}

// MARK: - Sidebar Edge Toggle Button

/// A small tab that sits on the edge of the sidebar to toggle the meetings list
struct SidebarEdgeToggle: View {
    @Binding var isCollapsed: Bool

    @State private var isHovered = false

    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCollapsed.toggle()
            }
        }) {
            ZStack {
                // Pill-shaped background
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? Color.brandViolet.opacity(0.1) : Color.brandSurface)
                    .frame(width: 24, height: 48)
                    .shadow(color: .black.opacity(0.08), radius: 2, x: 1, y: 0)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.brandBorder, lineWidth: 1)
                    )

                // Chevron icon
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isHovered ? .brandViolet : .brandTextSecondary)
            }
        }
        .buttonStyle(.plain)
        .help(isCollapsed ? "Show meeting list" : "Hide meeting list")
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

struct SidebarButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    var badge: Int? = nil
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                // Background & Icon
                ZStack {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.brandViolet.opacity(0.1))
                            .frame(width: 44, height: 44)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.05))
                            .frame(width: 44, height: 44)
                    }
                    
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? .brandViolet : .secondary)
                        .frame(width: 44, height: 44)
                }
                
                // Badge
                if let badge = badge {
                    Text("\(badge)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.brandCoral)
                        .clipShape(Capsule())
                        .offset(x: 4, y: -4)
                        .shadow(color: Color.brandCoral.opacity(0.3), radius: 2, x: 0, y: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .help(label)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
