#!/usr/bin/env bash
# SessionStart hook: ensure all .sh files in marketplace plugins are executable.
# Marketplace updates (GCS tarballs) can lose execute bits.
MARKETPLACES_DIR="$HOME/.claude/plugins/marketplaces"
[ -d "$MARKETPLACES_DIR" ] || exit 0
find "$MARKETPLACES_DIR" -name '*.sh' ! -perm -111 -exec chmod +x {} +
exit 0
