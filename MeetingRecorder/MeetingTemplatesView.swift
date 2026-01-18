//
//  MeetingTemplatesView.swift
//  MeetingRecorder
//
//  Amie-inspired template editor with sections.
//  Each template is a meeting type with multiple sections.
//

import SwiftUI

// MARK: - Meeting Templates View

struct MeetingTemplatesView: View {
    @ObservedObject private var templateManager = MeetingTemplateManager.shared
    @State private var selectedTemplate: MeetingTemplate?
    @State private var searchText = ""
    @State private var showingResetConfirmation = false
    @State private var isCreatingNew = false

    private var filteredTemplates: [MeetingTemplate] {
        if searchText.isEmpty {
            return templateManager.allTemplates
        }
        return templateManager.allTemplates.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.context.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        HSplitView {
            // Left: Template list
            templateListPane
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)

            // Right: Template editor
            if let template = selectedTemplate {
                MeetingTemplateEditorPane(
                    template: binding(for: template),
                    onDelete: {
                        templateManager.deleteTemplate(template)
                        selectedTemplate = templateManager.allTemplates.first
                    }
                )
            } else {
                emptyStateView
            }
        }
        .background(Color.brandBackground)
        .onAppear {
            if selectedTemplate == nil {
                selectedTemplate = templateManager.allTemplates.first
            }
        }
    }

    // MARK: - Template List Pane

    private var templateListPane: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Meeting Templates")
                        .font(.brandDisplay(18, weight: .bold))
                        .foregroundColor(.brandTextPrimary)

                    Spacer()

                    Button(action: { isCreatingNew = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.brandViolet)
                            .frame(width: 28, height: 28)
                            .background(Color.brandViolet.opacity(0.1))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help("Create new template")
                }

                // Search
                BrandSearchField(placeholder: "Search templates...", text: $searchText)

                // Auto-infer toggle
                Toggle(isOn: $templateManager.autoInferMeetingType) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-detect meeting type")
                            .font(.system(size: 12, weight: .medium))
                        Text("Infer template from transcript content")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .padding(.vertical, 4)
            }
            .padding(16)
            .background(Color.white)

            Divider()

            // Template list
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(filteredTemplates) { template in
                        MeetingTemplateRow(
                            template: template,
                            isSelected: selectedTemplate?.id == template.id,
                            isDefault: templateManager.selectedTemplateId == template.id,
                            onSelect: { selectedTemplate = template },
                            onSetDefault: { templateManager.selectTemplate(template) },
                            onDuplicate: {
                                let copy = templateManager.duplicateTemplate(template)
                                selectedTemplate = copy
                            },
                            onToggleEnabled: { templateManager.toggleEnabled(template) }
                        )
                    }
                }
                .padding(8)
            }

            Divider()

            // Footer actions
            HStack {
                Button(action: { showingResetConfirmation = true }) {
                    Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Reset all templates to defaults")

                Spacer()

                Text("\(templateManager.allTemplates.count) templates")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color.brandSurface)
        }
        .background(Color.white)
        .alert("Reset Templates?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                templateManager.resetToDefaults()
                selectedTemplate = templateManager.allTemplates.first
            }
        } message: {
            Text("This will delete all custom templates and restore built-in templates to their original state.")
        }
        .sheet(isPresented: $isCreatingNew) {
            NewMeetingTemplateSheet { newTemplate in
                templateManager.addTemplate(newTemplate)
                selectedTemplate = newTemplate
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.brandViolet.opacity(0.3))

            Text("Select a template")
                .font(.brandDisplay(18, weight: .semibold))

            Text("Choose a template from the list to edit")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.brandBackground)
    }

    // MARK: - Helpers

    private func binding(for template: MeetingTemplate) -> Binding<MeetingTemplate> {
        Binding(
            get: {
                templateManager.allTemplates.first { $0.id == template.id } ?? template
            },
            set: { newValue in
                templateManager.updateTemplate(newValue)
                selectedTemplate = newValue
            }
        )
    }
}

// MARK: - Template Row

struct MeetingTemplateRow: View {
    let template: MeetingTemplate
    let isSelected: Bool
    let isDefault: Bool
    var onSelect: () -> Void
    var onSetDefault: () -> Void
    var onDuplicate: () -> Void
    var onToggleEnabled: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.brandViolet : Color.brandViolet.opacity(0.1))
                        .frame(width: 36, height: 36)

                    Image(systemName: template.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(isSelected ? .white : .brandViolet)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(template.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(isSelected ? .white : .brandTextPrimary)

                        if template.isBuiltIn {
                            Text("Built-in")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? Color.white.opacity(0.2) : Color.brandSurface)
                                )
                        }

                        if isDefault {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(isSelected ? .white : .brandMint)
                        }
                    }

                    Text("\(template.sections.count) sections")
                        .font(.system(size: 11))
                        .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                }

                Spacer()

                // Enabled toggle (visible on hover)
                if isHovered && !isSelected {
                    Toggle("", isOn: Binding(
                        get: { template.isEnabled },
                        set: { _ in onToggleEnabled() }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.brandViolet : (isHovered ? Color.brandViolet.opacity(0.05) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button {
                onSetDefault()
            } label: {
                Label("Set as Default", systemImage: "checkmark.circle")
            }

            Button {
                onDuplicate()
            } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
            }

            Button {
                onToggleEnabled()
            } label: {
                Label(template.isEnabled ? "Disable" : "Enable", systemImage: template.isEnabled ? "eye.slash" : "eye")
            }
        }
        .opacity(template.isEnabled ? 1 : 0.5)
    }
}

