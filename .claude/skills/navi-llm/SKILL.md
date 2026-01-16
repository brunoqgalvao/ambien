---
name: navi-llm
description: Dispatch prompts to any LLM (OpenAI, Anthropic, Google). Use when Claude needs a second opinion, parallel research, or to leverage other models' strengths.
---

# Navi LLM - Multi-Model Dispatch

You can dispatch prompts to other LLMs for second opinions, parallel research, or leveraging model-specific strengths.

## Tool Location

```bash
~/.claude/skills/navi-llm/index.ts
```

## Setup

Run the interactive setup to configure API keys:

```bash
bun ~/.claude/skills/navi-llm/setup.ts
```

### Setup Commands

| Command | Description |
|---------|-------------|
| `bun setup.ts` | Interactive setup wizard |
| `bun setup.ts status` | Quick status check |
| `bun setup.ts test` | Test all configured providers |
| `bun setup.ts add openai` | Add/update specific provider |
| `bun setup.ts add anthropic` | Add/update Anthropic key |
| `bun setup.ts add google` | Add/update Gemini key |

### Get API Keys

| Provider | URL |
|----------|-----|
| OpenAI | https://platform.openai.com/api-keys |
| Anthropic | https://console.anthropic.com/settings/keys |
| Google | https://aistudio.google.com/app/apikey |

## Quick Commands

### Check Available Models
```bash
bun ~/.claude/skills/navi-llm/index.ts models
```

### Check Configured Providers
```bash
bun ~/.claude/skills/navi-llm/index.ts providers
```

### Dispatch a Prompt
```bash
bun ~/.claude/skills/navi-llm/index.ts <model> "<prompt>"
```

## Model Shortcuts

| Shortcut | Provider | Model |
|----------|----------|-------|
| `gpt4`, `gpt4o` | OpenAI | gpt-4o |
| `gpt4-mini` | OpenAI | gpt-4o-mini |
| `o1` | OpenAI | o1 |
| `o1-mini` | OpenAI | o1-mini |
| `opus` | Anthropic | claude-opus-4.5 |
| `sonnet` | Anthropic | claude-sonnet-4 |
| `haiku` | Anthropic | claude-3.5-haiku |
| `claude` | Anthropic | claude-3.5-sonnet |
| `gemini` | Google | gemini-2.0-flash |
| `gemini-pro` | Google | gemini-1.5-pro |
| `gemini-flash` | Google | gemini-1.5-flash |

## Options

| Flag | Description |
|------|-------------|
| `--stream` | Stream output in real-time |
| `--system "..."` | Set system prompt |
| `--max-tokens N` | Max tokens (default: 4096) |
| `--temperature N` | Temperature 0-2 |
| `--json` | Output as JSON for parsing |

## Examples

### Get a Second Opinion on Code
```bash
bun ~/.claude/skills/navi-llm/index.ts gpt4o "Review this code for bugs: $(cat src/utils.ts)"
```

### Quick Summary with Fast Model
```bash
bun ~/.claude/skills/navi-llm/index.ts haiku "Summarize in 2 sentences: ..."
```

### Reasoning Task
```bash
bun ~/.claude/skills/navi-llm/index.ts o1 "Think step by step: What's the optimal algorithm for..."
```

### Multimodal Analysis (Gemini)
```bash
bun ~/.claude/skills/navi-llm/index.ts gemini "Analyze this architecture diagram" --system "You are a senior architect"
```

### Stream Long Response
```bash
bun ~/.claude/skills/navi-llm/index.ts gpt4o "Write a detailed analysis of..." --stream
```

### JSON Output for Parsing
```bash
bun ~/.claude/skills/navi-llm/index.ts gpt4-mini "List 5 improvements" --json
```

## Use Cases for Claude

### 1. Second Opinion
When unsure about a solution, ask another model:
```bash
bun ~/.claude/skills/navi-llm/index.ts gpt4o "Is this the best approach for handling concurrent writes? $(cat my_solution.ts)"
```

### 2. Parallel Research
Dispatch multiple models for different perspectives:
```bash
# Run these in parallel
bun ~/.claude/skills/navi-llm/index.ts gpt4o "Research best practices for: X"
bun ~/.claude/skills/navi-llm/index.ts gemini "Find examples of: X"
```

### 3. Model-Specific Strengths
- **o1/o1-mini**: Complex reasoning, math, logic
- **Gemini**: Long context, multimodal, real-time info
- **GPT-4o**: General capability, tool use
- **Haiku**: Fast summaries, simple tasks (cheap)

### 4. Cost Optimization
Use cheaper models for simple tasks:
```bash
# Use haiku for quick classification
bun ~/.claude/skills/navi-llm/index.ts haiku "Classify this issue as bug/feature/question: ..."

# Use full model only for complex work
bun ~/.claude/skills/navi-llm/index.ts gpt4o "Design a solution for: ..."
```

## API Key Management

Keys are auto-discovered from keymanager. To add missing providers:

```bash
# Check what's available
export KEYMANAGER_MASTER_KEY="1479863a-96d5-4a9d-9824-1996c21a2d36"
/Users/brunogalvao/Documents/dev-bruno/api-key-manager/index.ts list

# Add OpenAI key
/Users/brunogalvao/Documents/dev-bruno/api-key-manager/index.ts add --service openai --key sk-... --global --env production

# Add Gemini key
/Users/brunogalvao/Documents/dev-bruno/api-key-manager/index.ts add --service gemini --key ... --global --env production
```

## Programmatic Integration

The tool can be called from other skills or scripts:

```typescript
import { execSync } from "child_process";

function askLLM(model: string, prompt: string): string {
  const result = execSync(
    `bun ~/.claude/skills/navi-llm/index.ts ${model} "${prompt.replace(/"/g, '\\"')}" --json`,
    { encoding: "utf-8" }
  );
  return JSON.parse(result).response;
}

// Usage
const review = askLLM("gpt4o", "Review this code...");
```

## Troubleshooting

### "No API key found"
Add the missing provider key via keymanager:
```bash
export KEYMANAGER_MASTER_KEY="1479863a-96d5-4a9d-9824-1996c21a2d36"
/Users/brunogalvao/Documents/dev-bruno/api-key-manager/index.ts add --service <provider> --key <key> --global --env production
```

### "Unknown model"
Run `bun ~/.claude/skills/navi-llm/index.ts models` to see available models and shortcuts.

### Rate Limits
If you hit rate limits, try:
1. Using a different provider
2. Adding delay between requests
3. Using a smaller/faster model (haiku, gpt4-mini)
