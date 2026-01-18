# PRD: Actionable Meeting Intelligence

**Version:** 1.0
**Date:** 2026-01-17
**Status:** Design Complete

---

## 1. The Problem

Current meeting "summaries" are passive recaps that get skimmed and forgotten. Users still:

- Forget follow-ups because action items aren't tracked anywhere
- Waste time re-watching recordings to remember what was decided
- Miss deadlines because there's no system connecting meetings to tasks
- Have no accountability on who's responsible for what

**The insight:** A meeting isn't valuable for what was *said* - it's valuable for what needs to *happen next*.

---

## 2. The Shift: From Summaries to Actionable Intelligence

### Before (Current)

```
Summary: "We discussed Q2 pricing. Everyone agreed to move to usage-based..."
```

→ Gets ignored. Falls into the void.

### After (New)

```
MEETING BRIEF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📌 Purpose: Q2 Pricing Review

👥 Participants: Bruno, Sarah, Mike

📝 Discussion Points:
   • Competitor analysis shows market moving to usage-based
   • Existing customers need migration path
   • Legal flagged contract amendment requirements

✅ Decisions Made:
   • Moving to usage-based for new customers
   • Existing customers get 6-month notice
   • Mike to lead implementation

⏳ Decisions Pending:
   • Final tier pricing (needs finance input)
   • Migration timeline (blocked on legal)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ACTION ITEMS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

□ Send pricing proposal to stakeholders
  → Bruno | Due: Friday, Jan 24 | Priority: High

□ Review competitor analysis spreadsheet
  → Sarah | Due: Wed, Jan 22 | Priority: Medium

□ Draft contract amendment templates
  → Mike | Due: Next week | Priority: Medium

□ Schedule follow-up with finance
  → Bruno | Due: Tomorrow | Priority: High
```

→ Clear accountability. Trackable. Actionable.

---

## 3. Core Features

### 3.1 Smart Meeting Brief

**Instead of a blob of text, generate structured intelligence:**

| Field | Description | Source |
|-------|-------------|--------|
| **Purpose** | What was this meeting about? (1 line) | Inferred from transcript |
| **Participants** | Who was in the meeting | Diarization + speaker labels |
| **Discussion Points** | 3-7 key topics discussed | Extracted from transcript |
| **Decisions Made** | What was agreed upon | Explicit decisions in transcript |
| **Decisions Pending** | What still needs to be decided | Unresolved topics |
| **Blockers Identified** | Dependencies or issues raised | Problems mentioned |

### 3.2 Structured Action Items

**Each action item has:**

```swift
struct ActionItem: Codable, Identifiable {
    let id: UUID
    let task: String                    // "Send pricing proposal"
    let assignee: String?               // "Bruno"
    let dueDate: Date?                  // Jan 24, 2026
    let dueSuggestion: String?          // "by Friday" (raw from AI)
    let priority: Priority              // high, medium, low
    let context: String?                // Meeting reference
    let meetingId: UUID                 // Link back to source meeting
    let status: ActionStatus            // open, completed, cancelled
    let createdAt: Date
    let completedAt: Date?

    enum Priority: String, Codable {
        case high, medium, low
    }

    enum ActionStatus: String, Codable {
        case open, completed, cancelled
    }
}
```

### 3.3 Action Items Dashboard

**A new view to manage all open action items across meetings:**

- **Grouped by due date:** Today, This Week, Next Week, Later, No Due Date
- **Filter by:** Assignee, Priority, Meeting, Status
- **Sort by:** Due date, Priority, Meeting date, Assignee
- **Quick actions:** Complete, Snooze, Delete, Edit
- **Sync status:** Indicator if synced to external systems

### 3.4 Sync to External Systems

**v1.0 - Export:**
- Copy all open action items as Markdown
- Copy as plain text checklist
- Export to JSON for automation

**v1.1 - Integrations:**
- Apple Reminders (native integration)
- Todoist (API)
- Linear (API)
- Notion (API)
- Custom webhook

---

## 4. AI Provider: Gemini Flash 3

### Why Gemini Flash 3?

