#!/usr/bin/env bash
# Claude Code Status Line Script
#
# Displays (left to right):
# 1. user@host (always) + machine name (SSH only, via custom_bins/machine-name)
# 2. Current working directory (~ for HOME)
# 3. Git branch with dirty indicator: (branch) green clean, (branch*) yellow dirty
# 4. Context usage percentage (color-coded: green <70%, yellow 70-89%, red 90%+)
# 5. Session cost in USD (if > $0)
# 6. Session duration (if >= 1 minute)
#
# Receives JSON via stdin from Claude Code.

input=$(cat)

cwd=$(echo "$input" | jq -r ".workspace.current_dir")
model=$(echo "$input" | jq -r '.model.display_name // empty')

# ============================================================================
# USER@HOST (always shown) + MACHINE NAME (SSH only)
# ============================================================================
user_host="$(whoami)@$(hostname -s)"

machine_prefix=""
if [ -n "$SSH_CONNECTION" ]; then
  machine_name_output=$(machine-name 2>/dev/null)
  if [ -n "$machine_name_output" ]; then
    icon="${machine_name_output%% *}"
    name="${machine_name_output#* }"
    machine_prefix="$icon $(printf '\033[35m')${name}$(printf '\033[0m') "
  fi
fi

# ============================================================================
# DIRECTORY PATH (~ for HOME)
# ============================================================================
if [ "$cwd" = "$HOME" ]; then
  dir="~"
else
  dir=$(echo "$cwd" | sed "s|^$HOME|~|")
fi

# ============================================================================
# GIT INFORMATION
# ============================================================================
git_info=""

if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git -C "$cwd" branch --show-current 2>/dev/null || \
           git -C "$cwd" rev-parse --short HEAD 2>/dev/null)

  if [ -n "$branch" ]; then
    has_changes=false
    if ! git -C "$cwd" diff --quiet 2>/dev/null || \
       ! git -C "$cwd" diff --cached --quiet 2>/dev/null; then
      has_changes=true
    fi

    if [ "$has_changes" = true ]; then
      git_info=" $(printf '\033[33m')(${branch}*)$(printf '\033[0m')"
    else
      git_info=" $(printf '\033[32m')(${branch})$(printf '\033[0m')"
    fi
  fi
fi

# ============================================================================
# MODEL NAME
# ============================================================================
model_info=""
if [ -n "$model" ]; then
  model_info=" · $(printf '\033[34m')[${model}]$(printf '\033[0m')"
fi

# ============================================================================
# CONTEXT USAGE (truncated to integer, color-coded by threshold)
# ============================================================================
context_info=""
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
if [ -n "$used_pct" ] && [ "$used_pct" != "0" ]; then
  used_int=${used_pct%.*}
  if [ "$used_int" -ge 90 ] 2>/dev/null; then
    context_info=" · $(printf '\033[31m')ctx:${used_int}%$(printf '\033[0m')"
  elif [ "$used_int" -ge 70 ] 2>/dev/null; then
    context_info=" · $(printf '\033[33m')ctx:${used_int}%$(printf '\033[0m')"
  else
    context_info=" · $(printf '\033[32m')ctx:${used_int}%$(printf '\033[0m')"
  fi
fi

# ============================================================================
# COST TRACKING (session total)
# ============================================================================
cost_info=""
total_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0' 2>/dev/null)

if [ -n "$total_cost" ] && [ "$total_cost" != "0" ] && [ "$total_cost" != "null" ]; then
  is_positive=$(echo "$total_cost" | awk '{print ($1 > 0) ? 1 : 0}')
  if [ "$is_positive" = "1" ]; then
    cost_formatted=$(printf "%.2f" "$total_cost")
    cost_info=" · $(printf '\033[35m')\$${cost_formatted}$(printf '\033[0m')"
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
    duration_info=" · $(printf '\033[2m')$((total_mins / 60))h $((total_mins % 60))m$(printf '\033[0m')"
  else
    duration_info=" · $(printf '\033[2m')${total_mins}m$(printf '\033[0m')"
  fi
fi

# ============================================================================
# OUTPUT
# ============================================================================
printf "%s%s\033[2m\033[36m%s\033[0m%s%s%s%s%s" "$machine_prefix" "$user_host " "$dir" "$git_info" "$model_info" "$context_info" "$cost_info" "$duration_info"
