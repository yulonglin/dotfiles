# Browser Automation Tool Selection

```
Browser automation needed?
├─ User's live browser (existing tabs, "look at my screen")?
│   └─ claude-in-chrome (main context only, not subagents)
│
├─ Local dev server / testing your own app?
│   └─ Playwright MCP (mcp__plugin_playwright_playwright__*)
│
├─ Authenticated website (subagent needs login state)?
│   └─ agent-browser --profile Default
│
├─ Public website (just reading)?
│   └─ WebFetch / any2md (no browser needed)
│
└─ DON'T USE:
    ├─ claude-in-chrome in subagents — unreliable for SPAs, tool loading issues
    └─ chrome-devtools — superseded by Playwright
```

## claude-in-chrome (User's Live Browser)

Best for interacting with the user's **actual Chrome browser** — existing tabs, logged-in sessions, extensions. The only tool that can see what the user sees.

- Use in **main context only**, never in subagents
- Must load tools via `ToolSearch` before calling (`select:mcp__claude-in-chrome__<tool>`)
- Call `tabs_context_mcp` first to see existing tabs

## Playwright MCP (Dev Server Testing)

Proper automation framework in a separate browser instance. Reliable snapshots, screenshots, form filling.

- Best for testing local apps, taking screenshots of your own work
- No access to user's Chrome auth/tabs — separate browser
- Tools: `browser_navigate`, `browser_snapshot`, `browser_take_screenshot`, `browser_click`, `browser_fill_form`

## agent-browser (Authenticated Sites in Subagents)

Reuses Chrome profile login state. For subagents that need to interact with authenticated websites (Telegram Web, WhatsApp Web, etc.).

### Critical: Session Management

`--profile` only applies when the daemon STARTS. A stale daemon from a previous agent inherits the wrong session. **Always close first:**

```bash
agent-browser close 2>/dev/null; sleep 1; agent-browser --profile Default open <url>
```

### Subagent Prompt Template

Always include in browser automation agent prompts:
```
Use Bash with dangerouslyDisableSandbox: true for ALL agent-browser commands.
FIRST: agent-browser close 2>/dev/null; sleep 1; agent-browser --profile Default open <url>
THEN: agent-browser wait 5000
THEN: agent-browser snapshot -i
```

## Reference

- Skill: `~/.claude/skills/browser-session.md` (full platform-specific patterns)
- Docs: `~/.claude/docs/browser-automation.md` (tool comparison)
