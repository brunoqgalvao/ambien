//
//  SummaryTemplate.swift
//  MeetingRecorder
//
//  Summary templates for post-processing transcripts into
//  structured summaries, action items, and diarized transcripts.
//

import Foundation

/// A template for processing meeting transcripts
struct SummaryTemplate: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var description: String
    var icon: String
    var isBuiltIn: Bool
    var isEnabled: Bool

    /// The system prompt for the AI
    var systemPrompt: String

    /// The user prompt template ({{transcript}} will be replaced)
    var userPromptTemplate: String

    /// Expected output format for rendering
    var outputFormat: OutputFormat

    /// Order in the list
    var sortOrder: Int

    enum OutputFormat: String, Codable, CaseIterable {
        case markdown           // Render as markdown
        case actionItems        // Render as checklist
        case diarizedTranscript // Render with speaker labels
        case keyPoints          // Render as bullet points
        case custom             // Raw text output

        var displayName: String {
            switch self {
            case .markdown: return "Rich Text"
            case .actionItems: return "Action Items"
            case .diarizedTranscript: return "Speaker Transcript"
            case .keyPoints: return "Key Points"
            case .custom: return "Custom"
            }
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        icon: String = "doc.text",
        isBuiltIn: Bool = false,
        isEnabled: Bool = true,
        systemPrompt: String,
        userPromptTemplate: String,
        outputFormat: OutputFormat = .markdown,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.isBuiltIn = isBuiltIn
        self.isEnabled = isEnabled
        self.systemPrompt = systemPrompt
        self.userPromptTemplate = userPromptTemplate
        self.outputFormat = outputFormat
        self.sortOrder = sortOrder
    }
}

// MARK: - Built-in Templates

extension SummaryTemplate {

    /// Executive Summary - concise overview with key decisions
    static let executiveSummary = SummaryTemplate(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Executive Summary",
        description: "Concise overview with key decisions and outcomes",
        icon: "briefcase.fill",
        isBuiltIn: true,
        systemPrompt: """
            You are an expert at summarizing meeting transcripts for busy executives.
            Be concise, focus on decisions made, and highlight what matters most.
            Use clear, professional language.
            """,
        userPromptTemplate: """
            Analyze this meeting transcript and provide an executive summary.

            Format your response as:

            ## Summary
            [2-3 sentence overview of the meeting]

            ## Key Decisions
            - [Decision 1]
            - [Decision 2]

            ## Action Items
            - [ ] [Action item with owner if mentioned]

            ## Next Steps
            [Brief description of what happens next]

            ---

            Transcript:
            {{transcript}}
            """,
        outputFormat: .markdown,
        sortOrder: 0
    )

    /// Action Items - extract all tasks and commitments
    static let actionItems = SummaryTemplate(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "Action Items",
        description: "Extract tasks, commitments, and follow-ups",
        icon: "checklist",
        isBuiltIn: true,
        systemPrompt: """
            You are an expert at extracting action items from meeting transcripts.
            Focus on identifying:
            - Explicit commitments ("I will...", "Let's...", "We need to...")
            - Implicit tasks (things that need to be done based on discussion)
            - Deadlines and owners when mentioned
            Be thorough but don't invent items that weren't discussed.
            """,
        userPromptTemplate: """
            Extract all action items from this meeting transcript.

            Format each item as:
            - [ ] [Task description] — [Owner if known] [Deadline if mentioned]

            Group by:
            ## Immediate (this week)
            ## Soon (next 2 weeks)
            ## Later / No deadline

            If no owner is mentioned, note it as "TBD".

            ---

            Transcript:
            {{transcript}}
            """,
        outputFormat: .actionItems,
        sortOrder: 1
    )

    /// Diarized Transcript - identify speakers and clean up
    static let diarizedTranscript = SummaryTemplate(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "Speaker Transcript",
        description: "Clean transcript with speaker identification",
        icon: "person.2.fill",
        isBuiltIn: true,
        systemPrompt: """
            You are an expert at processing meeting transcripts.
            Your job is to:
            1. Identify different speakers based on context clues (names mentioned, "I", different speaking styles)
            2. Clean up filler words (um, uh, like, you know) while preserving meaning
            3. Fix obvious transcription errors
            4. Add punctuation and formatting for readability

            If you can identify speakers by name, use their names.
            Otherwise use Speaker 1, Speaker 2, etc.
            Be consistent with speaker labels throughout.
            """,
        userPromptTemplate: """
            Process this transcript to identify speakers and improve readability.

            Format as:
            **[Speaker Name/Label]:** [Their statement]

            **[Next Speaker]:** [Their statement]

            Rules:
            - Start a new line for each speaker change
            - Remove filler words (um, uh, like, you know)
            - Fix obvious transcription errors
            - Keep the meaning and tone intact
            - Use timestamps if you can infer them: [00:00]

            ---

            Transcript:
            {{transcript}}
            """,
        outputFormat: .diarizedTranscript,
        sortOrder: 2
    )

