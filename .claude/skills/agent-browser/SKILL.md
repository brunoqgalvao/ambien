---
name: agent-browser
description: Fast CLI browser automation using Vercel's agent-browser. Use when you need quick browser automation with accessibility tree snapshots, @ref element targeting, semantic locators, or multi-session parallel browsing. Lighter and faster than Playwright for AI-driven workflows.
tools: Bash
---

# Agent-Browser Skill

A blazing-fast Rust CLI for browser automation, optimized for AI agents. Features accessibility tree snapshots with `@ref` element references for precise targeting.

## When to Use This vs Other Browser Skills

| Skill | Best For |
|-------|----------|
| **agent-browser** | Fast CLI commands, @ref targeting, parallel sessions, quick scraping |
| **playwright** | Screenshots, visual inspection, device emulation, complex JS flows |
| **browser-use** | AI-driven natural language browsing (Claude controls the browser) |
| **browser-agent** | User's Chrome with autofill (passwords/cards) |

## Installation

```bash
# Install globally
npm install -g agent-browser

# Install browser (Chromium)
agent-browser install
```

Verify installation:
```bash
agent-browser --version
```

## Quick Reference

| Action | Command |
|--------|---------|
| Open URL | `agent-browser open <url>` |
| Get page snapshot | `agent-browser snapshot` |
| Click by ref | `agent-browser click @e5` |
| Click by text | `agent-browser click "text=Sign up"` |
| Fill input | `agent-browser fill @e3 "value"` |
| Type text | `agent-browser type "hello world"` |
| Screenshot | `agent-browser screenshot /tmp/shot.png` |
| Get PDF | `agent-browser pdf /tmp/page.pdf` |
| Close browser | `agent-browser close` |

---

## Core Workflow: Snapshot → Interact

The key feature is the accessibility tree snapshot with `@ref` references:

```bash
# 1. Open a page
agent-browser open https://example.com/login

# 2. Get the accessibility snapshot
agent-browser snapshot
```

Output looks like:
```
@e1 heading "Sign In"
@e2 textbox "Email" [focused]
@e3 textbox "Password"
@e4 button "Sign In"
@e5 link "Forgot password?"
```

```bash
# 3. Interact using @ref
agent-browser fill @e2 "user@example.com"
agent-browser fill @e3 "mypassword"
agent-browser click @e4
```

---

## Navigation

```bash
# Open URL
agent-browser open https://example.com

# Go back/forward
agent-browser back
agent-browser forward

# Reload
agent-browser reload

# Close browser
agent-browser close
```

---

## Element Interaction

### Click

```bash
# By @ref (from snapshot)
agent-browser click @e5

# By text
agent-browser click "text=Submit"

# By role
agent-browser click "role=button[name=Submit]"

# By CSS selector
agent-browser click "css=#submit-btn"

# By placeholder
agent-browser click "placeholder=Search..."
```

### Fill (clear + type)

```bash
agent-browser fill @e2 "user@example.com"
agent-browser fill "css=#email" "user@example.com"
```

### Type (append)

```bash
agent-browser type "Hello world"
agent-browser type "Enter"  # Special keys
```

### Other Interactions

```bash
# Hover
agent-browser hover @e3

# Select dropdown
agent-browser select @e6 "option-value"

# Check/uncheck
agent-browser check @e7
agent-browser uncheck @e7

# Focus
agent-browser focus @e2

# Press key
agent-browser press Enter
agent-browser press Control+a
```

---

## Semantic Locators

Beyond @ref, you can use semantic locators:

```bash
# By role
agent-browser click "role=button[name=Submit]"
agent-browser click "role=link[name=Home]"
agent-browser click "role=checkbox[name=Remember me]"

# By text (exact)
agent-browser click "text=Sign In"

# By label
agent-browser fill "label=Email address" "user@example.com"

# By placeholder
agent-browser fill "placeholder=Enter your email" "user@example.com"

# By CSS
agent-browser click "css=.submit-button"
agent-browser click "css=#main-nav a.active"
```

---

## Screenshots & PDFs

```bash
# Screenshot (viewport)
agent-browser screenshot /tmp/viewport.png

# Full page screenshot
agent-browser screenshot /tmp/full.png --full-page

# PDF
agent-browser pdf /tmp/page.pdf
```

