# MeetingRecorder Skill

Read and query transcribed meeting recordings from the MeetingRecorder app.

## Data Location

Meetings are exported as JSON to `~/.meetingrecorder/meetings/`:

```
~/.meetingrecorder/meetings/
├── index.json              # List of all meetings
└── 2025-01-15/
    ├── daily-standup.json  # Individual meeting files
    └── client-call.json
```

## How to Use

### 1. Read the index first

```bash
cat ~/.meetingrecorder/meetings/index.json
```

This returns a list of all available meetings with their IDs, dates, and file paths.

### 2. Read individual meetings

```bash
cat ~/.meetingrecorder/meetings/2025-01-15/daily-standup.json
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

## Status Values

- `ready` - Transcription complete, safe to read
- `recording` - Currently recording (skip)
- `pendingTranscription` - Waiting for transcription (skip)
- `transcribing` - Being transcribed (skip)
- `failed` - Transcription failed

**Only read meetings with status `ready`.**

## Lock File Protocol

If `~/.meetingrecorder/meetings/.lock` exists, the app is writing files. Wait briefly and retry.

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

1. Read index.json to get meeting paths
2. Read each meeting JSON
3. Search transcript fields for the keyword

### "Summarize this week's meetings"

1. Filter index.json for this week's dates
2. Read each meeting JSON
3. Extract titles, durations, and key transcript excerpts

## Tips

- **Check status first** - Only process `ready` meetings
- **Use index.json** - Don't scan directories; use the index
- **Handle missing files** - Meetings may be deleted
- **Respect the lock** - If .lock exists, wait and retry
- **Transcripts are plain text** - No speaker identification
