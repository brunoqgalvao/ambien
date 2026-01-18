# MeetingRecorder Architecture

Quick reference for all components and what to call them.

---

## High-Level Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        APP ENTRY POINT                          │
│  MeetingRecorderApp.swift → AppDelegate → MenuBarDropdown       │
└─────────────────────────────────────────────────────────────────┘
                              │
          ┌───────────────────┼───────────────────┐
          ▼                   ▼                   ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│   MAIN WINDOW   │  │   MENU BAR      │  │   OVERLAYS      │
│   MainAppView   │  │   MenuBarExtra  │  │   Floating UI   │
└─────────────────┘  └─────────────────┘  └─────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────────┐
│                          VIEWS (UI)                             │
│  HomeView │ CalendarView │ MeetingDetailView │ MeetingGroupsView│
└─────────────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────────┐
│                    TRANSCRIPTION PIPELINE                       │
│  TranscriptionProcess → Provider (OpenAI/Deepgram/Gemini)       │
│  AudioCompressor → SilenceProcessor → SummarizationProcess      │
└─────────────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────────┐
│                       CORE SERVICES                             │
│  AudioCaptureManager │ DatabaseManager │ GroupManager           │
└─────────────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────────┐
│                       DATA MODELS                               │
│  Meeting │ MeetingGroup │ QuickRecording │ SummaryTemplate      │
└─────────────────────────────────────────────────────────────────┘
```

---

## Data Models

| Name | File | Purpose |
|------|------|---------|
| **Meeting** | `Meeting.swift` | Core meeting record (title, audio path, transcript, status, cost) |
| **MeetingStatus** | `Meeting.swift` | Enum: `recording`, `pendingTranscription`, `transcribing`, `ready`, `failed` |
| **MeetingGroup** | `MeetingGroup.swift` | Group of related meetings (project, client, series) |
| **QuickRecording** | `QuickRecording.swift` | Voice note from quick dictation |
| **SummaryTemplate** | `SummaryTemplate.swift` | AI prompt template for post-processing |
| **ProcessedSummary** | `Meeting.swift` | Result from running a template on transcript |
| **AutoRuleStat** | `AutoRuleStats.swift` | Tracks auto-record rule usage and discard counts |

---

## Backend Services

### Core Services

| Name | File | Purpose |
|------|------|---------|
| **AudioCaptureManager** | `AudioCaptureManager.swift` | Records system audio (ScreenCaptureKit) + mic (AVAudioEngine), saves .m4a |
| **DatabaseManager** | `DatabaseManager.swift` | SQLite via GRDB.swift with FTS5 search |
| **GroupManager** | `GroupManager.swift` | CRUD for meeting groups, membership, combined transcripts |
| **KeychainHelper** | `KeychainHelper.swift` | Secure API key storage (OpenAI, Deepgram, Anthropic, Gemini) |
| **AgentAPIManager** | `AgentAPIManager.swift` | JSON export to `~/.meetingrecorder/meetings/` for AI agents |

### Transcription Pipeline

| Name | File | Purpose |
|------|------|---------|
| **TranscriptionProcess** | `TranscriptionProcess.swift` | Orchestrates transcription: preprocess → transcribe → post-process |
| **TranscriptionService** | `TranscriptionService.swift` | Legacy facade (use TranscriptionProcess for new code) |
| **DeepgramTranscriptionProvider** | `DeepgramTranscriptionProvider.swift` | Deepgram API provider (Nova-3, $0.0043/min, 2GB max) |
| **SummarizationProcess** | `SummarizationProcess.swift` | Generates summaries via OpenAI/Anthropic/Gemini |
| **PostProcessingService** | `PostProcessingService.swift` | GPT-4o-mini for summaries, action items, diarization |

### Audio Processing

| Name | File | Purpose |
|------|------|---------|
| **AudioCompressor** | `AudioCompressor.swift` | Compresses audio to fit OpenAI's 25MB limit (32/16/8 kbps) |
| **SilenceProcessor** | `SilenceProcessor.swift` | Detects and crops silences to reduce file size |

### Meeting Context

| Name | File | Purpose |
|------|------|---------|
| **ParticipantService** | `ParticipantService.swift` | OCR screenshots to extract participant names |

---

## Automation Services

| Name | File | Purpose |
|------|------|---------|
| **HotkeyManager** | `HotkeyManager.swift` | Global hotkey registration (Ctrl+Cmd+D) via CGEvent tap |
| **DictationManager** | `DictationManager.swift` | Hold-to-dictate: record mic → transcribe → paste at cursor |
| **MeetingDetector** | `MeetingDetector.swift` | Auto-detect Zoom/Meet/Teams/Slack/FaceTime/WhatsApp |
| **WhatsAppCallDetector** | `WhatsAppCallDetector.swift` | Detects WhatsApp calls via audio activity monitoring |
| **AutoRuleStatsManager** | `AutoRuleStats.swift` | Tracks auto-record stats, auto-disables frequently discarded rules |

---

## UI - Windows & Controllers

| Name | File | Purpose |
|------|------|---------|
| **AppDelegate** | `MeetingRecorderApp.swift` | Menu bar icon, popover, global state |
| **MainAppWindowController** | `MainAppWindow.swift` | Main app window (singleton) |
| **SettingsWindowController** | `SettingsView.swift` | Settings window (singleton) |
| **OnboardingWizardController** | `OnboardingWizard.swift` | First-run wizard (singleton) |
| **AboutWindowController** | `MeetingRecorderApp.swift` | About window (singleton) |
| **RecordingIslandController** | `RecordingIsland.swift` | Floating notch indicator (singleton) |
| **QuickRecordingPillController** | `QuickDictationPill.swift` | Floating dictation pill (singleton) |

---

## UI - Main Views

| Name | File | Purpose |
|------|------|---------|
| **MainAppView** | `MainAppWindow.swift` | Root view: sidebar + detail area |
| **SidebarView** | `SidebarView.swift` | 80px icon navigation |
| **HomeView** | `HomeView.swift` | Welcome screen with nudges & recent activity |
| **CalendarView** | `CalendarView.swift` | Date picker + meeting list |
| **MeetingListView** | `MeetingListView.swift` | Scrollable meeting list with search |
| **MeetingDetailView** | `MeetingDetailView.swift` | Full meeting: transcript, audio, summaries, speakers |
| **MeetingGroupsView** | `MeetingGroupsView.swift` | Group management: list, create, detail |
| **TemplatesView** | `TemplatesView.swift` | Template editor (master-detail) |
| **AnalyticsView** | `AnalyticsView.swift` | Usage dashboard, spend tracking |
| **SettingsView** | `SettingsView.swift` | Settings tabs (General, API, Costs, Templates) |

---

## UI - Settings Tabs

| Name | File | Tab |
|------|------|-----|
| **GeneralSettingsTab** | `SettingsView.swift` | Auto-detection, hotkey, compression settings |
| **APISettingsTab** | `SettingsView.swift` | Multi-provider API key management |
| **CostsSettingsTab** | `SettingsView.swift` | Usage & spending |
| **SummaryTemplatesSettingsTab** | `SummaryTemplatesSettingsTab.swift` | Template management |

---

## UI - Components (Reusable)

### Brand Components (`BrandComponents.swift`)

| Name | Purpose |
|------|---------|
| **BrandPrimaryButton** | Main CTAs (violet) |
| **BrandSecondaryButton** | Cancel, secondary actions |
| **BrandDestructiveButton** | Delete, dangerous actions (coral) |
| **BrandIconButton** | Toolbar icons |
| **BrandMenuButton** | Menu dropdown items |
| **BrandTabButton** | Tab selectors |
| **BrandListRow** | List items with hover states |
| **BrandSearchField** | Search inputs |
| **BrandTextField** | Form inputs |
| **BrandCard** | Content containers |
| **BrandBadge** | Labels, tags |
| **BrandStatusBadge** | Meeting status indicators |
| **BrandStatusDot** | Simple status dots |

### Other Components

| Name | File | Purpose |
|------|------|---------|
| **MenuBarDropdown** | `MeetingRecorderApp.swift` | Menu bar popover content |
| **MeetingRowView** | `MeetingListView.swift` | Meeting card in list |
| **HomeMeetingRow** | `HomeView.swift` | Meeting preview on home |
| **NudgeCard** | `HomeView.swift` | Setup reminder cards |
| **CustomCalendarView** | `CalendarView.swift` | Interactive calendar grid |
| **AudioPlayerCard** | `MeetingDetailView.swift` | Audio playback controls |
| **TranscriptSummarySection** | `MeetingDetailView.swift` | Transcript vs summaries tabs |
| **SpeakerLabelingView** | `SpeakerLabelingView.swift` | Label speakers in diarized transcript |
| **QuickDictationPill** | `QuickDictationPill.swift` | Floating dictation indicator |
| **RecordingIsland** | `RecordingIsland.swift` | Notch-aware recording indicator |
| **ErrorToast** | `ErrorToast.swift` | Temporary error notifications |
| **OnboardingView** | `OnboardingView.swift` | Multi-step onboarding wizard |

---

## Design Tokens (`BrandAssets.swift`)

| Name | Values |
|------|--------|
| **Brand Colors** | violet, coral, mint, amber, cream, ink |
| **Semantic Colors** | brandBackground, brandSurface, brandTextPrimary/Secondary, brandBorder |
| **BrandRadius** | small(8), medium(16), large(32), pill(999) |
| **Font Extensions** | brandDisplay(), brandSerif(), brandMono() |

---

## Utilities

| Name | File | Purpose |
|------|------|---------|
| **AppLogger** | `AppLogger.swift` | Centralized file logging (~/Library/Logs/MeetingRecorder/) |
| **TestAPIServer** | `TestAPIServer.swift` | Local HTTP server for automated testing (localhost:8765) |
| **ValidationManager** | `ValidationManager.swift` | M0 dev environment tests |
| **DebugKeyboardHandler** | `DebugTools.swift` | Cmd+Shift+D frame inspector |
| **SummaryTemplateManager** | `TemplatesView.swift` | Template persistence (singleton) |
| **QuickRecordingStorage** | `QuickRecording.swift` | Quick recording SQLite storage |

---

## Enums & Types

### Transcription Providers
```swift
enum TranscriptionProvider: String, CaseIterable {
    case openai      // gpt-4o-mini-transcribe, whisper-1
    case deepgram    // Nova-3 ($0.0043/min, 2GB max)
    case assemblyai
    case gemini
}
```

### Summarization Providers
```swift
enum SummarizationProvider: String, CaseIterable {
    case openai    // GPT-4o-mini
    case anthropic // Claude
    case gemini
}
```

### Meeting Apps
```swift
enum MeetingApp: String, CaseIterable {
    case zoom, googleMeet, teams, slack, faceTime, whatsApp
}
```

### Audio Compression
```swift
enum CompressionLevel: Int, CaseIterable {
    case standard = 0   // 32kbps
    case aggressive = 1 // 16kbps
    case extreme = 2    // 8kbps
}
```

---

## Data Flow Diagrams

### Recording Flow
```
User clicks Record
       │
       ▼
