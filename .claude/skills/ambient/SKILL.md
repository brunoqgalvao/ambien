# Ambient Skill

Read and query transcribed meeting recordings from the Ambient app.

## Data Location

Meetings are exported as JSON to `~/.ambient/meetings/`:

```
~/.ambient/meetings/
├── index.json              # List of all meetings
├── groups/                 # Grouped meetings (project threads)
│   └── abc123.json
└── 2025-01-15/
    ├── daily-standup.json  # Individual meeting files
    └── client-call.json
```

## CLI Tool

If installed, use the `ambient` CLI for easier access:

```bash
# List recent meetings
ambient list

# List meetings from a specific date
ambient list --date 2025-01-15

# Search transcripts
ambient search "authentication"

# Get a specific meeting
ambient get <meeting-id>

# Export to markdown
ambient export <meeting-id> --format=md
```

## Direct JSON Access

### 1. Read the index first

```bash
cat ~/.ambient/meetings/index.json
```

This returns a list of all available meetings with their IDs, dates, and file paths.

### 2. Read individual meetings

```bash
cat ~/.ambient/meetings/2025-01-15/daily-standup.json
```

## JSON Formats

### index.json

```json
{
  "version": 1,
  "lastUpdated": "2025-01-15T18:30:00Z",
  "meetings": [
    {
      "id": "abc123-...",
      "date": "2025-01-15",
      "title": "Daily Standup",
      "status": "ready",
      "path": "2025-01-15/daily-standup.json"
    }
  ],
  "groups": [
    {
      "id": "def456-...",
      "name": "Project Alpha",
      "emoji": "🚀",
      "meetingCount": 5,
      "path": "groups/def456.json"
    }
  ]
}
```

### Meeting JSON

```json
{
  "id": "abc123-...",
  "title": "Daily Standup",
  "date": "2025-01-15",
  "startTime": "09:00:00",
  "endTime": "09:15:00",
  "duration": 900,
  "sourceApp": "zoom",
  "transcript": "Full transcript text...",
  "actionItems": ["Item 1", "Item 2"],
  "status": "ready",
  "audioPath": "/Users/.../audio/meeting.m4a",
  "apiCostCents": 14,
  "createdAt": "2025-01-15T09:15:00Z"
}
```

### Group JSON

```json
{
  "id": "def456-...",
  "name": "Project Alpha",
  "emoji": "🚀",
  "createdAt": "2025-01-10T10:00:00Z",
  "meetings": [
    {
      "id": "abc123-...",
      "title": "Kickoff",
      "date": "2025-01-10",
      "transcript": "..."
    }
  ],
  "combinedTranscript": "All meeting transcripts concatenated..."
}
```

## Status Values

- `ready` - Transcription complete, safe to read
- `recording` - Currently recording (skip)
- `pendingTranscription` - Waiting for transcription (skip)
- `transcribing` - Being transcribed (skip)
- `failed` - Transcription failed

**Only read meetings with status `ready`.**

## Lock File Protocol

If `~/.ambient/meetings/.lock` exists, the app is writing files. Wait briefly and retry.

## Example Queries

### "What did we discuss in yesterday's standup?"

1. Read index.json to find yesterday's meetings
2. Find the standup meeting by title/date
3. Read the transcript from the meeting JSON

### "What action items came out of recent meetings?"

1. Read index.json
2. For each recent meeting, read the JSON
3. Collect `actionItems` arrays from each

### "Search all meetings for mentions of 'authentication'"

```bash
# With CLI
ambient search "authentication"

# Or manually
grep -r "authentication" ~/.ambient/meetings/
```

### "Summarize this week's meetings"

1. Filter index.json for this week's dates
2. Read each meeting JSON
3. Extract titles, durations, and key transcript excerpts

### "Get context from project meetings"

1. Read index.json to find relevant group
2. Read the group JSON for combined transcript
3. Use combined transcript for full project context

## Tips

- **Check status first** - Only process `ready` meetings
- **Use index.json** - Don't scan directories; use the index
- **Handle missing files** - Meetings may be deleted
- **Respect the lock** - If .lock exists, wait and retry
- **Transcripts are plain text** - No speaker identification
- **Groups have combined context** - Use for project-wide queries
