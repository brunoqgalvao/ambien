# Development Guide

Technical documentation for contributors and developers.

## Build from Source

### Requirements

- macOS 12.3+ (Monterey or later)
- Xcode 15+
- OpenAI API key (for testing transcription)

### Setup

```bash
git clone https://github.com/brunoqgalvao/ambien.git
cd ambien
open MeetingRecorder.xcodeproj
```

Press `Cmd+R` to build and run.

### Permissions

On first run, you'll need to grant:

1. **Screen Recording** — Required for system audio capture
2. **Microphone** — Required for mic audio and dictation
3. **Accessibility** — Required for dictation text insertion

Check System Settings → Privacy & Security if things aren't working.

---

## Project Structure

```
ambien/
├── MeetingRecorder/              # Main macOS app (SwiftUI)
│   ├── MeetingRecorderApp.swift  # App entry, menu bar setup
│   ├── AudioCaptureManager.swift # ScreenCaptureKit for system audio
│   ├── TranscriptionManager.swift# OpenAI Whisper API
│   ├── DatabaseManager.swift     # SQLite via GRDB
│   ├── AgentAPIManager.swift     # JSON export for Claude Code
│   ├── MeetingDetector.swift     # Detects Zoom/Meet/Teams
│   ├── SpeakerIdentifier.swift   # Voice embeddings for speaker ID
│   └── Views/
│       ├── ContentView.swift     # Main calendar view
│       ├── SettingsView.swift    # Settings panel
│       └── ...
├── MeetingRecorder.xcodeproj/
├── AmbientCLI/                   # CLI tool (Swift Package)
│   └── Sources/ambient/main.swift
├── brand/                        # Logos and brand assets
└── landing-page/                 # Marketing site (Svelte)
```

---

## Architecture

### Audio Capture

Uses Apple's **ScreenCaptureKit** (macOS 12.3+) to capture system audio without joining calls as a bot.

```
AudioCaptureManager
├── SCStream (system audio)
├── AVAudioEngine (microphone)
└── AVAssetWriter (AAC encoding)
```

Audio is encoded as AAC in .m4a container (16kHz mono, 64kbps).

### Transcription

Sends audio to **OpenAI Whisper API** (`whisper-1` model).

Cost: ~$0.006/minute (~$0.36/hour)

### Speaker Identification

Uses voice embeddings to identify speakers:

1. Extract audio segments by voice activity detection
2. Generate embeddings using a local model
3. Cluster embeddings to identify unique speakers
4. Match against known speaker profiles

### Database

**SQLite** with **GRDB.swift**. Full-text search via FTS5.

```
~/Library/Application Support/Ambien/
├── ambien.db          # Main database
└── recordings/        # Audio files
```

### Agent API

Exports meetings as JSON for AI agents:

```
~/.ambien/meetings/
├── index.json
├── 2024-01-15-standup.json
└── ...
```

Uses atomic writes + lock files to prevent race conditions with concurrent agent access.

---

## Key Files

| File | Purpose |
|------|---------|
| `AudioCaptureManager.swift` | ScreenCaptureKit integration, audio encoding |
| `TranscriptionManager.swift` | OpenAI Whisper API client |
| `DatabaseManager.swift` | SQLite operations, FTS5 search |
| `MeetingDetector.swift` | Detects running meeting apps |
| `AgentAPIManager.swift` | JSON export for Claude Code |
| `SpeakerIdentifier.swift` | Voice embedding and clustering |
| `BrandComponents.swift` | Reusable UI components |
| `BrandAssets.swift` | Colors, typography constants |

---

## Code Style

- SwiftUI for all UI
- Use components from `BrandComponents.swift`
- Prefer `async/await` over completion handlers
- No force unwraps (`!`) unless absolutely necessary

### Commits

```
feat: add speaker diarization
fix: prevent crash on audio disconnect
docs: update README
```

---

## Testing

No automated tests yet (contributions welcome!).

Manual testing:
1. Build and run
2. Start a Zoom/Meet/Teams call
3. Test recording, transcription, search
4. Check debug console for errors

---

## CLI Tool

The CLI is a Swift Package in `AmbientCLI/`:

```bash
cd AmbientCLI
swift build
swift run ambient list
```

Install globally:
```bash
sudo ln -s $(pwd)/.build/debug/ambient /usr/local/bin/ambien
```

---

## Debugging

### Screen Recording permission not sticking?

1. Clean Build Folder (`Cmd+Shift+K`)
2. System Settings → Privacy → Screen Recording → Remove app
3. Delete `~/Library/Developer/Xcode/DerivedData/MeetingRecorder-*`
4. Rebuild

### Audio not capturing?

Check that the correct audio source is selected. ScreenCaptureKit captures from the system default output device.

### Transcription failing?

1. Check API key in Settings
2. Check network connection
3. Look at debug console for error messages

---

## Contributing

1. Fork the repo
2. Create a feature branch
3. Make changes
4. Test thoroughly
5. Submit a PR

See [CONTRIBUTING.md](CONTRIBUTING.md) for more details.
