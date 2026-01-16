# PRD: [Codename TBD]

**Version:** 0.4
**Date:** 2025-01-15
**Status:** Ready for build

---

## 1. The Problem

Knowledge workers spend 15-25 hours/week in meetings and typing all day. They:

- **Forget what was said** - No searchable record of discussions
- **Lose action items** - Agreed, then vanished into the void
- **Type the same things repeatedly** - Emails, Slack, docs, code comments
- **Pay for fragmented tools** - Otter ($20/mo) + Wispr Flow ($15/mo) + calendar app + notes app
- **Don't trust cloud services** - Otter.ai is literally getting sued for training on user data

**Why now:**
- GPT-4o-mini-transcribe is 50% cheaper than Whisper ($0.003/min)
- Claude Code / Codex OAuth lets users plug in their subscriptions
- One-time purchase apps are massively underserved
- "Agent-native" is the new "mobile-first"

---

## 2. The Customer

### Primary Persona: "Alex the Always-On"

**Who:** Knowledge worker (PM, founder, engineer lead, consultant), 28-45, Mac user

**Day-to-day:**
- 10-20 meetings/week
- Lives in Slack, email, docs
- Uses AI tools (ChatGPT, Claude) but frustrated by fragmentation
- Typing causes wrist pain (or fear of it)
- Privacy-conscious, subscription-fatigued

**Key frustrations:**
- "I can't remember what we agreed to 3 meetings ago"
- "I pay for 4 subscriptions that should be one tool"
- "I want Claude to analyze my meetings but my data is scattered"
- "I don't trust these tools with client calls"
- "Those bots joining calls are awkward as hell"

**Willingness to pay:** $49-99 one-time (hates subscriptions)

### Secondary Persona: "The AI-Native Builder"

**Who:** Developer/founder who lives in the terminal, uses Claude Code / Codex daily

**Wants:**
- AI agent to know what happened in meetings
- Trigger workflows when meetings end
- Search meetings like searching a codebase
- Pipe meeting data into their own scripts

---

## 3. The Solution

**One native macOS app that:**

1. **Records all your meetings** (no bot joins) → transcribes → calendar view
2. **Lets you dictate anywhere** (like Wispr Flow) → hold hotkey → speak → text appears
3. **Stores everything locally** → your Mac, your data
4. **Exposes to AI agents** → Claude Code / Codex can analyze your meetings
5. **Runs hooks after meetings** → extract action items, webhooks, scripts

**One-time purchase. BYOK for transcription. No cloud storage.**

---

## 4. Positioning

### One-liner

> **"Your Mac's memory for everything you say and hear."**

### Competitive position

```
                    Cloud Storage
                         │
         Otter ─────────┼───────── Fireflies
         Fathom         │          Grain
                        │
  Simple ───────────────┼─────────────── Complex
                        │
         MacWhisper ────┼
         Hyprnote       │
                        │
                    Local Storage
                        │
                    ★ YOU ★
                Local + Agent-Native
                  + Dictation
```

**Unique combo:** Local-first + meeting recorder + dictation + agent API + one-time purchase

Nobody else has this.

---

## 5. Go-to-Market

### Pricing

| Tier | Price | Includes |
|------|-------|----------|
| **Standard** | $69 one-time | Full app, BYOK transcription |
| **Pro** | $99 one-time | + Hooks system, priority support |

- 7-day money-back guarantee
- No free tier (signals value, avoids support burden)
- User pays their own transcription (~$0.18/hour via GPT-4o-mini-transcribe)

### Launch Channels

1. **ProductHunt** - "No bots. No subscriptions. No bullshit."
2. **Hacker News** - "Show HN: I built a local-first meeting recorder with agent API"
3. **r/macapps, r/productivity** - Mac power users
4. **Twitter/X** - Indie dev / founder community
5. **Claude Code / Codex communities** - Agent-native angle

### Key Messages

- "Otter.ai is getting sued. Your meetings deserve better."
- "One-time purchase. Lifetime of meetings."
- "Let Claude rip through your meeting history."
- "Dictate anywhere. Remember everything."
- "Your data never leaves your Mac."

---

## 6. Core Features (v1.0)

### 6.1 Meeting Recorder

**What:** Capture system audio + mic from any meeting app (Zoom, Meet, Teams, Slack, etc.)

**Two recording modes:**

1. **Manual start** - User clicks menu bar or hits shortcut (Cmd+Shift+R)
2. **Auto-detect** - App monitors for meeting apps and prompts to record

