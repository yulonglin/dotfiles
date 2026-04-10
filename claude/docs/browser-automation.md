# Browser Automation Tools

Comparison of available browser automation tools.

## Tool Landscape

| Tool | Type | Protocol | Auth Strategy | How Loaded | Status |
|------|------|----------|---------------|------------|--------|
| **claude-in-chrome** | MCP (Chrome ext) | Chrome extension | Already logged in (your tabs) | Dynamic — extension connects | Active |
| **chrome-devtools** | MCP (Chrome ext) | CDP | Connects to page via CDP | Dynamic — extension connects | Active |
| **agent-browser** | CLI | CDP (Playwright) | `--profile Default` reuses Chrome login | `brew`/`npm -g` (always available) | Installed |
| **dev-browser** | Plugin | Playwright (sandboxed) | `--auto-connect` to Chrome | Plugin (`automation` profile) | Installed |
| **playwright** | Plugin (MCP) | CDP + custom | `storageState` save/load | Plugin (`automation` profile) | Installed |

## Context Profiles

| Profile | Includes | Use Case |
|---------|----------|----------|
| `frontend` | typescript-lsp | Frontend dev (no browser tools) |
| `automation` | dev-browser, playwright | Browser automation tasks |
| `design` | figma, frontend-design, ui-ux-pro-max, etc. | Visual design |

MCP tools (claude-in-chrome, chrome-devtools) are always available when their Chrome extensions are running — not controlled by profiles.
agent-browser is a CLI — always available, not a plugin.

Skills: `agent-browser`, `chrome-devtools`, `claude-in-chrome` (in `~/.claude/skills/`).

## When to Use What

```
Need browser automation?
├─ Quick interaction with open tabs?
│   └─ claude-in-chrome (MCP) — no setup, uses your browser
│      Pros: instant, already logged in
│      Cons: clicking unreliable on SPAs, screenshots consume context
│
├─ Authenticated sites (Telegram, WhatsApp, etc.)?
│   └─ agent-browser --profile Default — reuses Chrome login state
│      Pros: snapshot/@ref pattern great for AI, CSS selectors, batch commands
│      Cons: needs dangerouslyDisableSandbox, SPA navigation quirks
│
├─ Scripted Playwright API (locators, network interception)?
│   └─ dev-browser — sandboxed Playwright scripts (automation profile)
│      Pros: full Playwright API, auto-connect to Chrome
│
├─ E2E testing or complex multi-step flows?
│   └─ Playwright directly — bunx playwright test (automation profile)
│
└─ DevTools-level inspection (performance, network, memory)?
    └─ chrome-devtools MCP — evaluate_script, take_snapshot, lighthouse
```

## agent-browser Tips (From Testing)

### Telegram Web Specifically
- **Clicking chat items**: `click 'a[href="#<user_id>"]'` works after `scrollintoview`. Clicking `@ref` buttons doesn't open chats.
- **Navigation**: `open https://web.telegram.org/a/#<user_id>` doesn't work (hash gets stripped). Use CSS selector clicks instead.
- **Extracting messages**: `eval` with `document.querySelectorAll('[class*="message"]')` — note Telegram triplicates DOM elements, need dedup.
- **Auth**: `--profile Default` picks up Chrome login state.

### General Patterns
- Always `snapshot -i` first to get `@ref` IDs
- For SPAs: CSS selector clicks (`click 'selector'`) more reliable than `@ref` clicks
- `scrollintoview 'selector'` before clicking off-screen elements
- `eval --stdin <<'EVALEOF' ... EVALEOF` for complex JS (avoids quoting issues)
- `batch "cmd1" "cmd2"` for sequential commands
- Needs `dangerouslyDisableSandbox: true` (writes to `~/.agent-browser`)

## Setup Notes

### agent-browser Auth with Chrome
```bash
# Option 1: Reuse Chrome profile (simplest)
agent-browser --profile Default open https://web.telegram.org
# ⚠️ --profile only applies if daemon not running. Use 'agent-browser close' first.

# Option 2: Named session (auto-persists)
agent-browser --session-name ambassador open https://web.telegram.org

# Option 3: State file
agent-browser --auto-connect state save ./auth.json
agent-browser --state ./auth.json open https://web.telegram.org
```

### Sandbox Issues
`agent-browser` writes to `~/.agent-browser` which Claude Code sandbox blocks.
All `agent-browser` Bash calls need `dangerouslyDisableSandbox: true`.
Consider adding `~/.agent-browser` to sandbox allowlist.