AppDelegate.toggleRecording()
       │
       ▼
AudioCaptureManager.startRecording()
       │
       ├─► ScreenCaptureKit (system audio)
       ├─► AVAudioEngine (microphone)
       └─► ParticipantService.captureParticipants() [optional]
               │
               ▼
         Mix + Save .m4a
               │
               ▼
    DatabaseManager.insert(Meeting)
               │
               ▼
    TranscriptionProcess.transcribe()
       │
       ├─► AudioCompressor (if > 25MB)
       ├─► SilenceProcessor (if enabled)
       └─► Provider (OpenAI/Deepgram/Gemini)
               │
               ▼
    Meeting.status = .ready
```

### Dictation Flow
```
User holds Ctrl+Cmd+D
       │
       ▼
HotkeyManager.onKeyDown
       │
       ▼
DictationManager.startDictation()
       │
       ▼
    AVAudioEngine (mic only)
       │
User releases key
       │
       ▼
DictationManager.stopDictation()
       │
       ▼
TranscriptionProcess.transcribe()
       │
       ▼
Paste at cursor (NSPasteboard)
```

### Post-Processing Flow
```
User selects template in MeetingDetailView
       │
       ▼
SummarizationProcess.process(transcript, template)
       │
       ├─► OpenAI (GPT-4o-mini)
       ├─► Anthropic (Claude)
       └─► Gemini
               │
               ▼
