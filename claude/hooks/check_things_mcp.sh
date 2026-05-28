#!/usr/bin/env bash
# SessionStart hook: warn if things-cloud-mcp is down
# Only fires on Linux, only for projects that have things-mcp enabled.

[[ "$(uname)" == "Linux" ]] || exit 0

# Check if this project has things-mcp enabled in its settings
settings=".claude/settings.json"
[[ -f "$settings" ]] || exit 0
grep -q '"things-mcp@productivity-tools": true' "$settings" 2>/dev/null || exit 0

# Project uses Things — check if the server is running
if ! systemctl --user is-active things-cloud-mcp >/dev/null 2>&1; then
    echo "WARNING: things-cloud-mcp is not running. Things 3 tools will be unavailable."
    echo "  Fix: things start"
fi
