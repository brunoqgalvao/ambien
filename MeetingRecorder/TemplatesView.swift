//
//  TemplatesView.swift
//  MeetingRecorder
//
//  Full-screen template editor integrated into the main app window.
//  Master-detail layout: template list on left, editor on right.
//

import SwiftUI

// MARK: - Templates View (Main Container)

struct TemplatesView: View {
    @ObservedObject private var templateManager = SummaryTemplateManager.shared
    @State private var selectedTemplate: SummaryTemplate?
    @State private var isCreatingNew = false
    @State private var searchText = ""
    @State private var showingResetConfirmation = false

    private var filteredTemplates: [SummaryTemplate] {
        if searchText.isEmpty {
            return templateManager.allTemplates
        }
        return templateManager.allTemplates.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            TemplatesToolbar(
                searchText: $searchText,
                onNew: {
                    isCreatingNew = true
                    selectedTemplate = nil
                },
                onReset: { showingResetConfirmation = true }
            )

            // Content
            HSplitView {
                // Template List
                TemplateListPane(
                    templates: filteredTemplates,
                    selectedTemplate: $selectedTemplate,
                    selectedTemplateId: templateManager.selectedTemplateId,
                    isCreatingNew: $isCreatingNew,
                    onToggleEnabled: { templateManager.toggleEnabled($0) },
                    onSetDefault: { templateManager.selectTemplate($0) },
                    onDuplicate: { template in
                        let copy = templateManager.duplicateTemplate(template)
                        selectedTemplate = copy
                        isCreatingNew = false
                    },
                    onDelete: { templateManager.deleteTemplate($0) }
                )
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)

                // Editor Pane
                if isCreatingNew {
                    TemplateEditorPane(
                        template: nil,
                        onSave: { newTemplate in
                            templateManager.addTemplate(newTemplate)
                            selectedTemplate = newTemplate
                            isCreatingNew = false
                        },
                        onCancel: {
                            isCreatingNew = false
                        }
                    )
                } else if let template = selectedTemplate {
                    TemplateEditorPane(
                        template: template,
                        onSave: { updatedTemplate in
                            templateManager.updateTemplate(updatedTemplate)
                            selectedTemplate = updatedTemplate
                        },
                        onCancel: nil
                    )
                } else {
                    EmptyTemplateView()
                }
            }
        }
        .background(Color.brandBackground)
        .alert("Reset All Templates?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                templateManager.resetToDefaults()
                selectedTemplate = nil
            }
        } message: {
            Text("This will remove all custom templates and restore defaults. This cannot be undone.")
        }
    }
}

// MARK: - Toolbar

struct TemplatesToolbar: View {
    @Binding var searchText: String
    var onNew: () -> Void
    var onReset: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Title
            VStack(alignment: .leading, spacing: 2) {
                Text("Summary Templates")
                    .font(.brandDisplay(20, weight: .semibold))
                    .foregroundColor(.brandTextPrimary)

                Text("Customize how your transcripts are processed")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Search
            BrandSearchField(placeholder: "Search templates...", text: $searchText)
                .frame(width: 200)

            // Actions
            BrandPrimaryButton(title: "New Template", icon: "plus", size: .small) {
                onNew()
            }

            Menu {
                Button(action: onReset) {
                    Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 32)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color.brandBackground)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.brandBorder),
            alignment: .bottom
        )
    }
}

// MARK: - Template List Pane

struct TemplateListPane: View {
    let templates: [SummaryTemplate]
    @Binding var selectedTemplate: SummaryTemplate?
    let selectedTemplateId: UUID?
    @Binding var isCreatingNew: Bool
    var onToggleEnabled: (SummaryTemplate) -> Void
    var onSetDefault: (SummaryTemplate) -> Void
    var onDuplicate: (SummaryTemplate) -> Void
    var onDelete: (SummaryTemplate) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Text("TEMPLATES")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(templates.filter { $0.isEnabled }.count) active")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()
                .padding(.horizontal, 16)

            // Template list
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(templates) { template in
                        TemplateListRow(
                            template: template,
                            isSelected: selectedTemplate?.id == template.id && !isCreatingNew,
                            isDefault: template.id == selectedTemplateId,
                            onSelect: {
                                selectedTemplate = template
                                isCreatingNew = false
                            },
                            onToggleEnabled: { onToggleEnabled(template) },
                            onSetDefault: { onSetDefault(template) },
                            onDuplicate: { onDuplicate(template) },
                            onDelete: { onDelete(template) }
                        )
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .background(Color.white)
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundColor(Color.brandBorder),
            alignment: .trailing
        )
    }
}

// MARK: - Template List Row