| Factor | Gemini Flash 3 | GPT-4o-mini | Claude Haiku |
|--------|---------------|-------------|--------------|
| **Cost** | ~$0.075/1M tokens | $0.15/1M | $0.25/1M |
| **Speed** | Very fast | Fast | Fast |
| **Long context** | 1M tokens | 128K | 200K |
| **Structured output** | Native JSON mode | JSON mode | Less reliable |

**Gemini Flash 3 is 2x cheaper and handles long transcripts better.**

### Implementation

```swift
enum SummarizationProvider {
    case geminiFlash3      // Default for v2
    case openai            // Fallback
    case anthropic         // Fallback
}
```

The existing `SummarizationProcess` already supports Gemini - we just need to:
1. Add `gemini-2.0-flash-exp` model option (or latest stable)
2. Make it the default for meeting briefs
3. Update the prompt to extract structured action items

---

## 5. Data Model Changes

### 5.1 New: ActionItem Table

```sql
CREATE TABLE action_items (
    id TEXT PRIMARY KEY,
    meeting_id TEXT NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
    task TEXT NOT NULL,
    assignee TEXT,
    due_date DATETIME,
    due_suggestion TEXT,
    priority TEXT NOT NULL DEFAULT 'medium',
    context TEXT,
    status TEXT NOT NULL DEFAULT 'open',
    created_at DATETIME NOT NULL,
    completed_at DATETIME,
    synced_to TEXT,           -- JSON array of sync targets
    external_ids TEXT         -- JSON object {todoist: "123", linear: "ABC-123"}
);

CREATE INDEX idx_action_items_meeting ON action_items(meeting_id);
CREATE INDEX idx_action_items_status ON action_items(status);
CREATE INDEX idx_action_items_due ON action_items(due_date);
CREATE INDEX idx_action_items_assignee ON action_items(assignee);
```

### 5.2 Enhanced: Meeting Brief

```sql
-- Add to meetings table
ALTER TABLE meetings ADD COLUMN meeting_brief TEXT;  -- JSON MeetingBrief
ALTER TABLE meetings ADD COLUMN brief_generated_at DATETIME;
```

```swift
struct MeetingBrief: Codable {
    let purpose: String
    let participants: [String]
    let discussionPoints: [String]
    let decisionsMade: [String]
    let decisionsPending: [String]
    let blockers: [String]?
    let generatedAt: Date
    let model: String
    let provider: String
}
```

---

## 6. UI Changes

### 6.1 Meeting Detail View - Enhanced

Replace the current summary section with the structured Meeting Brief:

