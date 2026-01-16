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

## ⚠️ CRITICAL: Project Structure

**DO NOT create files outside of `MeetingRecorder/` folder!**

```
ami-like/
├── MeetingRecorder/                 ← ALL Swift source files go HERE
│   ├── MeetingRecorderApp.swift
│   ├── ContentView.swift
│   ├── AudioCaptureManager.swift
│   ├── ... (all other .swift files)
│   ├── Info.plist
│   └── MeetingRecorder.entitlements
├── MeetingRecorder.xcodeproj/       ← Xcode project (references files in MeetingRecorder/)
├── CLAUDE.md
├── PRD.md
└── WIREFRAMES.md
```

**The Xcode project (`MeetingRecorder.xcodeproj`) references files from `MeetingRecorder/` folder. NEVER create a second source folder.**

---

## ⚠️ CRITICAL: Screen Recording Permission Fix

**Problem:** Screen Recording permission doesn't persist across builds.

**Root Cause:** Inconsistent code signing = macOS treats each build as a new app.

**Required Settings in Xcode:**

| Setting | Value | Where |
|---------|-------|-------|
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.meetingrecorder.app` | Build Settings |
| `CODE_SIGN_IDENTITY` | `Apple Development` | Build Settings (Debug + Release) |
| `CODE_SIGN_STYLE` | `Automatic` | Build Settings |
| `ENABLE_HARDENED_RUNTIME` | `YES` | Build Settings |
| App Sandbox | **DISABLED** | Signing & Capabilities |

**Entitlements file (`MeetingRecorder.entitlements`):**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
```

**DO NOT include `com.apple.security.app-sandbox` in entitlements - leaving it out disables sandbox.**

**If permission still doesn't stick:**
1. Clean Build Folder (`Cmd+Shift+K`)
2. System Settings → Privacy → Screen Recording → Remove app if listed
3. Delete `~/Library/Developer/Xcode/DerivedData/MeetingRecorder-*`
4. Rebuild and re-grant permission

---

## ⚠️ CRITICAL: Adding New Swift Files

When creating new Swift files:
1. Create the file in `/MeetingRecorder/` folder
2. **MUST also add to Xcode project** - the `project.pbxproj` file needs:
   - PBXFileReference entry
   - Entry in PBXGroup children
   - PBXBuildFile entry
   - Entry in PBXSourcesBuildPhase

**Or in Xcode GUI:** Right-click MeetingRecorder group → Add Files → Select file → Check "Add to target"

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

## ⚠️ SwiftUI Reactivity Best Practices

SwiftUI's reactivity is NOT like Svelte - it requires explicit wiring. Follow these rules to avoid bugs:

### 1. Single Source of Truth
Never duplicate state. If `AudioCaptureManager` has `isRecording`, don't create another `isRecording` in ViewModel.

```swift
// ❌ BAD - two sources of truth
class ViewModel {
    @Published var isRecording = false  // disconnected copy
}
class AudioManager {
    @Published var isRecording = false  // real state
}

// ✅ GOOD - one source, computed access
class ViewModel {
    let audioManager: AudioCaptureManager
    var isRecording: Bool { audioManager.isRecording }
}
```

### 2. Dependency Injection Over Global Access
Pass dependencies explicitly via init. Avoid `NSApp.delegate as? AppDelegate` buried in functions.

```swift
// ❌ BAD - hidden dependency
func toggleRecording() {
    guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
    // ...
}

// ✅ GOOD - explicit dependency
class ViewModel {
    private let audioManager: AudioCaptureManager
    init(audioManager: AudioCaptureManager) {
        self.audioManager = audioManager
    }
}
```

### 3. Combine Bindings for State Sync
If state must exist in multiple places, wire them up explicitly at init:

```swift
class ViewModel: ObservableObject {
    @Published var isRecording = false
    private var cancellables = Set<AnyCancellable>()

    init(audioManager: AudioCaptureManager) {
        audioManager.$isRecording
            .assign(to: &$isRecording)
    }
}
```

### 4. Always Add `.contentShape(Rectangle())` on Custom Buttons
SwiftUI's hit testing is weird with complex backgrounds. Always make the full area tappable:

```swift
Button(action: { ... }) {
    HStack { /* complex content */ }
        .padding()
        .background(RoundedRectangle(...))
        .contentShape(Rectangle())  // ← REQUIRED for reliable clicks
}
.buttonStyle(.plain)
```

### 5. Use `@StateObject` for View-Owned Objects
```swift
// ❌ BAD - recreated on every parent re-render
@ObservedObject var vm = ViewModel()

// ✅ GOOD - survives re-renders
@StateObject var vm = ViewModel()
```

### 6. Async Actions Should Provide Feedback
```swift
// ❌ BAD - fire and forget
func toggleRecording() {
    Task { /* stuff happens... somewhere */ }
}

// ✅ GOOD - caller knows outcome
func toggleRecording() async throws -> Bool {
    try await audioManager.startRecording()
    return audioManager.isRecording
}
```

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
