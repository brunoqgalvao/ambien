# Contributing to Ambien

Thanks for wanting to help! Here's how to get started.

## Quick Start

```bash
# 1. Fork the repo on GitHub

# 2. Clone your fork
git clone https://github.com/YOUR_USERNAME/ambien.git
cd ambien

# 3. Open in Xcode
open MeetingRecorder.xcodeproj

# 4. Build and run (Cmd+R)
```

## Development Setup

### Requirements

- macOS 12.3+ (Monterey)
- Xcode 15+
- OpenAI API key (for testing transcription)

### Permissions

The app needs these permissions to work:

1. **Screen Recording** — for system audio capture
2. **Microphone** — for mic audio + dictation
3. **Accessibility** — for dictation text insertion

On first run, macOS will prompt for these. If things aren't working, check System Settings → Privacy & Security.

### Project Structure

```
MeetingRecorder/
├── MeetingRecorderApp.swift    # App entry point, menu bar setup
├── AudioCaptureManager.swift   # ScreenCaptureKit for system audio
├── TranscriptionManager.swift  # OpenAI Whisper API
├── DatabaseManager.swift       # SQLite via GRDB
├── AgentAPIManager.swift       # JSON export for Claude Code
├── MeetingDetector.swift       # Detects Zoom/Meet/Teams
├── Views/
│   ├── ContentView.swift       # Main calendar view
│   ├── SettingsView.swift      # Settings panel
│   └── ...
└── Brand/
    ├── BrandComponents.swift   # Reusable UI components
    └── BrandAssets.swift       # Colors, typography
```

## Making Changes

### Code Style

- SwiftUI for all new UI
- Follow existing patterns (check `BrandComponents.swift` for UI)
- No force unwraps (`!`) unless absolutely necessary
- Prefer `async/await` over completion handlers

### Commits

Write clear commit messages:

```
feat: add speaker diarization support
fix: prevent crash when audio device disconnects
docs: update README with CLI examples
```

### Pull Requests

1. Create a feature branch: `git checkout -b feat/my-feature`
2. Make your changes
3. Test thoroughly (build, run, use the app)
4. Push and open a PR
5. Describe what you changed and why

## What to Work On

### Good First Issues

Look for issues tagged `good first issue` — these are scoped and have context.

### Feature Ideas

- **Speaker diarization** — identify who's speaking
- **Local Whisper** — run transcription locally (no API)
- **Export formats** — Notion, Obsidian, markdown
- **Calendar sync** — auto-name meetings from calendar
- **Better search** — semantic search with embeddings

### Bug Fixes

Found a bug?

1. Check if it's already reported in Issues
2. If not, open an issue with:
   - What you expected
   - What happened
   - Steps to reproduce
   - macOS version

## Testing

Currently no automated tests (contributions welcome!). For now:

1. Build and run the app
2. Test the feature you changed
3. Test adjacent features that might be affected
4. Check the debug console for errors

## Questions?

Open an issue or discussion. We're friendly!

---

Thanks for contributing! 🎉
