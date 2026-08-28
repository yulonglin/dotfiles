#!/usr/bin/env bash
# SessionStart hook: clean stale plugin-created skill symlinks in the background.
# Plugin operations recreate them (anthropics/claude-code#14549) and they cause
# duplicate entries in the slash-command picker. This is the sole survivor of the
# retired context_auto_apply.sh — profiles are gone, the cleanup is still needed.
CLEAN_SCRIPT="${DOT_DIR:-$HOME/code/dotfiles}/scripts/cleanup/clean_plugin_symlinks.sh"
if [ -f "$CLEAN_SCRIPT" ]; then
    bash "$CLEAN_SCRIPT" &>/dev/null &
    disown 2>/dev/null
fi
exit 0  # Never block session start
