#!/bin/bash

# ==============================================================================
# SYNC CLAUDE CODE TO GEMINI CLI
# Purpose: Ports Claude Code agents and skills into Gemini CLI by symlinking.
# Source:  ~/code/dotfiles/claude/
# Target:  ~/.gemini/skills/
# ==============================================================================

# --- Check for Stale Script ---
SCRIPT_PATH="${BASH_SOURCE[0]}"
# If running via pipe/eval, SCRIPT_PATH might be empty, use $0 or fallback
if [ -z "$SCRIPT_PATH" ]; then SCRIPT_PATH="$0"; fi

# Resolve absolute path if possible, or just use it if it exists
if [ -f "$SCRIPT_PATH" ]; then
    CURRENT_TIME=$(date +%s)
    # Use stat to get modification time (handle macOS vs Linux)
    if stat -f %m "$SCRIPT_PATH" >/dev/null 2>&1; then
        FILE_TIME=$(stat -f %m "$SCRIPT_PATH") # macOS
    else
        FILE_TIME=$(stat -c %Y "$SCRIPT_PATH") # Linux
    fi

    # 60 days in seconds = 60 * 24 * 3600 = 5184000
    DIFF=$((CURRENT_TIME - FILE_TIME))
    if [ "$DIFF" -gt 5184000 ]; then
        echo "================================================================================"
        echo "WARNING: This script hasn't been updated in over 60 days."
        echo "Please prompt an agent to search for 'Claude Code vs Gemini CLI' to check"
        echo "if migration logic needs updates or if new features are available."
        echo "================================================================================"
    fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HELPER="$SCRIPT_DIR/helpers/enumerate_claude_skills.sh"
SOURCE_DIR="$HOME/.claude"
TARGET_DIR="$HOME/.gemini/skills"

if [ ! -f "$HELPER" ]; then
    echo "Error: enumerate_claude_skills.sh not found at $HELPER" >&2
    exit 1
fi
source "$HELPER"

mkdir -p "$TARGET_DIR"

# Clean stale symlinks (broken or from old *__* pattern)
find "$TARGET_DIR" -maxdepth 1 -type l ! -exec test -e {} \; -delete 2>/dev/null || true
find "$TARGET_DIR" -maxdepth 1 -type l -name '*__*' -delete 2>/dev/null || true

echo ">>> Syncing Claude Code Skills to Gemini CLI..."

enumerate_claude_skills "$SOURCE_DIR" | while IFS=$'\t' read -r type name path; do
    case "$type" in
        user_skill)
            # Directory skill — symlink directly
            ln -sfn "$path" "$TARGET_DIR/$name"
            echo "  User Skill: $name"
            ;;
        standalone_skill)
            # Single .md file — wrap in a directory with SKILL.md symlink
            mkdir -p "$TARGET_DIR/$name"
            ln -sfn "$path" "$TARGET_DIR/$name/SKILL.md"
            echo "  Standalone Skill: $name"
            ;;
        plugin_skill)
            # Plugin skill directory — symlink directly
            ln -sfn "$path" "$TARGET_DIR/$name"
            echo "  Plugin Skill: $name"
            ;;
        agent_skill)
            # Agent .md file — wrap in directory with SKILL.md symlink
            mkdir -p "$TARGET_DIR/$name"
            ln -sfn "$path" "$TARGET_DIR/$name/SKILL.md"
            echo "  Agent Skill: $name"
            ;;
    esac
done

# Count results
TOTAL=$(find "$TARGET_DIR" -maxdepth 1 -mindepth 1 | wc -l | tr -d ' ')
echo "  Synced $TOTAL skills to $TARGET_DIR"

echo ">>> Ensuring GEMINI.md points to CLAUDE.md..."
GEMINI_MD="$DOTFILES_DIR/GEMINI.md"
if [ -f "$DOTFILES_DIR/CLAUDE.md" ]; then
    # Create a pointer file if it doesn't exist or if it's a symlink (we want to replace symlink with text)
    if [ -L "$GEMINI_MD" ] || [ ! -f "$GEMINI_MD" ]; then
        cat > "$GEMINI_MD" <<EOF
# GEMINI.md

This project uses [CLAUDE.md](CLAUDE.md) as the single source of truth for project-specific guidelines, architecture, and workflows.
Please refer to that file for all development patterns, conventions, and command usages.

For global Gemini agent guidelines and AI safety protocols, refer to [gemini/GEMINI.md](gemini/GEMINI.md).
EOF
        echo "Restored/Created GEMINI.md pointer file."
    else
        echo "GEMINI.md already exists (not a symlink). Keeping existing content."
    fi
else
    echo "Warning: CLAUDE.md not found. Skipping GEMINI.md update."
fi

echo ">>> Syncing Claude Code Permissions to Gemini CLI Policies..."
CLAUDE_SETTINGS="$DOTFILES_DIR/.claude/settings.json"
POLICY_DIR="$HOME/.gemini/policies"
CONVERT_SCRIPT="$DOTFILES_DIR/scripts/helpers/convert_claude_perms.py"

if [ -f "$CLAUDE_SETTINGS" ] && [ -f "$CONVERT_SCRIPT" ]; then
    mkdir -p "$POLICY_DIR"
    python3 "$CONVERT_SCRIPT" "$CLAUDE_SETTINGS" > "$POLICY_DIR/claude_sync.toml"
    echo "Generated $POLICY_DIR/claude_sync.toml"
else
    echo "Skipping permissions sync: .claude/settings.json or conversion script not found."
fi

echo ">>> Done! Gemini CLI is now synchronized with Claude Code configurations."