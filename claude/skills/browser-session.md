---
name: browser-session
description: Set up agent-browser with correct Chrome profile and session management. Use BEFORE any browser automation task — ensures login state is correct and stale daemons are cleaned up.
---

# Browser Session Setup

Run this before any `agent-browser` interaction to ensure correct login state.

## Setup Commands

Always run via Bash with `dangerouslyDisableSandbox: true`:

```bash
# 1. Kill any stale daemon (wrong profile inherits wrong logins)
agent-browser close 2>/dev/null
sleep 1

# 2. Start fresh with Chrome Default profile (has all logins)
agent-browser --profile Default open <TARGET_URL>

# 3. Wait for page to load
agent-browser wait 5000
```

## Why This Matters

- `--profile Default` only applies when the daemon STARTS — not to an already-running daemon
- If another agent started agent-browser without `--profile`, all subsequent agents inherit that anonymous session
- Always `close` first to guarantee a clean slate

## Platform-Specific Patterns

### Telegram Web
- URL: `https://web.telegram.org/a/`
- Chat items: `click 'a[href="#<user_id>"]'` after `scrollintoview`
- Hash navigation doesn't work (SPA strips it)
- Messages triplicated in DOM — dedup

### WhatsApp Web
- URL: `https://web.whatsapp.com/`
- Slow to load (syncs messages). Wait with `wait --text "Chats" --timeout 15000`
- Chat list items need CSS selector clicks

### Instagram DMs
- URL: `https://www.instagram.com/direct/inbox/`
- Standard web app, `snapshot -i` works well
- If login page appears after `--profile Default`, try `open https://www.instagram.com/` first

## Subagent Prompt Template

When spawning browser automation agents, include this in the prompt:

```
Use Bash with dangerouslyDisableSandbox: true for ALL agent-browser commands.
FIRST run: agent-browser close 2>/dev/null; sleep 1; agent-browser --profile Default open <url>
Then: agent-browser wait 5000
Then: agent-browser snapshot -i
```
