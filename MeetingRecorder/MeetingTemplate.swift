//
//  MeetingTemplate.swift
//  MeetingRecorder
//
//  Meeting type templates with sections for post-processing.
//  Inspired by Amie's approach: each meeting type has multiple
//  sections (Summary, Wins, Issues, Commitments, etc.)
//

import Foundation

// MARK: - Template Section

/// A section within a meeting template (e.g., "Summary", "Action Items")
struct TemplateSection: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var prompt: String
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        name: String,
        prompt: String,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.sortOrder = sortOrder
    }
}

// MARK: - Meeting Template

/// A meeting type template with multiple sections
struct MeetingTemplate: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var context: String  // When to use this template (for auto-detection)
    var icon: String
    var isBuiltIn: Bool
    var isEnabled: Bool
    var sections: [TemplateSection]
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        name: String,
        context: String,
        icon: String = "doc.text",
        isBuiltIn: Bool = false,
        isEnabled: Bool = true,
        sections: [TemplateSection] = [],
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.context = context
        self.icon = icon
        self.isBuiltIn = isBuiltIn
        self.isEnabled = isEnabled
        self.sections = sections
        self.sortOrder = sortOrder
    }

    /// Sorted sections by sortOrder
    var sortedSections: [TemplateSection] {
        sections.sorted { $0.sortOrder < $1.sortOrder }
    }
}

// MARK: - Built-in Meeting Templates

extension MeetingTemplate {

    // MARK: - General (Default/Fallback)

    static let general = MeetingTemplate(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
        name: "General",
        context: "General meeting or discussion without a specific format.",
        icon: "doc.text.fill",
        isBuiltIn: true,
        sections: [
            TemplateSection(
                id: UUID(uuidString: "10000001-0000-0000-0000-000000000001")!,
                name: "Summary",
                prompt: "Provide a concise summary of the meeting in 2-3 sentences.",
                sortOrder: 0
            ),
            TemplateSection(
                id: UUID(uuidString: "10000001-0000-0000-0000-000000000002")!,
                name: "Key Points",
                prompt: "List the main topics and key points discussed as bullet points.",
                sortOrder: 1
            ),
            TemplateSection(
                id: UUID(uuidString: "10000001-0000-0000-0000-000000000003")!,
                name: "Action Items",
                prompt: "Extract all action items, tasks, and commitments. Include owner if mentioned.",
                sortOrder: 2
            )
        ],
        sortOrder: 0
    )

    // MARK: - 1:1 Meeting

    static let oneOnOne = MeetingTemplate(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
        name: "1:1",
        context: "1:1 meeting with a team member, manager, or direct report. Typically covers updates, feedback, blockers, and career development.",
        icon: "person.2.fill",
        isBuiltIn: true,
        sections: [
            TemplateSection(
                id: UUID(uuidString: "10000002-0000-0000-0000-000000000001")!,
                name: "Summary",
                prompt: "Summarize the 1:1 conversation in 2-3 sentences.",
                sortOrder: 0
            ),
            TemplateSection(
                id: UUID(uuidString: "10000002-0000-0000-0000-000000000002")!,
                name: "Wins",
                prompt: "List any wins, accomplishments, or positive updates shared.",
                sortOrder: 1
            ),
            TemplateSection(
                id: UUID(uuidString: "10000002-0000-0000-0000-000000000003")!,
                name: "Issues",
                prompt: "List any blockers, challenges, or concerns raised.",
                sortOrder: 2
            ),
            TemplateSection(
                id: UUID(uuidString: "10000002-0000-0000-0000-000000000004")!,
                name: "Feedback",
                prompt: "Note any feedback given or received during the meeting.",
                sortOrder: 3
            ),
            TemplateSection(
                id: UUID(uuidString: "10000002-0000-0000-0000-000000000005")!,
                name: "Commitments",
                prompt: "List all commitments and action items with owner.",
                sortOrder: 4
            )
        ],
        sortOrder: 1
    )

    // MARK: - Strategy Meeting

