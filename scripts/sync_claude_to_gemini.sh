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

SOURCE_DIR="$HOME/code/dotfiles/claude"
TARGET_DIR="$HOME/.gemini/skills"
DOTFILES_DIR="$HOME/code/dotfiles"

mkdir -p "$TARGET_DIR"

echo ">>> Syncing Claude Code Skills to Gemini CLI..."
if [ -d "$SOURCE_DIR/skills" ]; then
    for skill in "$SOURCE_DIR/skills"/*; do
        [ -d "$skill" ] || continue
        name=$(basename "$skill")
        # Use -n to treat destination symlink to directory as a file (prevents dereferencing)
        ln -sfn "$skill" "$TARGET_DIR/$name"
        echo "Linked Skill: $name"
    done
fi

echo ">>> Syncing Claude Code Agents to Gemini CLI (as Skills)..."
if [ -d "$SOURCE_DIR/agents" ]; then
    for agent in "$SOURCE_DIR/agents"/*.md; do
        [ -f "$agent" ] || continue
        name=$(basename "$agent" .md)
        mkdir -p "$TARGET_DIR/$name"
        # Use -n to safer symlinking
        ln -sfn "$agent" "$TARGET_DIR/$name/SKILL.md"
        echo "Linked Agent: $name"
    done
fi

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
CLAUDE_SETTINGS="$HOME/code/dotfiles/.claude/settings.json"
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