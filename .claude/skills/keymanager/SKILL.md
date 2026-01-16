---
name: keymanager
description: Manage API keys with natural language. Use when the user wants to add, find, list, get, delete API keys, generate .env files, or manage project keys
---

# API Key Manager Skill

You are an expert at managing API keys using the keymanager CLI tool. The tool is **project-aware** and automatically detects the current project context. Help users manage their API keys using natural language.

## Tool Location

- **Script**: `/Users/brunogalvao/Documents/dev-bruno/api-key-manager/index.ts`
- **Master Key**: `1479863a-96d5-4a9d-9824-1996c21a2d36`

## Command Template

**ALWAYS** prefix commands with the master key:
```bash
export KEYMANAGER_MASTER_KEY="1479863a-96d5-4a9d-9824-1996c21a2d36" && /Users/brunogalvao/Documents/dev-bruno/api-key-manager/index.ts <command>
```

## Project-Aware Behavior

The tool automatically detects the current project using (in priority order):
1. Git repo name
2. package.json name
3. Directory name

When adding keys, it auto-tags them with the current project and updates .env if it exists.

## Available Commands

### 1. Status - See Current Project Context
```bash
export KEYMANAGER_MASTER_KEY="1479863a-96d5-4a9d-9824-1996c21a2d36" && /Users/brunogalvao/Documents/dev-bruno/api-key-manager/index.ts status [--format json]
```
Shows: project name, .env files, keys in use, keys available

### 2. Add - Add a Key (Auto-detects project)
```bash
export KEYMANAGER_MASTER_KEY="1479863a-96d5-4a9d-9824-1996c21a2d36" && /Users/brunogalvao/Documents/dev-bruno/api-key-manager/index.ts add --service <service> --key <key> [--env local|dev|staging|prod] [--global] [--description "desc"]
```
- Auto-tags with current project unless `--global` is used
- Auto-updates .env if it exists
- `--env` tag is required (defaults to 'local')

### 3. Use - Add Existing Keys to Current Project
```bash
export KEYMANAGER_MASTER_KEY="1479863a-96d5-4a9d-9824-1996c21a2d36" && /Users/brunogalvao/Documents/dev-bruno/api-key-manager/index.ts use <service1> <service2> ... [--env-file .env]
```
Links existing global keys to current project and updates .env

### 4. Import - Import Keys from .env File
```bash
export KEYMANAGER_MASTER_KEY="1479863a-96d5-4a9d-9824-1996c21a2d36" && /Users/brunogalvao/Documents/dev-bruno/api-key-manager/index.ts import [--file .env] [--env local]
```
Reads .env file and imports all keys into vault

### 5. List Keys
```bash
export KEYMANAGER_MASTER_KEY="1479863a-96d5-4a9d-9824-1996c21a2d36" && /Users/brunogalvao/Documents/dev-bruno/api-key-manager/index.ts list [--format table|json|compact] [--project <project>] [--service <service>] [--tag <tag>]
```

### 6. Find Keys (LLM-friendly, JSON by default)
```bash
export KEYMANAGER_MASTER_KEY="1479863a-96d5-4a9d-9824-1996c21a2d36" && /Users/brunogalvao/Documents/dev-bruno/api-key-manager/index.ts find [--service <service>] [--project <project>] [--tag <tag>]
```

### 7. Get Specific Key
```bash
export KEYMANAGER_MASTER_KEY="1479863a-96d5-4a9d-9824-1996c21a2d36" && /Users/brunogalvao/Documents/dev-bruno/api-key-manager/index.ts get <id> [--show-key] [--format json]
```

### 8. Inject - Generate .env File
```bash
export KEYMANAGER_MASTER_KEY="1479863a-96d5-4a9d-9824-1996c21a2d36" && /Users/brunogalvao/Documents/dev-bruno/api-key-manager/index.ts inject <output-file> [--project <project>] [--service <service>] [--tag <tag>] [--append]
```

### 9. Delete Key
```bash
export KEYMANAGER_MASTER_KEY="1479863a-96d5-4a9d-9824-1996c21a2d36" && /Users/brunogalvao/Documents/dev-bruno/api-key-manager/index.ts delete <id> --force
```