Meeting.processedSummaries.append(result)
       │
       ▼
DatabaseManager.update(meeting)
```

### Meeting Group Flow
```
User creates group in MeetingGroupsView
       │
       ▼
GroupManager.createGroup(name, emoji, color)
       │
       ▼
User adds meetings to group
       │
       ▼
GroupManager.addMeetings(groupId, meetingIds)
       │
       ▼
GroupManager.getCombinedTranscript(groupId)
       │
       ▼
AgentAPIManager.exportGroup(group) → ~/.meetingrecorder/groups/
```

---

## File Structure

```
MeetingRecorder/
├── MeetingRecorderApp.swift       # Entry point, AppDelegate, MenuBarDropdown
├── Meeting.swift                  # Meeting model, MeetingStatus enum
├── MeetingGroup.swift             # Group model for organizing meetings
├── QuickRecording.swift           # Voice note model + storage
├── SummaryTemplate.swift          # AI template model
│
├── AudioCaptureManager.swift      # Recording service (ScreenCaptureKit + AVAudioEngine)
├── AudioCompressor.swift          # Compress audio to fit API limits
├── SilenceProcessor.swift         # Crop silences from audio
│
├── TranscriptionProcess.swift     # Orchestrates transcription pipeline
├── TranscriptionService.swift     # Legacy facade (backwards compat)
├── DeepgramTranscriptionProvider.swift  # Deepgram API
├── SummarizationProcess.swift     # Multi-provider summarization
├── PostProcessingService.swift    # GPT summaries/action items
│
├── DatabaseManager.swift          # SQLite + FTS5
├── GroupManager.swift             # Meeting groups CRUD
├── KeychainHelper.swift           # Secure API key storage
├── AgentAPIManager.swift          # JSON export for agents
├── ParticipantService.swift       # OCR participant detection
│
├── HotkeyManager.swift            # Global hotkey (Ctrl+Cmd+D)
├── DictationManager.swift         # Hold-to-dictate system
├── MeetingDetector.swift          # Auto-detect meetings
├── WhatsAppCallDetector.swift     # WhatsApp call detection
├── AutoRuleStats.swift            # Auto-record rule statistics
│
├── MainAppWindow.swift            # Main window controller
├── SidebarView.swift              # Navigation sidebar
├── HomeView.swift                 # Welcome screen
├── CalendarView.swift             # Date picker + list
├── MeetingListView.swift          # Meeting list
├── MeetingDetailView.swift        # Meeting detail + speakers
├── MeetingGroupsView.swift        # Group management UI
├── TemplatesView.swift            # Template editor
├── AnalyticsView.swift            # Usage dashboard
├── SettingsView.swift             # Settings window + tabs
├── SummaryTemplatesSettingsTab.swift
├── SpeakerLabelingView.swift      # Label speakers in transcript
│
├── BrandAssets.swift              # Design tokens (colors, fonts, radius)
├── BrandComponents.swift          # Reusable UI components
├── ContentView.swift              # Legacy menu bar UI
├── RecordingIsland.swift          # Floating notch indicator
├── QuickDictationPill.swift       # Floating dictation pill
├── OnboardingWizard.swift         # First-run wizard controller
├── OnboardingView.swift           # Onboarding UI
├── ErrorToast.swift               # Error notifications
│
├── AppLogger.swift                # Centralized logging
├── TestAPIServer.swift            # Test HTTP server
├── ValidationManager.swift        # Dev validation
├── DebugTools.swift               # Debug utilities
│
├── Info.plist
└── MeetingRecorder.entitlements
```

---

## Optimistic Updates Pattern

**Principle:** Update the UI immediately, then perform the actual operation in the background. If the operation fails, revert (or show error). This provides a snappy, responsive feel.

### Pattern

```swift
// 1. Update UI state immediately (optimistic)
viewModel.items.removeAll { $0.id == item.id }
selectedItem = nil  // Clear selection if deleting selected item