    static let strategy = MeetingTemplate(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
        name: "Strategy",
        context: "Strategy meeting, planning session, or brainstorming. Focuses on decisions, direction, and long-term planning.",
        icon: "lightbulb.fill",
        isBuiltIn: true,
        sections: [
            TemplateSection(
                id: UUID(uuidString: "10000003-0000-0000-0000-000000000001")!,
                name: "Summary",
                prompt: "Summarize the strategic discussion in 2-3 sentences.",
                sortOrder: 0
            ),
            TemplateSection(
                id: UUID(uuidString: "10000003-0000-0000-0000-000000000002")!,
                name: "Key Decisions",
                prompt: "List all decisions made during the meeting with rationale if provided.",
                sortOrder: 1
            ),
            TemplateSection(
                id: UUID(uuidString: "10000003-0000-0000-0000-000000000003")!,
                name: "Open Questions",
                prompt: "List questions that remain unanswered or need more research.",
                sortOrder: 2
            ),
            TemplateSection(
                id: UUID(uuidString: "10000003-0000-0000-0000-000000000004")!,
                name: "Risks",
                prompt: "Identify any risks or concerns raised during the discussion.",
                sortOrder: 3
            ),
            TemplateSection(
                id: UUID(uuidString: "10000003-0000-0000-0000-000000000005")!,
                name: "Next Steps",
                prompt: "List concrete next steps and action items with owners.",
                sortOrder: 4
            )
        ],
        sortOrder: 2
    )

    // MARK: - Sales Call

    static let sales = MeetingTemplate(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!,
        name: "Sales",
        context: "Sales call, demo, or customer meeting. Focus on understanding needs, handling objections, and closing.",
        icon: "dollarsign.circle.fill",
        isBuiltIn: true,
        sections: [
            TemplateSection(
                id: UUID(uuidString: "10000004-0000-0000-0000-000000000001")!,
                name: "Summary",
                prompt: "Summarize the sales conversation in 2-3 sentences.",
                sortOrder: 0
            ),
            TemplateSection(
                id: UUID(uuidString: "10000004-0000-0000-0000-000000000002")!,
                name: "Customer Needs",
                prompt: "List the customer's stated needs, pain points, and requirements.",
                sortOrder: 1
            ),
            TemplateSection(
                id: UUID(uuidString: "10000004-0000-0000-0000-000000000003")!,
                name: "Objections",
                prompt: "List any objections, concerns, or hesitations raised by the customer.",
                sortOrder: 2
            ),
            TemplateSection(
                id: UUID(uuidString: "10000004-0000-0000-0000-000000000004")!,
                name: "Commitments",
                prompt: "List all commitments made by both parties.",
                sortOrder: 3
            ),
            TemplateSection(
                id: UUID(uuidString: "10000004-0000-0000-0000-000000000005")!,
                name: "Follow-up",
                prompt: "List follow-up actions needed and next meeting/call if scheduled.",
                sortOrder: 4
            )
        ],
        sortOrder: 3
    )

    // MARK: - Interview

    static let interview = MeetingTemplate(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000005")!,
        name: "Interview",
        context: "Job interview, candidate screening, or hiring discussion.",
        icon: "person.crop.rectangle.fill",
        isBuiltIn: true,
        sections: [
            TemplateSection(
                id: UUID(uuidString: "10000005-0000-0000-0000-000000000001")!,
                name: "Summary",
                prompt: "Summarize the interview in 2-3 sentences.",
                sortOrder: 0
            ),
            TemplateSection(
                id: UUID(uuidString: "10000005-0000-0000-0000-000000000002")!,
                name: "Strengths",
                prompt: "List the candidate's demonstrated strengths and positive signals.",
                sortOrder: 1
            ),
            TemplateSection(
                id: UUID(uuidString: "10000005-0000-0000-0000-000000000003")!,
                name: "Concerns",
                prompt: "List any concerns, gaps, or areas needing more evaluation.",
                sortOrder: 2
            ),
            TemplateSection(
                id: UUID(uuidString: "10000005-0000-0000-0000-000000000004")!,
                name: "Key Answers",
                prompt: "Note the candidate's answers to key questions asked.",
                sortOrder: 3
            ),
            TemplateSection(
                id: UUID(uuidString: "10000005-0000-0000-0000-000000000005")!,
                name: "Recommendation",
                prompt: "Based on the discussion, provide a hiring recommendation (proceed/hold/pass) with reasoning.",
                sortOrder: 4
            )
        ],
        sortOrder: 4
    )

    // MARK: - Standup

