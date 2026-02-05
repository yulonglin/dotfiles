# Debug: Serena Dashboard Auto-Opening on Session Start

## Problem Statement

Serena website (`http://127.0.0.1:24286/dashboard/index.html`) opens automatically every time a new Claude Code session starts.

## Root Cause Analysis

**Confirmed root cause**: `~/.serena/serena_config.yml` has `web_dashboard_open_on_launch: true`

The MCP args approach (`--open-web-dashboard false`) was already applied but **did not work** - the config file setting takes precedence or the flag isn't being parsed correctly.

## Solution: Edit Serena Config File Directly

**File**: `~/.serena/serena_config.yml`

**Change**:
```yaml
# From:
web_dashboard_open_on_launch: true

# To:
web_dashboard_open_on_launch: false
```

**Sources**:
- [GitHub Discussion #271](https://github.com/oraios/serena/discussions/271) - How to disable logs opening
- [Serena Dashboard Documentation](https://oraios.github.io/serena/02-usage/060_dashboard.html)
- [GitHub Issue #613](https://github.com/oraios/serena/issues/613) - Don't open dashboard by default

## Implementation Steps

1. Edit `~/.serena/serena_config.yml`: Change `web_dashboard_open_on_launch: true` → `false`
2. Restart Claude Code session
3. Verify browser doesn't auto-open
4. Verify dashboard still accessible manually at `http://127.0.0.1:24286/dashboard/index.html`

## Verification

After fix:
- New Claude Code session should NOT open browser
- Dashboard still accessible manually when needed
- Serena MCP tools still functional