// 2. Perform actual operation in background
Task {
    try? await DatabaseManager.shared.delete(item.id)
    NotificationCenter.default.post(name: .dataDidChange, object: nil)
}
```

### When to Use

| Operation | Optimistic? | Why |
|-----------|-------------|-----|
| Delete | Yes | User expects immediate removal |
| Create | Yes | Show new item immediately |
| Update/Edit | Yes | Reflect changes instantly |
| Fetch/Load | No | Can't show data we don't have |

### Delete Flow Example

```swift
private func deleteMeeting(_ meeting: Meeting) {
    // 1. Clear selection if this is selected
    if selectedMeeting?.id == meeting.id {
        selectedMeeting = nil
    }

    // 2. Remove from local list immediately
    viewModel.meetings.removeAll { $0.id == meeting.id }

    // 3. Actual deletion in background
    Task {
        try? FileManager.default.removeItem(atPath: meeting.audioPath)
        try? await DatabaseManager.shared.delete(meeting.id)
        NotificationCenter.default.post(name: .meetingsDidChange, object: nil)
    }
}
```

### Handling in Child Views

When a detail view deletes its item:
1. Notify parent via callback (`onDeleted`)
2. Parent clears selection and removes from list

```swift
// Parent view
MeetingDetailView(
    meeting: meeting,
    onDeleted: { selectedMeeting = nil }
)

