//
//  ActionItemViews.swift
//  MeetingRecorder
//
//  Views for displaying and managing action items
//

import SwiftUI

// MARK: - Action Item Row

/// A single action item row with checkbox, details, and hover actions
struct ActionItemRow: View {
    let item: ActionItem
    var meetingTitle: String? = nil
    var showMeetingContext: Bool = false
    var onComplete: ((ActionItem) -> Void)?
    var onEdit: ((ActionItem) -> Void)?
    var onDelete: ((ActionItem) -> Void)?
    var onMoveToBacklog: ((ActionItem) -> Void)?
    var onUpdateDueDate: ((ActionItem, Date?) -> Void)?
    var onUpdateAssignee: ((ActionItem, String?) -> Void)?

    @State private var isHovered = false
    @State private var showDueDatePicker = false
    @State private var showAssigneePicker = false
    @State private var tempDueDate: Date = Date()
    @State private var tempAssignee: String = ""

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Checkbox
            Button(action: { onComplete?(item) }) {
                Image(systemName: checkmarkIcon)
                    .font(.system(size: 20))
                    .foregroundColor(checkmarkColor)
            }
            .buttonStyle(.plain)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                // Task text
                Text(item.task)
                    .font(.system(size: 14))
                    .foregroundColor(item.status == .completed ? .brandTextSecondary : .brandTextPrimary)
                    .strikethrough(item.status == .completed)

                // Metadata row with inline edit buttons
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
                                .font(.system(size: 12))
                        }
                        .foregroundColor(item.assignee != nil ? .brandTextSecondary : .brandTextSecondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showAssigneePicker) {
                        assigneePopover
                    }

                    // Due date button (clickable to edit)
                    Button(action: {
                        tempDueDate = item.dueDate ?? Date()
                        showDueDatePicker = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 10))
                            Text(item.formattedDueDate ?? "Set due date")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(dueDateColor)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showDueDatePicker) {
                        dueDatePopover
                    }

                    // Priority badge
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
                            .font(.system(size: 12))
                            .foregroundColor(.brandMint)
                    }
                }

                // Meeting context (for dashboard view)
                if showMeetingContext, let title = meetingTitle {
                    Text("From: \(title)")
                        .font(.system(size: 11))
                        .foregroundColor(.brandTextSecondary.opacity(0.7))
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
                            Button(action: { onComplete?(item) }) {
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
                // Undo button for completed items
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
            RoundedRectangle(cornerRadius: BrandRadius.small)
                .fill(isHovered ? Color.brandSurface : Color.clear)
        )
        .overlay(
            // Overdue indicator
            item.isOverdue && item.status == .open ?
                RoundedRectangle(cornerRadius: BrandRadius.small)
                    .fill(Color.brandCoral.opacity(0.1))
                    .overlay(
                        Rectangle()
                            .fill(Color.brandCoral)
                            .frame(width: 3),
                        alignment: .leading
                    )
                    .clipShape(RoundedRectangle(cornerRadius: BrandRadius.small))
            : nil
        )
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
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
}

// MARK: - Action Items List (for Meeting Detail)

