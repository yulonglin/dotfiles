#!/usr/bin/env bash
# SessionStart hook: auto-apply context.yaml, warn if no context configured.
# Also triggers background marketplace sync if stale (>6h since last sync).
#
# This hook must keep running on EVERY SessionStart source, compact included.
# Only its *output* is redundant after a compaction - the marketplace sync and
# the stale-symlink cleanup below are side effects, and skipping them means a
# session running past the 6h window never syncs and accumulates the duplicate
# plugin symlinks that clean-skill-dupes exists to remove. So the quieting is
# done here, per-section, rather than by excluding the hook in settings.json.
#
# An unreadable source, or a missing jq, leaves QUIET false and yields exactly
# the previous behaviour - the fallback is the status quo, never a silent skip.
if [ -t 0 ]; then
    hook_input=""
else
    hook_input=$(cat)
fi
session_source=$(printf '%s' "$hook_input" | jq -r '.source // ""' 2>/dev/null || echo "")
QUIET=false
[ "$session_source" = "compact" ] && QUIET=true

CONTEXT_FILE=".claude/context.yaml"
if [ -f "$CONTEXT_FILE" ]; then
    # The applied-profiles banner is a fixed block that cannot change during a
    # compaction, but --apply also rewrites .claude/settings.json, so it runs
    # either way and only the banner is dropped.
    if [ "$QUIET" = true ]; then
        claude-tools context --apply >/dev/null 2>&1
    else
        claude-tools context --apply 2>/dev/null
    fi
elif [ "$QUIET" = false ]; then
    # Warn if inside a git repo without context profiles
    if git rev-parse --is-inside-work-tree &>/dev/null; then
        echo -e "\033[0;33mNo context profiles configured for this project.\033[0m"
        echo -e "Run: claude-tools context <profile>  (e.g., claude-tools context code python)"
        echo -e "List profiles: claude-tools context --list"
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

if $should_sync && command -v claude-tools &>/dev/null; then
    # Run sync in background, then clean plugin symlinks (anthropics/claude-code#14549)
    CLEAN_SCRIPT="${DOT_DIR:-$HOME/code/dotfiles}/scripts/cleanup/clean_plugin_symlinks.sh"
    (claude-tools context --sync &>/dev/null && touch "$SYNC_STAMP"; bash "$CLEAN_SCRIPT" &>/dev/null) &
    disown 2>/dev/null
fi

# Always clean stale plugin symlinks (sync recreates them, but they also appear from other operations)
CLEAN_SCRIPT="${DOT_DIR:-$HOME/code/dotfiles}/scripts/cleanup/clean_plugin_symlinks.sh"
if [ -f "$CLEAN_SCRIPT" ]; then
    bash "$CLEAN_SCRIPT" &>/dev/null &
    disown 2>/dev/null
fi

exit 0  # Don't block session start