```
┌─────────────────────────────────────────────────────────────────┐
│  ← Back           Client Call - Acme Corp           [▶ Play]   │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  [Transcript] [Brief] [Action Items] [Speakers]                 │
│                 ▼                                               │
│  ───────────────────────────────────────────────────────────── │
│                                                                 │
│  📌 Purpose                                                     │
│  Q2 pricing strategy review and alignment                       │
│                                                                 │
│  👥 Participants                                                │
│  Bruno, Sarah, Mike, Jennifer                                   │
│                                                                 │
│  📝 Key Discussion Points                                       │
│  • Competitor pricing analysis (usage-based trending)           │
│  • Migration path for existing enterprise customers             │
│  • Legal review of contract amendments                          │
│  • Timeline constraints from sales team                         │
│                                                                 │
│  ✅ Decisions Made                                              │
│  • New customers will be on usage-based starting Q2             │
│  • Existing customers get 6-month migration notice              │
│  • Mike will own implementation                                 │
│                                                                 │
│  ⏳ Pending Decisions                                           │
│  • Final tier pricing needs finance approval                    │
│  • Migration timeline blocked on legal review                   │
│                                                                 │
│  ⚠️ Blockers                                                    │
│  • Legal hasn't reviewed contract templates yet                 │
│  • Finance input needed for tier calculations                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 6.2 Meeting Detail View - Action Items Tab

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  [Transcript] [Brief] [Action Items] [Speakers]                 │
│                              ▼                                  │
│  ───────────────────────────────────────────────────────────── │
│                                                                 │
│  4 action items from this meeting              [+ Add] [Export] │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ □  Send pricing proposal to stakeholders                  │ │
│  │    Bruno • Due Friday, Jan 24 • 🔴 High                   │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ □  Review competitor analysis spreadsheet                 │ │
│  │    Sarah • Due Wed, Jan 22 • 🟡 Medium                    │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ ☑  Draft contract amendment templates                     │ │
│  │    Mike • Completed Jan 20 ✓                              │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ □  Schedule follow-up with finance                        │ │
│  │    Bruno • Due Tomorrow • 🔴 High                         │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 6.3 New: Action Items Dashboard (Sidebar Item)

A new top-level view in the sidebar:

```
┌────────────────────────────────────────────────────────────────────────────┐
│                                                                            │
│  Action Items                                                   [Export ▾] │
│                                                                            │
│  ┌────────────────────────────────────────────────────────────────────┐   │
│  │  🔍 Search action items...                      [All ▾] [Open ▾]   │   │
│  └────────────────────────────────────────────────────────────────────┘   │
│                                                                            │
│  ───────────────────────────────────────────────────────────────────────  │
│                                                                            │
│  🔴 OVERDUE (2)                                                           │
│  ───────────────────────────────────────────────────────────────────────  │
│                                                                            │
│  ┌────────────────────────────────────────────────────────────────────┐   │
│  │ □  Finalize Q1 retrospective doc                                  │   │
│  │    You • Due Jan 15 (2 days ago)                                  │   │
│  │    From: Weekly Planning (Jan 13)                         [Mark ✓]│   │
│  └────────────────────────────────────────────────────────────────────┘   │
│                                                                            │
│  📅 TODAY (1)                                                             │
│  ───────────────────────────────────────────────────────────────────────  │
│                                                                            │
│  ┌────────────────────────────────────────────────────────────────────┐   │
│  │ □  Schedule follow-up with finance                                │   │
│  │    You • Due today                                                │   │
│  │    From: Client Call - Acme (Jan 17)                      [Mark ✓]│   │
│  └────────────────────────────────────────────────────────────────────┘   │
│                                                                            │
│  📆 THIS WEEK (3)                                                         │
│  ───────────────────────────────────────────────────────────────────────  │
│                                                                            │
│  ┌────────────────────────────────────────────────────────────────────┐   │
│  │ □  Review competitor analysis                                     │   │
│  │    Sarah • Due Wed, Jan 22                                        │   │
│  │    From: Client Call - Acme (Jan 17)                      [Mark ✓]│   │
│  └────────────────────────────────────────────────────────────────────┘   │
│                                                                            │
│  ┌────────────────────────────────────────────────────────────────────┐   │
│  │ □  Send pricing proposal                                          │   │
│  │    You • Due Fri, Jan 24                                          │   │
│  │    From: Client Call - Acme (Jan 17)                      [Mark ✓]│   │
│  └────────────────────────────────────────────────────────────────────┘   │
│                                                                            │
│  📆 NEXT WEEK (1)                                                         │
│  ───────────────────────────────────────────────────────────────────────  │
│                                                                            │
│  ...                                                                       │
│                                                                            │
│  🗓 NO DUE DATE (2)                                                       │
│  ───────────────────────────────────────────────────────────────────────  │
│                                                                            │
│  ...                                                                       │
│                                                                            │
│  ───────────────────────────────────────────────────────────────────────  │
│                                                                            │
│  ✅ COMPLETED (12)                                              [Show ▾]  │
│                                                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

### 6.4 Sidebar Update

```
┌────────────┐
│    🏠      │  Home (unchanged)
├────────────┤
│    📅      │  Calendar (unchanged)
├────────────┤
│    ☐       │  Action Items (NEW)
├────────────┤
│    📁      │  Groups (unchanged)
├────────────┤
│    📊      │  Analytics (unchanged)
├────────────┤
│    ⚙️      │  Settings (unchanged)
└────────────┘
```

### 6.5 Home View Update

