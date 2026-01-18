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
                        ForEach(DueDateGroup.allCases.filter { $0 != .completed && $0 != .backlog }, id: \.self) { group in
                            let items = itemsForGroup(group)
                            if !items.isEmpty {
                                groupSection(group: group, items: items)
                            }
                        }

                        // Backlog section (collapsible, no badge contribution)
                        if !backlogItems.isEmpty {
                            backlogSection
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
                        onNavigateToMeeting: { navigateToMeeting($0) },
                        onMoveToBacklog: { moveToBacklog($0) },
                        onRestoreFromBacklog: { restoreFromBacklog($0) },
                        onUpdateDueDate: { updateDueDate($0, $1) },
                        onUpdateAssignee: { updateAssignee($0, $1) }
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

    // MARK: - Backlog Section

    @State private var showBacklog = false

    private var backlogSection: some View {
        DisclosureGroup(isExpanded: $showBacklog) {
            VStack(spacing: 2) {
                ForEach(backlogItems) { item in
                    ActionItemDashboardRow(
                        item: item,
                        onComplete: { completeItem($0) },
                        onEdit: { editItem($0) },
                        onDelete: { deleteItem($0) },
                        onNavigateToMeeting: { navigateToMeeting($0) },
                        onRestoreFromBacklog: { restoreFromBacklog($0) },
                        onUpdateDueDate: { updateDueDate($0, $1) },
                        onUpdateAssignee: { updateAssignee($0, $1) }
                    )
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
                Text("📦 BACKLOG")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.brandTextSecondary)

                Text("(\(backlogItems.count))")
                    .font(.system(size: 11))
                    .foregroundColor(.brandTextSecondary.opacity(0.7))

                Text("• Won't count in stats")
                    .font(.system(size: 10))
                    .foregroundColor(.brandTextSecondary.opacity(0.5))
            }
        }
        .accentColor(.brandTextSecondary)
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

    private var backlogItems: [ActionItem] {
        actionItems.filter { $0.status == .backlog }
            .sorted { $0.createdAt > $1.createdAt }
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

    private func moveToBacklog(_ item: ActionItem) {
        Task {
            try? await ActionItemManager.shared.moveToBacklog(item.id)
        }
    }

    private func restoreFromBacklog(_ item: ActionItem) {
        Task {
            try? await ActionItemManager.shared.restoreFromBacklog(item.id)
        }
    }

    private func updateDueDate(_ item: ActionItem, _ newDate: Date?) {
        Task {
            try? await ActionItemManager.shared.updateDueDate(item.id, dueDate: newDate)
        }
    }

    private func updateAssignee(_ item: ActionItem, _ newAssignee: String?) {
        Task {
            try? await ActionItemManager.shared.updateAssignee(item.id, assignee: newAssignee)
        }
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
    var onMoveToBacklog: ((ActionItem) -> Void)?
    var onRestoreFromBacklog: ((ActionItem) -> Void)?
    var onUpdateDueDate: ((ActionItem, Date?) -> Void)?
    var onUpdateAssignee: ((ActionItem, String?) -> Void)?

    @State private var isHovered = false
    @State private var meetingTitle: String?
    @State private var showDueDatePicker = false
    @State private var showAssigneePicker = false
    @State private var tempDueDate: Date = Date()
    @State private var tempAssignee: String = ""

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Checkbox
            Button(action: { onComplete?(item) }) {
                Image(systemName: checkmarkIcon)
                    .font(.system(size: 18))
                    .foregroundColor(checkmarkColor)
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
                    // Assignee button (clickable to edit)
                    Button(action: {
                        tempAssignee = item.assignee ?? ""
                        showAssigneePicker = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 10))
                            Text(item.assignee ?? "Assign")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(item.assignee != nil ? .brandTextSecondary : .brandTextSecondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showAssigneePicker) {
                        assigneePopover
                    }

                    // Due date button (clickable to edit)
                    if item.status == .open || item.status == .backlog {
                        Button(action: {
                            tempDueDate = item.dueDate ?? Date()
                            showDueDatePicker = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 10))
                                Text(item.formattedDueDate ?? "Set due date")
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(dueDateColor)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showDueDatePicker) {
                            dueDatePopover
                        }
                    }

                    // Priority
                    if item.status == .open || item.status == .backlog {
                        Text(item.priority.emoji)
                            .font(.system(size: 10))
                    }

                    // Backlog indicator
                    if item.status == .backlog {
                        Text("Backlog")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.brandTextSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.brandSurface)
                            .cornerRadius(4)
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
            if item.status == .open || item.status == .backlog {
                HStack(spacing: 4) {
                    // Complete button (always visible)
                    BrandSecondaryButton(title: "", icon: "checkmark", size: .small) {
                        onComplete?(item)
                    }
                    .frame(width: 32)

                    // Three-dot menu
                    Menu {
                        Button(action: { onEdit?(item) }) {
                            Label("Edit", systemImage: "pencil")
                        }

                        Divider()

                        // Copy options
                        Button(action: { copyItemAsText() }) {
                            Label("Copy as Text", systemImage: "doc.on.doc")
                        }
                        Button(action: { copyItemAsMarkdown() }) {
                            Label("Copy as Markdown", systemImage: "text.badge.checkmark")
                        }

                        Divider()

                        if item.status == .open {
                            Button(action: { onMoveToBacklog?(item) }) {
                                Label("Move to Backlog", systemImage: "archivebox")
                            }
                        } else if item.status == .backlog {
                            Button(action: { onRestoreFromBacklog?(item) }) {
                                Label("Restore to Open", systemImage: "arrow.uturn.backward")
                            }
                        }

                        Divider()

                        Button(role: .destructive, action: { onDelete?(item) }) {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.brandTextSecondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 28)
                }
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

    // MARK: - Copy Actions

    private func copyItemAsText() {
        var text = item.task
        var details: [String] = []

        if let assignee = item.assignee {
            details.append("@\(assignee)")
        }
        if let due = item.formattedDueDate {
            details.append("Due: \(due)")
        }
        if !details.isEmpty {
            text += " (\(details.joined(separator: ", ")))"
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func copyItemAsMarkdown() {
        let checkbox = item.status == .completed ? "[x]" : "[ ]"
        var text = "- \(checkbox) \(item.task)"
        var details: [String] = []

        if let assignee = item.assignee {
            details.append("**@\(assignee)**")
        }
        if let due = item.formattedDueDate {
            details.append("📅 \(due)")
        }
        details.append(item.priority.emoji)

        if !details.isEmpty {
            text += " — \(details.joined(separator: " "))"
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Computed Properties

    private var checkmarkIcon: String {
        switch item.status {
        case .completed: return "checkmark.circle.fill"
        case .backlog: return "circle.dashed"
        default: return "circle"
        }
    }

    private var checkmarkColor: Color {
        switch item.status {
        case .completed: return .brandMint
        case .backlog: return .brandTextSecondary.opacity(0.5)
        default: return .brandTextSecondary
        }
    }

    private var dueDateColor: Color {
        if item.dueDate == nil {
            return .brandTextSecondary.opacity(0.5)
        } else if item.isOverdue {
            return .brandCoral
        } else {
            return .brandTextSecondary
        }
    }

    // MARK: - Popovers

    private var dueDatePopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Set Due Date")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.brandTextPrimary)

            DatePicker("", selection: $tempDueDate, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.graphical)

            HStack {
                Button("Clear") {
                    onUpdateDueDate?(item, nil)
                    showDueDatePicker = false
                }
                .font(.system(size: 12))
                .foregroundColor(.brandCoral)
                .buttonStyle(.plain)

                Spacer()

                Button("Cancel") {
                    showDueDatePicker = false
                }
                .font(.system(size: 12))
                .foregroundColor(.brandTextSecondary)
                .buttonStyle(.plain)

                Button("Save") {
                    onUpdateDueDate?(item, tempDueDate)
                    showDueDatePicker = false
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.brandViolet)
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(width: 280)
    }

    private var assigneePopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Assign To")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.brandTextPrimary)

            TextField("Enter name...", text: $tempAssignee)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(10)
                .background(Color.brandSurface)
                .cornerRadius(BrandRadius.small)
                .overlay(
                    RoundedRectangle(cornerRadius: BrandRadius.small)
                        .stroke(Color.brandBorder, lineWidth: 1)
                )

            HStack {
                Button("Clear") {
                    onUpdateAssignee?(item, nil)
                    showAssigneePicker = false
                }
                .font(.system(size: 12))
                .foregroundColor(.brandCoral)
                .buttonStyle(.plain)

                Spacer()

                Button("Cancel") {
                    showAssigneePicker = false
                }
                .font(.system(size: 12))
                .foregroundColor(.brandTextSecondary)
                .buttonStyle(.plain)

                Button("Save") {
                    onUpdateAssignee?(item, tempAssignee.isEmpty ? nil : tempAssignee)
                    showAssigneePicker = false
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.brandViolet)
                .buttonStyle(.plain)
            }
        }
        .padding()
        .frame(width: 240)
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