/// Action items list for the meeting detail view
struct MeetingActionItemsList: View {
    let meetingId: UUID
    @State private var actionItems: [ActionItem] = []
    @State private var isLoading = true
    @State private var showAddSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("\(openItems.count) action items")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.brandTextSecondary)

                Spacer()

                Button(action: { showAddSheet = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Add")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.brandViolet)
                }
                .buttonStyle(.plain)

                Menu {
                    Button("Copy as Markdown") { copyAsMarkdown() }
                    Button("Copy as Plain Text") { copyAsPlainText() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.brandViolet)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 70)
            }

            if isLoading {
                HStack {
                    Spacer()
                    BrandLoadingIndicator(size: .medium)
                    Spacer()
                }
                .padding(.vertical, 40)
            } else if actionItems.isEmpty {
                emptyState
            } else {
                // Open items
                if !openItems.isEmpty {
                    VStack(spacing: 2) {
                        ForEach(openItems) { item in
                            ActionItemRow(
                                item: item,
                                onComplete: { completeItem($0) },
                                onEdit: { editItem($0) },
                                onDelete: { deleteItem($0) },
                                onMoveToBacklog: { moveToBacklog($0) },
                                onUpdateDueDate: { updateDueDate($0, $1) },
                                onUpdateAssignee: { updateAssignee($0, $1) }
                            )
                        }
                    }
                }

                // Backlog items (collapsible, no badge contribution)
                if !backlogItems.isEmpty {
                    DisclosureGroup {
                        VStack(spacing: 2) {
                            ForEach(backlogItems) { item in
                                ActionItemRow(
                                    item: item,
                                    onComplete: { restoreFromBacklog($0) },
                                    onEdit: { editItem($0) },
                                    onDelete: { deleteItem($0) },
                                    onUpdateDueDate: { updateDueDate($0, $1) },
                                    onUpdateAssignee: { updateAssignee($0, $1) }
                                )
                            }
                        }
                    } label: {
                        Text("📦 Backlog (\(backlogItems.count))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.brandTextSecondary)
                    }
                    .padding(.top, 8)
                }

                // Completed items (collapsible)
                if !completedItems.isEmpty {
                    DisclosureGroup {
                        VStack(spacing: 2) {
                            ForEach(completedItems) { item in
                                ActionItemRow(
                                    item: item,
                                    onComplete: { reopenItem($0) }
                                )
                            }
                        }
                    } label: {
                        Text("Completed (\(completedItems.count))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.brandTextSecondary)
                    }
                    .padding(.top, 8)
                }
            }
        }
        .task {
            await loadItems()
        }
        .onReceive(NotificationCenter.default.publisher(for: .actionItemsDidChange)) { _ in
            Task { await loadItems() }
        }
        .sheet(isPresented: $showAddSheet) {
            ActionItemEditSheet(meetingId: meetingId, onSave: { newItem in
                Task {
                    try? await ActionItemManager.shared.insert(newItem)
                }
            })
        }
    }

    private var openItems: [ActionItem] {
        actionItems.filter { $0.status == .open }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    private var backlogItems: [ActionItem] {
        actionItems.filter { $0.status == .backlog }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var completedItems: [ActionItem] {
        actionItems.filter { $0.status == .completed }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checklist")
                .font(.system(size: 48))
                .foregroundColor(.brandViolet.opacity(0.4))

            Text("No action items from this meeting")
                .font(.brandDisplay(16, weight: .medium))
                .foregroundColor(.brandTextSecondary)

            Text("Generate a brief to extract action items or add them manually")
                .font(.brandDisplay(12))
                .foregroundColor(.brandTextSecondary.opacity(0.7))
                .multilineTextAlignment(.center)

            Button(action: { showAddSheet = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("Add Manually")
                }
                .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundColor(.brandViolet)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func loadItems() async {
        isLoading = true
        do {
            actionItems = try await ActionItemManager.shared.getItemsForMeeting(meetingId)
        } catch {
            logError("[MeetingActionItemsList] Failed to load items: \(error)")
        }
        isLoading = false
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
            let markdown = await ActionItemManager.shared.exportAsMarkdown(items: actionItems)
            await MainActor.run {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(markdown, forType: .string)
            }
        }
    }

    private func copyAsPlainText() {
        Task {
            let text = await ActionItemManager.shared.exportAsPlainText(items: actionItems)
            await MainActor.run {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }
    }
}

// MARK: - Action Item Edit Sheet

struct ActionItemEditSheet: View {
    let meetingId: UUID
    var existingItem: ActionItem? = nil
    var onSave: (ActionItem) -> Void
    var onDelete: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var task: String = ""
    @State private var assignee: String = ""
    @State private var dueDate: Date? = nil
    @State private var hasDueDate: Bool = false
    @State private var priority: ActionItem.Priority = .medium
    @State private var context: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(existingItem == nil ? "Add Action Item" : "Edit Action Item")
                    .font(.brandDisplay(16, weight: .semibold))

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.brandTextSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Form
            VStack(alignment: .leading, spacing: 16) {
                // Task
                VStack(alignment: .leading, spacing: 6) {
                    Text("Task")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.brandTextSecondary)

                    TextField("What needs to be done?", text: $task)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(10)
                        .background(Color.brandSurface)
                        .cornerRadius(BrandRadius.small)
                        .overlay(
                            RoundedRectangle(cornerRadius: BrandRadius.small)
                                .stroke(Color.brandBorder, lineWidth: 1)
                        )
                }

                // Assignee
                VStack(alignment: .leading, spacing: 6) {
                    Text("Assignee")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.brandTextSecondary)

                    TextField("Who's responsible?", text: $assignee)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(10)
                        .background(Color.brandSurface)
                        .cornerRadius(BrandRadius.small)
                        .overlay(
                            RoundedRectangle(cornerRadius: BrandRadius.small)
                                .stroke(Color.brandBorder, lineWidth: 1)
                        )
                }

                // Due Date & Priority
                HStack(spacing: 16) {
                    // Due Date
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Due Date")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.brandTextSecondary)

                        HStack {
                            Toggle("", isOn: $hasDueDate)
                                .labelsHidden()
                                .toggleStyle(.checkbox)

                            if hasDueDate {
                                DatePicker("", selection: Binding(
                                    get: { dueDate ?? Date() },
                                    set: { dueDate = $0 }
                                ), displayedComponents: .date)
                                .labelsHidden()
                            } else {
                                Text("No due date")
                                    .font(.system(size: 13))
                                    .foregroundColor(.brandTextSecondary)
                            }
                        }
                    }

                    // Priority
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Priority")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.brandTextSecondary)

                        Picker("", selection: $priority) {
                            ForEach(ActionItem.Priority.allCases, id: \.self) { p in
                                Text("\(p.emoji) \(p.displayName)").tag(p)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                    }
                }

                // Context
                VStack(alignment: .leading, spacing: 6) {
                    Text("Context (optional)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.brandTextSecondary)

                    TextField("Additional notes...", text: $context, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .lineLimit(3...5)
                        .padding(10)
                        .background(Color.brandSurface)
                        .cornerRadius(BrandRadius.small)
                        .overlay(
                            RoundedRectangle(cornerRadius: BrandRadius.small)
                                .stroke(Color.brandBorder, lineWidth: 1)
                        )
                }
            }
            .padding()

            Divider()

            // Actions
            HStack {
                if let onDelete = onDelete {
                    Button("Delete", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                    .foregroundColor(.brandCoral)
                }

                Spacer()

                BrandSecondaryButton(title: "Cancel", size: .medium) {
                    dismiss()
                }

                BrandPrimaryButton(title: existingItem == nil ? "Add Item" : "Save Changes", size: .medium) {
                    save()
                }
                .disabled(task.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 420)
        .background(Color.brandBackground)
        .onAppear {
            if let item = existingItem {
                task = item.task
                assignee = item.assignee ?? ""
                dueDate = item.dueDate
                hasDueDate = item.dueDate != nil
                priority = item.priority
                context = item.context ?? ""
            }
        }
    }

    private func save() {
        let item = ActionItem(
            id: existingItem?.id ?? UUID(),
            meetingId: meetingId,
            task: task.trimmingCharacters(in: .whitespaces),
            assignee: assignee.isEmpty ? nil : assignee,
            dueDate: hasDueDate ? dueDate : nil,
            priority: priority,
            context: context.isEmpty ? nil : context,
            status: existingItem?.status ?? .open,
            createdAt: existingItem?.createdAt ?? Date()
        )
        onSave(item)
        dismiss()
    }
}

// MARK: - Brief Content View (Markdown)

/// Displays the structured meeting brief with markdown rendering
struct BriefContentView: View {
    let meeting: Meeting
    var onGenerateBrief: (() async -> Void)?
    var onCitationTap: ((TranscriptCitation) -> Void)? = nil  // Optional handler for citation taps
    @State private var isGenerating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isGenerating {
                // Loading state - show loading indicator (for both initial and regenerate)
                VStack(spacing: 16) {
                    BrandLoadingIndicator(size: .large)
                    Text(meeting.meetingBrief != nil ? "Regenerating brief..." : "Generating brief...")
                        .font(.brandDisplay(14))
                        .foregroundColor(.brandTextSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 80)
            } else if let brief = meeting.meetingBrief {
                // Render brief as markdown with citation support
                MarkdownTextView(
                    text: brief.markdown,
                    speakerNameResolver: { speakerId in
                        // Resolve speaker ID to name from meeting's speaker labels
                        meeting.speakerName(for: speakerId)
                    },
                    onCitationTap: onCitationTap
                )

                // Footer with generation info
                HStack {
                    Text("Generated by \(brief.provider)")
                        .font(.system(size: 11))
                        .foregroundColor(.brandTextSecondary.opacity(0.7))

                    Text("•")
                        .foregroundColor(.brandTextSecondary.opacity(0.5))

                    Text(brief.generatedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 11))
                        .foregroundColor(.brandTextSecondary.opacity(0.7))

                    Spacer()

                    if let onGenerateBrief = onGenerateBrief {
                        Button(action: {
                            isGenerating = true
                            Task {
                                await onGenerateBrief()
                                isGenerating = false
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                Text("Regenerate")
                            }
                            .font(.system(size: 11))
                            .foregroundColor(.brandViolet)
                        }
                        .buttonStyle(.plain)
                        .disabled(isGenerating)
                    }
                }
                .padding(.top, 8)
            } else {
                // No brief yet - empty state
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.brandViolet.opacity(0.4))

                    Text("No meeting brief yet")
                        .font(.brandDisplay(16, weight: .medium))
                        .foregroundColor(.brandTextSecondary)

                    if meeting.transcript != nil {
                        if let onGenerateBrief = onGenerateBrief {
                            BrandPrimaryButton(
                                title: "Generate Brief",
                                icon: "sparkles",
                                size: .medium,
                                action: {
                                    isGenerating = true
                                    Task {
                                        await onGenerateBrief()
                                        isGenerating = false
                                    }
                                }
                            )
                        }

                        Text("AI will extract key points, decisions, and action items")
                            .font(.brandDisplay(12))
                            .foregroundColor(.brandTextSecondary.opacity(0.7))
                    } else {
                        Text("Transcript must be ready before generating a brief")
                            .font(.brandDisplay(12))
                            .foregroundColor(.brandTextSecondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            }
        }
    }
}

// MARK: - Markdown Text View

/// Renders markdown text with proper styling - handles full markdown including headers, lists, and citations
struct MarkdownTextView: View {
    let text: String
    var speakerNameResolver: ((String) -> String?)? = nil  // Resolves speaker IDs to names
    var onCitationTap: ((TranscriptCitation) -> Void)? = nil  // Callback when citation is tapped

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(parseMarkdownBlocks().enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
        .textSelection(.enabled)
    }

    private enum MarkdownBlock: Hashable {
        case heading2(String)
        case heading3(String)
        case paragraph(String)
        case bulletList([String])
        case bold(String)
    }

    private func parseMarkdownBlocks() -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var currentList: [String] = []
        let lines = text.components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Flush any pending list
            if !trimmed.hasPrefix("- ") && !currentList.isEmpty {
                blocks.append(.bulletList(currentList))
                currentList = []
            }

            if trimmed.isEmpty {
                continue
            } else if trimmed.hasPrefix("## ") {
                let content = String(trimmed.dropFirst(3))
                blocks.append(.heading2(content))
            } else if trimmed.hasPrefix("### ") {
                let content = String(trimmed.dropFirst(4))
                blocks.append(.heading3(content))
            } else if trimmed.hasPrefix("- ") {
                let content = String(trimmed.dropFirst(2))
                currentList.append(content)
            } else if trimmed.hasPrefix("**") && trimmed.hasSuffix("**") && trimmed.count > 4 {
                // Standalone bold line
                let content = String(trimmed.dropFirst(2).dropLast(2))
                blocks.append(.bold(content))
            } else {
                blocks.append(.paragraph(trimmed))
            }
        }

        // Flush any remaining list
        if !currentList.isEmpty {
            blocks.append(.bulletList(currentList))
        }

        return blocks
    }

    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading2(let text):
            CitationAwareText(
                text: text,
                font: .system(size: 16, weight: .semibold),
                speakerNameResolver: speakerNameResolver,
                onCitationTap: onCitationTap
            )
            .padding(.top, 8)

        case .heading3(let text):
            CitationAwareText(
                text: text,
                font: .system(size: 14, weight: .semibold),
                speakerNameResolver: speakerNameResolver,
                onCitationTap: onCitationTap
            )
            .padding(.top, 4)

        case .paragraph(let text):
            CitationAwareText(
                text: text,
                font: .system(size: 14),
                speakerNameResolver: speakerNameResolver,
                onCitationTap: onCitationTap
            )

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(.system(size: 14))
                            .foregroundColor(.brandTextSecondary)
                        CitationAwareText(
                            text: item,
                            font: .system(size: 14),
                            speakerNameResolver: speakerNameResolver,
                            onCitationTap: onCitationTap
                        )
                    }
                }
            }

        case .bold(let text):
            Text(text)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.brandTextSecondary)
        }
    }
}

