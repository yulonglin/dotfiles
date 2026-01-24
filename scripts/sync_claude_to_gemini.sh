#!/bin/bash

# ==============================================================================
# SYNC CLAUDE CODE TO GEMINI CLI
# Purpose: Ports Claude Code agents and skills into Gemini CLI by symlinking.
# Source:  ~/code/dotfiles/claude/
# Target:  ~/.gemini/skills/
# ==============================================================================

SOURCE_DIR="$HOME/code/dotfiles/claude"
TARGET_DIR="$HOME/.gemini/skills"

mkdir -p "$TARGET_DIR"

echo ">>> Syncing Claude Code Skills to Gemini CLI..."
if [ -d "$SOURCE_DIR/skills" ]; then
    for skill in "$SOURCE_DIR/skills"/*; do
        [ -d "$skill" ] || continue
        name=$(basename "$skill")
        ln -sf "$skill" "$TARGET_DIR/$name"
        echo "Linked Skill: $name"
    done
fi

echo ">>> Syncing Claude Code Agents to Gemini CLI (as Skills)..."
if [ -d "$SOURCE_DIR/agents" ]; then
    for agent in "$SOURCE_DIR/agents"/*.md; do
        [ -f "$agent" ] || continue
        name=$(basename "$agent" .md)
        mkdir -p "$TARGET_DIR/$name"
        ln -sf "$agent" "$TARGET_DIR/$name/SKILL.md"
        echo "Linked Agent: $name"
    done
fi

echo ">>> Done! Gemini CLI is now synchronized with Claude Code configurations."
