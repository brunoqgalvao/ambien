---
name: generate-product-name
description: Generate creative product and company names with domain availability checking. Use when the user asks to name a product, name an app, brainstorm names, find a startup name, suggest brand names, or needs naming ideas.
---

# Generate Product Name Skill

Brainstorm creative, memorable product and company names with domain checking.

## How to Use

When user needs a name:

### 1. Gather Context

Ask about:
- **What it does** (core function/value prop)
- **Target audience** (developers, consumers, enterprise)
- **Vibe/tone** (playful, professional, techy, friendly)
- **Industry** (SaaS, food, fitness, fintech)
- **Any constraints** (length, must include certain sounds, avoid certain words)
- **Naming style preference** (see styles below)

### 2. Generate Names

Use this structured approach:

```
Based on:
- Product: [DESCRIPTION]
- Audience: [TARGET]
- Vibe: [TONE]
- Industry: [SECTOR]

Generate 10-15 names across these categories:

**Descriptive** (says what it does)
**Abstract** (unique made-up words)
**Metaphor** (evokes a feeling/concept)
**Compound** (two words combined)
**Acronym** (if applicable)
```

### 3. Check Domain Availability

For top picks, check domain availability:

```bash
# Quick domain check using whois
whois [name].com | grep -E "(No match|NOT FOUND|available)" || echo "Likely taken"

# Or use web search
# Search: "[name].com domain available"
```

## Naming Styles

### 1. Descriptive Names
Says what it does on the tin.
- Examples: YouTube, Facebook, PayPal, Dropbox
- Pattern: `[Action][Object]` or `[Object][Action]`

### 2. Abstract/Invented
Made-up words that sound good.
- Examples: Spotify, Hulu, Zapier, Figma
- Techniques: blend syllables, use prefixes (ify, ly, io)

### 3. Metaphor Names
Evokes a concept indirectly.
- Examples: Amazon, Apple, Slack, Asana
- Pattern: Find concepts related to your value prop

### 4. Compound Words
Two words smashed together.
- Examples: MailChimp, SurveyMonkey, HubSpot
- Pattern: `[Concept][Animal/Object]` or `[Action][Noun]`

### 5. Misspellings/Alterations
Intentionally modified spellings.
- Examples: Lyft, Tumblr, Fiverr, Reddit
- Technique: Drop vowels, swap letters, phonetic spelling

### 6. Personal Names
Named after people or characters.
- Examples: Ben & Jerry's, Tesla, Alexa
- Use: Adds personality, works for certain brands

### 7. Acronyms
Abbreviations that became words.
- Examples: IKEA, NASA, CAPTCHA
- Caution: Usually organic, hard to force

## Generation Prompt Template

```
I need creative names for:

PRODUCT: [what it does]
AUDIENCE: [who uses it]
VIBE: [tone/feeling]
INDUSTRY: [sector]
CONSTRAINTS: [any requirements]

Generate 15 names with brief rationale:

DESCRIPTIVE (3 names)
- [Name]: [why it works]

ABSTRACT (4 names)
- [Name]: [why it works]

METAPHOR (3 names)
- [Name]: [why it works]

COMPOUND (3 names)
- [Name]: [why it works]

WILDCARD (2 names)
- [Name]: [why it works]

For each, note:
- Pronunciation clarity (1-5)
- Memorability (1-5)
- Domain likelihood (likely available / maybe / probably taken)
```

## Domain Checking Script

After generating names, check availability:

```bash
#!/bin/bash
# Quick domain availability check
names=("name1" "name2" "name3")

for name in "${names[@]}"; do
  echo "Checking $name.com..."
  if whois "$name.com" 2>/dev/null | grep -qiE "(no match|not found|available)"; then
    echo "  ✓ Likely AVAILABLE"
  else
    echo "  ✗ Likely taken"
  fi
  sleep 1  # Be nice to whois servers
done
```

## Example Session

**User:** "I need a name for a CLI tool that helps developers manage their dotfiles"

**Response:**

Great! Let me brainstorm some names for your dotfiles CLI:

**DESCRIPTIVE**
- **DotSync** - Clear, says what it does
- **ConfigFlow** - Emphasizes the workflow aspect
- **DotKeeper** - Friendly, protective vibe

**ABSTRACT**
- **Dotr** - Short, dev-friendly, missing vowel
- **Konfig** - Playful K spelling
- **Dotti** - Cute, memorable

**METAPHOR**
- **Stash** - Like git stash, implies storage
- **Vault** - Secure storage connotation
- **Nest** - Home for your configs

**COMPOUND**
- **DotHerd** - Herding your dotfiles together
- **ConfigCrate** - Container for configs
- **FileForge** - Crafting your setup

**WILDCARD**
- **../** - Literally dots (risky but memorable)
- **Tilde** - ~ is home, dotfiles live there

Let me check domain availability for top picks...

```bash
# Checking dotr.dev, dotsync.dev, stash.dev...
```

## Tips

1. **Say it out loud** - If you can't pronounce it, neither can users
2. **Check for meanings in other languages** - Avoid accidental insults
3. **Search trademark databases** - Before falling in love with a name
4. **Test the "radio test"** - Can someone spell it after hearing it?
5. **Consider adjacent domains** - .io, .dev, .app if .com is taken
6. **Shorter is usually better** - But not at the cost of clarity

## Output Format

Always present names in a structured table:

| Name | Style | Vibe | Domain Likely? |
|------|-------|------|----------------|
| DotSync | Descriptive | Professional | Maybe |
| Dotr | Abstract | Dev-cool | Likely |
| Stash | Metaphor | Casual | Taken |

Then offer to:
1. Generate more variations of favorites
2. Check specific domains
3. Create a logo for the chosen name (use generate-logo skill)
