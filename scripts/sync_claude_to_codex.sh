#!/bin/bash
set -euo pipefail

# ==============================================================================
# SYNC CLAUDE CODE PERMISSIONS TO CODEX CLI RULES
# Purpose: Convert Claude Code allow/deny/ask entries into Codex rules.
# Source:  claude/settings.json
# Target:  codex/rules/claude_sync.rules
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CLAUDE_SETTINGS="$DOTFILES_DIR/claude/settings.json"
CONVERT_SCRIPT="$DOTFILES_DIR/scripts/helpers/convert_claude_perms.py"
CODEX_RULES_DIR="$DOTFILES_DIR/codex/rules"
OUTPUT_RULES="$CODEX_RULES_DIR/claude_sync.rules"

if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
  echo "Claude settings not found: $CLAUDE_SETTINGS" >&2
  exit 1
fi

if [[ ! -f "$CONVERT_SCRIPT" ]]; then
  echo "Conversion script not found: $CONVERT_SCRIPT" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required but not installed." >&2
  exit 1
fi

mkdir -p "$CODEX_RULES_DIR"
python3 "$CONVERT_SCRIPT" "$CLAUDE_SETTINGS" --format codex > "$OUTPUT_RULES"

echo "Generated $OUTPUT_RULES"
