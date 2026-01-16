---
name: navi
description: Control the Navi GUI from Claude Code. Create/fork chats, manage projects/folders, open previews, change settings, and more. Use when Claude needs to interact with the Navi UI itself.
---

# Navi Control Skill

Control the Navi GUI directly from Claude Code. This skill lets you manage sessions, projects, folders, open previews, and configure settings programmatically.

## API Base

All endpoints are at `http://localhost:3001/api`. Use `curl` for all requests.

## Quick Reference

| Action | Endpoint | Method |
|--------|----------|--------|
| Create new chat | `/projects/{id}/sessions` | POST |
| Fork chat | `/sessions/{id}/fork` | POST |
| Open URL preview | WebSocket message | - |
| Create folder | `/folders` | POST |
| List projects | `/projects` | GET |
| Change model | WebSocket message | - |

---

## Session Management

### Create New Chat Session

```bash
curl -X POST http://localhost:3001/api/projects/{projectId}/sessions \
  -H "Content-Type: application/json" \
  -d '{"title": "New Chat"}'
```

### Fork an Existing Chat

Fork from a specific message (great for exploring alternative approaches):

```bash
curl -X POST http://localhost:3001/api/sessions/{sessionId}/fork \
  -H "Content-Type: application/json" \
  -d '{"fromMessageId": "msg_123", "title": "Forked: Trying different approach"}'
```

### List Recent Sessions

```bash
curl http://localhost:3001/api/sessions/recent?limit=10
```

### Get Session Details

```bash
curl http://localhost:3001/api/sessions/{sessionId}
```

### Update Session Title

```bash
curl -X PATCH http://localhost:3001/api/sessions/{sessionId} \
  -H "Content-Type: application/json" \
  -d '{"title": "New Title"}'
```

### Pin/Unpin Session

```bash
curl -X POST http://localhost:3001/api/sessions/{sessionId}/pin \
  -H "Content-Type: application/json" \
  -d '{"pinned": true}'
```

### Favorite a Session

```bash
curl -X POST http://localhost:3001/api/sessions/{sessionId}/favorite \
  -H "Content-Type: application/json" \
  -d '{"favorite": true}'
```

### Delete Session

```bash
curl -X DELETE http://localhost:3001/api/sessions/{sessionId}
```

### Export Session as Markdown

```bash
curl http://localhost:3001/api/sessions/{sessionId}/export
```

---

## Project Management

### List All Projects

```bash
curl http://localhost:3001/api/projects
# Include archived:
curl "http://localhost:3001/api/projects?includeArchived=true"
```

### Create New Project

```bash
curl -X POST http://localhost:3001/api/projects \
  -H "Content-Type: application/json" \
  -d '{"name": "My Project", "path": "/path/to/project", "description": "Optional description"}'
```

### Update Project

```bash
curl -X PUT http://localhost:3001/api/projects/{projectId} \
  -H "Content-Type: application/json" \
  -d '{"name": "Updated Name", "path": "/new/path", "context_window": 200000}'
```

### Pin/Unpin Project

```bash
curl -X POST http://localhost:3001/api/projects/{projectId}/pin \
  -H "Content-Type: application/json" \
  -d '{"pinned": true}'
```

### Archive/Unarchive Project

```bash
curl -X POST http://localhost:3001/api/projects/{projectId}/archive \
  -H "Content-Type: application/json" \
  -d '{"archived": true}'
```

### Move Project to Folder

```bash
curl -X POST http://localhost:3001/api/projects/{projectId}/folder \
  -H "Content-Type: application/json" \
  -d '{"folderId": "folder_123"}'
# Remove from folder:
curl -X POST http://localhost:3001/api/projects/{projectId}/folder \
  -H "Content-Type: application/json" \
  -d '{"folderId": null}'
```

### Generate Project Summary

```bash
curl -X POST http://localhost:3001/api/projects/{projectId}/summary
```

### Delete Project

```bash
curl -X DELETE http://localhost:3001/api/projects/{projectId}
```

---

## Folder Management

### List Folders

```bash
curl http://localhost:3001/api/folders
```

### Create Folder

```bash
curl -X POST http://localhost:3001/api/folders \
  -H "Content-Type: application/json" \
  -d '{"name": "Work Projects"}'
```

### Rename Folder

```bash
curl -X PUT http://localhost:3001/api/folders/{folderId} \
  -H "Content-Type: application/json" \
  -d '{"name": "New Folder Name"}'
```

### Collapse/Expand Folder

```bash
curl -X POST http://localhost:3001/api/folders/{folderId}/collapse \
  -H "Content-Type: application/json" \
  -d '{"collapsed": true}'
```

### Delete Folder

```bash
curl -X DELETE http://localhost:3001/api/folders/{folderId}
```

---

## Messages

### List Messages in Session

```bash
curl http://localhost:3001/api/sessions/{sessionId}/messages
```

### Rollback to a Message

Revert session to a previous point (deletes messages after the specified one):

```bash
curl -X POST http://localhost:3001/api/sessions/{sessionId}/rollback \
  -H "Content-Type: application/json" \
  -d '{"messageId": "msg_123"}'
```

---

## Search

### Search Sessions and Messages

```bash
curl "http://localhost:3001/api/search?q=search+term"
# Limit to project:
curl "http://localhost:3001/api/search?q=term&projectId=proj_123"
```

### Reindex Search

```bash
curl -X POST http://localhost:3001/api/search/reindex
```

---

## Preview Panel

To open a URL or file in Navi's preview panel, send a WebSocket message. The UI listens for these special markdown patterns:

### In Your Response

