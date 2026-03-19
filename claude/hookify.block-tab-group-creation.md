---
name: block-tab-group-creation
enabled: true
event: all
pattern: createIfEmpty
action: block
---

**Tab group creation blocked.**

Do NOT create Chrome tab groups via `tabs_context_mcp` with `createIfEmpty: true`. Chrome auto-saves tab groups to the bookmarks bar, creating persistent clutter that must be manually deleted.

**Instead:**
- Only use browser tools when the user explicitly asks for browser automation
- Call `tabs_context_mcp` WITHOUT `createIfEmpty` to check for existing groups first
- If no MCP group exists and browser automation isn't explicitly requested, find an alternative approach
