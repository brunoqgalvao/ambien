//
//  SummaryTemplatesSettingsTab.swift
//  MeetingRecorder
//
//  Settings UI for managing summary templates:
//  - View built-in templates
//  - Create custom templates
//  - Enable/disable templates
//  - Set default template
//

import SwiftUI

// MARK: - Templates Settings Tab

struct SummaryTemplatesSettingsTab: View {
    @StateObject private var templateManager = SummaryTemplateManager.shared
    @State private var showingNewTemplate = false
    @State private var editingTemplate: SummaryTemplate?
    @State private var showingResetConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Summary Templates")
                        .font(.headline)
                    Text("Choose how your transcripts are summarized")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: { showingNewTemplate = true }) {
                    Label("New Template", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            // Default template selector
            HStack {
                Text("Default template:")
                    .foregroundColor(.secondary)

                Picker("", selection: Binding(
                    get: { templateManager.selectedTemplateId ?? SummaryTemplate.defaultTemplate.id },
                    set: { newId in templateManager.selectedTemplateId = newId }
                )) {
                    ForEach(templateManager.enabledTemplates) { template in
                        Text(template.name).tag(template.id)
                    }
                }
                .frame(width: 200)
            }

            Divider()

            // Templates list
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(templateManager.allTemplates) { template in
                        TemplateRow(
                            template: template,
                            isSelected: template.id == templateManager.selectedTemplateId,
                            onToggle: { templateManager.toggleEnabled(template) },
                            onEdit: { editingTemplate = template },
                            onDuplicate: { _ = templateManager.duplicateTemplate(template) },
                            onDelete: { templateManager.deleteTemplate(template) },
                            onSelect: { templateManager.selectTemplate(template) }
                        )
                    }
                }
            }

            Divider()

            // Footer actions
            HStack {
                Button(action: { showingResetConfirmation = true }) {
                    Text("Reset to Defaults")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("\(templateManager.enabledTemplates.count) of \(templateManager.allTemplates.count) enabled")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .sheet(isPresented: $showingNewTemplate) {
            TemplateEditorSheet(
                template: nil,
                onSave: { template in
                    templateManager.addTemplate(template)
                }
            )
        }
        .sheet(item: $editingTemplate) { template in
            TemplateEditorSheet(
                template: template,
                onSave: { updated in
                    templateManager.updateTemplate(updated)
                }
            )
        }
        .alert("Reset Templates?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                templateManager.resetToDefaults()
            }
        } message: {
            Text("This will remove all custom templates and restore default settings.")
        }
    }
}

// MARK: - Template Row