**Audio capture:**
- **Always capture both** system audio AND microphone
- Mix into single stream or keep separate tracks (TBD)
- System audio via ScreenCaptureKit, mic via AVAudioEngine

**Auto-detection (v1.0):**

| App | Detection Method |
|-----|------------------|
| Zoom | `NSRunningApplication` for `zoom.us` |
| Microsoft Teams | `NSRunningApplication` for `Microsoft Teams` |
| Slack Huddle | `NSRunningApplication` for `Slack` + huddle window |
| FaceTime | `NSRunningApplication` for `FaceTime` |
| Discord | `NSRunningApplication` for `Discord` |
| Google Meet PWA | `NSRunningApplication` for `Google Meet.app` |
| Google Meet (Chrome) | AppleScript query Chrome tabs for `meet.google.com` |
| Google Meet (Safari) | AppleScript query Safari tabs for `meet.google.com` |

**Detection flow:**
1. NSWorkspace notifications for app launch/terminate
2. When meeting app detected → check if mic is active (CoreAudio)
3. If both true → show notification: "Meeting detected. Record?"
4. User can enable "always record" per app in settings

**UX:**
- Menu bar icon → click "Start Recording" or use keyboard shortcut
- Red dot in menu bar while recording
- Click again or shortcut to stop
- "Transcribing..." indicator → notification when done

**Technical:**
- macOS ScreenCaptureKit for system audio
- AVAudioEngine for microphone
- Records to compressed .m4a locally
- No bot joins the call
- Process monitoring via `NSWorkspace` notifications (not polling - battery friendly)

### 6.2 Transcription (BYOK)

**What:** Convert recordings to searchable text using user's API key

**Default:** `gpt-4o-mini-transcribe` - $0.003/min, better than Whisper

**Alternatives:**
- `whisper-1` - $0.006/min, if user prefers
- Future: Gemini, local Whisper

**UX:**
- User pastes OpenAI API key in settings
- Show estimated cost before transcribing
- Show running total ("$4.32 spent this month")

**Cost Tracking:**
- Track cost per meeting (API response includes token/duration)
- Daily/weekly/monthly totals in Settings
- Optional spending alerts ("You've spent $10 this week")

### 6.3 Calendar View

**What:** Browse meetings by date, like a calendar

**UX:**
- Week view (default) showing meeting dots per day
- Click day → see list of meetings
- Click meeting → view transcript, play audio
- Search across all transcripts

**Transcript Interaction:**
- View full transcript with timestamps
- Click timestamp → play audio from that point
- **Chat with transcript** - Ask questions about meeting content
  - "What did we decide about pricing?"
  - "Summarize the key points"
  - Uses user's LLM API key (same BYOK)
- Copy/export transcript (plain text, markdown)

**Design:**
- Amie-inspired: minimal, clean, fast
- Keyboard-first: j/k navigation, / to search
- Native SwiftUI feel

### 6.4 System-Wide Dictation

**What:** Hold hotkey → speak → release → text appears at cursor (Wispr Flow style)

**UX:**
- Global hotkey (default: `Ctrl+Cmd+D` - avoids conflicts with Fn/emoji and Cmd+Shift+D/dictionary)
- Floating pill shows "Listening..." with waveform indicator
- Release → transcribe → paste at cursor (~1-2 seconds)
- Works in any app
- Pill is dockable/movable (not fixed center-top)

**Technical:**
- Same transcription API as meetings
- Uses `whisper-1` for lower latency (or let user choose)
- Optional: AI cleanup (remove filler words, fix grammar)

### 6.5 Agent API

**What:** Expose meetings as files for Claude Code / Codex to consume

**File structure:**
```
~/.appname/meetings/
  2025-01-15/
    standup-9am.json
    client-call-2pm.json
  index.json
```

**JSON format:**
```json
{
  "id": "abc123",
  "title": "Daily Standup",
  "date": "2025-01-15",
  "startTime": "09:00",
  "duration": 900,
  "sourceApp": "zoom",
  "transcript": "...",
  "actionItems": ["...", "..."]
}
```

**Agent integration:**
- Claude Code: OAuth with user's Claude subscription (Agent SDK)
- Codex: OAuth with user's ChatGPT Plus/Pro subscription
- Skill reads `~/.appname/meetings/`, answers questions about meetings

### 6.6 Hooks (Pro)

**What:** Trigger actions when meetings end

**Built-in hooks:**
- **Extract action items** - LLM parses transcript, saves to JSON
- **macOS notification** - Summary of what was discussed
- **Webhook** - POST to URL with transcript/summary
- **Run script** - Execute shell command with meeting data

