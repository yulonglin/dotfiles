#!/usr/bin/env bash
# shellcheck shell=bash
# SessionStart hook: reap background-session job dirs (~/.claude/jobs) older
# than 7 days, at most once per day. Claude Code has no built-in retention for
# these (cleanupPeriodDays covers ~/.claude/projects transcripts only), so
# without this they accumulate indefinitely. Transcripts are untouched.
# Also purges ~/.claude/jobs-archive, where the claude() wrapper parks finished
# jobs to hide them from `claude agents`, at 30 days — a recoverable holding
# pen, not a second indefinite pile.
set -u

STAMP="$HOME/.cache/claude-jobs-reap.stamp"
mkdir -p "$(dirname "$STAMP")"

# Debounce: skip if we ran within the last 24h (portable across GNU/BSD).
if [ -f "$STAMP" ] && [ -n "$(find "$STAMP" -mmin -1440 2>/dev/null)" ]; then
  exit 0
fi
touch "$STAMP"

# Resolve the reaper: PATH first, else relative to this hook's real location
# (claude/hooks/ and custom_bins/ are siblings in the dotfiles repo).
if command -v claude-jobs-reap >/dev/null 2>&1; then
  REAPER="claude-jobs-reap"
else
  # pwd -P resolves the ~/.claude -> dotfiles symlink; macOS readlink has no -f
  hook_dir="$(cd "$(dirname "$0")" 2>/dev/null && pwd -P)" || exit 0
  REAPER="$hook_dir/../../custom_bins/claude-jobs-reap"
  [ -x "$REAPER" ] || exit 0
fi

"$REAPER" --days 7 >/dev/null 2>&1 || true
if [ -d "$HOME/.claude/jobs-archive" ]; then
  "$REAPER" --jobs-dir "$HOME/.claude/jobs-archive" --days 30 >/dev/null 2>&1 || true
fi
exit 0
