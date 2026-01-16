# Keymanager Skill for Claude

This skill enables Claude to manage your API keys using natural language.

## Installation

The skill is already installed at `~/.claude/skills/keymanager/`

## Usage

Just talk to Claude naturally:

- "Add my OpenAI key"
- "Show all my keys"
- "What keys do I have for my chatbot project?"
- "Create a .env file for my app"
- "Get my stripe API key"

## Examples

### Adding Keys
```
You: "Add my OpenAI API key sk-proj-123 for the chatbot project"
Claude: ✅ Added your OpenAI key for the chatbot project!
```

### Finding Keys
```
You: "What OpenAI keys do I have?"
Claude: You have 1 OpenAI key for projects: chatbot, assistant
```

### Creating .env
```
You: "Set up my .env for the backend"
Claude: ✅ Created .env with 3 keys (OpenAI, Stripe, Supabase)
```

## How It Works

Claude translates your natural language into keymanager CLI commands and runs them securely with your encrypted vault.

All keys are encrypted with AES-256-GCM and stored at `~/.keymanager/vault.enc`
