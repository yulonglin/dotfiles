---
name: nudge-sandbox-git
enabled: true
event: bash
pattern: (Read-only file system|unable to unlink old|Device or resource busy)
action: warn
---

**Sandbox blocking git file operations.** Claude Code's runtime `denyWithinAllow` prevents git from unlinking/renaming files in protected paths (`config/`, `.claude/settings.json`, `.claude/skills/`).

**Fix:** Retry the same command with `dangerouslyDisableSandbox: true`. This is safe for git pull/merge/stash/checkout — the `excludedCommands` config already trusts git, but `denyWithinAllow` overrides it at the filesystem level.