// MARK: - Template Editor Pane

struct MeetingTemplateEditorPane: View {
    @Binding var template: MeetingTemplate
    var onDelete: () -> Void

    @State private var editedName: String = ""
    @State private var editedContext: String = ""
    @State private var editedIcon: String = ""
    @State private var showingDeleteConfirmation = false
    @State private var showingIconPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                headerSection

                Divider()

                // Context
                contextSection

                Divider()

                // Sections
                sectionsSection

                Spacer(minLength: 40)
            }
            .padding(24)
        }
        .background(Color.brandBackground)
        .onAppear {
            editedName = template.name
            editedContext = template.context
            editedIcon = template.icon
        }
        .onChange(of: template.id) { _, _ in
            editedName = template.name
            editedContext = template.context
            editedIcon = template.icon
        }
        .alert("Delete Template?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { onDelete() }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(spacing: 16) {
            // Icon button
            Button(action: { showingIconPicker = true }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.brandViolet.opacity(0.1))
                        .frame(width: 56, height: 56)

                    Image(systemName: editedIcon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.brandViolet)
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingIconPicker) {
                IconPickerView(selectedIcon: $editedIcon) {
                    template.icon = editedIcon
                    showingIconPicker = false
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                // Name
                if template.isBuiltIn {
                    Text(template.name)
                        .font(.brandDisplay(24, weight: .bold))
                        .foregroundColor(.brandTextPrimary)
                } else {
                    TextField("Template Name", text: $editedName)
                        .font(.brandDisplay(24, weight: .bold))
                        .textFieldStyle(.plain)
                        .onSubmit {
                            template.name = editedName
                        }
                }

                // Built-in badge
                if template.isBuiltIn {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                        Text("Built-in template (read-only)")
                            .font(.system(size: 11))
                    }
                    .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Delete button (only for custom templates)
            if !template.isBuiltIn {
                Button(action: { showingDeleteConfirmation = true }) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundColor(.brandCoral)
                        .frame(width: 32, height: 32)
                        .background(Color.brandCoral.opacity(0.1))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .help("Delete template")
            }
        }
    }

    // MARK: - Context Section

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Context")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            Text("When to use this template")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            if template.isBuiltIn {
                Text(template.context)
                    .font(.system(size: 14))
                    .foregroundColor(.brandTextPrimary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.brandSurface)
                    .cornerRadius(8)
            } else {
                TextEditor(text: $editedContext)
                    .font(.system(size: 14))
                    .frame(minHeight: 60, maxHeight: 100)
                    .padding(8)
                    .background(Color.brandSurface)
                    .cornerRadius(8)
                    .onChange(of: editedContext) { _, newValue in
                        template.context = newValue
                    }
            }
        }
    }

    // MARK: - Sections Section

    private var sectionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Sections")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                Spacer()

                if !template.isBuiltIn {
                    Button(action: addSection) {
                        Label("New section", systemImage: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.brandViolet)
                    }
                    .buttonStyle(.plain)
                }
            }

            ForEach(template.sortedSections.indices, id: \.self) { index in
                let section = template.sortedSections[index]
                SectionEditorCard(
                    section: sectionBinding(for: section),
                    isReadOnly: template.isBuiltIn,
                    onDelete: {
                        removeSection(section)
                    },
                    onMoveUp: index > 0 ? { moveSection(section, direction: -1) } : nil,
                    onMoveDown: index < template.sortedSections.count - 1 ? { moveSection(section, direction: 1) } : nil
                )
            }
        }
    }

    // MARK: - Helpers

    private func sectionBinding(for section: TemplateSection) -> Binding<TemplateSection> {
        Binding(
            get: {
                template.sections.first { $0.id == section.id } ?? section
            },
            set: { newValue in
                if let index = template.sections.firstIndex(where: { $0.id == section.id }) {
                    template.sections[index] = newValue
                }
            }
        )
    }

    private func addSection() {
        let newSection = TemplateSection(
            name: "New Section",
            prompt: "Describe what to extract...",
            sortOrder: template.sections.count
        )
        template.sections.append(newSection)
    }

    private func removeSection(_ section: TemplateSection) {
        template.sections.removeAll { $0.id == section.id }
        // Reorder remaining sections
        for i in template.sections.indices {
            template.sections[i].sortOrder = i
        }
    }

    private func moveSection(_ section: TemplateSection, direction: Int) {
        guard let index = template.sections.firstIndex(where: { $0.id == section.id }) else { return }
        let newIndex = index + direction
        guard newIndex >= 0 && newIndex < template.sections.count else { return }

        // Swap sort orders
        let currentOrder = template.sections[index].sortOrder
        template.sections[index].sortOrder = template.sections[newIndex].sortOrder
        template.sections[newIndex].sortOrder = currentOrder
    }
}

