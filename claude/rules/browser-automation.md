# Browser Automation Tool Selection

When subagents need to interact with authenticated websites (Telegram Web, WhatsApp Web, Instagram, etc.):

- **Use `agent-browser --profile Default`** via Bash (with `dangerouslyDisableSandbox: true`)
- **Do NOT use** `mcp__claude-in-chrome__*` or `mcp__chrome-devtools__*` MCP tools — these are unreliable for SPAs and subagents often can't load them properly
- `agent-browser` reuses the Chrome Default profile login state — no re-authentication needed

## Critical: Session Management

`--profile` only applies when the daemon STARTS. A stale daemon from a previous agent inherits the wrong session (no logins). **Always close first:**

```bash
agent-browser close 2>/dev/null; sleep 1; agent-browser --profile Default open <url>
```

## Subagent Prompt Template

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