// MARK: - Citation Aware Text

/// Renders text with inline citation badges
struct CitationAwareText: View {
    let text: String
    var font: Font = .system(size: 14)
    var speakerNameResolver: ((String) -> String?)? = nil
    var onCitationTap: ((TranscriptCitation) -> Void)? = nil

    @State private var selectedCitation: TranscriptCitation? = nil

    var body: some View {
        let segments = parseTextWithCitations(text)

        CitationFlowLayout(spacing: 4) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let content):
                    Text(renderInlineMarkdown(content))
                        .font(font)
                        .foregroundColor(.brandTextPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                case .citation(let citation):
                    CitationBadge(
                        citation: citation,
                        speakerName: resolveSpeakerName(citation),
                        onTap: {
                            if let onCitationTap = onCitationTap {
                                onCitationTap(citation)
                            } else {
                                selectedCitation = citation
                            }
                        }
                    )
                    .popover(isPresented: Binding(
                        get: { selectedCitation?.id == citation.id },
                        set: { if !$0 { selectedCitation = nil } }
                    )) {
                        CitationPopover(
                            citation: citation,
                            speakerName: resolveSpeakerName(citation)
                        )
                    }
                }
            }
        }
    }

    private func resolveSpeakerName(_ citation: TranscriptCitation) -> String? {
        if let name = citation.speakerName {
            return name
        }
        if let speakerId = citation.speakerId, let resolver = speakerNameResolver {
            return resolver(speakerId)
        }
        return citation.speakerId
    }

    private enum TextSegment {
        case text(String)
        case citation(TranscriptCitation)
    }

    private func parseTextWithCitations(_ text: String) -> [TextSegment] {
        let parsed = CitationParser.parse(text)

        if parsed.isEmpty {
            return [.text(text)]
        }

        var segments: [TextSegment] = []
        var currentIndex = 0
        let nsString = text as NSString

        for item in parsed {
            // Add text before this citation
            if item.range.location > currentIndex {
                let textRange = NSRange(location: currentIndex, length: item.range.location - currentIndex)
                let textContent = nsString.substring(with: textRange)
                if !textContent.trimmingCharacters(in: .whitespaces).isEmpty {
                    segments.append(.text(textContent))
                }
            }

            // Add the citation
            segments.append(.citation(item.citation))

            currentIndex = item.range.location + item.range.length
        }

        // Add remaining text
        if currentIndex < nsString.length {
            let textContent = nsString.substring(from: currentIndex)
            if !textContent.trimmingCharacters(in: .whitespaces).isEmpty {
                segments.append(.text(textContent))
            }
        }

        return segments
    }

    private func renderInlineMarkdown(_ text: String) -> AttributedString {
        do {
            let result = try AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
            return result
        } catch {
            return AttributedString(text)
        }
    }
}