// MARK: - Section Editor Card

struct SectionEditorCard: View {
    @Binding var section: TemplateSection
    let isReadOnly: Bool
    var onDelete: () -> Void
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?

    @State private var isHovered = false
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                // Drag handle (visual only for now)
                if !isReadOnly {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.5))
                }

                // Section name
                if isReadOnly {
                    Text(section.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.brandTextPrimary)
                } else {
                    TextField("Section Name", text: $section.name)
                        .font(.system(size: 14, weight: .semibold))
                        .textFieldStyle(.plain)
                }

                Spacer()

                // Move buttons
                if !isReadOnly && isHovered {
                    HStack(spacing: 4) {
                        if let moveUp = onMoveUp {
                            Button(action: moveUp) {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        if let moveDown = onMoveDown {
                            Button(action: moveDown) {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Delete button
                if !isReadOnly && isHovered {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }

                // Expand/collapse
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.brandSurface)

            // Prompt content
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    if isReadOnly {
                        Text(section.prompt)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    } else {
                        TextEditor(text: $section.prompt)
                            .font(.system(size: 13))
                            .frame(minHeight: 60, maxHeight: 120)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                    }
                }
                .padding(16)
            }
        }
        .background(Color.white)
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.brandBorder, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Icon Picker

struct IconPickerView: View {
    @Binding var selectedIcon: String
    var onDismiss: () -> Void

    private let icons = [
        "doc.text.fill", "person.2.fill", "lightbulb.fill", "dollarsign.circle.fill",
        "person.crop.rectangle.fill", "person.3.fill", "chevron.left.forwardslash.chevron.right",
        "chart.bar.fill", "calendar", "checkmark.circle.fill", "star.fill",
        "heart.fill", "bolt.fill", "gear", "folder.fill", "tray.fill"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Icon")
                .font(.system(size: 13, weight: .semibold))

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(44), spacing: 8), count: 4), spacing: 8) {
                ForEach(icons, id: \.self) { icon in
                    Button(action: {
                        selectedIcon = icon
                        onDismiss()
                    }) {
                        Image(systemName: icon)
                            .font(.system(size: 18))
                            .foregroundColor(selectedIcon == icon ? .white : .brandViolet)
                            .frame(width: 40, height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedIcon == icon ? Color.brandViolet : Color.brandViolet.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .frame(width: 220)
    }
}

// MARK: - New Template Sheet

struct NewMeetingTemplateSheet: View {
    var onCreate: (MeetingTemplate) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var context = ""
    @State private var selectedIcon = "doc.text.fill"

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Meeting Template")
                    .font(.brandDisplay(16, weight: .bold))

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            // Form
            VStack(alignment: .leading, spacing: 20) {
                // Name
                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)

                    TextField("e.g., Product Review", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(10)
                        .background(Color.brandSurface)
                        .cornerRadius(8)
                }

                // Context
                VStack(alignment: .leading, spacing: 6) {
                    Text("Context")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)

                    TextEditor(text: $context)
                        .font(.system(size: 14))
                        .frame(height: 80)
                        .padding(6)
                        .background(Color.brandSurface)
                        .cornerRadius(8)
                }

                // Hint
                Text("You can add sections after creating the template.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(20)

            Divider()

            // Actions
            HStack {
                Spacer()

                BrandSecondaryButton(title: "Cancel") {
                    dismiss()
                }

                BrandPrimaryButton(title: "Create", icon: "plus", isDisabled: !isValid) {
                    let newTemplate = MeetingTemplate(
                        name: name.trimmingCharacters(in: .whitespaces),
                        context: context.trimmingCharacters(in: .whitespaces),
                        icon: selectedIcon,
                        sections: [
                            TemplateSection(name: "Summary", prompt: "Summarize the meeting.", sortOrder: 0)
                        ]
                    )
                    onCreate(newTemplate)
                    dismiss()
                }
            }
            .padding(20)
        }
        .frame(width: 400)
        .background(Color.brandBackground)
    }
}

// MARK: - Preview

#Preview("Meeting Templates View") {
    MeetingTemplatesView()
        .frame(width: 1100, height: 700)
}
