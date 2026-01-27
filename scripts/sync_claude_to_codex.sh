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
DEFAULT_RULES="$CODEX_RULES_DIR/default.rules"
BEGIN_MARKER="# BEGIN CLAUDE SYNC (auto-generated)"
END_MARKER="# END CLAUDE SYNC"

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
tmp_rules="$(mktemp)"
python3 "$CONVERT_SCRIPT" "$CLAUDE_SETTINGS" --format codex > "$tmp_rules"
cp "$tmp_rules" "$OUTPUT_RULES"

python3 - "$DEFAULT_RULES" "$tmp_rules" "$BEGIN_MARKER" "$END_MARKER" <<'PY'
import sys
from pathlib import Path

default_path = Path(sys.argv[1])
block_path = Path(sys.argv[2])
begin = sys.argv[3]
end = sys.argv[4]

block = block_path.read_text()
if not block.endswith("\n"):
    block += "\n"

content = default_path.read_text() if default_path.exists() else ""

if begin in content and end in content:
    pre, rest = content.split(begin, 1)
    _, post = rest.split(end, 1)
    new_content = f"{pre}{begin}\n{block}{end}{post}"
else:
    prefix = f"{begin}\n{block}{end}\n"
    new_content = prefix + content.lstrip("\n") if content else prefix

default_path.write_text(new_content)
PY

rm -f "$tmp_rules"

echo "Generated $OUTPUT_RULES"
echo "Updated $DEFAULT_RULES"
