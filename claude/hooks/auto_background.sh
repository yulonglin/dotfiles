#!/bin/bash
# Claude Code PreToolUse hook: Auto-background long-running bash commands
# Detects package installs, builds, test suites, dev servers, etc. and sets
# run_in_background: true via updatedInput to avoid blocking the conversation.
#
# Tier 1 (force): High-confidence long-running patterns → updatedInput
# Tier 2 (suggest): Medium-confidence patterns → additionalContext only
#
# Config env vars:
#   CLAUDE_AUTOBACKGROUND=0        — disable entirely
#   CLAUDE_AUTOBACKGROUND_MODE=suggest — suggest-only (no updatedInput)
#   CLAUDE_AUTOBACKGROUND_EXTRA    — additional ERE patterns for Tier 1
#   CLAUDE_AUTOBACKGROUND_DEBUG=1  — log decisions to stderr
#
# Exit codes:
#   0 - Allow (with optional JSON output on stdout)

set -euo pipefail

# --- Early exits ---

# Disabled?
[[ "${CLAUDE_AUTOBACKGROUND:-1}" == "0" ]] && exit 0

# jq required for JSON parsing/output
if ! command -v jq &>/dev/null; then
  echo "auto_background: jq not found, skipping" >&2
  exit 0
fi

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

# Empty command
[[ -z "$COMMAND" ]] && exit 0

# Already backgrounded
if echo "$INPUT" | jq -e '.tool_input.run_in_background == true' &>/dev/null; then
  [[ "${CLAUDE_AUTOBACKGROUND_DEBUG:-0}" == "1" ]] && echo "auto_background: already backgrounded, skip" >&2
  exit 0
fi

# Explicit short timeout (≤30s = 30000ms) — caller expects fast execution
TIMEOUT=$(echo "$INPUT" | jq -r '.tool_input.timeout // 0')
if [[ "$TIMEOUT" -gt 0 && "$TIMEOUT" -le 30000 ]] 2>/dev/null; then
  [[ "${CLAUDE_AUTOBACKGROUND_DEBUG:-0}" == "1" ]] && echo "auto_background: short timeout ($TIMEOUT ms), skip" >&2
  exit 0
fi

# --- Exclusion check (bash case — zero subprocess cost) ---
case "$COMMAND" in
  *--version*|*--help*|*--dry-run*|*" -h"*|*" -V"*)
    [[ "${CLAUDE_AUTOBACKGROUND_DEBUG:-0}" == "1" ]] && echo "auto_background: excluded (flag)" >&2
    exit 0 ;;
  *"pip list"*|*"pip show"*|*"pip freeze"*)
    exit 0 ;;
  *"npm list"*|*"npm ls"*|*"npm --version"*)
    exit 0 ;;
  *"brew list"*|*"brew info"*)
    exit 0 ;;
  *"docker ps"*|*"docker images"*|*"docker inspect"*)
    exit 0 ;;
  *"git status"*|*"git log"*|*"git diff"*|*"git branch"*|*"git show"*)
    exit 0 ;;
  *"make -n"*|*"make clean"*|*"make help"*|*"make format"*|*"make lint"*|*"make check"*)
    exit 0 ;;
  *"npm run lint"*|*"npm run format"*|*"pnpm run lint"*|*"pnpm run format"*)
    exit 0 ;;
  *"yarn lint"*|*"yarn format"*|*"bun run lint"*|*"bun run format"*)
    exit 0 ;;
esac

# --- Tier 1: Force-background (single combined regex) ---

TIER1_RE='\bsleep\s+[0-9]'
TIER1_RE="$TIER1_RE"'|\b(npm|yarn|pnpm|bun)\s+(install|ci|add)\b'
TIER1_RE="$TIER1_RE"'|\b(pip|pip3)\s+install\b'
TIER1_RE="$TIER1_RE"'|\buv\s+(sync|pip\s+install|add)\b'
TIER1_RE="$TIER1_RE"'|\bbrew\s+(install|upgrade|update)\b'
TIER1_RE="$TIER1_RE"'|\b(apt|apt-get)\s+(install|update|upgrade|dist-upgrade)\b'
TIER1_RE="$TIER1_RE"'|\bconda\s+(install|update|create)\b'
TIER1_RE="$TIER1_RE"'|\b(npm|yarn|pnpm|bun)\s+run\s+(build|dev|start|serve|watch)\b'
TIER1_RE="$TIER1_RE"'|\b(npm|yarn|pnpm|bun)\s+(test|start)\b'
TIER1_RE="$TIER1_RE"'|\b(npm|yarn|pnpm|bun)\s+run\s+test\b'
TIER1_RE="$TIER1_RE"'|\bcargo\s+(build|test)\b'
TIER1_RE="$TIER1_RE"'|\bdocker\s+build\b'
TIER1_RE="$TIER1_RE"'|\bdocker\s+compose\s+(up|build)\b'
TIER1_RE="$TIER1_RE"'|\bgo\s+test\s+\./\.\.\.'
TIER1_RE="$TIER1_RE"'|\b(python|python3).*\b(manage\.py\s+runserver|http\.server|flask\s+run|uvicorn|gunicorn)\b'
TIER1_RE="$TIER1_RE"'|\bnext\s+(dev|start)\b'
TIER1_RE="$TIER1_RE"'|\bvite(\s|$)'
TIER1_RE="$TIER1_RE"'|\bgit\s+clone\b'
TIER1_RE="$TIER1_RE"'|\b(python3?|uv\s+run)\s+.*\b(train|finetune|eval)\b'
TIER1_RE="$TIER1_RE"'|HYDRA_FULL_ERROR'

# Append user-defined extra patterns
if [[ -n "${CLAUDE_AUTOBACKGROUND_EXTRA:-}" ]]; then
  TIER1_RE="$TIER1_RE|${CLAUDE_AUTOBACKGROUND_EXTRA}"
fi

MODE="${CLAUDE_AUTOBACKGROUND_MODE:-force}"

if echo "$COMMAND" | grep -qE "$TIER1_RE"; then
  [[ "${CLAUDE_AUTOBACKGROUND_DEBUG:-0}" == "1" ]] && echo "auto_background: Tier 1 match → $MODE" >&2

  if [[ "$MODE" == "force" ]]; then
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        updatedInput: { run_in_background: true },
        additionalContext: "Auto-backgrounded: long-running command detected. Use TaskOutput to check results. To override: re-run with run_in_background: false."
      }
    }'
  else
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: "NOTE: This command may take >1 minute. Consider using run_in_background: true."
      }
    }'
  fi
  exit 0
fi

# --- Tier 2: Suggest-background (single combined regex) ---

TIER2_RE='\bpytest\b'
TIER2_RE="$TIER2_RE"'|\bdocker\s+(exec|run)\b'
TIER2_RE="$TIER2_RE"'|\b(wget|curl)\b.*\.(tar|zip|gz)\b'
TIER2_RE="$TIER2_RE"'|\b(rsync|scp)\b'
TIER2_RE="$TIER2_RE"'|\bmake\b'
TIER2_RE="$TIER2_RE"'|\btsc(\s|$)'

if echo "$COMMAND" | grep -qE "$TIER2_RE"; then
  [[ "${CLAUDE_AUTOBACKGROUND_DEBUG:-0}" == "1" ]] && echo "auto_background: Tier 2 match → suggest" >&2

  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      additionalContext: "NOTE: This command may take >1 minute. Consider using run_in_background: true."
    }
  }'
  exit 0
fi

[[ "${CLAUDE_AUTOBACKGROUND_DEBUG:-0}" == "1" ]] && echo "auto_background: no match" >&2
exit 0
