#!/usr/bin/env bash
# Claude Code Status Line Script (bash fallback)
# Rust primary: tools/claude-tools/src/statusline.rs (recompile with cargo build --release)
#
# Displays on up to 3 lines:
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
# MODEL NAME (+ reasoning effort level, when the model supports it)
# ============================================================================
model_info=""
model_name=$(echo "$input" | jq -r '.model.display_name // empty')
effort_level=$(echo "$input" | jq -r '.effort.level // empty')
if [ -n "$model_name" ]; then
  if [ -n "$effort_level" ]; then
    model_info="$(printf '\033[34m')[${model_name} · ${effort_level}]$(printf '\033[0m')"
  else
    model_info="$(printf '\033[34m')[${model_name}]$(printf '\033[0m')"
  fi
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

# Helper: build a progress bar with an explicit color (color decision lives
# in color_for_pace/color_for_pct so bar color and label color always agree)
build_bar() {
  local pct=$1 color=$2 width=10
  [ "$pct" -lt 0 ] 2>/dev/null && pct=0
  [ "$pct" -gt 100 ] 2>/dev/null && pct=100
  local filled=$((pct * width / 100))
  local empty=$((width - filled))

  local filled_str="" empty_str=""
  for ((i=0; i<filled; i++)); do filled_str+="●"; done
  for ((i=0; i<empty; i++)); do empty_str+="○"; done

  printf "${color}${filled_str}\033[2m${empty_str}\033[0m ${color}%d%%\033[0m" "$pct"
}

# Helper: color by absolute usage — fallback when reset time is unavailable
color_for_pct() {
  local pct=$1
  if [ "$pct" -ge 90 ] 2>/dev/null; then printf '\033[31m'
  elif [ "$pct" -ge 70 ] 2>/dev/null; then printf '\033[33m'
  elif [ "$pct" -ge 50 ] 2>/dev/null; then printf '\033[38;2;255;176;85m'
  else printf '\033[32m'; fi
}

# Helper: color by pace — how far ahead of the linear burn rate (percentage
# points). Warm only when burning faster than the window allows; on pace,
# behind, or barely ahead stays green.
color_for_pace() {
  local delta=$1
  if [ "$delta" -ge 30 ] 2>/dev/null; then printf '\033[31m'
  elif [ "$delta" -ge 15 ] 2>/dev/null; then printf '\033[33m'
  elif [ "$delta" -ge 5 ] 2>/dev/null; then printf '\033[38;2;255;176;85m'
  else printf '\033[32m'; fi
}

