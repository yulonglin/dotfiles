#!/bin/bash

# ==============================================================================
# SYNC CLAUDE CODE TO ANTIGRAVITY CLI
# Purpose: Ports Claude Code agents/skills into Antigravity CLI (`agy`) by symlinking.
# Source:  ~/.claude/
# Target:  ~/.gemini/antigravity-cli/skills/   (Antigravity reuses the ~/.gemini dir)
#
# Antigravity CLI is Google's official successor to Gemini CLI (consumer Gemini CLI
# access ended 2026-06-18). Project instructions come from AGENTS.md (already in repo),
# so the old GEMINI.md pointer is no longer generated here.
#
# NOTE (unverified): the skills target path below is per Google's docs; the permission
# /policy sync that the Gemini CLI version did is NOT ported — Antigravity stores
# settings in ~/.gemini/antigravity-cli/settings.json with a different schema. Porting
# convert_claude_perms.py to that schema is a follow-up (test on a machine with `agy`).
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/helpers/enumerate_claude_skills.sh"
SOURCE_DIR="$HOME/.claude"
TARGET_DIR="$HOME/.gemini/antigravity-cli/skills"

if [ ! -f "$HELPER" ]; then
    echo "Error: enumerate_claude_skills.sh not found at $HELPER" >&2
    exit 1
fi
source "$HELPER"

mkdir -p "$TARGET_DIR"

# Clean stale symlinks (broken or from old *__* pattern)
find "$TARGET_DIR" -maxdepth 1 -type l ! -exec test -e {} \; -delete 2>/dev/null || true
find "$TARGET_DIR" -maxdepth 1 -type l -name '*__*' -delete 2>/dev/null || true

echo ">>> Syncing Claude Code Skills to Antigravity CLI..."

enumerate_claude_skills "$SOURCE_DIR" | while IFS=$'\t' read -r type name path; do
    case "$type" in
        user_skill)
            ln -sfn "$path" "$TARGET_DIR/$name"
            echo "  User Skill: $name"
            ;;
        standalone_skill)
            mkdir -p "$TARGET_DIR/$name"
            ln -sfn "$path" "$TARGET_DIR/$name/SKILL.md"
            echo "  Standalone Skill: $name"
            ;;
        plugin_skill)
            ln -sfn "$path" "$TARGET_DIR/$name"
            echo "  Plugin Skill: $name"
            ;;
        agent_skill)
            mkdir -p "$TARGET_DIR/$name"
            ln -sfn "$path" "$TARGET_DIR/$name/SKILL.md"
            echo "  Agent Skill: $name"
            ;;
    esac
done

TOTAL=$(find "$TARGET_DIR" -maxdepth 1 -mindepth 1 | wc -l | tr -d ' ')
echo "  Synced $TOTAL skills to $TARGET_DIR"
echo ">>> Done. Antigravity CLI skills synchronized with Claude Code."
echo "    (Project instructions: AGENTS.md. Permission sync not yet ported — see header.)"
