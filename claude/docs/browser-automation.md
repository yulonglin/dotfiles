# Browser Automation Tools (Tentative — Evolving)

Comparison of available browser automation tools. This is a working document — update as understanding improves.

## Tool Landscape

| Tool | By | Protocol | Auth Strategy | Claude Code Integration | Status |
|------|-----|----------|---------------|------------------------|--------|
| **agent-browser** | Vercel Labs | CDP (Chrome DevTools Protocol) | `--profile Default` reuses Chrome login; `--session-name` for persistence; state save/load | CLI via Bash (needs `dangerouslyDisableSandbox`) | Installed, tested |
| **dev-browser** | Do Browser / sawyerhood | Playwright (via sandboxed WASM) | `--auto-connect` to running Chrome; `--profile` | Plugin in `dev-browser-marketplace`, skill exists | Plugin installed, CLI not installed |
| **claude-in-chrome** | ? | Chrome extension + MCP | Already logged in (your actual browser tabs) | MCP tools (`mcp__claude-in-chrome__*`) | Extension active |
| **Playwright** | Microsoft | CDP + custom protocol | Manual login → `storageState` save/load; `bunx playwright` | Plugin in `claude-plugins-official` (?) | Available via bunx |
| **chrome-devtools** | ? | CDP MCP server | Connects to specific page via CDP | MCP tools (`mcp__chrome-devtools__*`) | Active but limited |

## When to Use What (Tentative)

```
Need browser automation?
├─ Already have tabs open in Chrome? Want quick interaction?
│   └─ claude-in-chrome (MCP) — no setup, uses your browser
│      Pros: instant access, logged in
│      Cons: clicking unreliable on SPAs, screenshots consume context
│
├─ Need to read/write on authenticated sites (Telegram, WhatsApp, etc.)?
│   └─ agent-browser --profile Default — reuses Chrome login state
│      Pros: snapshot/@ref pattern great for AI, CSS selectors work, batch commands
│      Cons: needs dangerouslyDisableSandbox, SPA navigation quirks
│      Pattern: open URL → snapshot -i → click 'css-selector' → eval JS → extract
│
├─ Need scripted Playwright API (locators, network interception, complex flows)?
│   └─ dev-browser — sandboxed Playwright scripts
│      Pros: full Playwright API, auto-connect to Chrome
│      Cons: CLI not installed yet, heavier setup
│
├─ Need E2E testing or complex multi-step flows?
│   └─ Playwright directly — bunx playwright test
│
└─ Need DevTools-style inspection (performance, network, memory)?
    └─ chrome-devtools MCP — evaluate_script, take_snapshot
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
