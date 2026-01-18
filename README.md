<p align="center">
  <img src="brand/logo/bloop-1024.png" width="128" height="128" alt="Ambien logo">
</p>

<h1 align="center">Ambien</h1>

<p align="center">
  <strong>The invisible meeting recorder for macOS</strong><br>
  Record system audio from Zoom, Meet, and Teams. No bot joins your call.<br>
  Transcribe with AI. Query with Claude Code.
</p>

<p align="center">
  <a href="#features">Features</a> •
  <a href="#installation">Installation</a> •
  <a href="#usage">Usage</a> •
  <a href="#agent-api">Agent API</a> •
  <a href="#contributing">Contributing</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2012.3%2B-blue" alt="macOS 12.3+">
  <img src="https://img.shields.io/badge/swift-5.9%2B-orange" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License">
</p>

---

## Why Ambien?

Every meeting recorder either:
- **Joins as a bot** → awkward "Recording Bot has joined" notifications
- **Lives in the cloud** → your conversations on someone else's servers
- **Costs $20+/month** → subscription fatigue

Ambien is different:

| Feature | Ambien | Otter/Fireflies/etc |
|---------|--------|---------------------|
| Bot joins call | **No** | Yes, awkward |
| Data stored | **Your Mac only** | Their cloud |
| Pricing | **Free & open source** | $20+/month |
| Agent API | **Built-in** | None |

## Features

- **Invisible Recording** — Captures system audio via ScreenCaptureKit. No one knows you're recording.
- **AI Transcription** — Uses OpenAI's Whisper API (bring your own key). ~$0.006/minute.
- **Local-First** — All data stays on your Mac. SQLite database with full-text search.
- **Meeting Detection** — Auto-detects Zoom, Google Meet, Microsoft Teams, Slack Huddles.
- **Calendar View** — Browse recordings by date. Search across all transcripts.
- **Dictation Mode** — Hold `Ctrl+Cmd+D` anywhere, speak, release → text at cursor.
- **Agent API** — Expose meetings as JSON for Claude Code, Codex, or any AI agent.

## Installation

### Download Release (Recommended)

1. Go to [Releases](https://github.com/brunoqgalvao/ambien/releases)
2. Download the latest `.dmg`
3. Drag to Applications
4. Open and grant permissions (Screen Recording, Microphone)

### Build from Source

```bash
# Clone the repo
git clone https://github.com/brunoqgalvao/ambien.git
cd ambien

# Open in Xcode
open MeetingRecorder.xcodeproj

# Build and run (Cmd+R)
```

**Requirements:**
- macOS 12.3+ (Monterey or later)
- Xcode 15+
- OpenAI API key for transcription

## Usage

### Recording

1. Click the menu bar icon (or press `Ctrl+Cmd+R`)
2. Select "Start Recording"
3. Have your meeting
4. Click "Stop Recording" when done
5. Transcription starts automatically

### Transcription Setup

Ambien uses your own OpenAI API key (BYOK model):

1. Open Settings (`Cmd+,`)
2. Enter your OpenAI API key
3. That's it — transcription costs ~$0.006/minute

### Dictation

Hold `Ctrl+Cmd+D`, speak, release. Your speech appears at the cursor. Works in any app.

## Agent API

Ambien exposes your meetings as JSON files for AI agents to query:

```
~/.ambien/meetings/
├── index.json              # List of all meetings
├── 2024-01-15-standup.json # Individual meeting with transcript
└── 2024-01-14-review.json
```

### Claude Code Integration

Install the CLI tool:

```bash
# From the app: Settings → Install CLI
ambien install-cli

# Or manually
sudo ln -s /Applications/Ambien.app/Contents/MacOS/ambien /usr/local/bin/ambien
```

Then Claude Code can query your meetings:

```bash
# List recent meetings
ambien list --limit 5

# Search transcripts
ambien search "action items"

# Get full transcript
ambien get 2024-01-15-standup
```

### JSON Schema

```json
{
  "id": "uuid",
  "title": "Team Standup",
  "date": "2024-01-15T10:00:00Z",
  "duration": 1847,
  "participants": ["Alice", "Bob"],
  "transcript": [
    {
      "speaker": "Alice",
      "timestamp": 0.0,
      "text": "Good morning everyone..."
    }
  ],
  "summary": "Discussed Q1 roadmap...",
  "action_items": [
    "Bob to send proposal by Friday"
  ]
}
```

## Project Structure

```
ambien/
├── MeetingRecorder/           # Main macOS app (SwiftUI)
│   ├── MeetingRecorderApp.swift
│   ├── AudioCaptureManager.swift   # ScreenCaptureKit integration
│   ├── TranscriptionManager.swift  # OpenAI Whisper API
│   ├── DatabaseManager.swift       # SQLite + GRDB
│   ├── AgentAPIManager.swift       # JSON export for agents
│   └── ...
├── MeetingRecorder.xcodeproj/
├── AmbientCLI/                # CLI tool (Swift Package)
└── brand/                     # Logos and brand assets
```

## Contributing

We'd love your help! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Quick Start

```bash
# Fork and clone
git clone https://github.com/YOUR_USERNAME/ambien.git
cd ambien

# Open in Xcode
open MeetingRecorder.xcodeproj

# Make changes, test, submit PR
```

### Ideas for Contribution

- [ ] Speaker diarization (who said what)
- [ ] Local Whisper model option (no API needed)
- [ ] Export to Notion/Obsidian
- [ ] Calendar integration (auto-name meetings)
- [ ] Linux port (PipeWire audio capture)

## Privacy

- **All recordings stay on your Mac** — nothing uploaded without your explicit action
- **Transcription uses OpenAI API** — audio sent to OpenAI, then deleted (per their API policy)
- **No analytics or telemetry** — we don't track anything

## License

MIT License — do whatever you want. See [LICENSE](LICENSE).

## Acknowledgments

- [ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit) — Apple's framework for system audio
- [GRDB.swift](https://github.com/groue/GRDB.swift) — SQLite toolkit
- [OpenAI Whisper](https://openai.com/research/whisper) — Speech recognition

---

<p align="center">
  Made with coffee in San Francisco ☕
</p>