// MARK: - Citation Badge

/// A small inline badge that represents a citation reference
struct CitationBadge: View {
    let citation: TranscriptCitation
    var speakerName: String? = nil
    var onTap: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 4) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 8))

                Text(citation.formattedStartTime)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))

                if let speaker = speakerName ?? citation.speakerName ?? citation.speakerId {
                    Text("•")
                        .font(.system(size: 8))
                    Text(speaker)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
            }
            .foregroundColor(isHovered ? .white : .brandViolet)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? Color.brandViolet : Color.brandViolet.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.brandViolet.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Click to see full quote")
    }
}

// MARK: - Citation Popover

/// Popover content showing the full citation context
struct CitationPopover: View {
    let citation: TranscriptCitation
    var speakerName: String? = nil
    var onPlayTap: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with speaker and timestamp
            HStack(spacing: 8) {
                // Speaker avatar
                Circle()
                    .fill(speakerColor)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Text(speakerInitial)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(displaySpeaker)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.brandTextPrimary)

                    Text(citation.formattedTimeRange)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.brandTextSecondary)
                }

                Spacer()

                // Play button (if handler provided)
                if let onPlayTap = onPlayTap {
                    Button(action: onPlayTap) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.brandViolet)
                    }
                    .buttonStyle(.plain)
                    .help("Play from this moment")
                }
            }

            Divider()

            // Quote text
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 12))
                    .foregroundColor(.brandTextSecondary)

                Text(citation.text)
                    .font(.system(size: 14))
                    .foregroundColor(.brandTextPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(12)
            .background(Color.brandSurface.opacity(0.5))
            .cornerRadius(8)
        }
        .padding(16)
        .frame(width: 320)
    }

    private var displaySpeaker: String {
        speakerName ?? citation.speakerName ?? citation.speakerId ?? "Unknown Speaker"
    }

    private var speakerInitial: String {
        String(displaySpeaker.prefix(1)).uppercased()
    }

    private var speakerColor: Color {
        // Generate consistent color from speaker ID
        let colors: [Color] = [.blue, .purple, .orange, .green, .pink, .teal, .indigo, .mint]
        let hash = displaySpeaker.hashValue
        return colors[abs(hash) % colors.count]
    }
}

