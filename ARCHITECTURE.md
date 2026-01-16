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
│  HomeView │ CalendarView │ MeetingDetailView │ SettingsView     │
└─────────────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────────┐
│                       SERVICES (Backend)                        │
│  AudioCaptureManager │ TranscriptionService │ DatabaseManager   │
└─────────────────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────────┐
│                       DATA MODELS                               │
│  Meeting │ QuickRecording │ SummaryTemplate │ MeetingStatus     │
└─────────────────────────────────────────────────────────────────┘
```

---

## Data Models

| Name | File | Purpose |
|------|------|---------|
| **Meeting** | `Meeting.swift` | Core meeting record (title, audio path, transcript, status, cost) |
| **MeetingStatus** | `Meeting.swift` | Enum: `recording`, `pendingTranscription`, `transcribing`, `ready`, `failed` |
| **QuickRecording** | `QuickRecording.swift` | Voice note from quick dictation |
| **SummaryTemplate** | `SummaryTemplate.swift` | AI prompt template for post-processing |
| **ProcessedSummary** | `Meeting.swift` | Result from running a template on transcript |

---

## Backend Services

| Name | File | Purpose |
|------|------|---------|
| **AudioCaptureManager** | `AudioCaptureManager.swift` | Records system audio (ScreenCaptureKit) + mic (AVAudioEngine), saves .m4a |
| **TranscriptionService** | `TranscriptionService.swift` | OpenAI API calls (gpt-4o-mini-transcribe / whisper-1) |
| **PostProcessingService** | `PostProcessingService.swift` | GPT-4o-mini for summaries, action items, diarization |
| **DatabaseManager** | `DatabaseManager.swift` | SQLite via GRDB.swift with FTS5 search |
| **KeychainHelper** | `KeychainHelper.swift` | Secure API key storage |
| **AgentAPIManager** | `AgentAPIManager.swift` | JSON export to `~/.meetingrecorder/meetings/` for AI agents |

---

## Automation Services

| Name | File | Purpose |
|------|------|---------|
| **HotkeyManager** | `HotkeyManager.swift` | Global hotkey registration (Ctrl+Cmd+D) via CGEvent tap |
| **DictationManager** | `DictationManager.swift` | Hold-to-dictate: record mic → transcribe → paste at cursor |
| **MeetingDetector** | `MeetingDetector.swift` | Auto-detect Zoom/Meet/Teams/Slack/FaceTime meetings |

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
| **SidebarView** | `MainAppWindow.swift` | 80px icon navigation (Home, Calendar, Dictations, Templates, Analytics) |
| **HomeView** | `HomeView.swift` | Welcome screen with nudges & recent activity |
| **CalendarView** | `CalendarView.swift` | Date picker + meeting list |
| **MeetingListView** | `MeetingListView.swift` | Scrollable meeting list with search |
| **MeetingDetailView** | `MeetingDetailView.swift` | Full meeting: transcript, audio player, summaries |
| **TemplatesView** | `TemplatesView.swift` | Template editor (master-detail) |
| **AnalyticsView** | `AnalyticsView.swift` | Usage dashboard, spend tracking |
| **SettingsView** | `SettingsView.swift` | Settings tabs (General, API, Costs, Templates) |

---

## UI - Settings Tabs

| Name | File | Tab |
|------|------|-----|
| **GeneralSettingsTab** | `SettingsView.swift` | Auto-detection, hotkey config |
| **APISettingsTab** | `SettingsView.swift` | OpenAI API key management |
| **CostsSettingsTab** | `SettingsView.swift` | Usage & spending |
| **SummaryTemplatesSettingsTab** | `SummaryTemplatesSettingsTab.swift` | Template management |

---

## UI - Components (Reusable)

| Name | File | Purpose |
|------|------|---------|
| **MenuBarDropdown** | `MeetingRecorderApp.swift` | Menu bar popover content |
| **MeetingRowView** | `MeetingListView.swift` | Meeting card in list |
| **HomeMeetingRow** | `HomeView.swift` | Meeting preview on home |
| **NudgeCard** | `HomeView.swift` | Setup reminder cards |
| **CustomCalendarView** | `CalendarView.swift` | Interactive calendar grid |
| **AudioPlayerCard** | `MeetingDetailView.swift` | Audio playback controls |
| **TranscriptSummarySection** | `MeetingDetailView.swift` | Transcript vs summaries tabs |
| **QuickDictationPill** | `QuickDictationPill.swift` | Floating dictation indicator |
| **RecordingIsland** | `RecordingIsland.swift` | Notch-aware recording indicator |
| **ErrorToast** | `ErrorToast.swift` | Temporary error notifications |

---

## UI - Menu Bar (Legacy ContentView)

| Name | File | Purpose |
|------|------|---------|
| **ContentView** | `ContentView.swift` | Tab-based menu dropdown (old design) |
| **RecordingView** | `ContentView.swift` | Recording controls |
| **QuickSettingsView** | `ContentView.swift` | Mini settings in menu |
| **ValidationView** | `ContentView.swift` | M0 validation checklist |

---

## Design Tokens

| Name | File | Purpose |
|------|------|---------|
| **Brand Colors** | `BrandAssets.swift` | violet, coral, mint, amber, cream, ink |
| **BrandRadius** | `BrandAssets.swift` | small(8), medium(16), large(32), pill(999) |
| **Font Extensions** | `BrandAssets.swift` | brandDisplay(), brandSerif(), brandMono() |

---

## Utilities

| Name | File | Purpose |
|------|------|---------|
| **ValidationManager** | `ValidationManager.swift` | M0 dev environment tests |
| **DebugKeyboardHandler** | `DebugTools.swift` | Cmd+Shift+D frame inspector |
| **SummaryTemplateManager** | `TemplatesView.swift` | Template persistence (singleton) |
| **QuickRecordingStorage** | `QuickRecording.swift` | Quick recording SQLite storage |

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
       └─► AVAudioEngine (microphone)
               │
               ▼
         Mix + Save .m4a
               │
               ▼
    DatabaseManager.insert(Meeting)
               │
               ▼
    TranscriptionService.transcribe()
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
TranscriptionService.transcribe()
       │
       ▼
Paste at cursor (NSPasteboard)
```