    static let standup = MeetingTemplate(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000006")!,
        name: "Standup",
        context: "Daily standup, sync, or status update meeting. Short meeting for team alignment.",
        icon: "person.3.fill",
        isBuiltIn: true,
        sections: [
            TemplateSection(
                id: UUID(uuidString: "10000006-0000-0000-0000-000000000001")!,
                name: "Summary",
                prompt: "Summarize the standup in 1-2 sentences.",
                sortOrder: 0
            ),
            TemplateSection(
                id: UUID(uuidString: "10000006-0000-0000-0000-000000000002")!,
                name: "Updates by Person",
                prompt: "List each person's update (what they did, what they're doing next).",
                sortOrder: 1
            ),
            TemplateSection(
                id: UUID(uuidString: "10000006-0000-0000-0000-000000000003")!,
                name: "Blockers",
                prompt: "List any blockers or impediments raised by the team.",
                sortOrder: 2
            )
        ],
        sortOrder: 5
    )

    // MARK: - Technical/Engineering

    static let technical = MeetingTemplate(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000007")!,
        name: "Technical",
        context: "Technical discussion, architecture review, code review, or engineering meeting.",
        icon: "chevron.left.forwardslash.chevron.right",
        isBuiltIn: true,
        sections: [
            TemplateSection(
                id: UUID(uuidString: "10000007-0000-0000-0000-000000000001")!,
                name: "Summary",
                prompt: "Summarize the technical discussion in 2-3 sentences.",
                sortOrder: 0
            ),
            TemplateSection(
                id: UUID(uuidString: "10000007-0000-0000-0000-000000000002")!,
                name: "Technical Decisions",
                prompt: "List all technical decisions made with their rationale.",
                sortOrder: 1
            ),
            TemplateSection(
                id: UUID(uuidString: "10000007-0000-0000-0000-000000000003")!,
                name: "Architecture Notes",
                prompt: "Note any architecture, design, or system changes discussed.",
                sortOrder: 2
            ),
            TemplateSection(
                id: UUID(uuidString: "10000007-0000-0000-0000-000000000004")!,
                name: "Technical Debt",
                prompt: "List any technical debt or concerns identified.",
                sortOrder: 3
            ),
            TemplateSection(
                id: UUID(uuidString: "10000007-0000-0000-0000-000000000005")!,
                name: "Tasks",
                prompt: "List all technical tasks and who's responsible.",
                sortOrder: 4
            )
        ],
        sortOrder: 6
    )

    // MARK: - All Built-in Templates

    static let builtInTemplates: [MeetingTemplate] = [
        .general,
        .oneOnOne,
        .strategy,
        .sales,
        .interview,
        .standup,
        .technical
    ]

    /// Default template (General)
    static let defaultTemplate = general
}

// MARK: - Processed Section Result

/// Result of processing a single section
struct ProcessedSection: Identifiable, Codable, Equatable {
    let id: UUID
    let sectionId: UUID
    let sectionName: String
    let content: String
    let processedAt: Date

    init(
        id: UUID = UUID(),
        sectionId: UUID,
        sectionName: String,
        content: String,
        processedAt: Date = Date()
    ) {
        self.id = id
        self.sectionId = sectionId
        self.sectionName = sectionName
        self.content = content
        self.processedAt = processedAt
    }
}

// MARK: - Meeting Post-Processing Result

/// Complete post-processing result for a meeting
struct MeetingPostProcessingResult: Identifiable, Codable, Equatable {
    let id: UUID
    let meetingId: UUID
    let templateId: UUID
    let templateName: String
    var sections: [ProcessedSection]
    let processedAt: Date
    let modelUsed: String
    let totalCostCents: Int
    let wasAutoInferred: Bool

    init(
        id: UUID = UUID(),
        meetingId: UUID,
        templateId: UUID,
        templateName: String,
        sections: [ProcessedSection] = [],
        processedAt: Date = Date(),
        modelUsed: String = "gpt-4o-mini",
        totalCostCents: Int = 0,
        wasAutoInferred: Bool = false
    ) {
        self.id = id
        self.meetingId = meetingId
        self.templateId = templateId
        self.templateName = templateName
        self.sections = sections
        self.processedAt = processedAt
        self.modelUsed = modelUsed
        self.totalCostCents = totalCostCents
        self.wasAutoInferred = wasAutoInferred
    }

    /// Get content for a specific section by name
    func content(for sectionName: String) -> String? {
        sections.first { $0.sectionName == sectionName }?.content
    }
}

// MARK: - Meeting Template Manager

/// Manages meeting templates (built-in + custom)
class MeetingTemplateManager: ObservableObject {
    static let shared = MeetingTemplateManager()

    @Published var templates: [MeetingTemplate] = []
    @Published var selectedTemplateId: UUID?

    /// Setting: Auto-infer meeting type from transcript
    @Published var autoInferMeetingType: Bool {
        didSet {
            UserDefaults.standard.set(autoInferMeetingType, forKey: autoInferKey)
        }
    }