// MARK: - Citation Flow Layout

/// A layout that flows items horizontally and wraps to new lines (for citation text)
struct CitationFlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)

        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var frames: [CGRect] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                // Wrap to next line
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            frames.append(CGRect(x: currentX, y: currentY, width: size.width, height: size.height))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX - spacing)
        }

        return (
            size: CGSize(width: totalWidth, height: currentY + lineHeight),
            frames: frames
        )
    }
}

// MARK: - Home Widget

/// Action items summary widget for the home screen
struct ActionItemsHomeWidget: View {
    @Binding var selectedTab: NavigationItem
    @State private var actionItems: [ActionItem] = []
    @State private var counts = ActionItemCounts()
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "checklist")
                        .font(.system(size: 16))
                        .foregroundColor(.brandViolet)

                    Text("Action Items")
                        .font(.brandDisplay(18, weight: .semibold))
                        .foregroundColor(.brandTextPrimary)
                }

                Spacer()

                Button(action: { selectedTab = .actionItems }) {
                    HStack(spacing: 4) {
                        Text("See All")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10))
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.brandViolet)
                }
                .buttonStyle(.plain)
            }

            // Stats row
            if counts.hasUrgent || counts.totalOpen > 0 {
                HStack(spacing: 16) {
                    if counts.overdue > 0 {
                        HStack(spacing: 4) {
                            Text("🔴")
                                .font(.system(size: 10))
                            Text("\(counts.overdue) overdue")
                                .font(.system(size: 12))
                                .foregroundColor(.brandCoral)
                        }
                    }

                    if counts.dueToday > 0 {
                        HStack(spacing: 4) {
                            Text("📅")
                                .font(.system(size: 10))
                            Text("\(counts.dueToday) due today")
                                .font(.system(size: 12))
                                .foregroundColor(.brandAmber)
                        }
                    }

                    if counts.dueThisWeek > 0 {
                        HStack(spacing: 4) {
                            Text("📆")
                                .font(.system(size: 10))
                            Text("\(counts.dueThisWeek) this week")
                                .font(.system(size: 12))
                                .foregroundColor(.brandTextSecondary)
                        }
                    }

                    Spacer()
                }
            }

            // Items list
            if isLoading {
                HStack {
                    Spacer()
                    BrandLoadingIndicator(size: .small)
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if actionItems.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 28))
                            .foregroundColor(.brandMint.opacity(0.6))
                        Text("All caught up!")
                            .font(.system(size: 13))
                            .foregroundColor(.brandTextSecondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 2) {
                    ForEach(actionItems.prefix(3)) { item in
                        HomeActionItemRow(item: item, onComplete: { completeItem($0) })
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
        .padding(20)
        .background(Color.white)
        .cornerRadius(BrandRadius.medium)
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: BrandRadius.medium)
                .stroke(Color.brandBorder, lineWidth: 1)
        )
        .task {
            await loadData()
        }
        .onReceive(NotificationCenter.default.publisher(for: .actionItemsDidChange)) { _ in
            Task { await loadData() }
        }
    }

    private func loadData() async {
        isLoading = true
        do {
            actionItems = try await ActionItemManager.shared.getOpenItems()
            counts = try await ActionItemManager.shared.getCounts()
        } catch {
            logError("[ActionItemsHomeWidget] Failed to load: \(error)")
        }
        isLoading = false
    }

    private func completeItem(_ item: ActionItem) {
        Task {
            try? await ActionItemManager.shared.complete(item.id)
        }
    }
}