    /// Key Points - bullet point summary
    static let keyPoints = SummaryTemplate(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        name: "Key Points",
        description: "Quick bullet-point summary of main topics",
        icon: "list.bullet",
        isBuiltIn: true,
        systemPrompt: """
            You are an expert at distilling meeting content into key points.
            Focus on the most important information discussed.
            Be concise - each point should be one line.
            """,
        userPromptTemplate: """
            Extract the key points from this meeting.

            Format as a simple bullet list:
            • [Key point 1]
            • [Key point 2]
            • [Key point 3]
            ...

            Aim for 5-10 key points depending on meeting length.
            Each point should be self-contained and actionable if relevant.

            ---

            Transcript:
            {{transcript}}
            """,
        outputFormat: .keyPoints,
        sortOrder: 3
    )

    /// Technical Notes - for engineering/technical meetings
    static let technicalNotes = SummaryTemplate(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
        name: "Technical Notes",
        description: "Structured notes for engineering meetings",
        icon: "chevron.left.forwardslash.chevron.right",
        isBuiltIn: true,
        systemPrompt: """
            You are a senior software engineer summarizing technical meetings.
            Focus on:
            - Technical decisions and their rationale
            - Architecture choices
            - Code/system changes discussed
            - Technical debt and concerns raised
            - Performance/security considerations
            Use technical terminology appropriately.
            """,
        userPromptTemplate: """
            Summarize this technical meeting.

            Format:

            ## Overview
            [What was this meeting about?]

            ## Technical Decisions
            - **[Decision]**: [Rationale]

            ## Architecture/Design
            [Any architecture discussions, diagrams in text if relevant]

            ## Code Changes
            - [Component/file]: [What needs to change]

            ## Technical Debt / Concerns
            - [Issue]: [Impact/Priority]

            ## Follow-up Tasks
            - [ ] [Technical task]

            ---

            Transcript:
            {{transcript}}
            """,
        outputFormat: .markdown,
        sortOrder: 4
    )

    /// 1:1 Meeting Notes
    static let oneOnOne = SummaryTemplate(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
        name: "1:1 Notes",
        description: "Structure for manager/report 1:1 meetings",
        icon: "person.crop.circle.badge.checkmark",
        isBuiltIn: true,
        systemPrompt: """
            You are summarizing a 1:1 meeting between a manager and their direct report.
            Focus on:
            - Career development discussions
            - Blockers and challenges
            - Feedback given/received
            - Personal goals and growth areas
            - Team dynamics
            Be sensitive and professional with personal topics.
            """,
        userPromptTemplate: """
            Summarize this 1:1 meeting.

            Format:

            ## Quick Summary
            [1-2 sentences]

            ## Topics Discussed
            - [Topic 1]: [Brief notes]
            - [Topic 2]: [Brief notes]

            ## Blockers / Challenges
            - [Blocker]: [Status/Resolution]

            ## Feedback
            - [Any feedback exchanged]

            ## Career / Growth
            - [Development discussions]

            ## Action Items
            - [ ] [Manager action]
            - [ ] [Report action]

            ## Follow-up for Next 1:1
            - [Topics to revisit]

            ---

            Transcript:
            {{transcript}}
            """,
        outputFormat: .markdown,
        sortOrder: 5
    )

    /// All built-in templates
    static let builtInTemplates: [SummaryTemplate] = [
        .executiveSummary,
        .actionItems,
        .diarizedTranscript,
        .keyPoints,
        .technicalNotes,
        .oneOnOne
    ]

    /// Default template for new meetings
    static let defaultTemplate = executiveSummary
}

// MARK: - Processed Summary

/// The result of processing a transcript with a template
struct ProcessedSummary: Identifiable, Codable, Equatable {
    let id: UUID
    let templateId: UUID
    let templateName: String
    let outputFormat: SummaryTemplate.OutputFormat
    let content: String
    let processedAt: Date
    let modelUsed: String
    let costCents: Int

    init(
        id: UUID = UUID(),
        templateId: UUID,
        templateName: String,
        outputFormat: SummaryTemplate.OutputFormat,
        content: String,
        processedAt: Date = Date(),
        modelUsed: String = "gpt-4o-mini",
        costCents: Int = 0
    ) {
        self.id = id
        self.templateId = templateId
        self.templateName = templateName
        self.outputFormat = outputFormat
        self.content = content
        self.processedAt = processedAt
        self.modelUsed = modelUsed
        self.costCents = costCents
    }
}

// MARK: - Template Manager

/// Manages summary templates (built-in + custom)
class SummaryTemplateManager: ObservableObject {
    static let shared = SummaryTemplateManager()

    @Published var templates: [SummaryTemplate] = []
    @Published var selectedTemplateId: UUID?

    private let storageKey = "customSummaryTemplates"
    private let selectedTemplateKey = "selectedSummaryTemplateId"
    private let enabledTemplatesKey = "enabledSummaryTemplates"

