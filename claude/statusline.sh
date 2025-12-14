#!/usr/bin/env bash

# Claude Code Status Line Script
#
# This script generates a comprehensive status line for Claude Code CLI.
#
# Displays (left to right):
# 1. Current working directory (full path, ~ for HOME)
# 2. Git branch with status indicator (clean/dirty)
# 3. Git changes: insertions/deletions (+X,-Y)
# 4. Context usage percentage (tokens used / context window size)
# 5. Session cost in USD (if > $0)
#
# Technical details:
# - Receives JSON via stdin from Claude Code with session/workspace/cost data
# - Uses git commands to check repository status and diff statistics
# - Parses transcript JSONL for accurate context (statusline JSON only has per-turn tokens)
# - Context = input_tokens + cache_read + cache_creation + output_tokens
# - Percentage = (context + 45k autocompact buffer) / 200k to match /context
# - Uses cost.total_cost_usd for session cost tracking
# - Git branch shown in brackets: (branch) or (branch*) for dirty repos

# Read JSON input from stdin
input=$(cat)

# Extract data from JSON
cwd=$(echo "$input" | jq -r ".workspace.current_dir")
model_id=$(echo "$input" | jq -r ".model.id // empty")

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

    # Format branch with status indicator using brackets
    if [ "$has_changes" = true ]; then
      # Yellow for dirty repo
      git_info=" $(printf "\033[33m")(${branch}*)$(printf "\033[0m")${changes}"
    else
      # Green for clean repo
      git_info=" $(printf "\033[32m")(${branch})$(printf "\033[0m")${changes}"
    fi
  fi
fi

# ============================================================================
# CONTEXT USAGE (percentage of usable context)
# ============================================================================
context_info=""

# Get transcript path to read token metrics (statusline JSON fields are per-turn, not cumulative)
transcript_path=$(echo "$input" | jq -r ".transcript_path // empty")

if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
  # Find the most recent assistant message with usage data
  # Search backwards through the transcript (tac reverses lines)
  last_assistant_msg=$(tac "$transcript_path" 2>/dev/null | \
    grep -m 1 '"type":"assistant"' | \
    grep 'input_tokens')

  if [ -n "$last_assistant_msg" ]; then
    # Extract token counts from the usage field (nested in message)
    input_tokens=$(echo "$last_assistant_msg" | jq -r '.message.usage.input_tokens // 0' 2>/dev/null)
    cache_read=$(echo "$last_assistant_msg" | jq -r '.message.usage.cache_read_input_tokens // 0' 2>/dev/null)
    cache_creation=$(echo "$last_assistant_msg" | jq -r '.message.usage.cache_creation_input_tokens // 0' 2>/dev/null)
    output_tokens=$(echo "$last_assistant_msg" | jq -r '.message.usage.output_tokens // 0' 2>/dev/null)

    # Calculate context length (input + cached + output tokens)
    # Output tokens from this turn become input tokens in the next turn
    context_length=$((input_tokens + cache_read + cache_creation + output_tokens))

    if [ "$context_length" -gt 0 ]; then
      # Claude Code uses 200k context with 45k autocompact buffer
      # Percentage = (context + buffer) / 200k to match /context display
      total_tokens=200000
      autocompact_buffer=45000
      context_with_buffer=$((context_length + autocompact_buffer))

      percentage=$((context_with_buffer * 100 / total_tokens))

      # Color-code based on usage
      if [ "$percentage" -ge 90 ]; then
        # Red: very high (90%+)
        context_info=" · 📊 $(printf "\033[31m")${percentage}%$(printf "\033[0m")"
      elif [ "$percentage" -ge 70 ]; then
        # Yellow: moderate (70-89%)
        context_info=" · 📊 $(printf "\033[33m")${percentage}%$(printf "\033[0m")"
      else
        # Green: low (<70%)
        context_info=" · 📊 $(printf "\033[32m")${percentage}%$(printf "\033[0m")"
      fi
    fi
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
# OUTPUT FORMATTED STATUS LINE
# ============================================================================
printf "\033[2m\033[36m%s\033[0m%s%s%s" "$dir" "$git_info" "$context_info" "$cost_info"