# Helper: compute pace delta for a rate-limit bucket. Sets PACE_DELTA and
# PACE_EPOCH; returns 1 (leaving both empty) if the reset time is missing or
# unparseable, so callers can fall back to color_for_pct.
compute_pace() {
  local pct=$1 resets_iso=$2 window_secs=$3
  PACE_DELTA=""
  PACE_EPOCH=""
  [ -z "$resets_iso" ] && return 1
  local epoch; epoch=$(parse_iso_epoch "$resets_iso")
  [ -z "$epoch" ] && return 1
  local now remaining elapsed expected
  now=$(date +%s)
  remaining=$(( epoch - now )); [ "$remaining" -lt 0 ] && remaining=0
  elapsed=$(( window_secs - remaining ))
  expected=$(( elapsed * 100 / window_secs ))
  PACE_DELTA=$(( pct - expected ))
  PACE_EPOCH=$epoch
  return 0
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

# Helper: format remaining seconds as a compact countdown "2h30m" / "45m" / "5d3h"
format_countdown() {
  local remaining_secs="$1"
  local mins=$(( (remaining_secs + 30) / 60 ))
  local h=$(( mins / 60 ))
  local m=$(( mins % 60 ))
  if [ "$h" -ge 24 ]; then
    printf '%dd%dh' "$((h / 24))" "$((h % 24))"
  elif [ "$h" -gt 0 ]; then
    printf '%dh%dm' "$h" "$m"
  else
    printf '%dm' "$m"
  fi
}

# ============================================================================
# MULTI-ACCOUNT TRACKING (other logged-out account's last-known 5h reset)
# ============================================================================
# Account switching here means log-out/log-in on this same ~/.claude — not
# separate CLAUDE_CONFIG_DIR instances — so only one account's credentials
# are ever live at a time. We snapshot the *active* account's 5h reset into a
# persistent, email-keyed cache on every tick, and surface whichever *other*
# entry exists as a last-known countdown. Persists across logout (unlike the
# volatile TMPDIR usage cache above, which is overwritten per active account).
accounts_cache_dir="$HOME/.claude/usage-data"
accounts_cache_file="$accounts_cache_dir/accounts.json"

# Helper: current account's identity (email), the cache key
get_account_email() {
  local claude_json="$HOME/.claude.json"
  [ -f "$claude_json" ] || return 1
  local email
  email=$(jq -r '.oauthAccount.emailAddress // empty' "$claude_json" 2>/dev/null)
  [ -n "$email" ] && [ "$email" != "null" ] && { echo "$email"; return 0; }
  return 1
}

# Render usage bars
if [ -n "$usage_data" ] && echo "$usage_data" | jq -e . >/dev/null 2>&1; then
  five_pct=$(echo "$usage_data" | jq -r '.five_hour.utilization // 0' | awk '{printf "%.0f", $1}')
  seven_pct=$(echo "$usage_data" | jq -r '.seven_day.utilization // 0' | awk '{printf "%.0f", $1}')

  # Snapshot this account into the persistent multi-account cache, keyed by
  # email, so the *other* (logged-out) account's last-known 5h reset can
  # still be surfaced after switching away from it.
  current_account_email=$(get_account_email)
  if [ -n "$current_account_email" ]; then
    mkdir -p "$accounts_cache_dir" 2>/dev/null
    five_resets_for_cache=$(echo "$usage_data" | jq -r '.five_hour.resets_at // empty')
    if [ -n "$five_resets_for_cache" ]; then
      existing_accounts="{}"
      [ -f "$accounts_cache_file" ] && existing_accounts=$(cat "$accounts_cache_file" 2>/dev/null)
      [ -n "$existing_accounts" ] || existing_accounts="{}"
      echo "$existing_accounts" | jq \
        --arg email "$current_account_email" \
        --arg resets "$five_resets_for_cache" \
        --argjson pct "$five_pct" \
        '.[$email] = {five_hour_resets_at: $resets, five_hour_pct: $pct}' \
        > "$accounts_cache_file.tmp" 2>/dev/null && mv "$accounts_cache_file.tmp" "$accounts_cache_file"
    fi
  fi

  printf "\n"

  if [ "$five_pct" = "0" ] && [ "$seven_pct" = "0" ]; then
    printf "\033[2m—\033[0m"
  else
    # 5h bucket: color + delta by pace vs linear burn rate, falls back to
    # absolute-usage color if reset time is unavailable
    five_resets=$(echo "$usage_data" | jq -r '.five_hour.resets_at // empty')
    if compute_pace "$five_pct" "$five_resets" 18000; then
      five_color=$(color_for_pace "$PACE_DELTA")
      five_delta=$PACE_DELTA
      five_epoch=$PACE_EPOCH
    else
      five_color=$(color_for_pct "$five_pct")
      five_delta=""
      five_epoch=""
    fi

    printf "${five_color}5h\033[0m "
    build_bar "$five_pct" "$five_color"
    if [ -n "$five_delta" ]; then
      if [ "$five_delta" -gt 0 ]; then printf " ${five_color}+%d%%\033[0m" "$five_delta"
      else printf " ${five_color}%d%%\033[0m" "$five_delta"; fi
    fi
    if [ -n "$five_epoch" ]; then
      five_time=$(format_epoch_time "$five_epoch")
      [ -n "$five_time" ] && printf " \033[2m⟳ %s\033[0m" "$five_time"
    fi

    printf "  ·  "

    # 7d bucket: same pace-based treatment
    seven_resets=$(echo "$usage_data" | jq -r '.seven_day.resets_at // empty')
    if compute_pace "$seven_pct" "$seven_resets" 604800; then
      seven_color=$(color_for_pace "$PACE_DELTA")
      seven_delta=$PACE_DELTA
      seven_epoch=$PACE_EPOCH
    else
      seven_color=$(color_for_pct "$seven_pct")
      seven_delta=""
      seven_epoch=""
    fi

    printf "${seven_color}7d\033[0m "
    build_bar "$seven_pct" "$seven_color"
    if [ -n "$seven_delta" ]; then
      if [ "$seven_delta" -gt 0 ]; then printf " ${seven_color}+%d%%\033[0m" "$seven_delta"
      else printf " ${seven_color}%d%%\033[0m" "$seven_delta"; fi
    fi
    if [ -n "$seven_epoch" ]; then
      seven_datetime=$(format_epoch_datetime "$seven_epoch")
      [ -n "$seven_datetime" ] && printf " \033[2m⟳ %s\033[0m" "$seven_datetime"
    fi

    # Model-scoped weekly limits (e.g. Fable) — separate quota from the
    # aggregate 7d bucket above, surfaced by the API as `weekly_scoped`.
    while IFS=$'\t' read -r limit_name limit_pct_raw limit_resets; do
      [ -z "$limit_name" ] && continue
      limit_pct=$(printf '%.0f' "$limit_pct_raw")
      printf "  ·  "
      if compute_pace "$limit_pct" "$limit_resets" 604800; then
        limit_color=$(color_for_pace "$PACE_DELTA")
        limit_delta=$PACE_DELTA
        limit_epoch=$PACE_EPOCH
      else
        limit_color=$(color_for_pct "$limit_pct")
        limit_delta=""
        limit_epoch=""
      fi
      printf "${limit_color}%s\033[0m " "$limit_name"
      build_bar "$limit_pct" "$limit_color"
      if [ -n "$limit_delta" ]; then
        if [ "$limit_delta" -gt 0 ]; then printf " ${limit_color}+%d%%\033[0m" "$limit_delta"
        else printf " ${limit_color}%d%%\033[0m" "$limit_delta"; fi
      fi
      if [ -n "$limit_epoch" ]; then
        limit_datetime=$(format_epoch_datetime "$limit_epoch")
        [ -n "$limit_datetime" ] && printf " \033[2m⟳ %s\033[0m" "$limit_datetime"
      fi
    done < <(echo "$usage_data" | jq -r '.limits[]? | select(.kind == "weekly_scoped") | select(.scope.model.display_name != null) | [.scope.model.display_name, (.percent // 0), (.resets_at // "")] | @tsv')

  fi

  # Other account's last-known 5h reset — always-on compact indicator,
  # visually separated with "|" since it's a different account's data.
  if [ -n "$current_account_email" ] && [ -f "$accounts_cache_file" ]; then
    other_resets=$(jq -r --arg email "$current_account_email" \
      'to_entries | map(select(.key != $email)) | sort_by(.value.five_hour_resets_at) | last.value.five_hour_resets_at // empty' \
      "$accounts_cache_file" 2>/dev/null)
    if [ -n "$other_resets" ] && [ "$other_resets" != "null" ]; then
      other_epoch=$(parse_iso_epoch "$other_resets")
      if [ -n "$other_epoch" ]; then
        now_epoch=$(date +%s)
        if [ "$other_epoch" -gt "$now_epoch" ]; then
          printf "  |  \033[2m⇄ %s\033[0m" "$(format_countdown "$((other_epoch - now_epoch))")"
        else
          printf "  |  \033[32m⇄ ready\033[0m"
        fi
      fi
    fi
  fi
else
  if [ -n "$token" ] || [ -z "$(get_oauth_token)" ]; then
    printf "\n\033[2m\033[31mno oauth token found\033[0m"
  else
    printf "\n\033[2m\033[31mapi request failed\033[0m"
  fi
fi