    private init() {
        loadTemplates()
    }

    /// All templates (built-in + custom), sorted by sortOrder
    var allTemplates: [SummaryTemplate] {
        templates.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Only enabled templates
    var enabledTemplates: [SummaryTemplate] {
        allTemplates.filter { $0.isEnabled }
    }

    /// The currently selected template (or default)
    var selectedTemplate: SummaryTemplate {
        if let id = selectedTemplateId,
           let template = templates.first(where: { $0.id == id }) {
            return template
        }
        return SummaryTemplate.defaultTemplate
    }

    // MARK: - Persistence

    private func loadTemplates() {
        // Start with built-in templates
        var loadedTemplates = SummaryTemplate.builtInTemplates
        var seenIds = Set(loadedTemplates.map { $0.id })

        // Load custom templates from UserDefaults (dedupe by ID)
        // Skip any that have built-in IDs (corrupted data cleanup)
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let customTemplates = try? JSONDecoder().decode([SummaryTemplate].self, from: data) {
            var cleanedCustom: [SummaryTemplate] = []
            for template in customTemplates {
                // Skip if it's a duplicate or has a built-in ID
                if !seenIds.contains(template.id) {
                    cleanedCustom.append(template)
                    loadedTemplates.append(template)
                    seenIds.insert(template.id)
                }
            }
            // If we cleaned up corrupted data, save it back
            if cleanedCustom.count != customTemplates.count {
                print("[SummaryTemplateManager] Cleaned up \(customTemplates.count - cleanedCustom.count) duplicate templates from storage")
                if let cleanedData = try? JSONEncoder().encode(cleanedCustom) {
                    UserDefaults.standard.set(cleanedData, forKey: storageKey)
                }
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

        // Final deduplication safety check (should not be needed but prevents runtime crash)
        var finalIds = Set<UUID>()
        var uniqueTemplates: [SummaryTemplate] = []
        for template in loadedTemplates {
            if !finalIds.contains(template.id) {
                uniqueTemplates.append(template)
                finalIds.insert(template.id)
            }
        }

        if uniqueTemplates.count != loadedTemplates.count {
            print("[SummaryTemplateManager] Warning: Removed \(loadedTemplates.count - uniqueTemplates.count) duplicate templates")
        }

        templates = uniqueTemplates

        // Load selected template
        if let selectedIdString = UserDefaults.standard.string(forKey: selectedTemplateKey),
           let selectedId = UUID(uuidString: selectedIdString) {
            selectedTemplateId = selectedId
        } else {
            selectedTemplateId = SummaryTemplate.defaultTemplate.id
        }
    }

    func saveTemplates() {
        // Only save custom templates
        let customTemplates = templates.filter { !$0.isBuiltIn }
        if let data = try? JSONEncoder().encode(customTemplates) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }

        // Save enabled states for all templates
        var enabledStates: [String: Bool] = [:]
        for template in templates {
            enabledStates[template.id.uuidString] = template.isEnabled
        }
        UserDefaults.standard.set(enabledStates, forKey: enabledTemplatesKey)

        // Save selected template
        if let selectedId = selectedTemplateId {
            UserDefaults.standard.set(selectedId.uuidString, forKey: selectedTemplateKey)
        }
    }

    // MARK: - CRUD

    func addTemplate(_ template: SummaryTemplate) {
        var newTemplate = template
        newTemplate.sortOrder = templates.count
        templates.append(newTemplate)
        saveTemplates()
    }

    func updateTemplate(_ template: SummaryTemplate) {
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index] = template
            saveTemplates()
        }
    }

    func deleteTemplate(_ template: SummaryTemplate) {
        guard !template.isBuiltIn else { return } // Can't delete built-in
        templates.removeAll { $0.id == template.id }
        saveTemplates()
    }

    func toggleEnabled(_ template: SummaryTemplate) {
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index].isEnabled.toggle()
            saveTemplates()
        }
    }

    func selectTemplate(_ template: SummaryTemplate) {
        selectedTemplateId = template.id
        saveTemplates()
    }

    func resetToDefaults() {
        // Remove custom templates
        templates = SummaryTemplate.builtInTemplates
        selectedTemplateId = SummaryTemplate.defaultTemplate.id

        // Clear storage
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: enabledTemplatesKey)
        saveTemplates()
    }

    /// Duplicate a template (creates an editable copy)
    func duplicateTemplate(_ template: SummaryTemplate) -> SummaryTemplate {
        let copy = SummaryTemplate(
            id: UUID(),
            name: "\(template.name) (Copy)",
            description: template.description,
            icon: template.icon,
            isBuiltIn: false,
            isEnabled: template.isEnabled,
            systemPrompt: template.systemPrompt,
            userPromptTemplate: template.userPromptTemplate,
            outputFormat: template.outputFormat,
            sortOrder: templates.count
        )
        addTemplate(copy)
        return copy
    }
}
