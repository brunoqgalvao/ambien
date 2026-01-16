---
name: gemini-cli
description: Use when the user asks to run Gemini CLI, Google Gemini for code tasks, or references Gemini for analysis, code generation, or automated editing
---

# Gemini CLI Skill Guide (v0.23.0+)

## ALWAYS USE GEMINI 3

**Default to Gemini 3 models for all tasks.** These are the current generation with superior reasoning.

| Model | When to Use |
|-------|-------------|
| `gemini-3-flash-preview` | **DEFAULT** - Use for most tasks. Fast + smart. |
| `gemini-3-pro-preview` | Complex reasoning, architecture, 1M context tasks |

### Legacy Models (only if specifically requested)
| Model | Notes |
|-------|-------|
| `gemini-2.5-pro` | Previous flagship |
| `gemini-2.5-flash` | High throughput |

### Gemini 3 Features
- **`thinking_level`** - Control reasoning depth (`low`, `medium`, `high`)
- **`media_resolution`** - Vision processing quality (`low`, `medium`, `high`, `ultra_high`)
- **Thought Signatures** - Maintains chain of reasoning across calls

## Running a Task

1. Ask the user which model to run (default: `gemini-3-flash-preview`) AND which approval mode (`default`, `auto_edit`, `yolo`) in a **single prompt**.
2. Select approval mode based on task:
   - `default` - Prompt for approval on each action
   - `auto_edit` - Auto-approve file edits only
   - `yolo` - Auto-approve all actions (use with caution)
3. Assemble command with options:
   - `-m, --model <MODEL>` (e.g., `-m gemini-2.5-pro`)
   - `--approval-mode <default|auto_edit|yolo>`
   - `-y, --yolo` (shortcut for `--approval-mode yolo`)
   - `-s, --sandbox` (run in sandbox mode)
   - `--include-directories <PATH>` (add additional directories)
   - `-r, --resume <latest|INDEX>` (resume previous session)
   - `-o, --output-format <text|json|stream-json>` (output format)
4. **Non-interactive one-shot**: `gemini "your prompt here"` (positional argument)
5. **Interactive after prompt**: `gemini -i "initial prompt"`
6. **Resume syntax**: `gemini -r latest` or `gemini -r 5`
7. **After completion**: Inform user they can resume with `gemini -r latest`.

> **Note**: The `-p/--prompt` flag is **deprecated**. Use positional arguments instead.

### Quick Reference

| Use case | Approval mode | Command |
|----------|---------------|---------|
| Read-only review | `default` | `gemini -m gemini-3-flash-preview "prompt"` |
| Complex reasoning | `default` | `gemini -m gemini-3-pro-preview "prompt"` |
| Auto file edits | `auto_edit` | `gemini -m gemini-3-flash-preview --approval-mode auto_edit "prompt"` |
| Full auto (YOLO) | `yolo` | `gemini -m gemini-3-flash-preview -y "prompt"` |
| Sandboxed | `default` | `gemini -m gemini-3-flash-preview -s "prompt"` |
| With extra dirs | Match task | `gemini -m gemini-3-flash-preview --include-directories /path/to/other "prompt"` |
| Resume latest | Inherited | `gemini -r latest` |
| Resume specific | Inherited | `gemini -r 5` |
| Interactive mode | Match task | `gemini -i "start with this prompt"` |
| JSON output | Match task | `gemini -m gemini-3-flash-preview -o json "prompt"` |
| Stream JSON | Match task | `gemini -m gemini-3-flash-preview -o stream-json "prompt"` |

## Session Management

| Command | Description |
|---------|-------------|
| `gemini --list-sessions` | List available sessions |
| `gemini -r latest` | Resume most recent session |
| `gemini -r <INDEX>` | Resume session by index |
| `gemini --delete-session <INDEX>` | Delete a session |

## MCP & Extensions

| Command | Description |
|---------|-------------|
| `gemini mcp` | Manage MCP servers |
| `gemini -l` / `--list-extensions` | List available extensions |
| `gemini -e ext1 ext2` | Use specific extensions only |
| `--allowed-mcp-server-names` | Specify allowed MCP servers |
| `--allowed-tools` | Tools that run without confirmation |

## Built-in Tools

Gemini CLI has these tools enabled by default:
- **File operations**: Read/write files in working directory
- **Shell commands**: Execute terminal commands
- **Web fetch**: Retrieve web content
- **Google Search**: Grounded search for current information

## Project Context

Create `GEMINI.md` in project root for project-specific instructions (similar to CLAUDE.md).

## Following Up

- After every `gemini` command, confirm next steps or offer to resume.
- Resume preserves original model and approval mode.
- Restate configuration when proposing follow-up actions.

## Error Handling

- Stop and report failures on non-zero exit; request direction before retry.
- Ask permission before using `-y`/`--yolo` mode.
- Summarize warnings/partial results and ask how to proceed.
- Check authentication if getting 401/403 errors.
- For quota issues, suggest switching auth methods or waiting.

## Key Differences from Codex

| Feature | Gemini CLI | Codex CLI |
|---------|------------|-----------|
| One-shot syntax | `gemini "prompt"` | `codex exec "prompt"` |
| Auto mode | `-y` or `--approval-mode yolo` | `--full-auto` |
| Sandbox | `-s` | `--sandbox <mode>` |
| Resume | `-r latest` | `resume --last` |
| Interactive | `-i "prompt"` | Default interactive |
| Output format | `-o json/stream-json` | N/A |
