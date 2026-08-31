#!/usr/bin/env bash
# shellcheck shell=bash
# SessionStart hook: refresh the read-only-ish mirror of the Claude config
# markdown in the Obsidian vault (~/vault/tooling/claude-config/), so rules and
# skills are readable from a phone. Outbound only — the vault -> repo direction
# is never automatic and only ever runs from an explicit `claude-config-sync pull`.
#
# Synchronous by design: it copies a few dozen small markdown files and finishes
# in well under a second. Backgrounding it from a hook would risk the
# process-group death documented in rules/delegation.md and buy
# nothing.
#
# Always exits 0. A refusal (vault missing, or a vault that has never completed
# a sync) and a conflict report are both normal outcomes here, not session
# failures — run `claude-config-sync status` to see them.
set -u

HOOK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 0
python3 "$HOOK_DIR/hook_feature.py" enabled sync.claude-config >/dev/null 2>&1 || exit 0

STAMP="$HOME/.cache/claude-config-sync.stamp"
mkdir -p "$(dirname "$STAMP")"

# Debounce: many sessions and subagents start per hour; once every 10 minutes is
# plenty for config markdown (portable across GNU/BSD find).
if [ -f "$STAMP" ] && [ -n "$(find "$STAMP" -mmin -10 2>/dev/null)" ]; then
  exit 0
fi
touch "$STAMP"

# Resolve the tool: PATH first, else relative to this hook's real location
# (claude/hooks/ and custom_bins/ are siblings in the dotfiles repo; pwd -P above
# resolved the ~/.claude -> dotfiles symlink).
if command -v claude-config-sync >/dev/null 2>&1; then
  SYNC="claude-config-sync"
else
  SYNC="$HOOK_DIR/../../custom_bins/claude-config-sync"
  [ -x "$SYNC" ] || exit 0
fi

"$SYNC" push >/dev/null 2>&1 || true
exit 0
