# Fix Missing Claude Code Plugins

## Problem
Three official Claude Code plugins are enabled but their directories are missing:
- `claude-md-management@claude-plugins-official`
- `claude-code-setup@claude-plugins-official`
- `playground@claude-plugins-official`

## Root Cause
These plugins may be in the demo `anthropics/claude-code` marketplace, not the official marketplace.

## Solution
Add the `anthropics/claude-code` marketplace to make these plugins available:
```bash
/plugin marketplace add anthropics/claude-code
```

## Verification
After adding the marketplace:
1. Run `claude doctor` to verify no plugin errors
2. Check `/plugin` to see if the missing plugins are now available
3. If they're in the demo marketplace, they should auto-install or can be manually installed