/// Compact action item row for home widget
struct HomeActionItemRow: View {
    let item: ActionItem
    var onComplete: ((ActionItem) -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Button(action: { onComplete?(item) }) {
                Image(systemName: "circle")
                    .font(.system(size: 16))
                    .foregroundColor(.brandTextSecondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.task)
                    .font(.system(size: 13))
                    .foregroundColor(.brandTextPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let assignee = item.assignee {
                        Text(assignee)
                            .font(.system(size: 11))
                            .foregroundColor(.brandTextSecondary)
                    }

                    if let due = item.formattedDueDate {
                        Text("• \(due)")
                            .font(.system(size: 11))
                            .foregroundColor(item.isOverdue ? .brandCoral : .brandTextSecondary)
                    }
                }
            }

            Spacer()

            Button(action: { onComplete?(item) }) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.brandViolet)
                    .padding(6)
                    .background(Color.brandViolet.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Preview

#Preview("Action Item Row") {
    VStack(spacing: 8) {
        ActionItemRow(
            item: ActionItem(
                meetingId: UUID(),
                task: "Send pricing proposal to stakeholders",
                assignee: "Bruno",
                dueDate: Date().addingTimeInterval(86400 * 3),
                priority: .high
            ),
            onComplete: { _ in }
        )

        ActionItemRow(
            item: ActionItem(
                meetingId: UUID(),
                task: "Review competitor analysis",
                assignee: "Sarah",
                dueDate: Date().addingTimeInterval(-86400 * 2),
                priority: .medium
            ),
            onComplete: { _ in }
        )

        ActionItemRow(
            item: ActionItem(
                meetingId: UUID(),
                task: "Schedule follow-up meeting",
                priority: .low,
                status: .completed,
                completedAt: Date()
            ),
            onComplete: { _ in }
        )
    }
    .padding()
    .background(Color.brandBackground)
}
