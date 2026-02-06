#!/bin/bash
set -euo pipefail

# ==============================================================================
# SYNC CLAUDE CODE TO CODEX CLI
# Purpose: Sync skills and permissions from Claude Code to Codex CLI.
#   1. Skills: user, plugin, standalone, and agent skills → ~/.codex/skills/
#   2. Permissions: Claude Code allow/deny → Codex rules
# Source:  claude/ (skills, agents, settings.json)
# Target:  codex/ (skills/, rules/)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$SCRIPT_DIR/helpers/enumerate_claude_skills.sh"
SOURCE_DIR="$HOME/.claude"
TARGET_SKILLS="$HOME/.codex/skills"

# ---------- Skills Sync ----------

if [ ! -f "$HELPER" ]; then
    echo "Error: enumerate_claude_skills.sh not found at $HELPER" >&2
    exit 1
fi
source "$HELPER"

mkdir -p "$TARGET_SKILLS"

# Clean stale symlinks (broken or from old *__* pattern)
find "$TARGET_SKILLS" -maxdepth 1 -type l ! -exec test -e {} \; -delete 2>/dev/null || true
find "$TARGET_SKILLS" -maxdepth 1 -type l -name '*__*' -delete 2>/dev/null || true

echo ">>> Syncing Claude Code Skills to Codex CLI..."

enumerate_claude_skills "$SOURCE_DIR" | while IFS=$'\t' read -r type name path; do
    case "$type" in
        user_skill)
            ln -sfn "$path" "$TARGET_SKILLS/$name"
            echo "  User Skill: $name"
            ;;
        standalone_skill)
            mkdir -p "$TARGET_SKILLS/$name"
            ln -sfn "$path" "$TARGET_SKILLS/$name/SKILL.md"
            echo "  Standalone Skill: $name"
            ;;
        plugin_skill)
            # Plugin skill directory — symlink directly
            ln -sfn "$path" "$TARGET_SKILLS/$name"
            echo "  Plugin Skill: $name"
            ;;
        agent_skill)
            mkdir -p "$TARGET_SKILLS/$name"
            ln -sfn "$path" "$TARGET_SKILLS/$name/SKILL.md"
            echo "  Agent Skill: $name"
            ;;
    esac
done

TOTAL=$(find -L "$TARGET_SKILLS" -maxdepth 1 -mindepth 1 | wc -l | tr -d ' ')
echo "  Synced $TOTAL skills to $TARGET_SKILLS"

# ---------- Permissions Sync ----------

echo ">>> Syncing Claude Code Permissions to Codex CLI Rules..."

CLAUDE_SETTINGS="$DOTFILES_DIR/claude/settings.json"
CONVERT_SCRIPT="$DOTFILES_DIR/scripts/helpers/convert_claude_perms.py"
CODEX_RULES_DIR="$DOTFILES_DIR/codex/rules"
OUTPUT_RULES="$CODEX_RULES_DIR/claude_sync.generated.rules"
DEFAULT_RULES="$CODEX_RULES_DIR/default.rules"
BEGIN_MARKER="# BEGIN CLAUDE SYNC (auto-generated)"
END_MARKER="# END CLAUDE SYNC"

if [[ ! -f "$CLAUDE_SETTINGS" ]]; then
    echo "  Skipping: Claude settings not found at $CLAUDE_SETTINGS"
elif [[ ! -f "$CONVERT_SCRIPT" ]]; then
    echo "  Skipping: Conversion script not found at $CONVERT_SCRIPT"
elif ! command -v python3 >/dev/null 2>&1; then
    echo "  Skipping: python3 not installed"
else
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
    rm -f "$OUTPUT_RULES"

    echo "  Updated $DEFAULT_RULES"
fi

echo ">>> Done! Codex CLI is now synchronized with Claude Code configurations."