// Also handle deletion from elsewhere
.onChange(of: viewModel.meetings) { _, newMeetings in
    if let currentId = selectedMeeting?.id,
       !newMeetings.contains(where: { $0.id == currentId }) {
        selectedMeeting = nil  // Meeting was deleted
    }
}
```

---

## Quick Reference: "What do I call..."

| When you want to... | Reference |
|---------------------|-----------|
| Start/stop recording | `AudioCaptureManager.shared` |
| Transcribe audio | `TranscriptionProcess.shared` |
| Compress large audio | `AudioCompressor` |
| Crop silences | `SilenceProcessor` |
| Generate summary | `SummarizationProcess` / `PostProcessingService` |
| Store/query meetings | `DatabaseManager` |
| Manage meeting groups | `GroupManager` |
| Store API key | `KeychainHelper` |
| Export for agents | `AgentAPIManager` |
| Register hotkey | `HotkeyManager` |
| Dictate anywhere | `DictationManager` |
| Detect meetings | `MeetingDetector` |
| Detect WhatsApp calls | `WhatsAppCallDetector` |
| Extract participants | `ParticipantService` |
| Show main app | `MainAppWindowController.shared.show()` |
| Show settings | `SettingsWindowController.shared.show()` |
| Show onboarding | `OnboardingWizardController.shared.show()` |
| The floating recording pill | `RecordingIslandController` |
| The dictation pill | `QuickRecordingPillController` |
| Meeting data | `Meeting` struct |
| Recording status | `MeetingStatus` enum |
| Meeting groups | `MeetingGroup` struct |
| Voice notes | `QuickRecording` |
| AI templates | `SummaryTemplate` |
| Colors/fonts | `BrandAssets.swift` |
| UI components | `BrandComponents.swift` |
| Logging | `AppLogger.shared` |
