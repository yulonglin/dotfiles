#!/usr/bin/env bash

# Claude Code Status Line Script
#
# This script generates a comprehensive status line for Claude Code CLI.
#
# Displays (left to right):
# 1. Machine name (SSH sessions only: SSH config alias or abbreviated hostname)
# 2. Current working directory (full path, ~ for HOME)
# 3. Git branch with status indicator (clean/dirty)
# 4. Context usage percentage (from context_window.used_percentage)
# 5. Session cost in USD (if > $0)
# 6. Session duration (if >= 1 minute)
#
# Technical details:
# - Receives JSON via stdin from Claude Code with session/workspace/cost/context data
# - Machine name: Uses shared machine-name script (custom_bins/machine-name)
#   Priority: $SERVER_NAME env > SSH config alias (by public IP) > abbreviated hostname
#   Supports $MACHINE_EMOJI env var, caches public IP for 1 hour
# - Uses git commands to check repository status and diff statistics
# - Uses context_window.used_percentage directly (pre-computed by Claude Code)
# - Uses cost.total_cost_usd for session cost tracking
# - Uses cost.total_duration_ms for session duration
# - Git branch shown in brackets: (branch) or (branch*) for dirty repos

# Read JSON input from stdin
input=$(cat)

# Extract data from JSON
cwd=$(echo "$input" | jq -r ".workspace.current_dir")
model_id=$(echo "$input" | jq -r ".model.id // empty")

# ============================================================================
# MACHINE NAME (SSH config alias, only shown in SSH sessions)
# ============================================================================
# Uses shared machine-name script (custom_bins/machine-name)
# See that script for priority logic and caching details

machine_info=""
if [ -n "$SSH_CONNECTION" ]; then
  machine_name_output=$(machine-name 2>/dev/null)
  if [ -n "$machine_name_output" ]; then
    # Extract emoji and name from output (format: "EMOJI NAME")
    icon="${machine_name_output%% *}"
    name="${machine_name_output#* }"
    machine_info="$icon $(printf "\033[35m")${name}$(printf "\033[0m") "
  fi
fi

# ============================================================================
# CONTEXT PROFILES (from context.yaml if present)
# ============================================================================
context_profiles=""
if [ -f "$cwd/.claude/context.yaml" ]; then
    # Extract profile names from YAML using awk (no pyyaml dependency)
    # Handles both block style ("- code\n- python") and flow style ("[code, python]")
    profiles=$(awk '
/^profiles:/ {
    if (index($0, "[") > 0) {
        s = $0; gsub(/.*\[/, "", s); gsub(/\].*/, "", s)
        gsub(/,/, " ", s); gsub(/^ +| +$/, "", s); print s; exit
    }
    result = ""
    while ((getline line) > 0) {
        if (line ~ /^- /) {
            sub(/^- /, "", line)
            result = result (result ? " " : "") line
        } else break
    }
    print result; exit
}' "$cwd/.claude/context.yaml" 2>/dev/null)
    if [ -n "$profiles" ]; then
        context_profiles="[$(printf "\033[36m")${profiles}$(printf "\033[0m")] "
    fi
fi

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

    # Format branch with status indicator using brackets
    if [ "$has_changes" = true ]; then
      # Yellow for dirty repo
      git_info=" $(printf "\033[33m")(${branch}*)$(printf "\033[0m")"
    else
      # Green for clean repo
      git_info=" $(printf "\033[32m")(${branch})$(printf "\033[0m")"
    fi
  fi
fi

# ============================================================================
# CONTEXT USAGE (from context_window.used_percentage, pre-computed by Claude Code)
# ============================================================================
context_info=""
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
if [ -n "$used_pct" ] && [ "$used_pct" != "0" ]; then
  # Round to integer (jq handles float→int)
  used_pct=$(echo "$used_pct" | jq -r '. | round')
  if [ "$used_pct" -ge 90 ] 2>/dev/null; then
    context_info=" · 📊 $(printf "\033[31m")${used_pct}%$(printf "\033[0m")"
  elif [ "$used_pct" -ge 70 ] 2>/dev/null; then
    context_info=" · 📊 $(printf "\033[33m")${used_pct}%$(printf "\033[0m")"
  else
    context_info=" · 📊 $(printf "\033[32m")${used_pct}%$(printf "\033[0m")"
  fi
fi

# ============================================================================
# COST TRACKING (session total)
# ============================================================================
cost_info=""

total_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0' 2>/dev/null)

# Only show cost if it's non-zero (use awk for portability)
if [ -n "$total_cost" ] && [ "$total_cost" != "0" ] && [ "$total_cost" != "null" ]; then
  is_positive=$(echo "$total_cost" | awk '{print ($1 > 0) ? 1 : 0}')
  if [ "$is_positive" = "1" ]; then
    # Format cost with 2 decimal places
    cost_formatted=$(printf "%.2f" "$total_cost")
    cost_info=" · $(printf "\033[35m")\$${cost_formatted}$(printf "\033[0m")"
  fi
fi

# ============================================================================
# SESSION DURATION (from cost.total_duration_ms)
# ============================================================================
duration_info=""
duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
if [ "$duration_ms" -gt 60000 ] 2>/dev/null; then
  total_mins=$((duration_ms / 60000))
  if [ "$total_mins" -ge 60 ]; then
    duration_info=" · $(printf "\033[2m")$((total_mins / 60))h $((total_mins % 60))m$(printf "\033[0m")"
  else
    duration_info=" · $(printf "\033[2m")${total_mins}m$(printf "\033[0m")"
  fi
fi

# ============================================================================
# OUTPUT FORMATTED STATUS LINE
# ============================================================================
printf "%s%s\033[2m\033[36m%s\033[0m%s%s%s%s" "$machine_info" "$context_profiles" "$dir" "$git_info" "$context_info" "$cost_info" "$duration_info"
