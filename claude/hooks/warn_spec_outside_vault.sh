#!/usr/bin/env bash
# PreToolUse(Write) hook: detect-only warning when a NEW spec is written
# outside the vault. Never blocks — emits a systemMessage and always exits 0.
#
# Fires only when ALL of these hold:
#   1. the target is a .md file with a `specs` path component (pre-resolution),
#   2. the path resolved through symlinks (realpath -m) is NOT under the vault
#      — repo `specs/` symlinks point into per-repo vault homes such as
#      ~/vault/tooling/<repo>/specs, so writes through them stay silent,
#   3. the target does not already exist (edits to existing specs are silent).
#
# Env overrides for tests: VAULT_STRUCTURE_VAULT (same knob as the other
# vault hooks). Fail-open on missing jq/realpath or unparseable input.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
command -v realpath >/dev/null 2>&1 || exit 0
INPUT=$(cat)
file=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0
[ -n "$file" ] || exit 0

case "$file" in
  *.md) ;;
  *) exit 0 ;;
esac
case "$file" in
  specs/*|*/specs/*) ;;
  *) exit 0 ;;
esac

# Relative paths resolve against the session cwd the hook runs in.
resolved=$(realpath -m -- "$file" 2>/dev/null) || exit 0
VAULT="${VAULT_STRUCTURE_VAULT:-$HOME/vault}"
VAULT_REAL=$(realpath -m -- "$VAULT" 2>/dev/null) || VAULT_REAL="$VAULT"
case "$resolved" in
  "$VAULT_REAL"/*) exit 0 ;;
esac

[ -e "$resolved" ] && exit 0

MSG="New spec written outside the vault: $file resolves to $resolved. Specs live in ~/vault (per-repo homes like tooling/<repo>/specs), reached via the repo's specs/ symlink. Detect-only — the write went through."
jq -n --arg msg "$MSG" '{systemMessage: $msg}'
exit 0