struct TemplateRow: View {
    let template: SummaryTemplate
    let isSelected: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            // Enable toggle
            Toggle("", isOn: Binding(
                get: { template.isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            // Icon
            Image(systemName: template.icon)
                .font(.title3)
                .foregroundColor(template.isEnabled ? .accentColor : .secondary)
                .frame(width: 24)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(template.name)
                        .fontWeight(.medium)
                        .foregroundColor(template.isEnabled ? .primary : .secondary)

                    if template.isBuiltIn {
                        Text("Built-in")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2))
                            .cornerRadius(4)
                    }

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    }
                }

                Text(template.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Output format badge
            Text(template.outputFormat.displayName)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.brandViolet.opacity(0.1))
                .cornerRadius(4)

            // Actions (shown on hover)
            if isHovering {
                HStack(spacing: 4) {
                    if !isSelected && template.isEnabled {
                        Button(action: onSelect) {
                            Image(systemName: "checkmark.circle")
                                .foregroundColor(.green)
                        }
                        .buttonStyle(.plain)
                        .help("Set as default")
                    }

                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                    .help("Edit template")

                    Button(action: onDuplicate) {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .help("Duplicate")

                    if !template.isBuiltIn {
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .help("Delete")
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.brandViolet.opacity(0.08) : (isHovering ? Color.brandSurface : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.brandViolet.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Template Editor Sheet

struct TemplateEditorSheet: View {
    let template: SummaryTemplate?
    let onSave: (SummaryTemplate) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var icon: String = "doc.text"
    @State private var systemPrompt: String = ""
    @State private var userPromptTemplate: String = ""
    @State private var outputFormat: SummaryTemplate.OutputFormat = .markdown
    @State private var showingIconPicker = false

    private let availableIcons = [
        "doc.text", "doc.text.fill", "list.bullet", "checklist",
        "person.2.fill", "briefcase.fill", "chart.bar.fill",
        "brain.head.profile", "lightbulb.fill", "star.fill",
        "chevron.left.forwardslash.chevron.right", "gear",
        "person.crop.circle.badge.checkmark", "bubble.left.and.bubble.right.fill"
    ]

    var isEditing: Bool { template != nil }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "Edit Template" : "New Template")
                    .font(.headline)
                Spacer()
                SecondaryActionButton(title: "Cancel") { dismiss() }
            }
            .padding()

            Divider()

            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Basic info
                    GroupBox("Basic Info") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Name")
                                    .frame(width: 80, alignment: .leading)
                                TextField("My Template", text: $name)
                                    .textFieldStyle(.roundedBorder)
                            }

                            HStack {
                                Text("Description")
                                    .frame(width: 80, alignment: .leading)
                                TextField("What this template does", text: $description)
                                    .textFieldStyle(.roundedBorder)
                            }

                            HStack {
                                Text("Icon")
                                    .frame(width: 80, alignment: .leading)

                                Button(action: { showingIconPicker.toggle() }) {
                                    HStack {
                                        Image(systemName: icon)
                                            .font(.title2)
                                        Image(systemName: "chevron.down")
                                            .font(.caption)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.brandSurface)
                                    .cornerRadius(BrandRadius.small)
                                }
                                .buttonStyle(.plain)
                                .popover(isPresented: $showingIconPicker) {
                                    IconPickerPopover(selectedIcon: $icon, icons: availableIcons)
                                }

                                Spacer()

                                Picker("Output Format", selection: $outputFormat) {
                                    ForEach(SummaryTemplate.OutputFormat.allCases, id: \.self) { format in
                                        Text(format.displayName).tag(format)
                                    }
                                }
                                .frame(width: 180)
                            }
                        }
                        .padding(8)
                    }

                    // System prompt
                    GroupBox("System Prompt") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Instructions for the AI's behavior")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            TextEditor(text: $systemPrompt)
                                .font(.system(.body, design: .monospaced))
                                .frame(minHeight: 80)
                                .scrollContentBackground(.hidden)
                                .padding(4)
                                .background(Color.brandCreamDark)
                                .cornerRadius(4)
                        }
                        .padding(8)
                    }

                    // User prompt template
                    GroupBox("User Prompt Template") {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Use {{transcript}} where the transcript should be inserted")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Spacer()

                                Button("Insert {{transcript}}") {
                                    userPromptTemplate += "\n\n{{transcript}}"
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                            }

                            TextEditor(text: $userPromptTemplate)
                                .font(.system(.body, design: .monospaced))
                                .frame(minHeight: 200)
                                .scrollContentBackground(.hidden)
                                .padding(4)
                                .background(Color.brandCreamDark)
                                .cornerRadius(4)
                        }
                        .padding(8)
                    }
                }
                .padding()
            }

            Divider()

            // Footer
            HStack {
                if !isEditing {
                    Menu("Start from...") {
                        ForEach(SummaryTemplate.builtInTemplates) { builtin in
                            Button(builtin.name) {
                                loadTemplate(builtin)
                            }
                        }
                    }
                }

                Spacer()

                PrimaryActionButton(
                    title: "Save",
                    icon: "checkmark",
                    isDisabled: name.isEmpty || systemPrompt.isEmpty || userPromptTemplate.isEmpty
                ) {
                    saveTemplate()
                }
            }
            .padding()
        }
        .frame(width: 600, height: 700)
        .onAppear {
            if let template = template {
                loadTemplate(template)
            }
        }
    }

    private func loadTemplate(_ template: SummaryTemplate) {
        name = template.name
        description = template.description
        icon = template.icon
        systemPrompt = template.systemPrompt
        userPromptTemplate = template.userPromptTemplate
        outputFormat = template.outputFormat
    }

    private func saveTemplate() {
        let newTemplate = SummaryTemplate(
            id: template?.id ?? UUID(),
            name: name,
            description: description,
            icon: icon,
            isBuiltIn: false,
            isEnabled: template?.isEnabled ?? true,
            systemPrompt: systemPrompt,
            userPromptTemplate: userPromptTemplate,
            outputFormat: outputFormat,
            sortOrder: template?.sortOrder ?? 999
        )
        onSave(newTemplate)
        dismiss()
    }
}

// MARK: - Icon Picker Popover

struct IconPickerPopover: View {
    @Binding var selectedIcon: String
    let icons: [String]

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(44)), count: 4), spacing: 8) {
            ForEach(icons, id: \.self) { iconName in
                Button(action: { selectedIcon = iconName }) {
                    Image(systemName: iconName)
                        .font(.title2)
                        .frame(width: 36, height: 36)
                        .background(selectedIcon == iconName ? Color.brandViolet.opacity(0.2) : Color.clear)
                        .cornerRadius(BrandRadius.small)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }
}

// MARK: - Preview

#Preview("Templates Settings") {
    SummaryTemplatesSettingsTab()
        .frame(width: 550, height: 500)
        .padding()
}

#Preview("Template Editor") {
    TemplateEditorSheet(template: nil) { _ in }
}

#Preview("Template Editor - Editing") {
    TemplateEditorSheet(template: .executiveSummary) { _ in }
}
