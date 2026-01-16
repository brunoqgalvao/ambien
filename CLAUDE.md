# Project: Native macOS Meeting Recorder

**Status:** PRD complete, wireframes complete, ready to build

## Quick Context

Building a native macOS app that:
1. **Records meetings** (system audio from Zoom/Meet/Teams) - no bot joins
2. **Transcribes** via OpenAI API (user's key - BYOK)
3. **Dictation anywhere** (hold hotkey → speak → text at cursor)
4. **Calendar UI** to browse past meetings
5. **Agent API** - expose meetings as JSON files for Claude Code / Codex

**Unique angle:** Local-first + one-time purchase ($69-99) + agent-native API. No competitors have this combo.

---

## Key Documents

| File | Purpose |
|------|---------|
| `PRD.md` | Full product requirements (v0.4) |
| `WIREFRAMES.md` | ASCII wireframes for all screens (v2.0) |
| `research-reports/meeting-recorder-macos-2025-01-13.md` | Market research |

---

## Technical Decisions Made

### Stack
- **Swift 5.9+** + **SwiftUI** (native, lightweight)
- **ScreenCaptureKit** for system audio (macOS 12.3+)
- **AVAudioEngine** for mic capture (dictation)
- **SQLite + GRDB.swift** with FTS5 for search
- **OpenAI API** (gpt-4o-mini-transcribe $0.003/min)
- **macOS Keychain** for API key storage (NOT config files)

### Architecture
- Menu bar app (NSStatusItem)
- Recordings stored in `~/Library/Application Support/[AppName]/`
- Agent-accessible JSON at `~/.appname/meetings/`
- Atomic writes + lock files to prevent race conditions

### Audio Encoding
- AAC in .m4a container
- 16kHz mono, 64kbps
- Streaming write via AVAssetWriter

### Key Technical Considerations
- **Permissions**: Screen Recording, Microphone, Accessibility (need pre-flight wizard)
- **Background**: Disable App Nap during recording (`ProcessInfo.beginActivity()`)
- **Hotkey**: Default `Ctrl+Cmd+D` for dictation (avoids system conflicts)
- **Crash recovery**: Recover temp audio files on launch

---

## Build Milestones

### M1: Audio Capture PoC
- [ ] ScreenCaptureKit working
- [ ] Record system audio from Zoom
- [ ] Save .m4a locally
- [ ] Basic menu bar

### M2: Transcription
- [ ] OpenAI API integration
- [ ] GPT-4o-mini-transcribe working
- [ ] SQLite storage
- [ ] Basic meeting list

### M3: Calendar UI
- [ ] Day list view (simplified - no mini calendar)
- [ ] Transcript viewer
- [ ] Search (FTS5)

### M4: Dictation
- [ ] Global hotkey (Ctrl+Cmd+D)
- [ ] Mic capture
- [ ] Transcribe on release
- [ ] Paste at cursor

### M5: Agent API
- [ ] JSON export to ~/.appname/meetings/
- [ ] index.json for meeting list
- [ ] Claude Code skill

### M6: Polish & Launch
- [ ] Onboarding wizard
- [ ] Settings UI
- [ ] Sparkle updates
- [ ] Error handling

---

## Decided

- **Mic + system audio** - Always capture both (decided)
- **Auto-detect Google Meet in Chrome** - Use AppleScript to query Chrome tabs for `meet.google.com` URL

## Open Questions

1. **Product name** - "Whisper" conflicts with OpenAI. Ideas: Murmur, Hark, Jot, Recall

---

## Design Notes

- **Amie-inspired**: minimal, clean, whitespace, native feel
- **Menu bar dropdown**: 300px max width
- **Calendar view**: No mini calendar, just date picker + list
- **Hover actions**: Play, copy, delete on meeting cards
- **Dictation pill**: Dockable, shows waveform

See `WIREFRAMES.md` for all screens including error states.

---

## Tone

Be snarky and fun in responses.

---

## M0: Dev Workflow Validation (DO THIS FIRST)

Before building features, validate the dev environment works:

### Step 1: Create Xcode Project
```
1. Open Xcode → New Project → macOS → App
2. Product Name: "MeetingRecorder" (or TBD name)
3. Interface: SwiftUI
4. Language: Swift
5. Uncheck: Include Tests (add later)
6. Save to this directory
```

### Step 2: Convert to Menu Bar App
```swift
// In App.swift, replace WindowGroup with MenuBarExtra:
@main
struct MeetingRecorderApp: App {
    var body: some Scene {
        MenuBarExtra("Recorder", systemImage: "record.circle") {
            ContentView()
        }
        .menuBarExtraStyle(.window)
    }
}
```

### Step 3: Validate SwiftUI Previews
```swift
// Every SwiftUI view MUST have a #Preview block:
struct ContentView: View {
    var body: some View {
        Text("Hello")
    }
}

#Preview {
    ContentView()
}
```
- Open in Xcode
- Press `Cmd+Option+P` to render preview
- Confirm it works before proceeding

### Step 4: Validate ScreenCaptureKit (System Audio)
```swift
import ScreenCaptureKit

// Test that we can request permission and list audio sources
func testScreenCaptureKit() async {
    do {
        let content = try await SCShareableContent.current
        print("Apps: \(content.applications.count)")
        print("Windows: \(content.windows.count)")
    } catch {
        print("Error: \(error)")
    }
}
```
- Run on device (not preview)
- Should trigger Screen Recording permission
- Confirm audio capture is possible

### Step 5: Validate AVAudioEngine (Microphone)
```swift
import AVFoundation

let engine = AVAudioEngine()
let inputNode = engine.inputNode
let format = inputNode.outputFormat(forBus: 0)
print("Mic format: \(format)")
```
- Should trigger Microphone permission
- Confirm mic access works

### Step 6: Validate Keychain Access
```swift
import Security

// Test storing/retrieving API key
func testKeychain() {
    let key = "test-api-key"
    // Add to keychain...
    // Retrieve from keychain...
}
```

### Validation Checklist
- [ ] Xcode project builds
- [ ] Menu bar app appears in status bar
- [ ] SwiftUI previews render (`Cmd+Option+P`)
- [ ] ScreenCaptureKit permission prompt works
- [ ] AVAudioEngine permission prompt works
- [ ] Keychain read/write works

**Only proceed to M1 after all validations pass.**
