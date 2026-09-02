#!/usr/bin/env bash
# SessionStart hook: repair known plugin-hook issues and executable bits.
# Marketplace updates (GCS tarballs) can lose execute bits.
PATCHER="$HOME/.claude/hooks/patch_ralph_loop_stop_hook.py"
if [ -f "$PATCHER" ]; then
    # Ralph Loop 1.0.0 prints prose from two successful Stop branches. Claude
    # parses nonempty Stop stdout as JSON, so repair the ignored install cache.
    python3 "$PATCHER" >/dev/null 2>&1 || true
fi

MARKETPLACES_DIR="$HOME/.claude/plugins/marketplaces"
[ -d "$MARKETPLACES_DIR" ] || exit 0
find "$MARKETPLACES_DIR" -name '*.sh' ! -perm -111 -exec chmod +x {} +
exit 0