### Post-Processing Flow
```
User selects template in MeetingDetailView
       │
       ▼
PostProcessingService.process(transcript, template)
       │
       ▼
GPT-4o-mini API call
       │
       ▼
Meeting.processedSummaries.append(result)
       │
       ▼
DatabaseManager.update(meeting)
```

---

## File Structure

```
MeetingRecorder/
├── MeetingRecorderApp.swift    # Entry point, AppDelegate, MenuBarDropdown
├── Meeting.swift               # Meeting model, MeetingStatus enum
├── QuickRecording.swift        # Voice note model + storage
├── SummaryTemplate.swift       # AI template model
│
├── AudioCaptureManager.swift   # Recording service
├── TranscriptionService.swift  # OpenAI transcription
├── PostProcessingService.swift # GPT summaries/action items
├── DatabaseManager.swift       # SQLite + FTS5
├── KeychainHelper.swift        # Secure API key storage
├── AgentAPIManager.swift       # JSON export for agents
│
├── HotkeyManager.swift         # Global hotkey (Ctrl+Cmd+D)
├── DictationManager.swift      # Hold-to-dictate system
├── MeetingDetector.swift       # Auto-detect meetings
│
├── MainAppWindow.swift         # Main window + SidebarView
├── HomeView.swift              # Welcome screen
├── CalendarView.swift          # Date picker + list
├── MeetingListView.swift       # Meeting list
├── MeetingDetailView.swift     # Meeting detail
├── TemplatesView.swift         # Template editor
├── AnalyticsView.swift         # Usage dashboard
├── SettingsView.swift          # Settings window + tabs
├── SummaryTemplatesSettingsTab.swift
│
├── ContentView.swift           # Legacy menu bar UI
├── RecordingIsland.swift       # Floating notch indicator
├── QuickDictationPill.swift    # Floating dictation pill
├── OnboardingWizard.swift      # First-run wizard
├── ErrorToast.swift            # Error notifications
├── BrandAssets.swift           # Design tokens
├── ValidationManager.swift     # Dev validation
├── DebugTools.swift            # Debug utilities
│
├── Info.plist
└── MeetingRecorder.entitlements
```

---

## Quick Reference: "What do I call..."

| When you want to... | Reference |
|---------------------|-----------|
| Start/stop recording | `AudioCaptureManager` |
| Transcribe audio | `TranscriptionService` |
| Generate summary | `PostProcessingService` |
| Store/query meetings | `DatabaseManager` |
| Store API key | `KeychainHelper` |
| Register hotkey | `HotkeyManager` |
| Dictate anywhere | `DictationManager` |
| Detect meetings | `MeetingDetector` |
| Show main app | `MainAppWindowController.shared.show()` |
| Show settings | `SettingsWindowController.shared.show()` |
| Show onboarding | `OnboardingWizardController.shared.show()` |
| The floating recording pill | `RecordingIslandController` |
| The dictation pill | `QuickRecordingPillController` |
| Meeting data | `Meeting` struct |
| Recording status | `MeetingStatus` enum |
| Voice notes | `QuickRecording` |
| AI templates | `SummaryTemplate` |
| Colors/fonts | `BrandAssets.swift` |
