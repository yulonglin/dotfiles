#!/usr/bin/env bash

# Claude Code Status Line Script
#
# This script generates a comprehensive status line for Claude Code CLI.
#
# Displays (left to right):
# 1. Current working directory (full path, ~ for HOME)
# 2. Git branch with status indicator (clean/dirty)
# 3. Git changes: insertions/deletions (+X,-Y)
# 4. Context usage percentage (of usable context before auto-compact)
# 5. Thinking mode indicator (🧠 if enabled)
#
# Technical details:
# - Receives JSON via stdin from Claude Code with session/workspace data
# - Uses git commands to check repository status and diff statistics
# - Calculates context based on model (1M for Sonnet 4.5, 200k otherwise)
# - Usable context = 80% of total (auto-compact threshold)
# - Git branch symbol: ⎇ (U+2387) - works without Nerd Fonts
#   Alternative: use \ue0a0 if you have Powerline/Nerd Fonts installed

# Read JSON input from stdin
input=$(cat)

# Extract data from JSON
cwd=$(echo "$input" | jq -r ".workspace.current_dir")
model_id=$(echo "$input" | jq -r ".model.id // empty")
thinking_enabled=$(echo "$input" | jq -r ".thinking_enabled // false")

# ============================================================================
# DIRECTORY PATH (full path, ~ for HOME)
# ============================================================================
if [ "$cwd" = "$HOME" ]; then
  dir="~"
else
  # Replace HOME with ~ for cleaner display
  dir=$(echo "$cwd" | sed "s|^$HOME|~|")
fi

# ============================================================================
# GIT INFORMATION
# ============================================================================
git_info=""

if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  # Get branch name or short commit hash
  branch=$(git -C "$cwd" branch --show-current 2>/dev/null || \
           git -C "$cwd" rev-parse --short HEAD 2>/dev/null)

  if [ -n "$branch" ]; then
    # Check for uncommitted changes
    has_changes=false
    if ! git -C "$cwd" diff --quiet 2>/dev/null || \
       ! git -C "$cwd" diff --cached --quiet 2>/dev/null; then
      has_changes=true
    fi

    # Get git diff statistics (insertions/deletions)
    # Combine unstaged and staged changes
    unstaged=$(git -C "$cwd" diff --shortstat 2>/dev/null)
    staged=$(git -C "$cwd" diff --cached --shortstat 2>/dev/null)

    # Parse insertions and deletions using regex
    insertions=0
    deletions=0

    # Parse unstaged changes
    if [ -n "$unstaged" ]; then
      ins=$(echo "$unstaged" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+')
      del=$(echo "$unstaged" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+')
      insertions=$((insertions + ${ins:-0}))
      deletions=$((deletions + ${del:-0}))
    fi

    # Parse staged changes
    if [ -n "$staged" ]; then
      ins=$(echo "$staged" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+')
      del=$(echo "$staged" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+')
      insertions=$((insertions + ${ins:-0}))
      deletions=$((deletions + ${del:-0}))
    fi

    # Format git changes if any exist
    changes=""
    if [ "$insertions" -gt 0 ] || [ "$deletions" -gt 0 ]; then
      changes=" $(printf "\033[32m")+${insertions}$(printf "\033[0m"),$(printf "\033[31m")-${deletions}$(printf "\033[0m")"
    fi

    # Format branch with status indicator
    # Using ⎇ (U+2387) which works without Nerd Fonts
    # Change to \ue0a0 if you prefer Powerline symbols and have Nerd Fonts
    if [ "$has_changes" = true ]; then
      # Yellow for dirty repo
      git_info=" $(printf "\033[33m")⎇ ${branch}*$(printf "\033[0m")${changes}"
    else
      # Green for clean repo
      git_info=" $(printf "\033[32m")⎇ ${branch}$(printf "\033[0m")${changes}"
    fi
  fi
fi

# ============================================================================
# CONTEXT USAGE (percentage of usable context)
# ============================================================================
context_info=""

# Check if we have context data in the JSON
if echo "$input" | jq -e '.context_length' > /dev/null 2>&1; then
  context_length=$(echo "$input" | jq -r ".context_length")

  # Determine total context based on model
  # Sonnet 4.5 has 1M context, others have 200k
  if echo "$model_id" | grep -q "sonnet-4"; then
    total_context=1000000
  else
    total_context=200000
  fi

  # Usable context is 80% of total (auto-compact threshold)
  usable_context=$((total_context * 80 / 100))

  # Calculate percentage of usable context
  if [ "$context_length" -gt 0 ]; then
    percentage=$((context_length * 100 / usable_context))

    # Color-code based on usage
    if [ "$percentage" -ge 90 ]; then
      # Red: very high usage (90%+)
      context_info=" $(printf "\033[31m")${percentage}%%$(printf "\033[0m")"
    elif [ "$percentage" -ge 70 ]; then
      # Yellow: moderate usage (70-89%)
      context_info=" $(printf "\033[33m")${percentage}%%$(printf "\033[0m")"
    else
      # Green: low usage (<70%)
      context_info=" $(printf "\033[32m")${percentage}%%$(printf "\033[0m")"
    fi
  fi
fi

# ============================================================================
# THINKING MODE INDICATOR
# ============================================================================
thinking_info=""
if [ "$thinking_enabled" = "true" ]; then
  thinking_info=" $(printf "\033[35m")🧠$(printf "\033[0m")"
fi

# ============================================================================
# OUTPUT FORMATTED STATUS LINE
# ============================================================================
printf "\033[2m\033[36m%s\033[0m%s%s%s" "$dir" "$git_info" "$context_info" "$thinking_info"
