<p align="center">
  <img src="brand/logo/bloop-1024.png" width="128" height="128" alt="Ambien logo">
</p>

<h1 align="center">Ambien</h1>

<p align="center">
  <strong>The invisible meeting recorder for macOS</strong><br>
  No bot joins your call. No one knows you're recording.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS%2012.3+-blue" alt="macOS 12.3+">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License">
</p>

---

## Download

**[Download the latest release](https://github.com/brunoqgalvao/ambien/releases)** → Open the `.dmg` → Drag to Applications → Done.

On first launch, grant Screen Recording and Microphone permissions when prompted.

---

## What is this?

Ambien sits in your menu bar and records system audio from Zoom, Google Meet, Microsoft Teams, Slack, and WhatsApp — without joining as a bot.

After your meeting, it transcribes everything using OpenAI's Whisper and identifies who said what.

**Your recordings stay on your Mac.** Nothing leaves your machine unless you choose to transcribe.

---

## Philosophy

**Local-first.** All data stays on your Mac.

**Bring your own keys.** Use your own OpenAI API key. No middleman. ~$0.36 per hour of audio.

**Open source.** Customize it however you want. MIT licensed.

---

## Why not Otter, Fireflies, etc?

| | Ambien | Others |
|---|--------|--------|
| Bot joins your call | **No** | Yes — "Recording Bot has joined" |
| Where's your data | **Your Mac** | Their cloud |
| Cost | **Free** + ~$0.36/hr for transcription | $20+/month |
| Customizable | **Yes** — it's open source | No |

---

## Features

- **Invisible recording** — No one knows you're recording
- **Automatic speaker identification** — Knows who said what
- **Custom templates** — Configure summaries and action items how you want
- **Full-text search** — Find anything across all your meetings
- **Dictation mode** — `Ctrl+Cmd+D` anywhere to speak-to-text
- **Agent API** — Let Claude Code query your meetings

---

## Quick Start

1. **Download** from [Releases](https://github.com/brunoqgalvao/ambien/releases)
2. **Open** the app and grant permissions
3. **Add your OpenAI API key** in Settings (`Cmd+,`)
4. **Click record** when your meeting starts
5. **Stop** when done — transcription happens automatically

---

## Roadmap

**Coming soon:**
- Local transcription (no API needed)
- Export to Notion/Obsidian
- Calendar integration

**Later:**
- Real-time meeting assistant
- Always-on background recording (Rewind-style)
- Slack, Linear, Jira integrations

[Open an issue](https://github.com/brunoqgalvao/ambien/issues) with ideas!

---

## Build from Source

Want to hack on it? See **[DEVELOPMENT.md](DEVELOPMENT.md)** for build instructions and architecture docs.

---

## Privacy

- Recordings stay on your Mac
- Transcription uses OpenAI (audio sent, then deleted per their policy)
- No telemetry — we don't track anything

---

## License

MIT — do whatever you want. See [LICENSE](LICENSE).

---

<p align="center">
  Made with coffee in San Francisco
</p>
