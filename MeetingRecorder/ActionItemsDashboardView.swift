//
//  ActionItemsDashboardView.swift
//  MeetingRecorder
//
//  Dashboard view for managing all action items across meetings
//

import SwiftUI

// MARK: - Dashboard View

struct ActionItemsDashboardView: View {
    @State private var actionItems: [ActionItem] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var filterStatus: FilterStatus = .open
    @State private var showCompleted = false
    @State private var counts = ActionItemCounts()

    enum FilterStatus: String, CaseIterable {
        case all = "All"
        case open = "Open"
        case myItems = "My Items"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            dashboardHeader

            Divider()

            // Content
            if isLoading {
                loadingState
            } else if filteredItems.isEmpty && completedItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Grouped items
                        ForEach(DueDateGroup.allCases.filter { $0 != .completed }, id: \.self) { group in
                            let items = itemsForGroup(group)
                            if !items.isEmpty {
                                groupSection(group: group, items: items)
                            }
                        }

                        // Completed section (collapsible)
                        if !completedItems.isEmpty {
                            completedSection
                        }
                    }
                    .padding()
                }
            }
        }
        .background(Color.brandBackground)
        .task {
            await loadItems()
            await loadCounts()
        }
        .onReceive(NotificationCenter.default.publisher(for: .actionItemsDidChange)) { _ in
            Task {
                await loadItems()
                await loadCounts()
            }
        }
    }

    // MARK: - Header

    private var dashboardHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Text("Action Items")
                    .font(.brandDisplay(20, weight: .semibold))
                    .foregroundColor(.brandTextPrimary)

                Spacer()

                // Export menu
                Menu {
                    Button("Copy as Markdown") { copyAsMarkdown() }
                    Button("Copy as Plain Text") { copyAsPlainText() }
                    Divider()
                    Button("Export to JSON") { exportToJSON() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.brandViolet)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 80)
            }

            // Stats row
            HStack(spacing: 16) {
                if counts.overdue > 0 {
                    StatBadge(
                        icon: "exclamationmark.circle.fill",
                        count: counts.overdue,
                        label: "overdue",
                        color: .brandCoral
                    )
                }

                StatBadge(
                    icon: "calendar",
                    count: counts.dueToday,
                    label: "due today",
                    color: .brandAmber
                )

                StatBadge(
                    icon: "calendar.badge.clock",
                    count: counts.dueThisWeek,
                    label: "this week",
                    color: .brandViolet
                )

                Spacer()

                // Filter & Search
                HStack(spacing: 12) {
                    Picker("", selection: $filterStatus) {
                        ForEach(FilterStatus.allCases, id: \.self) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)

                    BrandSearchField(placeholder: "Search...", text: $searchText)
                        .frame(width: 180)
                }
            }
        }
        .padding()
    }

    // MARK: - Group Section

    private func groupSection(group: DueDateGroup, items: [ActionItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Text("\(group.emoji) \(group.displayName.uppercased())")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.brandTextSecondary)

                Text("(\(items.count))")
                    .font(.system(size: 11))
                    .foregroundColor(.brandTextSecondary.opacity(0.7))
            }

            // Items
            VStack(spacing: 2) {
                ForEach(items) { item in
                    ActionItemDashboardRow(
                        item: item,
                        onComplete: { completeItem($0) },
                        onEdit: { editItem($0) },
                        onDelete: { deleteItem($0) },
                        onNavigateToMeeting: { navigateToMeeting($0) }
                    )
                }
            }
            .background(Color.brandSurface)
            .cornerRadius(BrandRadius.small)
            .overlay(
                RoundedRectangle(cornerRadius: BrandRadius.small)
                    .stroke(Color.brandBorder, lineWidth: 1)
            )
        }
    }

    // MARK: - Completed Section

    private var completedSection: some View {
        DisclosureGroup(isExpanded: $showCompleted) {
            VStack(spacing: 2) {
                ForEach(completedItems.prefix(10)) { item in
                    ActionItemDashboardRow(
                        item: item,
                        onComplete: { reopenItem($0) }
                    )
                }

                if completedItems.count > 10 {
                    Text("+ \(completedItems.count - 10) more")
                        .font(.system(size: 12))
                        .foregroundColor(.brandTextSecondary)
                        .padding(.vertical, 8)
                }
            }
            .background(Color.brandSurface)
            .cornerRadius(BrandRadius.small)
            .overlay(
                RoundedRectangle(cornerRadius: BrandRadius.small)
                    .stroke(Color.brandBorder, lineWidth: 1)
            )
        } label: {
            HStack {
                Text("COMPLETED")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.brandTextSecondary)

                Text("(\(completedItems.count))")
                    .font(.system(size: 11))
                    .foregroundColor(.brandTextSecondary.opacity(0.7))
            }
        }
        .accentColor(.brandTextSecondary)
    }

    // MARK: - States

    private var loadingState: some View {
        VStack {
            Spacer()
            BrandLoadingIndicator(size: .large)
            Text("Loading action items...")
                .font(.system(size: 14))
                .foregroundColor(.brandTextSecondary)
                .padding(.top, 12)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle")
                .font(.system(size: 64))
                .foregroundColor(.brandMint.opacity(0.6))

            Text("All caught up!")
                .font(.brandDisplay(20, weight: .semibold))
                .foregroundColor(.brandTextPrimary)

            Text("You have no open action items.\nRecord meetings and generate briefs to extract action items.")
                .font(.system(size: 14))
                .foregroundColor(.brandTextSecondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Computed Properties

    private var filteredItems: [ActionItem] {
        var items = actionItems.filter { $0.status == .open }

        // Apply filter
        if filterStatus == .myItems {
            // TODO: Filter by current user when we have user accounts
            // For now, show items with "You" or no assignee
            items = items.filter { $0.assignee == nil || $0.assignee?.lowercased() == "you" }
        }

        // Apply search
        if !searchText.isEmpty {
            items = items.filter { item in
                item.task.localizedCaseInsensitiveContains(searchText) ||
                (item.assignee?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (item.context?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        return items
    }

    private var completedItems: [ActionItem] {
        actionItems.filter { $0.status == .completed }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    private func itemsForGroup(_ group: DueDateGroup) -> [ActionItem] {
        filteredItems.filter { $0.dueDateGroup == group }
            .sorted {
                if $0.priority.sortOrder != $1.priority.sortOrder {
                    return $0.priority.sortOrder < $1.priority.sortOrder
                }
                return ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
            }
    }

    // MARK: - Actions

    private func loadItems() async {
        isLoading = true
        do {
            actionItems = try await ActionItemManager.shared.getAllItems()
        } catch {
            logError("[ActionItemsDashboard] Failed to load: \(error)")
        }
        isLoading = false
    }

    private func loadCounts() async {
        do {
            counts = try await ActionItemManager.shared.getCounts()
        } catch {
            logError("[ActionItemsDashboard] Failed to load counts: \(error)")
        }
    }

    private func completeItem(_ item: ActionItem) {
        Task {
            try? await ActionItemManager.shared.complete(item.id)
        }
    }

    private func reopenItem(_ item: ActionItem) {
        Task {
            try? await ActionItemManager.shared.reopen(item.id)
        }
    }

    private func editItem(_ item: ActionItem) {
        // TODO: Show edit sheet
    }

    private func deleteItem(_ item: ActionItem) {
        Task {
            try? await ActionItemManager.shared.delete(item.id)
        }
    }

    private func navigateToMeeting(_ item: ActionItem) {
        // TODO: Navigate to meeting detail
    }

    private func copyAsMarkdown() {
        Task {
            let openItems = filteredItems
            let markdown = await ActionItemManager.shared.exportAsMarkdown(items: openItems)
            await MainActor.run {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(markdown, forType: .string)
            }
        }
    }

    private func copyAsPlainText() {
        Task {
            let openItems = filteredItems
            let text = await ActionItemManager.shared.exportAsPlainText(items: openItems)
            await MainActor.run {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }
    }

    private func exportToJSON() {
        // TODO: Export to file
    }
}

// MARK: - Dashboard Row

struct ActionItemDashboardRow: View {
    let item: ActionItem
    var onComplete: ((ActionItem) -> Void)?
    var onEdit: ((ActionItem) -> Void)?
    var onDelete: ((ActionItem) -> Void)?
    var onNavigateToMeeting: ((ActionItem) -> Void)?

    @State private var isHovered = false
    @State private var meetingTitle: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Checkbox
            Button(action: { onComplete?(item) }) {
                Image(systemName: item.status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(item.status == .completed ? .brandMint : .brandTextSecondary)
            }
            .buttonStyle(.plain)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(item.task)
                    .font(.system(size: 14))
                    .foregroundColor(item.status == .completed ? .brandTextSecondary : .brandTextPrimary)
                    .strikethrough(item.status == .completed)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    // Assignee
                    if let assignee = item.assignee {
                        HStack(spacing: 4) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 10))
                            Text(assignee)
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.brandTextSecondary)
                    }

                    // Due date
                    if item.status == .open, let dueText = item.formattedDueDate {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 10))
                            Text(dueText)
                        }
                        .font(.system(size: 11))
                        .foregroundColor(item.isOverdue ? .brandCoral : .brandTextSecondary)
                    }

                    // Priority
                    if item.status == .open {
                        Text(item.priority.emoji)
                            .font(.system(size: 10))
                    }

                    // Completed date
                    if item.status == .completed, let completed = item.formattedCompletedDate {
                        Text(completed)
                            .font(.system(size: 11))
                            .foregroundColor(.brandMint)
                    }
                }

                // Meeting reference
                if let title = meetingTitle {
                    Button(action: { onNavigateToMeeting?(item) }) {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 10))
                            Text("From: \(title)")
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.brandViolet.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            // Actions
            if isHovered && item.status == .open {
                HStack(spacing: 4) {
                    if let onEdit = onEdit {
                        BrandIconButton(icon: "pencil", size: 22, action: { onEdit(item) })
                            .help("Edit")
                    }
                    if let onDelete = onDelete {
                        BrandIconButton(icon: "trash", size: 22, color: .brandCoral, action: { onDelete(item) })
                            .help("Delete")
                    }
                }
            } else if item.status == .open {
                BrandSecondaryButton(title: "", icon: "checkmark", size: .small) {
                    onComplete?(item)
                }
                .frame(width: 32)
            } else {
                Button("Undo") {
                    onComplete?(item)
                }
                .font(.system(size: 12))
                .foregroundColor(.brandViolet)
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            item.isOverdue && item.status == .open ?
                Color.brandCoral.opacity(0.05) :
                (isHovered ? Color.brandSurface : Color.clear)
        )
        .overlay(
            item.isOverdue && item.status == .open ?
                Rectangle()
                    .fill(Color.brandCoral)
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)
            : nil,
            alignment: .leading
        )
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
        .task {
            await loadMeetingTitle()
        }
    }

    private func loadMeetingTitle() async {
        do {
            if let meeting = try await DatabaseManager.shared.getMeeting(id: item.meetingId) {
                await MainActor.run {
                    meetingTitle = meeting.title
                }
            }
        } catch {
            // Ignore
        }
    }
}

// MARK: - Stat Badge

struct StatBadge: View {
    let icon: String
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)

            Text("\(count)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)

            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.brandTextSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .cornerRadius(BrandRadius.small)
    }
}

// MARK: - Preview

#Preview("Action Items Dashboard") {
    ActionItemsDashboardView()
        .frame(width: 800, height: 600)
}