struct TemplateListRow: View {
    let template: SummaryTemplate
    let isSelected: Bool
    let isDefault: Bool
    var onSelect: () -> Void
    var onToggleEnabled: () -> Void
    var onSetDefault: () -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Enable toggle
                Button(action: onToggleEnabled) {
                    Image(systemName: template.isEnabled ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundColor(template.isEnabled ? .brandViolet : .secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
                .help(template.isEnabled ? "Disable template" : "Enable template")

                // Icon
                Image(systemName: template.icon)
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? .white : (template.isEnabled ? .brandViolet : .secondary))
                    .frame(width: 20)

                // Info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(template.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(isSelected ? .white : .primary)

                        if template.isBuiltIn {
                            Text("Built-in")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.15))
                                )
                        }

                        if isDefault {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                                .foregroundColor(isSelected ? .white : .brandAmber)
                        }
                    }

                    Text(template.description)
                        .font(.system(size: 11))
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Format badge
                Text(template.outputFormat.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isSelected ? .white.opacity(0.9) : .brandViolet)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.white.opacity(0.2) : Color.brandViolet.opacity(0.1))
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.brandViolet : (isHovered ? Color.brandViolet.opacity(0.05) : Color.clear))
            )
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            if template.isEnabled && !isDefault {
                Button {
                    onSetDefault()
                } label: {
                    Label("Set as Default", systemImage: "star")
                }
            }

            Button {
                onDuplicate()
            } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
            }

            Divider()

            Button(action: onToggleEnabled) {
                Label(template.isEnabled ? "Disable" : "Enable", systemImage: template.isEnabled ? "xmark.circle" : "checkmark.circle")
            }

            if !template.isBuiltIn {
                Divider()

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - Template Editor Pane

struct TemplateEditorPane: View {
    let template: SummaryTemplate?
    var onSave: (SummaryTemplate) -> Void
    var onCancel: (() -> Void)?

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var icon: String = "doc.text"
    @State private var systemPrompt: String = ""
    @State private var userPromptTemplate: String = ""
    @State private var outputFormat: SummaryTemplate.OutputFormat = .markdown
    @State private var showingIconPicker = false
    @State private var hasChanges = false

    private let availableIcons = [
        "doc.text", "doc.text.fill", "list.bullet", "checklist",
        "person.2.fill", "briefcase.fill", "chart.bar.fill",
        "brain.head.profile", "lightbulb.fill", "star.fill",
        "chevron.left.forwardslash.chevron.right", "gear",
        "person.crop.circle.badge.checkmark", "bubble.left.and.bubble.right.fill",
        "hammer.fill", "wrench.and.screwdriver.fill", "bookmark.fill"
    ]

    var isEditing: Bool { template != nil }
    var isBuiltIn: Bool { template?.isBuiltIn ?? false }

    var body: some View {
        VStack(spacing: 0) {
            // Editor Header
            HStack {
                if let template = template {
                    Image(systemName: template.icon)
                        .font(.system(size: 20))
                        .foregroundColor(.brandViolet)

                    Text(isBuiltIn ? "Viewing \(template.name)" : "Editing \(template.name)")
                        .font(.brandDisplay(18, weight: .semibold))
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.brandViolet)

                    Text("New Template")
                        .font(.brandDisplay(18, weight: .semibold))
                }

                Spacer()

                if let onCancel = onCancel {
                    Button("Cancel") {
                        onCancel()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }

                if !isBuiltIn {
                    Button(action: saveTemplate) {
                        Text(isEditing ? "Save Changes" : "Create Template")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandViolet)
                    .disabled(!canSave)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color.white)
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color.brandBorder),
                alignment: .bottom
            )

            // Editor Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Basic Info Section
                    EditorSection(title: "Basic Info", icon: "info.circle") {
                        VStack(spacing: 16) {
                            // Name
                            EditorField(label: "Name") {
                                TextField("My Template", text: $name)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 14))
                                    .disabled(isBuiltIn)
                            }

                            // Description
                            EditorField(label: "Description") {
                                TextField("What this template does", text: $description)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 14))
                                    .disabled(isBuiltIn)
                            }

                            // Icon & Format row
                            HStack(spacing: 24) {
                                EditorField(label: "Icon", width: 80) {
                                    Button(action: { showingIconPicker.toggle() }) {
                                        HStack(spacing: 8) {
                                            Image(systemName: icon)
                                                .font(.system(size: 18))
                                                .foregroundColor(.brandViolet)

                                            Image(systemName: "chevron.down")
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.brandBackground)
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.brandBorder, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isBuiltIn)
                                    .popover(isPresented: $showingIconPicker) {
                                        IconPickerGrid(selectedIcon: $icon, icons: availableIcons)
                                    }
                                }

                                EditorField(label: "Output Format", width: 120) {
                                    Picker("", selection: $outputFormat) {
                                        ForEach(SummaryTemplate.OutputFormat.allCases, id: \.self) { format in
                                            Text(format.displayName).tag(format)
                                        }
                                    }
                                    .labelsHidden()
                                    .disabled(isBuiltIn)
                                }

                                Spacer()
                            }
                        }
                    }

                    // System Prompt Section
                    EditorSection(title: "System Prompt", icon: "cpu") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Instructions that define the AI's behavior and expertise")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)

                            PromptTextEditor(
                                text: $systemPrompt,
                                placeholder: "You are an expert at...",
                                minHeight: 120,
                                disabled: isBuiltIn
                            )
                        }
                    }

                    // User Prompt Template Section
                    EditorSection(title: "User Prompt Template", icon: "text.alignleft") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("The prompt sent with each transcript. Use {{transcript}} as placeholder.")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)

                                Spacer()

                                if !isBuiltIn {
                                    Button {
                                        userPromptTemplate += "\n\n{{transcript}}"
                                    } label: {
                                        Label("Insert {{transcript}}", systemImage: "plus.circle")
                                            .font(.system(size: 11, weight: .medium))
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }

                            PromptTextEditor(
                                text: $userPromptTemplate,
                                placeholder: "Analyze this meeting transcript and...",
                                minHeight: 240,
                                disabled: isBuiltIn
                            )

                            // Variable reference
                            HStack(spacing: 16) {
                                VariableChip(name: "{{transcript}}", description: "Full transcript text")
                            }
                        }
                    }

                    // Start from template (only for new)
                    if !isEditing && !isBuiltIn {
                        EditorSection(title: "Quick Start", icon: "sparkles") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Start with a built-in template as your base")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(SummaryTemplate.builtInTemplates) { builtin in
                                            Button {
                                                loadTemplate(builtin)
                                            } label: {
                                                HStack(spacing: 6) {
                                                    Image(systemName: builtin.icon)
                                                        .font(.system(size: 12))
                                                    Text(builtin.name)
                                                        .font(.system(size: 12, weight: .medium))
                                                }
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .background(Color.brandBackground)
                                                .cornerRadius(8)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .stroke(Color.brandBorder, lineWidth: 1)
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }
            .background(Color.brandBackground)
        }
        .onAppear {
            if let template = template {
                loadTemplate(template)
            }
        }
        .onChange(of: template) { newTemplate in
            if let template = newTemplate {
                loadTemplate(template)
            } else {
                clearFields()
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !systemPrompt.trimmingCharacters(in: .whitespaces).isEmpty &&
        !userPromptTemplate.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func loadTemplate(_ template: SummaryTemplate) {
        name = template.name
        description = template.description
        icon = template.icon
        systemPrompt = template.systemPrompt
        userPromptTemplate = template.userPromptTemplate
        outputFormat = template.outputFormat
    }

    private func clearFields() {
        name = ""
        description = ""
        icon = "doc.text"
        systemPrompt = ""
        userPromptTemplate = ""
        outputFormat = .markdown
    }

    private func saveTemplate() {
        let newTemplate = SummaryTemplate(
            id: template?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            description: description.trimmingCharacters(in: .whitespaces),
            icon: icon,
            isBuiltIn: false,
            isEnabled: template?.isEnabled ?? true,
            systemPrompt: systemPrompt,
            userPromptTemplate: userPromptTemplate,
            outputFormat: outputFormat,
            sortOrder: template?.sortOrder ?? 999
        )
        onSave(newTemplate)
    }
}

// MARK: - Editor Section

struct EditorSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.brandViolet)

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
            }

            content()
                .padding(16)
                .background(Color.white)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.brandBorder, lineWidth: 1)
                )
        }
    }
}