    private let storageKey = "customMeetingTemplates"
    private let selectedTemplateKey = "selectedMeetingTemplateId"
    private let enabledTemplatesKey = "enabledMeetingTemplates"
    private let autoInferKey = "autoInferMeetingType"

    private init() {
        self.autoInferMeetingType = UserDefaults.standard.object(forKey: autoInferKey) as? Bool ?? true
        loadTemplates()
    }

    /// All templates sorted by sortOrder
    var allTemplates: [MeetingTemplate] {
        templates.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Only enabled templates
    var enabledTemplates: [MeetingTemplate] {
        allTemplates.filter { $0.isEnabled }
    }

    /// Currently selected template (or default)
    var selectedTemplate: MeetingTemplate {
        if let id = selectedTemplateId,
           let template = templates.first(where: { $0.id == id }) {
            return template
        }
        return MeetingTemplate.defaultTemplate
    }

    /// Get template by ID
    func template(for id: UUID) -> MeetingTemplate? {
        templates.first { $0.id == id }
    }

    // MARK: - Persistence

    private func loadTemplates() {
        var loadedTemplates = MeetingTemplate.builtInTemplates
        var seenIds = Set(loadedTemplates.map { $0.id })

        // Load custom templates
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let customTemplates = try? JSONDecoder().decode([MeetingTemplate].self, from: data) {
            for template in customTemplates where !seenIds.contains(template.id) {
                loadedTemplates.append(template)
                seenIds.insert(template.id)
            }
        }

        // Load enabled states
        if let enabledData = UserDefaults.standard.dictionary(forKey: enabledTemplatesKey) as? [String: Bool] {
            for i in loadedTemplates.indices {
                if let enabled = enabledData[loadedTemplates[i].id.uuidString] {
                    loadedTemplates[i].isEnabled = enabled
                }
            }
        }

        templates = loadedTemplates

        // Load selected template
        if let selectedIdString = UserDefaults.standard.string(forKey: selectedTemplateKey),
           let selectedId = UUID(uuidString: selectedIdString) {
            selectedTemplateId = selectedId
        } else {
            selectedTemplateId = MeetingTemplate.defaultTemplate.id
        }
    }

    func saveTemplates() {
        // Only save custom templates
        let customTemplates = templates.filter { !$0.isBuiltIn }
        if let data = try? JSONEncoder().encode(customTemplates) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }

        // Save enabled states
        var enabledStates: [String: Bool] = [:]
        for template in templates {
            enabledStates[template.id.uuidString] = template.isEnabled
        }
        UserDefaults.standard.set(enabledStates, forKey: enabledTemplatesKey)

        // Save selected
        if let selectedId = selectedTemplateId {
            UserDefaults.standard.set(selectedId.uuidString, forKey: selectedTemplateKey)
        }
    }

    // MARK: - CRUD

    func addTemplate(_ template: MeetingTemplate) {
        var newTemplate = template
        newTemplate.sortOrder = templates.count
        templates.append(newTemplate)
        saveTemplates()
    }

    func updateTemplate(_ template: MeetingTemplate) {
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index] = template
            saveTemplates()
        }
    }

    func deleteTemplate(_ template: MeetingTemplate) {
        guard !template.isBuiltIn else { return }
        templates.removeAll { $0.id == template.id }
        saveTemplates()
    }

    func toggleEnabled(_ template: MeetingTemplate) {
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index].isEnabled.toggle()
            saveTemplates()
        }
    }

    func selectTemplate(_ template: MeetingTemplate) {
        selectedTemplateId = template.id
        saveTemplates()
    }

    func resetToDefaults() {
        templates = MeetingTemplate.builtInTemplates
        selectedTemplateId = MeetingTemplate.defaultTemplate.id
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: enabledTemplatesKey)
        saveTemplates()
    }

    /// Duplicate a template
    func duplicateTemplate(_ template: MeetingTemplate) -> MeetingTemplate {
        let newSections = template.sections.map { section in
            TemplateSection(
                id: UUID(),
                name: section.name,
                prompt: section.prompt,
                sortOrder: section.sortOrder
            )
        }

        let copy = MeetingTemplate(
            id: UUID(),
            name: "\(template.name) (Copy)",
            context: template.context,
            icon: template.icon,
            isBuiltIn: false,
            isEnabled: template.isEnabled,
            sections: newSections,
            sortOrder: templates.count
        )
        addTemplate(copy)
        return copy
    }
}