---

## Multi-Session (Parallel Browsing)

Run multiple browser sessions for parallel tasks:

```bash
# Session 1: Research
agent-browser --session research open https://docs.example.com
agent-browser --session research snapshot

# Session 2: Testing
agent-browser --session testing open http://localhost:3000
agent-browser --session testing screenshot /tmp/test.png

# Each session is isolated
agent-browser --session research close
agent-browser --session testing close
```

---

## Waiting

```bash
# Wait for element
agent-browser wait "css=.loaded"
agent-browser wait @e5

# Wait for navigation
agent-browser wait navigation

# Wait for network idle
agent-browser wait networkidle

# Wait with timeout
agent-browser wait "css=.result" --timeout 10000
```

---

## JavaScript Evaluation

```bash
# Execute JS
agent-browser evaluate "document.title"
agent-browser evaluate "window.scrollTo(0, document.body.scrollHeight)"

# Get element text
agent-browser evaluate "document.querySelector('.price').textContent"
```

---

## Advanced Options

```bash
# Custom viewport
agent-browser open https://example.com --viewport 375x812

# Custom headers
agent-browser open https://api.example.com --headers '{"Authorization": "Bearer token"}'

# Emulate device
agent-browser open https://example.com --device "iPhone 14"

# Geolocation
agent-browser open https://maps.example.com --geolocation "37.7749,-122.4194"

# Offline mode
agent-browser offline true

# JSON output (for parsing)
agent-browser snapshot --json
```

---

## Cookie & Storage

```bash
# Get cookies
agent-browser cookies

# Set cookie
agent-browser set-cookie "name=value; domain=example.com"

# Clear cookies
agent-browser clear-cookies

# Local storage
agent-browser evaluate "localStorage.getItem('key')"
agent-browser evaluate "localStorage.setItem('key', 'value')"
```

---

## Dialog Handling

```bash
# Accept alert/confirm/prompt
agent-browser on-dialog accept

# Dismiss
agent-browser on-dialog dismiss

# Accept with text (for prompts)
agent-browser on-dialog accept "my input"
```

---

## Common Workflows

### Login Flow

```bash
agent-browser open https://example.com/login
agent-browser snapshot  # Find the refs
agent-browser fill @e2 "user@example.com"
agent-browser fill @e3 "password123"
agent-browser click @e4
agent-browser wait navigation
agent-browser screenshot /tmp/logged-in.png
```

### Form Submission

```bash
agent-browser open https://example.com/contact
agent-browser snapshot
agent-browser fill @e2 "John Doe"
agent-browser fill @e3 "john@example.com"
agent-browser fill @e4 "Hello, I have a question..."
agent-browser click @e5  # Submit button
agent-browser wait "css=.success-message"
agent-browser screenshot /tmp/submitted.png
```

### Scraping Data

```bash
agent-browser open https://example.com/products
agent-browser snapshot --json > /tmp/products.json
# Parse the JSON to extract product info
```

### Parallel Research

```bash
# Open multiple docs in parallel sessions
agent-browser --session docs1 open https://docs.python.org
agent-browser --session docs2 open https://docs.rust-lang.org
agent-browser --session docs3 open https://docs.deno.com

# Get snapshots from each
agent-browser --session docs1 snapshot > /tmp/python-docs.txt
agent-browser --session docs2 snapshot > /tmp/rust-docs.txt
agent-browser --session docs3 snapshot > /tmp/deno-docs.txt

# Clean up
agent-browser --session docs1 close
agent-browser --session docs2 close
agent-browser --session docs3 close
```

---

## Tips

1. **Always snapshot first** to get @ref values for the current page state
2. **Use --json** for machine-parseable output
3. **Multi-session** for parallel tasks that don't interfere
4. **Semantic locators** are more stable than CSS selectors
5. **@ref values change** when the page updates - re-snapshot after navigation

## Troubleshooting

### "Browser not found"
```bash
agent-browser install
```

### "Element not found"
```bash
# Re-snapshot to get current refs
agent-browser snapshot
```

### "Timeout waiting for element"
```bash
# Increase timeout
agent-browser wait "css=.slow-element" --timeout 30000
```

### "Session not found"
```bash
# Sessions close automatically - reopen if needed
agent-browser --session mysession open https://example.com
```