**Technical:**
- Hooks run async after transcription completes
- Uses user's LLM API key (same BYOK model)
- Future: Custom LLM prompts, Zapier/Make

---

## 7. Why Native (Not Web)

**Question:** Could this be a web app to avoid installation?

**Answer:** No - system audio capture requires native app.

| Capability | Web Browser | Native macOS |
|------------|-------------|--------------|
| Microphone capture | ✅ getUserMedia() | ✅ AVAudioEngine |
| **System audio** (Zoom, Meet) | ❌ Not possible | ✅ ScreenCaptureKit |
| Global hotkeys | ❌ Only when focused | ✅ CGEvent / NSEvent |
| Menu bar presence | ❌ No | ✅ NSStatusItem |
| Background operation | ❌ Limited | ✅ Full |

**Web can only capture mic, not what others say in the meeting.** Native is required.

---

## 8. Non-Features (v1.0)

Explicitly NOT building (yet):

- ❌ Cloud sync / backup
- ❌ Team collaboration
- ❌ Analytics dashboards
- ❌ Web app
- ❌ Mobile app

---

## 9. Tech Stack

### Principles

1. **Native & lightweight** - No Electron. Pure Swift.
2. **Minimal dependencies** - Fewer moving parts = fewer bugs
3. **Local-first** - SQLite, file system, no cloud infra
4. **Agent-friendly** - JSON files, simple file access

### Stack

| Layer | Technology | Why |
|-------|------------|-----|
| **Language** | Swift 5.9+ | Native, fast, modern concurrency |
| **UI** | SwiftUI | Declarative, native feel, fast iteration |
| **Audio Capture** | ScreenCaptureKit | macOS 12.3+, system audio capture |
| **Mic Capture** | AVAudioEngine | For dictation |
| **Database** | SQLite via GRDB.swift | Fast, local, FTS5 for search |
| **Transcription** | OpenAI API (GPT-4o-mini-transcribe) | BYOK, cheap, accurate |
| **AI (hooks)** | OpenAI / Anthropic API | BYOK |
| **Agent Auth** | Claude Agent SDK, Codex OAuth | User's subscription |
| **Updates** | Sparkle | Standard macOS update framework |
| **Distribution** | Direct download (Gumroad) | No App Store cut, faster iteration |

### Why Not...

| Alternative | Why Not |
|-------------|---------|
| Electron | Heavy, slow, not native |
| Tauri | Still web UI, less native |
| Local Whisper first | Slower, complex setup - add later |
| Core Data | Overkill, SQLite is simpler |
| Cloud backend | Adds complexity, privacy concerns |

---

