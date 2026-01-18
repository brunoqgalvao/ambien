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

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Checkbox
            Button(action: { onComplete?(item) }) {
                Image(systemName: item.status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(item.status == .completed ? .brandMint : .brandTextSecondary)
            }
            .buttonStyle(.plain)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                // Task text
                Text(item.task)
                    .font(.system(size: 14))
                    .foregroundColor(item.status == .completed ? .brandTextSecondary : .brandTextPrimary)
                    .strikethrough(item.status == .completed)

                // Metadata row
                HStack(spacing: 8) {
                    // Assignee
                    if let assignee = item.assignee {
                        Text(assignee)
                            .font(.system(size: 12))
                            .foregroundColor(.brandTextSecondary)
                    }

                    // Due date
                    if let dueText = item.formattedDueDate {
                        Text(item.isOverdue ? dueText : dueText)
                            .font(.system(size: 12))
                            .foregroundColor(item.isOverdue ? .brandCoral : .brandTextSecondary)
                    } else if item.status == .completed, let completed = item.formattedCompletedDate {
                        Text(completed)
                            .font(.system(size: 12))
                            .foregroundColor(.brandMint)
                    }

                    // Priority badge
                    if item.status == .open {
                        Text(item.priority.emoji)
                            .font(.system(size: 10))
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

            // Complete button or hover actions
            if item.status == .open {
                if isHovered {
                    HStack(spacing: 4) {
                        if let onEdit = onEdit {
                            BrandIconButton(icon: "pencil", size: 24, action: { onEdit(item) })
                                .help("Edit")
                        }
                        if let onDelete = onDelete {
                            BrandIconButton(icon: "trash", size: 24, color: .brandCoral, action: { onDelete(item) })
                                .help("Delete")
                        }
                    }
                } else {
                    BrandSecondaryButton(title: "", icon: "checkmark", size: .small) {
                        onComplete?(item)
                    }
                    .frame(width: 32)
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
            item.isOverdue ?
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
                                onDelete: { deleteItem($0) }
                            )
                        }
                    }
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
    @State private var isGenerating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let brief = meeting.meetingBrief {
                // Render brief as markdown
                MarkdownTextView(text: brief.markdown)

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
                // No brief yet
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.brandViolet.opacity(0.4))

                    Text("No meeting brief yet")
                        .font(.brandDisplay(16, weight: .medium))
                        .foregroundColor(.brandTextSecondary)

                    if meeting.transcript != nil {
                        if isGenerating {
                            HStack(spacing: 8) {
                                BrandLoadingIndicator(size: .medium)
                                Text("Generating brief...")
                                    .font(.brandDisplay(13))
                                    .foregroundColor(.brandTextSecondary)
                            }
                        } else if let onGenerateBrief = onGenerateBrief {
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

/// Renders markdown text with proper styling
struct MarkdownTextView: View {
    let text: String

    var body: some View {
        Text(attributedText)
            .textSelection(.enabled)
    }

    private var attributedText: AttributedString {
        do {
            var result = try AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
            // Apply base styling
            result.font = .system(size: 14)
            result.foregroundColor = .brandTextPrimary
            return result
        } catch {
            return AttributedString(text)
        }
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
