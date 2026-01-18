# Development Guide

Technical documentation for building, running, and contributing to Ambien.

## Build from Source

### Requirements

- macOS 12.3+ (Monterey or later)
- Xcode 15+
- OpenAI API key (for testing transcription)

### Clone and Build

```bash
git clone https://github.com/brunoqgalvao/ambien.git
cd ambien
open MeetingRecorder.xcodeproj
```

In Xcode, press `Cmd+R` to build and run.

### Permissions

On first run, macOS will prompt for:

1. **Screen Recording** — Required for system audio capture
2. **Microphone** — Required for mic audio and dictation
3. **Accessibility** — Required for dictation text insertion

If permissions aren't working, check System Settings → Privacy & Security.

---

## Project Structure

```
ambien/
├── MeetingRecorder/              # Main macOS app (SwiftUI)
│   ├── MeetingRecorderApp.swift  # App entry, menu bar setup
│   ├── AudioCaptureManager.swift # ScreenCaptureKit for system audio
│   ├── TranscriptionManager.swift# OpenAI Whisper API
│   ├── DatabaseManager.swift     # SQLite via GRDB
│   ├── AgentAPIManager.swift     # JSON export for AI agents
│   ├── MeetingDetector.swift     # Detects Zoom/Meet/Teams
│   ├── SpeakerIdentification/    # Voice embedding & clustering
│   └── Views/                    # SwiftUI views
├── MeetingRecorder.xcodeproj/
├── AmbientCLI/                   # CLI tool (Swift Package)
├── brand/                        # Logos and brand assets
└── voice-embedding-service/      # Python service for speaker ID
```

---

## Architecture

### Audio Capture

Uses Apple's **ScreenCaptureKit** to capture system audio without joining calls as a bot.

```swift
// AudioCaptureManager.swift
let filter = SCContentFilter(desktopIndependentWindow: window)
let stream = SCStream(filter: filter, configuration: config, delegate: self)
```

### Transcription

OpenAI Whisper API via chunked uploads:

```swift
// TranscriptionManager.swift
POST https://api.openai.com/v1/audio/transcriptions
Content-Type: multipart/form-data
model: whisper-1
```

Cost: ~$0.006/minute ($0.36/hour)

### Speaker Identification

Voice embeddings generated locally, then clustered to identify speakers:

1. Audio segmented by voice activity detection
2. Embeddings extracted using speechbrain
3. Agglomerative clustering groups similar voices
4. User can label speakers post-hoc

### Database

SQLite with **GRDB.swift** and FTS5 for full-text search:

```
~/Library/Application Support/Ambien/
├── ambien.sqlite          # Main database
└── recordings/            # Audio files (.m4a)
```

### Agent API

Meetings exported as JSON to `~/.ambien/meetings/`:

```json
{
  "id": "uuid",
  "title": "Team Standup",
  "date": "2024-01-15T10:00:00Z",
  "duration": 1847,
  "participants": ["Alice", "Bob"],
  "transcript": [
    { "speaker": "Alice", "timestamp": 0.0, "text": "Good morning..." }
  ],
  "summary": "...",
  "action_items": ["..."]
}
```

CLI tool for querying:

```bash
ambien list --limit 5
ambien search "action items"
ambien get 2024-01-15-standup
```

---

## Key Technologies

| Component | Technology |
|-----------|------------|
| UI | SwiftUI |
| Audio capture | ScreenCaptureKit |
| Database | SQLite + GRDB.swift |
| Search | FTS5 |
| Transcription | OpenAI Whisper API |
| Speaker ID | speechbrain embeddings |
| API key storage | macOS Keychain |

---

## Code Style

- SwiftUI for all new UI
- Follow existing patterns (see `BrandComponents.swift` for UI)
- Prefer `async/await` over completion handlers
- No force unwraps unless absolutely necessary

---

## Testing

Currently no automated tests. Manual testing workflow:

1. Build and run
2. Test your changes
3. Test adjacent features
4. Check debug console for errors

Automated test contributions welcome!

---

## Making a Release

1. Update version in Xcode (General → Version)
2. Archive: Product → Archive
3. Export as Developer ID signed app
4. Create `.dmg` with create-dmg or similar
5. Create GitHub release, attach `.dmg`

---

## Common Issues

### Screen Recording permission doesn't persist

Inconsistent code signing. Clean build folder (`Cmd+Shift+K`), remove app from Screen Recording permissions, delete DerivedData, rebuild.

### Audio not capturing

Check that ScreenCaptureKit permission is granted. The app needs Screen Recording permission even though it's capturing audio.

### Transcription failing

Verify OpenAI API key in Settings. Check console for API errors. Ensure audio file isn't corrupted.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for PR guidelines.

Quick start:

```bash
git clone https://github.com/YOUR_USERNAME/ambien.git
cd ambien
open MeetingRecorder.xcodeproj
# Make changes, test, submit PR
```

---

## Questions?

[Open an issue](https://github.com/brunoqgalvao/ambien/issues) or check existing discussions.