## 9. Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        macOS App                            │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  Menu Bar    │  │  Main Window │  │  Hotkey      │      │
│  │  (Controls)  │  │  (Calendar)  │  │  Listener    │      │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘      │
│         │                 │                  │              │
│         ▼                 ▼                  ▼              │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                     Core Services                    │   │
│  │                                                      │   │
│  │  ┌────────────┐ ┌────────────┐ ┌────────────────┐   │   │
│  │  │ Recording  │ │ Meeting    │ │ Dictation      │   │   │
│  │  │ Engine     │ │ Manager    │ │ Engine         │   │   │
│  │  │(ScreenCap) │ │            │ │ (AVAudio)      │   │   │
│  │  └─────┬──────┘ └─────┬──────┘ └───────┬────────┘   │   │
│  │        │              │                │             │   │
│  │        ▼              ▼                ▼             │   │
│  │  ┌─────────────────────────────────────────────┐    │   │
│  │  │              Transcription Service          │    │   │
│  │  │         (OpenAI API - GPT-4o-mini)          │    │   │
│  │  └─────────────────────┬───────────────────────┘    │   │
│  │                        │                             │   │
│  │                        ▼                             │   │
│  │  ┌─────────────────────────────────────────────┐    │   │
│  │  │                 Storage Layer               │    │   │
│  │  │  ┌─────────┐  ┌─────────┐  ┌─────────────┐ │    │   │
│  │  │  │ SQLite  │  │ Audio   │  │ JSON Export │ │    │   │
│  │  │  │ + FTS5  │  │ Files   │  │ (for agents)│ │    │   │
│  │  │  └─────────┘  └─────────┘  └─────────────┘ │    │   │
│  │  └─────────────────────────────────────────────┘    │   │
│  │                        │                             │   │
│  │                        ▼                             │   │
│  │  ┌─────────────────────────────────────────────┐    │   │
│  │  │                 Hooks Engine                │    │   │
│  │  │  (Action items, Webhooks, Scripts)          │    │   │
│  │  └─────────────────────────────────────────────┘    │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Agent Interface                          │
│                                                             │
│   ~/.appname/meetings/*.json  ←──  Claude Code / Codex      │
│                                    (OAuth with user sub)    │
└─────────────────────────────────────────────────────────────┘
```

### Data Flow: Recording

```
User starts recording
        │
        ▼
ScreenCaptureKit captures system audio
        │
        ▼
Audio buffered to temp .m4a
        │
        ▼
User stops recording
        │
        ▼
Audio moved to ~/Library/.../audio/
        │
        ▼
Async: POST to GPT-4o-mini-transcribe
        │
        ▼
Transcript saved to SQLite
        │
        ▼
JSON exported to ~/.appname/meetings/
        │
        ▼
Hooks triggered (action items, webhook, etc.)
```

### Data Flow: Dictation

```
User holds hotkey
        │
        ▼
AVAudioEngine captures mic
        │
        ▼
User releases hotkey
        │
        ▼
Audio sent to Whisper API
        │
        ▼
Text returned (~1s)
        │
        ▼
Text pasted at cursor (Accessibility API)
```

### File Layout

```
~/Library/Application Support/[AppName]/
├── database.sqlite           # Metadata, transcripts
├── audio/
│   └── 2025/01/15/
│       └── abc123.m4a
└── config.json               # Settings (non-sensitive only)

~/.appname/                   # Agent-accessible
└── meetings/
    ├── index.json            # List of all meetings
    └── 2025-01-15/
        ├── standup-9am.json
        └── client-call.json
```

### Security

**API Key Storage:**
- **Use macOS Keychain** via Security framework - NEVER in config files
- Keychain provides hardware-backed security (Secure Enclave on Apple Silicon)
- Keys stored with service identifier: `com.appname.api-keys`

**Data at Rest:**
- `~/.appname/` is world-readable by design (for agents)
- Users must be informed: "Any app can read your meeting transcripts"
- Audio files in `~/Library/Application Support/` have standard macOS protection
- Consider: Option to encrypt audio files with user password (v1.1)

### SQLite Schema

```sql
CREATE TABLE meetings (
  id TEXT PRIMARY KEY,
  title TEXT,
  start_time DATETIME,
  end_time DATETIME,
  duration_seconds INTEGER,
  source_app TEXT,
  audio_path TEXT,
  transcript TEXT,
  action_items TEXT,          -- JSON array
  api_cost_cents INTEGER,
  created_at DATETIME
);

CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT
);

-- Full-text search
CREATE VIRTUAL TABLE meetings_fts USING fts5(
  title, transcript,
  content=meetings, content_rowid=rowid
);

CREATE INDEX idx_meetings_date ON meetings(start_time);
```

---

## 10. Agent Integration Spec

### File-Based API

Claude Code / Codex reads directly from `~/.appname/meetings/`

**index.json:**
```json
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

**Meeting JSON:**
```json
{
  "id": "abc123",
  "title": "Daily Standup",
  "date": "2025-01-15",
  "startTime": "09:00:00",
  "endTime": "09:15:00",
  "duration": 900,
  "sourceApp": "zoom",
  "transcript": "Full transcript text here...",
  "actionItems": [
    "Bruno to send proposal by Friday",
    "Review API docs before next sync"
  ],
  "audioPath": "~/Library/.../audio/2025/01/15/abc123.m4a"
}
```

### Claude Code Skill

```markdown
# [AppName] Skill

Access your recorded meetings.

## Usage

- "What action items came from today's meetings?"
- "Summarize my call with Acme Corp"
- "Find discussions about the API redesign"

## Data Location

Meetings stored at: ~/.appname/meetings/
Read index.json for meeting list.
```

### Auth Flow

**Claude Code:**
1. User has Claude Pro subscription
2. App uses Claude Agent SDK OAuth
3. Claude Code can query meetings via skill
4. Uses user's Claude credits for LLM calls

**Codex:**
1. User has ChatGPT Plus/Pro
2. App uses Codex OAuth flow
3. Codex reads meeting files, answers questions
4. Uses user's ChatGPT credits

---

## 11. Success Metrics

### Launch (Week 1)
- [ ] 500+ ProductHunt upvotes
- [ ] 100+ downloads
- [ ] 20+ paid conversions
- [ ] <5% refund rate

### Month 1
- [ ] 500+ paid users
- [ ] $30k revenue
- [ ] 4.5+ star rating

### Month 3
- [ ] 2,000+ paid users
- [ ] Organic word-of-mouth >50% of sales
- [ ] 5+ community-created integrations

---

## 12. Technical Considerations

### Permissions Required

| Permission | Why | UX Impact |
|------------|-----|-----------|
| **Screen Recording** | ScreenCaptureKit needs this for system audio | Scary dialog, requires System Prefs |
| **Microphone** | Dictation feature | Standard dialog |
| **Accessibility** | Paste at cursor position | Requires System Prefs |

**Mitigation:** Permission pre-flight wizard explaining why each is needed before triggering dialogs.

### Background App Behavior

- **Disable App Nap**: Use `ProcessInfo.beginActivity()` during recording
- **Prevent auto-termination**: Set `NSSupportsAutomaticTermination = NO` in Info.plist
- **Launch at login**: ServiceManagement framework (expected for menu bar apps)

### Audio Encoding

- **Format**: AAC in .m4a container
- **Sample rate**: 16kHz (sufficient for speech, matches Whisper expectation)
- **Bit rate**: 64kbps mono
- **Streaming write**: Use AVAssetWriter to avoid memory issues on long meetings

### Race Condition Prevention

- **Atomic JSON writes**: Write to `.tmp` file, then rename
- **Status field in JSON**: `"status": "ready"` vs `"transcribing"`
- **Lock protocol**: `.lock` file when writing (agents should skip locked files)

### Error Handling

| Scenario | Response |
|----------|----------|
| API key invalid | Show error in Settings, mark transcription as failed |
| Network down | Queue transcription, retry when online |
| Transcription fails | Keep audio, show "Retry" option |
| Disk full | Alert user, pause recording |
| App crash during recording | Recover temp file on next launch |

---

## 13. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Apple adds native meeting transcription | High | Differentiate on agent API, hooks, BYOK |
| OpenAI raises API prices | Medium | Support Gemini, local Whisper |
| macOS permission changes | High | Stay on Apple developer news |
| Users confused by BYOK | Medium | Excellent onboarding, cost calculator |
| High support volume | Medium | Good docs, no free tier |
| Permission UX death spiral | High | Pre-flight wizard, graceful degradation |

---

## 14. Roadmap

### v1.0 (Launch)
- [ ] Meeting recording (manual + auto-detect)
- [ ] Transcription (GPT-4o-mini-transcribe BYOK)
- [ ] Calendar view with transcript chat
- [ ] System-wide dictation
- [ ] Agent API (files)
- [ ] Claude Code skill
- [ ] Cost tracking

### v1.1 (Month 2)
- [ ] Post-processing templates (action items, summary, custom prompts)
- [ ] Speaker diarization & identification
- [ ] Recurring speaker profiles ("characters")
- [ ] Real-time transcription with live insights
- [ ] Codex skill

### v1.2 (Month 3)
- [ ] Screen capture → GIF-like video clips (queryable)
- [ ] Local Whisper option
- [ ] Gemini API support
- [ ] Export (Markdown, Notion)

### v2.0 (Month 6)
- [ ] CRM integrations (Salesforce, HubSpot)
- [ ] Slack integration (post summaries to channels)
- [ ] Full-time low-quality recording (Rewind-like ambient capture)
- [ ] iCloud sync (optional, encrypted)
- [ ] iOS companion (view only)

---

## 15. Open Questions

1. **Name?** - "Whisper" conflicts with OpenAI. Ideas: Murmur, Hark, Jot, Recall, Echo
2. **Auto-detect meetings?** - How reliable is detecting Zoom/Meet/Teams starting?
3. **Mic + system audio?** - Always both, or user choice?
4. **Dictation model?** - Whisper for speed vs GPT-4o for quality?
5. **Mac App Store?** - MAS has discovery but 30% cut + review delays

---

## 16. Milestones

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
- [ ] Week view
- [ ] Transcript viewer
- [ ] Search (FTS5)
- [ ] Clean design

### M4: Dictation
- [ ] Global hotkey
- [ ] Mic capture
- [ ] Transcribe on release
- [ ] Paste at cursor

### M5: Agent API
- [ ] JSON export
- [ ] Claude Code skill
- [ ] Hooks (action items, webhook)

### M6: Polish & Launch
- [ ] Onboarding
- [ ] Settings UI
- [ ] Sparkle updates
- [ ] Landing page
- [ ] ProductHunt

---

*Ready to build.*