Simply include a URL in your text response and the user can click to preview:

```
You can preview this at http://localhost:3000
```

### Media Display

Use a media code block to show images/audio/video inline:

~~~
```media
src: /path/to/image.png
caption: Screenshot of the result
```
~~~

---

## Permissions & Settings

### Get Permission Settings

```bash
curl http://localhost:3001/api/permissions
```

### Update Permissions

```bash
curl -X POST http://localhost:3001/api/permissions \
  -H "Content-Type: application/json" \
  -d '{
    "autoAcceptAll": false,
    "allowedTools": ["Read", "Glob", "Grep"],
    "requireConfirmation": ["Bash", "Write", "Edit"]
  }'
```

### Set Session Auto-Accept

```bash
curl -X POST http://localhost:3001/api/sessions/{sessionId}/auto-accept \
  -H "Content-Type: application/json" \
  -d '{"autoAcceptAll": true}'
```

### Set Project Auto-Accept

```bash
curl -X POST http://localhost:3001/api/projects/{projectId}/auto-accept \
  -H "Content-Type: application/json" \
  -d '{"autoAcceptAll": true}'
```

---

## CLAUDE.md Management

### Get Default CLAUDE.md

```bash
curl http://localhost:3001/api/claude-md/default
```

### Set Default CLAUDE.md

```bash
curl -X POST http://localhost:3001/api/claude-md/default \
  -H "Content-Type: application/json" \
  -d '{"content": "# Instructions\n\nBe helpful."}'
```

### Get Project CLAUDE.md

```bash
curl "http://localhost:3001/api/claude-md/project?path=/path/to/project"
```

### Set Project CLAUDE.md

```bash
curl -X POST "http://localhost:3001/api/claude-md/project?path=/path/to/project" \
  -H "Content-Type: application/json" \
  -d '{"content": "# Project Instructions\n..."}'
```

### Initialize Project CLAUDE.md

Creates a CLAUDE.md file if it doesn't exist:

```bash
curl -X POST http://localhost:3001/api/claude-md/init \
  -H "Content-Type: application/json" \
  -d '{"path": "/path/to/project"}'
```

---

## Models

### List Available Models

```bash
curl http://localhost:3001/api/models
```

---

## Cost Tracking

### Get Total Costs

```bash
curl http://localhost:3001/api/costs
```

### Get Cost Analytics

```bash
curl http://localhost:3001/api/costs/analytics
# Filter by projects:
curl "http://localhost:3001/api/costs/analytics?projectIds=proj1,proj2"
```

### Get Session Cost

```bash
curl http://localhost:3001/api/sessions/{sessionId}/cost
```

---

## Skills Management

### List All Skills

```bash
curl http://localhost:3001/api/skills
```

### Enable Skill Globally

```bash
curl -X POST http://localhost:3001/api/skills/{skillId}/enable
```

### Enable Skill for Project

```bash
curl -X POST http://localhost:3001/api/projects/{projectId}/skills/{skillId}/enable
```

### Sync Skills from Filesystem

```bash
curl -X POST http://localhost:3001/api/skills/sync-global
```

---

## Authentication

### Check Auth Status

```bash
curl http://localhost:3001/api/auth/status
```

### Set API Key

```bash
curl -X POST http://localhost:3001/api/auth/api-key \
  -H "Content-Type: application/json" \
  -d '{"apiKey": "sk-ant-..."}'
```

---

## Filesystem Operations

### Create Directory

```bash
curl -X POST http://localhost:3001/api/fs/mkdir \
  -H "Content-Type: application/json" \
  -d '{"path": "/path/to/new/directory"}'
```

### Reveal in Finder

```bash
curl -X POST http://localhost:3001/api/fs/reveal \
  -H "Content-Type: application/json" \
  -d '{"path": "/path/to/file"}'
```

---

## Common Workflows

### Start a Fresh Conversation on Same Topic

```bash
# 1. Get current session to find project
curl http://localhost:3001/api/sessions/{currentSessionId}

# 2. Create new session in same project
curl -X POST http://localhost:3001/api/projects/{projectId}/sessions \
  -H "Content-Type: application/json" \
  -d '{"title": "Fresh start: Same topic"}'
```

### Fork to Try Different Approach

```bash
# Get message ID from session messages
curl http://localhost:3001/api/sessions/{sessionId}/messages

# Fork from that point
curl -X POST http://localhost:3001/api/sessions/{sessionId}/fork \
  -H "Content-Type: application/json" \
  -d '{"fromMessageId": "last_good_msg_id", "title": "Alternative: Trying X approach"}'
```

### Organize Projects into Folders

```bash
# Create folder
FOLDER=$(curl -s -X POST http://localhost:3001/api/folders \
  -H "Content-Type: application/json" \
  -d '{"name": "Client Work"}' | jq -r '.id')

# Move projects to folder
curl -X POST http://localhost:3001/api/projects/{projectId}/folder \
  -H "Content-Type: application/json" \
  -d "{\"folderId\": \"$FOLDER\"}"
```

---

## Tips

1. **Use jq** for parsing JSON responses: `curl ... | jq '.id'`
2. **Session IDs** are UUIDs like `550e8400-e29b-41d4-a716-446655440000`
3. **Forking** is non-destructive - original session remains unchanged
4. **Auto-accept** settings cascade: Session > Project > Global
5. **Search** is full-text across all sessions and messages

## Guidelines

1. Always check the response for errors before proceeding
2. Use descriptive titles when creating sessions/folders
3. Prefer forking over rollback when exploring alternatives
4. Clean up test sessions/projects when done experimenting
5. Use the preview panel for visual content rather than terminal output
