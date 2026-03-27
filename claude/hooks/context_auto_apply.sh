#!/usr/bin/env bash
# SessionStart hook: auto-apply context.yaml, warn if no context configured.
# Also triggers background marketplace sync if stale (>6h since last sync).
CONTEXT_FILE=".claude/context.yaml"
if [ -f "$CONTEXT_FILE" ]; then
    claude-context 2>/dev/null
else
    # Warn if inside a git repo without context profiles
    if git rev-parse --is-inside-work-tree &>/dev/null; then
        echo -e "\033[0;33mNo context profiles configured for this project.\033[0m"
        echo -e "Run: claude-context <profile>  (e.g., claude-context code python)"
        echo -e "List profiles: claude-context --list"
    fi
fi

# Background marketplace sync (throttled: skip if synced within 6 hours)
SYNC_STAMP="$HOME/.claude/plugins/.last_sync"
SYNC_INTERVAL=$((6 * 3600))  # 6 hours in seconds

should_sync=false
if [ ! -f "$SYNC_STAMP" ]; then
    should_sync=true
elif command -v stat &>/dev/null; then
    if [[ "$OSTYPE" == darwin* ]]; then
        last_sync=$(stat -f %m "$SYNC_STAMP" 2>/dev/null || echo 0)
    else
        last_sync=$(stat -c %Y "$SYNC_STAMP" 2>/dev/null || echo 0)
    fi
    now=$(date +%s)
    if (( now - last_sync > SYNC_INTERVAL )); then
        should_sync=true
    fi
fi

if $should_sync && command -v claude-context &>/dev/null; then
    # Run sync in background, then clean plugin symlinks (anthropics/claude-code#14549)
    CLEAN_SCRIPT="${DOT_DIR:-$HOME/code/dotfiles}/scripts/cleanup/clean_plugin_symlinks.sh"
    (claude-context --sync &>/dev/null && touch "$SYNC_STAMP"; bash "$CLEAN_SCRIPT" &>/dev/null) &
    disown 2>/dev/null
fi

# Always clean stale plugin symlinks (sync recreates them, but they also appear from other operations)
CLEAN_SCRIPT="${DOT_DIR:-$HOME/code/dotfiles}/scripts/cleanup/clean_plugin_symlinks.sh"
if [ -f "$CLEAN_SCRIPT" ]; then
    bash "$CLEAN_SCRIPT" &>/dev/null &
    disown 2>/dev/null
fi

exit 0  # Don't block session start
