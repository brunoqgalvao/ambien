# MeetingRecorder

A native macOS app for recording meetings, transcribing with AI, and enabling system-wide dictation.

**Version:** 1.0.0
**Requires:** macOS 12.3+
**Built with:** Swift 5.9, SwiftUI

---

## Features

- **Meeting Recording** — Capture system audio from Zoom, Google Meet, Teams, and more
- **AI Transcription** — Powered by OpenAI's gpt-4o-mini-transcribe ($0.003/min)
- **System-Wide Dictation** — Hold a hotkey anywhere, speak, release to paste text
- **Calendar View** — Browse and search all your meetings by date
- **Full-Text Search** — Find any word across all transcripts instantly
- **Agent API** — Expose meetings as JSON for Claude Code / Codex
- **Local-First** — All data stays on your Mac, API keys in Keychain
- **Menu Bar App** — Always accessible, never in your way

---

## Quick Start

### 1. Build the App

**Using Swift Package Manager:**
```bash
cd MeetingRecorder
swift build
```

**Using Xcode:**
1. Open `Package.swift` in Xcode
2. Press Cmd+R to build and run

### 2. Grant Permissions

On first launch, the onboarding wizard will guide you through:

1. **Microphone** — Required for dictation and recording your voice
2. **Screen Recording** — Required to capture audio from meeting apps
3. **Accessibility** — Required to paste dictated text at cursor

Go to **System Settings → Privacy & Security** to grant each permission.

### 3. Add Your OpenAI API Key

In the app:
1. Open **Settings** (Cmd+,)
2. Go to the **API** tab
3. Paste your OpenAI API key
4. Click **Save**

Get an API key at [platform.openai.com/api-keys](https://platform.openai.com/api-keys)

### 4. Start Recording

- Click the menu bar icon and hit **Start Recording**
- Or use the keyboard shortcut: **Cmd+Shift+R**

---

## Keyboard Shortcuts

### Global (Always Available)

| Shortcut | Action |
|----------|--------|
| `⌘⇧R` | Start/stop recording |
| `^⌘D` | Hold to dictate |

### Calendar View

| Shortcut | Action |
|----------|--------|
| `/` | Search meetings |
| `↑/↓` or `j/k` | Navigate list |
| `↵` | Open meeting |
| `T` | Jump to today |
| `← →` | Previous/next day |

### Meeting Detail

| Shortcut | Action |
|----------|--------|
| `Space` | Play/pause audio |
| `← →` | Seek 10 seconds |
| `C` | Copy transcript |
| `Esc` | Back to calendar |

### General

| Shortcut | Action |
|----------|--------|
| `⌘O` | Open calendar window |
| `⌘,` | Open settings |
| `⌘F` | Search |
| `⌘Q` | Quit |

---

## Project Structure

```
MeetingRecorder/
├── MeetingRecorderApp.swift    # App entry point, menu bar
├── OnboardingView.swift        # First-run wizard
├── SettingsView.swift          # Settings panel (4 tabs)
├── ContentView.swift           # Menu bar dropdown
├── CalendarView.swift          # Main calendar window
├── MeetingListView.swift       # Meeting list component
├── MeetingDetailView.swift     # Transcript viewer
├── SearchResultsView.swift     # Search interface
├── AudioCaptureManager.swift   # ScreenCaptureKit + AVAudioEngine
├── TranscriptionService.swift  # OpenAI API integration
├── DatabaseManager.swift       # SQLite with GRDB.swift
├── DictationManager.swift      # Global hotkey + mic
├── DictationIndicatorView.swift # Floating dictation pill
├── DictationOverlayWindow.swift # Overlay window management
├── HotkeyManager.swift         # CGEvent tap for hotkeys
├── AgentAPIManager.swift       # JSON export for agents
├── KeychainHelper.swift        # Secure API key storage
├── ErrorHandlingView.swift     # Error state views
├── CalendarMeetingRow.swift    # Meeting row component
├── Meeting.swift               # Data model
├── ValidationManager.swift     # Permission validation
├── Info.plist                  # App configuration
├── Package.swift               # Swift Package Manager
└── MeetingRecorder.entitlements # App capabilities
```

---

## Data Storage

| Location | Contents |
|----------|----------|
| `~/Library/Application Support/MeetingRecorder/` | Database, audio files |
| `~/.meetingrecorder/meetings/` | JSON exports for agents |
| macOS Keychain | API keys (encrypted) |

---

## Transcription Costs

| Model | Cost | When Used |
|-------|------|-----------|
| gpt-4o-mini-transcribe | $0.003/min | Default for meetings |
| whisper-1 | $0.006/min | Fallback / dictation |

**Typical usage:** ~$4/month for 20 meetings

---

## Agent API

Claude Code and Codex can read your meetings from `~/.meetingrecorder/meetings/`:

```json
// index.json
{
  "version": 1,
  "meetings": [
    {
      "id": "abc123",
      "date": "2025-01-15",
      "title": "Daily Standup",
      "path": "2025-01-15/standup-9am.json"
    }
  ]
}
```

Each meeting JSON includes the full transcript, action items, and metadata.

---

## Troubleshooting

### "Screen Recording permission not working"

1. Go to **System Settings → Privacy & Security → Screen Recording**
2. Find MeetingRecorder and enable it
3. Quit and relaunch the app

### "No audio captured from meetings"

- Ensure the meeting app (Zoom, Meet) is playing audio
- Check that Screen Recording permission is granted
- Try recording a YouTube video first to test

### "Transcription failed: Invalid API key"

1. Open **Settings → API**
2. Delete the current key
3. Paste a fresh key from [platform.openai.com](https://platform.openai.com/api-keys)
4. Check your OpenAI account has credits/billing enabled

### "Dictation not working"

1. Check **System Settings → Privacy & Security → Accessibility**
2. Enable MeetingRecorder
3. Verify the hotkey (default: Ctrl+Cmd+D) isn't conflicting

### "App not appearing in menu bar"

The app runs as a menu bar app (no Dock icon). Look for the mic icon in your menu bar.

### "Sandbox blocking audio capture"

ScreenCaptureKit doesn't work with App Sandbox. The app runs with sandbox disabled. For Mac App Store distribution, consider alternative approaches.

---

## Development Setup

### Requirements

- **macOS 12.3+** (for ScreenCaptureKit)
- **Xcode 15+** (for building)
- **OpenAI API key** (for transcription)

### Building from Source

```bash
# Clone and build
git clone https://github.com/yourname/meetingrecorder.git
cd meetingrecorder/MeetingRecorder
swift build

# Run
swift run

# Or open in Xcode
open Package.swift
```

### SwiftUI Previews

All views include `#Preview` blocks. Open any view file and press `Cmd+Option+P` to see previews.

### Testing Transcription

You can test the transcription API without recording:
```bash
export OPENAI_API_KEY=sk-your-key
swift test_transcription.swift path/to/audio.m4a
```

---

## Entitlements

The app requires these entitlements for full functionality:

```xml
<key>com.apple.security.app-sandbox</key>
<false/>
<key>com.apple.security.device.audio-input</key>
<true/>
```

---

## Privacy

- All recordings and transcripts are stored locally on your Mac
- API keys are stored in macOS Keychain (hardware-encrypted)
- Audio is sent to OpenAI only for transcription, then deleted from their servers
- No analytics, no tracking, no cloud sync

---

## License

Copyright © 2025 MeetingRecorder. All rights reserved.

---

## Support

- **Documentation:** https://meetingrecorder.app/docs
- **Issues:** https://github.com/meetingrecorder/app/issues
- **Email:** support@meetingrecorder.app
