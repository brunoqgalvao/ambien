---
name: ensemble-consensus
description: Run prompts through multiple LLMs and synthesize the best answer. Use when you need high confidence, second opinions, or consensus on important decisions like architecture, security review, or complex code.
tools: Read, Write, Bash
experimental: true
---

> **EXPERIMENTAL**: This skill is experimental and may change or be removed.

# Ensemble Consensus - Multi-Model Voting

Run the same prompt through multiple LLMs and get a synthesized, high-confidence answer. Perfect for critical decisions where you want multiple perspectives.

## Quick Usage

```bash
# Basic consensus (3 models)
bun ~/.claude/skills/ensemble-consensus/index.ts "What's the best approach for implementing auth?"

# With specific models
bun ~/.claude/skills/ensemble-consensus/index.ts "Review this code" --models "gpt4o,sonnet,gemini"

# Code review mode
bun ~/.claude/skills/ensemble-consensus/index.ts --code-review "$(cat src/auth.ts)"

# Security audit mode
bun ~/.claude/skills/ensemble-consensus/index.ts --security "$(cat package.json)"

# Architecture decision
bun ~/.claude/skills/ensemble-consensus/index.ts --architecture "Should we use REST or GraphQL for this API?"
```

## How It Works

1. **Parallel Dispatch**: Sends your prompt to multiple LLMs simultaneously
2. **Response Collection**: Gathers all responses with timing metrics
3. **Consensus Analysis**: A judge model analyzes agreement/disagreement
4. **Synthesis**: Produces a final answer combining the best insights

## Modes

| Mode | Models Used | Best For |
|------|-------------|----------|
| `default` | gpt4o, sonnet, gemini | General questions |
| `--code-review` | gpt4o, sonnet, o1 | Code quality review |
| `--security` | gpt4o, o1, sonnet | Security audits |
| `--architecture` | o1, opus, gemini-pro | Design decisions |
| `--quick` | haiku, gpt4-mini, gemini-flash | Fast consensus (cheap) |

## Options

| Flag | Description |
|------|-------------|
| `--models "m1,m2,m3"` | Custom model list |
| `--threshold 0.7` | Consensus threshold (0-1) |
| `--judge sonnet` | Model to judge consensus |
| `--json` | Output as JSON |
| `--verbose` | Show individual responses |
| `--timeout 30000` | Per-model timeout (ms) |

## Output Format

```
═══════════════════════════════════════════════════════════════════
                    ENSEMBLE CONSENSUS RESULT
═══════════════════════════════════════════════════════════════════

CONSENSUS: HIGH (87%)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

SYNTHESIZED ANSWER:
[The best combined answer from all models...]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

AGREEMENTS:
✓ All models agree authentication should use JWT
✓ All models recommend bcrypt for password hashing
✓ 2/3 models suggest rate limiting

DISAGREEMENTS:
⚡ Token expiry: GPT-4 says 15min, Sonnet says 1hr, Gemini says 30min
  → Recommendation: Use 15-30 min with refresh tokens

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

MODEL RESPONSES (3/3 succeeded):
┌─────────┬──────────┬────────────────────────────────────────┐
│ Model   │ Time     │ Key Points                             │
├─────────┼──────────┼────────────────────────────────────────┤
│ gpt4o   │ 2.3s     │ JWT, bcrypt, 15min expiry              │
│ sonnet  │ 1.8s     │ JWT, bcrypt, refresh tokens            │
│ gemini  │ 1.5s     │ JWT, argon2, 30min expiry              │
└─────────┴──────────┴────────────────────────────────────────┘
```

## Use Cases

### 1. Code Review with Consensus

```bash
# Get multiple expert opinions on your code
bun ~/.claude/skills/ensemble-consensus/index.ts --code-review "$(cat src/critical-function.ts)"
```

### 2. Security Audit

```bash
# Multi-model security review
bun ~/.claude/skills/ensemble-consensus/index.ts --security "$(cat src/api/handlers.ts)"
```

### 3. Architecture Decision

```bash
# Get consensus on design decisions
bun ~/.claude/skills/ensemble-consensus/index.ts --architecture \
  "We need to choose between: 1) Microservices with Kubernetes, 2) Monolith with good modularity, 3) Serverless functions. Context: Team of 3, MVP stage, expecting 10k users initially."
```

### 4. Quick Sanity Check

```bash
# Fast, cheap consensus for simple questions
bun ~/.claude/skills/ensemble-consensus/index.ts --quick "Is this SQL query safe: SELECT * FROM users WHERE id = '$userId'"
```

### 5. Custom Model Selection

```bash
# Use specific models you trust
bun ~/.claude/skills/ensemble-consensus/index.ts \
  --models "o1,opus,gpt4o" \
  "Design a caching strategy for a real-time dashboard"
```

## Programmatic Usage

```typescript
import { getConsensus } from "~/.claude/skills/ensemble-consensus";

const result = await getConsensus({
  prompt: "Review this authentication implementation",
  context: await fs.readFile("src/auth.ts", "utf-8"),
  models: ["gpt4o", "sonnet", "o1"],
  mode: "code-review",
  threshold: 0.7,
});

console.log(result.consensus); // "high" | "medium" | "low" | "none"
console.log(result.score); // 0.87
console.log(result.synthesizedAnswer);
console.log(result.agreements);
console.log(result.disagreements);
```

## Consensus Levels

| Level | Score | Meaning |
|-------|-------|---------|
| `HIGH` | ≥0.8 | Strong agreement, high confidence |
| `MEDIUM` | 0.6-0.8 | General agreement with minor differences |
| `LOW` | 0.4-0.6 | Mixed opinions, review carefully |
| `NONE` | <0.4 | Models disagree significantly |

## Tips

1. **For critical decisions**, use `--architecture` mode with `o1` for best reasoning
2. **For code review**, the `--verbose` flag shows each model's unique insights
3. **Low consensus** often reveals edge cases you should consider
4. **Disagreements section** highlights where you need to make a judgment call
5. **Use `--quick` mode** for sanity checks to save cost/time