## Natural Language Translation

Translate user requests into keymanager commands. Remember the tool is **project-aware**!

| User Says | You Run |
|-----------|---------|
| "What's the status?" | `status` |
| "Show me what keys I have" | `status` or `list` |
| "Add my OpenAI key sk-xxx" | `add --service openai --key sk-xxx --env local` (auto-detects project) |
| "Add OpenAI key as global" | `add --service openai --key sk-xxx --global --env production` |
| "Import my .env file" | `import` |
| "Use my OpenAI key in this project" | `use openai` |
| "Add Stripe and OpenAI to this project" | `use stripe openai` |
| "What OpenAI keys do I have?" | `find --service openai` |
| "Get my stripe key" | `get stripe --show-key` |
| "Create .env for production" | `inject .env.production --tag production` |
| "Delete old github key" | First confirm, then `delete github --force` |

## Common Workflows

### Workflow 1: Starting a New Project
```
User: "I'm starting a new project, set it up"
1. Run: `status` - See what's available
2. Suggest: "You have OpenAI and Stripe keys available. Want to add them?"
3. Run: `use openai stripe` - Link existing keys
```

### Workflow 2: Importing Existing Project
```
User: "Import my existing .env"
1. Run: `import --file .env`
2. Run: `status` - Show what was imported
```

### Workflow 3: Adding a New Key
```
User: "Add my database credentials"
1. Ask: "What's the DATABASE_URL?"
2. Run: `add --service database --key postgres://... --env local`
3. Note: .env is auto-updated if it exists
```

### Workflow 4: Environment-Specific Keys
```
User: "Set up production keys"
1. Run: `add --service db --key prod-url --env production`
2. Run: `inject .env.production --tag production`
```

## Service Name Mapping

Auto-detect services from common names:
- OpenAI, GPT → `openai`
- Claude, Anthropic → `anthropic`
- Stripe → `stripe`
- GitHub, GH → `github`
- Database, DB, Postgres, MySQL → `database`
- Redis → `redis`
- Supabase → `supabase`
- Vercel → `vercel`
- AWS → `aws`
- Google, GCP → `gcp`

## Environment Tags

Always use environment tags:
- `local` - Local development (default)
- `dev` - Development server
- `staging` - Staging environment
- `prod` or `production` - Production

## Key Behaviors

1. **When in a project directory**: Keys are auto-tagged with project name
2. **If .env exists**: Keys are automatically added/updated in .env
3. **Global keys**: Use `--global` flag to add keys not tied to a project
4. **Shared keys**: Same key can be linked to multiple projects

## Response Strategy

1. **Start with status** when user asks about keys or projects
2. **Suggest `use`** when user wants to add existing keys
3. **Suggest `import`** when user has an existing .env
4. **Use `add`** for new keys or project-specific keys
5. **Always mention** if .env was auto-updated

## Examples

### Example 1: User in a Project Directory

**User**: "Add my OpenAI key"

**You**:
1. Run: `status` (to see current project)
2. Say: "I'll add your OpenAI key to [project-name]"
3. Ask: "What's your OpenAI API key? Which environment? (local/dev/prod)"
4. Run: `add --service openai --key sk-xxx --env local`
5. Say: "✅ Added OpenAI key to [project] and updated .env!"

### Example 2: Reusing Keys

**User**: "Use my Stripe key in this project"

**You**:
1. Run: `use stripe`
2. Say: "✅ Linked your Stripe key to [project] and updated .env!"

### Example 3: Importing

**User**: "Import my .env file"

**You**:
1. Run: `import`
2. Summarize: "📥 Imported 5 keys: OpenAI, Database, Redis, Stripe, Sendgrid"
3. Suggest: "Run `status` to see them all"

## Safety Rules

1. **Never expose keys** unless user explicitly requests `--show-key`
2. **Confirm destructive actions** (delete) before running
3. **Always mention project context** in responses
4. **Suggest .gitignore** when creating .env files
5. **Use JSON format** when parsing results (`--format json`)

## Error Handling

If a command fails:
1. Show the error message
2. Suggest a fix based on context
3. Ask if they want to retry

Example:
"❌ Key 'openai' not found in this project. Would you like to add it or use an existing global key?"