Add an "Action Items" section to the home view:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│  Good morning, Bruno                                                        │
│                                                                             │
│  ═══════════════════════════════════════════════════════════════════════   │
│                                                                             │
│  ⚡ Action Items                                               [See All →] │
│  ─────────────────────────────────────────────────────────────────────────  │
│                                                                             │
│  🔴 2 overdue • 📅 1 due today • 📆 4 due this week                        │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐ │
│  │ □  Schedule follow-up with finance          You • Due today    [✓]   │ │
│  ├───────────────────────────────────────────────────────────────────────┤ │
│  │ □  Send pricing proposal                    You • Due Fri      [✓]   │ │
│  ├───────────────────────────────────────────────────────────────────────┤ │
│  │ □  Review competitor analysis               Sarah • Due Wed    [✓]   │ │
│  └───────────────────────────────────────────────────────────────────────┘ │
│                                                                             │
│  ═══════════════════════════════════════════════════════════════════════   │
│                                                                             │
│  📅 Recent Meetings                                            [See All →] │
│  ...                                                                        │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 7. Implementation Plan

### Phase 1: Core Data Model (Day 1)

1. Add `ActionItem` model with database migration
2. Add `MeetingBrief` model
3. Update Meeting model to include brief
4. Add `ActionItemManager` service

### Phase 2: AI Extraction (Day 1-2)

1. Create new Gemini Flash 3 prompt for structured extraction
2. Update `SummarizationProcess` to generate `MeetingBrief` + `ActionItem[]`
3. Add "Generate Brief" button to meeting detail
4. Auto-generate on transcription complete

### Phase 3: Meeting Detail UI (Day 2)

1. Add "Brief" tab to MeetingDetailView
2. Add "Action Items" tab to MeetingDetailView
3. Implement action item CRUD (complete, edit, delete)
4. Add inline action item creation

### Phase 4: Action Items Dashboard (Day 3)

1. Add Action Items to sidebar
2. Create `ActionItemsView` with grouping/filtering
3. Implement quick actions (complete, snooze)
4. Add export functionality

### Phase 5: Home View Integration (Day 3)

1. Add action items summary widget to HomeView
2. Show overdue/today/upcoming counts
3. Quick complete from home view

### Phase 6: Sync Infrastructure (Day 4, Optional)

1. Export to Markdown/JSON
2. Copy to clipboard
3. Apple Reminders integration (if time permits)

---

## 8. Prompt Engineering

### Meeting Brief + Action Items Prompt

```
You are an expert meeting analyst. Analyze this meeting transcript and extract actionable intelligence.

Respond with JSON in this exact format:
{
  "brief": {
    "purpose": "One-line description of meeting purpose",
    "participants": ["Name1", "Name2"],
    "discussion_points": ["Point 1", "Point 2", ...],
    "decisions_made": ["Decision 1", ...],
    "decisions_pending": ["Pending decision 1", ...],
    "blockers": ["Blocker 1", ...] or null if none
  },
  "action_items": [
    {
      "task": "Clear, actionable task description",
      "assignee": "Person name" or null if unclear,
      "due_suggestion": "by Friday" or "next week" or "ASAP" or null,
      "priority": "high" | "medium" | "low",
      "context": "Brief context from meeting" or null
    }
  ]
}

Guidelines:
- Extract ONLY explicitly mentioned action items (things someone committed to DO)
- Infer priority from urgency language ("ASAP", "critical", "when you get a chance")
- Use exact names mentioned in transcript for assignees
- If no clear assignee, leave null (don't guess)
- Due suggestions should use relative terms from the meeting context
- Keep discussion points to 3-7 most important topics
- Decisions must be explicit agreements, not assumptions

TRANSCRIPT:
{transcript}
```

---

## 9. Success Metrics

### Engagement

- % of meetings with generated briefs
- % of action items completed (vs abandoned)
- Time from meeting end to first action item completed

### Retention

- Users who view action items dashboard weekly
- Users who complete at least one action item per week

### Quality

- User edits to AI-generated action items (lower = better)
- Action items manually deleted (lower = better)
- User-added action items (shows engagement)

---

## 10. Future Enhancements (v1.1+)

### Smart Reminders
- Push notification before action item due
- Daily digest email with open items

### Team Features
- Share action items with teammates
- See items assigned to others
- Team action item dashboard

### Recurring Meetings
- Track action items across recurring meetings
- Show "carryover" items from previous meetings

### AI Follow-up
- "What happened to the action items from last week's standup?"
- Auto-detect completed items from subsequent meetings

### Calendar Integration
- Create calendar events for action items with due dates
- Block time for high-priority items

---

*Ready to build.*