// MARK: - Editor Field

struct EditorField<Content: View>: View {
    let label: String
    var width: CGFloat? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: width ?? 80, alignment: .leading)

            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.brandBackground)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.brandBorder, lineWidth: 1)
                )
        }
    }
}

// MARK: - Prompt Text Editor

struct PromptTextEditor: View {
    @Binding var text: String
    let placeholder: String
    var minHeight: CGFloat = 120
    var disabled: Bool = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.5))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }

            TextEditor(text: $text)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .disabled(disabled)
                .opacity(disabled ? 0.7 : 1)
        }
        .frame(minHeight: minHeight)
        .padding(4)
        .background(Color.brandBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.brandBorder, lineWidth: 1)
        )
    }
}

// MARK: - Variable Chip

struct VariableChip: View {
    let name: String
    let description: String

    var body: some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.brandViolet)

            Text("—")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.5))

            Text(description)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.brandViolet.opacity(0.08))
        .cornerRadius(BrandRadius.small)
    }
}

// MARK: - Icon Picker Grid

struct IconPickerGrid: View {
    @Binding var selectedIcon: String
    let icons: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            Text("Choose Icon")
                .font(.system(size: 13, weight: .semibold))

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(44)), count: 4), spacing: 8) {
                ForEach(icons, id: \.self) { iconName in
                    Button {
                        selectedIcon = iconName
                        dismiss()
                    } label: {
                        Image(systemName: iconName)
                            .font(.system(size: 18))
                            .foregroundColor(selectedIcon == iconName ? .white : .primary)
                            .frame(width: 40, height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedIcon == iconName ? Color.brandViolet : Color.brandBackground)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(Color.white)
    }
}

// MARK: - Empty Template View

struct EmptyTemplateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 56))
                .foregroundColor(.brandViolet.opacity(0.3))

            Text("Select a Template")
                .font(.brandDisplay(20, weight: .semibold))

            Text("Choose a template from the list to view or edit,\nor create a new one.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.brandBackground)
    }
}

// MARK: - Preview

#Preview("Templates View") {
    TemplatesView()
        .frame(width: 1100, height: 700)
}
