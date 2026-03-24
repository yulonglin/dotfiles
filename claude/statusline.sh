#!/usr/bin/env bash
# Claude Code Status Line Script (bash fallback)
#
# Displays on 3 lines:
# Line 1 (location): Machine name (SSH) + profiles + directory + git branch
# Line 2 (session): Model name + context % + duration
# Line 3 (usage): 5h and 7d API usage bars (cached, from /api/oauth/usage)
#
# Receives JSON via stdin from Claude Code.

input=$(cat)

cwd=$(echo "$input" | jq -r ".workspace.current_dir")

# ============================================================================
# MACHINE NAME (registered machines + SSH fallback)
# ============================================================================
machine_prefix=""
machine_name_output=$(machine-name 2>/dev/null)
if [ -n "$machine_name_output" ]; then
  icon="${machine_name_output%% *}"
  name="${machine_name_output#* }"
  machine_prefix="$icon $(printf '\033[35m')${name}$(printf '\033[0m') "
fi

# ============================================================================
# CONTEXT PROFILES from .claude/context.yaml
# ============================================================================
profiles_info=""
context_yaml="$cwd/.claude/context.yaml"
if [ -f "$context_yaml" ]; then
  # Extract profiles from YAML (handles both flow [a, b] and block - a style)
  profiles=$(python3 -c "
import yaml, sys
try:
    d = yaml.safe_load(open('$context_yaml'))
    p = d.get('profiles', [])
    if p: print(' '.join(p))
except: pass
" 2>/dev/null)
  if [ -n "$profiles" ]; then
    profiles_info="[$(printf '\033[36m')${profiles}$(printf '\033[0m')] "
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
model_name=$(echo "$input" | jq -r '.model.display_name // empty')
if [ -n "$model_name" ]; then
  model_info="$(printf '\033[34m')[${model_name}]$(printf '\033[0m')"
fi

# ============================================================================
# CONTEXT USAGE (truncated to integer, color-coded by threshold)
# ============================================================================
context_info=""
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
if [ -n "$used_pct" ] && [ "$used_pct" != "0" ]; then
  used_int=${used_pct%.*}
  if [ "$used_int" -ge 90 ] 2>/dev/null; then
    context_info="$(printf '\033[31m')ctx:${used_int}%$(printf '\033[0m')"
  elif [ "$used_int" -ge 70 ] 2>/dev/null; then
    context_info="$(printf '\033[33m')ctx:${used_int}%$(printf '\033[0m')"
  else
    context_info="$(printf '\033[32m')ctx:${used_int}%$(printf '\033[0m')"
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
    duration_info="$(printf '\033[2m')$((total_mins / 60))h $((total_mins % 60))m$(printf '\033[0m')"
  else
    duration_info="$(printf '\033[2m')${total_mins}m$(printf '\033[0m')"
  fi
fi

# ============================================================================
# OUTPUT: Line 1 (location) + Line 2 (session)
# ============================================================================
# Line 1: location
printf "%s%s\033[2m\033[36m%s\033[0m%s" "$machine_prefix" "$profiles_info" "$dir" "$git_info"

# Line 2: session state (model · ctx · duration)
session_parts=()
[ -n "$model_info" ] && session_parts+=("$model_info")
[ -n "$context_info" ] && session_parts+=("$context_info")
[ -n "$duration_info" ] && session_parts+=("$duration_info")
if [ ${#session_parts[@]} -gt 0 ]; then
  printf "\n"
  for i in "${!session_parts[@]}"; do
    [ "$i" -gt 0 ] && printf " · "
    printf "%s" "${session_parts[$i]}"
  done
fi

# ============================================================================
# API USAGE (5h + 7d rate limits, cached 60s)
# ============================================================================
cache_dir="${TMPDIR:-/tmp/claude}"
cache_file="$cache_dir/claude-statusline-usage.json"
cache_max_age=300

# Helper: build a progress bar
build_bar() {
  local pct=$1 width=10 color
  [ "$pct" -lt 0 ] 2>/dev/null && pct=0
  [ "$pct" -gt 100 ] 2>/dev/null && pct=100
  local filled=$((pct * width / 100)) empty=$((width - filled))

  if [ "$pct" -ge 90 ]; then color='\033[31m'
  elif [ "$pct" -ge 70 ]; then color='\033[33m'
  elif [ "$pct" -ge 50 ]; then color='\033[38;2;255;176;85m'
  else color='\033[32m'; fi

  local filled_str="" empty_str=""
  for ((i=0; i<filled; i++)); do filled_str+="●"; done
  for ((i=0; i<empty; i++)); do empty_str+="○"; done

  printf "${color}${filled_str}\033[2m${empty_str}\033[0m ${color}%d%%\033[0m" "$pct"
}

# Helper: resolve OAuth token
get_oauth_token() {
  [ -n "$CLAUDE_CODE_OAUTH_TOKEN" ] && { echo "$CLAUDE_CODE_OAUTH_TOKEN"; return 0; }

  if command -v security >/dev/null 2>&1; then
    local blob
    blob=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
    if [ -n "$blob" ]; then
      local token
      token=$(echo "$blob" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
      [ -n "$token" ] && [ "$token" != "null" ] && { echo "$token"; return 0; }
    fi
  fi

  local creds="$HOME/.claude/.credentials.json"
  if [ -f "$creds" ]; then
    local token
    token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds" 2>/dev/null)
    [ -n "$token" ] && [ "$token" != "null" ] && { echo "$token"; return 0; }
  fi
}

# Fetch or use cache
usage_data=""
needs_refresh=true
mkdir -p "$cache_dir"

if [ -f "$cache_file" ]; then
  cache_mtime=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null)
  now=$(date +%s)
  cache_age=$((now - cache_mtime))
  if [ "$cache_age" -lt "$cache_max_age" ]; then
    needs_refresh=false
    usage_data=$(cat "$cache_file" 2>/dev/null)
  fi
fi

if $needs_refresh; then
  token=$(get_oauth_token)
  if [ -n "$token" ]; then
    response=$(curl -s --max-time 2 \
      -H "Authorization: Bearer $token" \
      -H "Accept: application/json" \
      -H "anthropic-beta: oauth-2025-04-20" \
      "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
    if [ -n "$response" ] && echo "$response" | jq -e '.five_hour' >/dev/null 2>&1; then
      usage_data="$response"
      # Only cache if at least one utilization value is present
      has_util=$(echo "$response" | jq -r '(.five_hour.utilization // empty), (.seven_day.utilization // empty)' 2>/dev/null)
      if [ -n "$has_util" ]; then
        echo "$response" > "$cache_file"
      fi
    fi
  fi
  # Fall back to stale cache
  if [ -z "$usage_data" ] && [ -f "$cache_file" ]; then
    usage_data=$(cat "$cache_file" 2>/dev/null)
  fi
fi

# Helper: parse ISO 8601 timestamp to epoch
parse_iso_epoch() {
  local iso="$1"
  local stripped="${iso%%.*}"
  stripped="${stripped%Z}"
  # macOS
  local epoch
  epoch=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "$stripped" "+%s" 2>/dev/null)
  if [ -n "$epoch" ]; then echo "$epoch"; return; fi
  # Linux
  epoch=$(date -d "$iso" "+%s" 2>/dev/null)
  if [ -n "$epoch" ]; then echo "$epoch"; return; fi
}

# Helper: format epoch as time "4:30pm"
format_epoch_time() {
  local epoch="$1"
  # macOS
  local t
  t=$(date -j -r "$epoch" "+%l:%M%p" 2>/dev/null)
  if [ -n "$t" ]; then echo "${t## }" | tr '[:upper:]' '[:lower:]'; return; fi
  # Linux
  t=$(date -d "@$epoch" "+%l:%M%P" 2>/dev/null)
  if [ -n "$t" ]; then echo "${t## }"; return; fi
}

# Helper: format epoch as datetime "mar 12 4:30pm"
format_epoch_datetime() {
  local epoch="$1"
  # macOS
  local t
  t=$(date -j -r "$epoch" "+%b %-d %l:%M%p" 2>/dev/null)
  if [ -n "$t" ]; then echo "$t" | tr '[:upper:]' '[:lower:]' | sed 's/  / /g'; return; fi
  # Linux
  t=$(date -d "@$epoch" "+%b %-d %l:%M%P" 2>/dev/null)
  if [ -n "$t" ]; then echo "$t" | sed 's/  / /g'; return; fi
}

# Render usage bars
if [ -n "$usage_data" ] && echo "$usage_data" | jq -e . >/dev/null 2>&1; then
  five_pct=$(echo "$usage_data" | jq -r '.five_hour.utilization // 0' | awk '{printf "%.0f", $1}')
  seven_pct=$(echo "$usage_data" | jq -r '.seven_day.utilization // 0' | awk '{printf "%.0f", $1}')

  printf "\n"

  if [ "$five_pct" = "0" ] && [ "$seven_pct" = "0" ]; then
    printf "\033[2m—\033[0m"
  else
    if [ "$five_pct" -ge 90 ] 2>/dev/null; then five_color='\033[31m'
    elif [ "$five_pct" -ge 70 ] 2>/dev/null; then five_color='\033[33m'
    elif [ "$five_pct" -ge 50 ] 2>/dev/null; then five_color='\033[38;2;255;176;85m'
    else five_color='\033[32m'; fi
    printf "${five_color}5h\033[0m "
    build_bar "$five_pct"

    # 5h reset time
    five_resets=$(echo "$usage_data" | jq -r '.five_hour.resets_at // empty')
    if [ -n "$five_resets" ]; then
      five_epoch=$(parse_iso_epoch "$five_resets")
      if [ -n "$five_epoch" ]; then
        five_time=$(format_epoch_time "$five_epoch")
        [ -n "$five_time" ] && printf " \033[2m⟳ %s\033[0m" "$five_time"
      fi
    fi

    printf "  ·  "

    if [ "$seven_pct" -ge 90 ] 2>/dev/null; then seven_color='\033[31m'
    elif [ "$seven_pct" -ge 70 ] 2>/dev/null; then seven_color='\033[33m'
    elif [ "$seven_pct" -ge 50 ] 2>/dev/null; then seven_color='\033[38;2;255;176;85m'
    else seven_color='\033[32m'; fi
    printf "${seven_color}7d\033[0m "
    build_bar "$seven_pct"

    # 7d pace + reset datetime
    seven_resets=$(echo "$usage_data" | jq -r '.seven_day.resets_at // empty')
    if [ -n "$seven_resets" ]; then
      seven_epoch=$(parse_iso_epoch "$seven_resets")
      if [ -n "$seven_epoch" ]; then
        now=$(date +%s)
        remaining=$(( seven_epoch - now ))
        [ "$remaining" -lt 0 ] && remaining=0
        seven_day_secs=604800
        elapsed=$(( seven_day_secs - remaining ))
        # Pace calculation: expected % based on elapsed fraction
        expected=$(( elapsed * 100 / seven_day_secs ))
        delta=$(( seven_pct - expected ))
        if [ "$delta" -gt 0 ]; then
          printf " \033[31m+%d%%\033[0m" "$delta"
        elif [ "$delta" -lt 0 ]; then
          printf " \033[32m%d%%\033[0m" "$delta"
        else
          printf " \033[2m0%%\033[0m"
        fi
        seven_datetime=$(format_epoch_datetime "$seven_epoch")
        [ -n "$seven_datetime" ] && printf " \033[2m⟳ %s\033[0m" "$seven_datetime"
      fi
    fi

    # Near-limit reminder: suggest account switch when approaching cap
    if [ "$five_pct" -ge 95 ] 2>/dev/null || [ "$seven_pct" -ge 95 ] 2>/dev/null; then
      printf "\n\033[31;1m🚨 Near limit! \`claude-switch\` to logout+login — logout clears cached usage, restart alone won't help 🚨\033[0m"
    fi
  fi
else
  if [ -n "$token" ] || [ -z "$(get_oauth_token)" ]; then
    printf "\n\033[2m\033[31mno oauth token found\033[0m"
  else
    printf "\n\033[2m\033[31mapi request failed\033[0m"
  fi
fi
