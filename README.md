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
  <a href="#installation">Installation</a> •
  <a href="#features">Features</a> •
  <a href="#usage">Usage</a> •
  <a href="#agent-api">Agent API</a> •
  <a href="#roadmap">Roadmap</a> •
  <a href="#contributing">Contributing</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2012.3%2B-blue" alt="macOS 12.3+">
  <img src="https://img.shields.io/badge/swift-5.9%2B-orange" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License">
</p>

---

## Philosophy

**Local-first.** All recordings and transcripts stay on your Mac. Nothing leaves your machine unless you explicitly choose to transcribe.

**Bring your own keys.** You use your own OpenAI API key. No middleman, no markup. Pay OpenAI directly at ~$0.006/minute.

**Open source.** Tune it, fork it, self-host it. MIT licensed — do whatever you want.

---

## Why Ambien?

- **Lightweight** — Native Swift app. ~15MB. No Electron bloat.
- **Automatic speaker identification** — Knows who said what using voice embeddings.
- **Customizable post-processing** — Templates for summaries, action items, briefs. Make it output whatever you need.
- **Agent-native** — Built from day one to work with Claude Code, Codex, and AI agents.

### vs. Otter, Fireflies, etc.

| | Ambien | Others |
|---|--------|--------|
| Bot joins your call | **No** — captures system audio silently | Yes — "Recording Bot has joined" |
| Where's your data | **Your Mac** | Their cloud |
| Pricing | **Free** (you pay OpenAI directly) | $20+/month |
| Agent API | **Built-in** — query from Claude Code | None |
| Customizable | **Fully** — it's open source | Nope |

---

## Installation

### Download (Recommended)

1. Go to [Releases](https://github.com/brunoqgalvao/ambien/releases)
2. Download the latest `.dmg`
3. Drag to Applications
4. Open and grant permissions (Screen Recording, Microphone)

### Build from Source

```bash
git clone https://github.com/brunoqgalvao/ambien.git
cd ambien
open MeetingRecorder.xcodeproj
# Build and run (Cmd+R)
```

**Requirements:** macOS 12.3+, Xcode 15+

---

## Features

- **Invisible Recording** — Captures system audio via ScreenCaptureKit. No one knows you're recording.
- **AI Transcription** — OpenAI Whisper API with your own key. ~$0.006/minute.
- **Speaker Identification** — Automatic speaker labels using voice embeddings.
- **Meeting Detection** — Auto-detects Zoom, Google Meet, Microsoft Teams, Slack Huddles, WhatsApp.
- **Full-Text Search** — SQLite with FTS5. Search across all your transcripts instantly.
- **Custom Templates** — Configure how summaries and briefs are generated.
- **Dictation Mode** — Hold `Ctrl+Cmd+D` anywhere, speak, release → text appears at cursor.
- **Agent API** — Expose meetings as JSON for Claude Code, Codex, or any AI agent.

---

## Usage

### Recording

1. Click the menu bar icon (or `Ctrl+Cmd+R`)
2. Start your meeting in Zoom/Meet/Teams
3. Click "Stop Recording" when done
4. Transcription runs automatically

### Setup Transcription

1. Open Settings (`Cmd+,`)
2. Enter your OpenAI API key
3. Done — a 1-hour meeting costs ~$0.36

### Dictation

Hold `Ctrl+Cmd+D`, speak, release. Text appears at cursor. Works anywhere.

---

## Agent API

Ambien exposes your meetings as JSON for AI agents:

```
~/.ambien/meetings/
├── index.json
├── 2024-01-15-standup.json
└── 2024-01-14-review.json
```

### Claude Code Integration

```bash
# Install CLI (from Settings → Install CLI, or manually)
sudo ln -s /Applications/Ambien.app/Contents/MacOS/ambien /usr/local/bin/ambien

# Query your meetings
ambien list --limit 5
ambien search "action items"
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
    { "speaker": "Alice", "timestamp": 0.0, "text": "Good morning..." }
  ],
  "summary": "Discussed Q1 roadmap...",
  "action_items": ["Bob to send proposal by Friday"]
}
```

---

## Roadmap

What we're thinking about next:

### Near-term
- [ ] **Local Whisper** — Run transcription locally, no API needed
- [ ] **Export to Notion/Obsidian** — One-click export to your note-taking app
- [ ] **Calendar integration** — Auto-name meetings from your calendar

### Medium-term
- [ ] **Real-time meeting assistant** — Live suggestions and context during calls
- [ ] **Always-on screen capture** — Rewind-style, ultra-lightweight background recording
- [ ] **Integrations** — Slack, Linear, Jira, GitHub for auto-creating tickets from action items

### Long-term
- [ ] **Linux port** — PipeWire audio capture
- [ ] **Team features** — Shared meeting libraries (still local-first)

Have ideas? [Open an issue](https://github.com/brunoqgalvao/ambien/issues) or [submit a PR](CONTRIBUTING.md).

---

## Contributing

We'd love your help! See [CONTRIBUTING.md](CONTRIBUTING.md).

```bash
git clone https://github.com/YOUR_USERNAME/ambien.git
cd ambien
open MeetingRecorder.xcodeproj
# Make changes, test, submit PR
```

---

## Privacy

- **Recordings stay on your Mac** — nothing uploaded without your action
- **Transcription uses OpenAI** — audio sent to OpenAI, then deleted per their policy
- **No telemetry** — we don't track anything

---

## License

MIT — do whatever you want. See [LICENSE](LICENSE).

---

<p align="center">
  Made with coffee in San Francisco
</p>
