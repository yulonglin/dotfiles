#!/usr/bin/env bash
# Claude Code Status Line Script (bash fallback)
# Rust primary: tools/claude-tools/src/statusline.rs (recompile with cargo build --release)
#
# Displays on up to 3 lines:
# Line 1 (location): Machine name (SSH) + profiles + directory + git branch
# Line 2 (session): Model name (with reasoning effort) + context tokens/%
#                   + duration + approval-classifier state
# Line 3 (usage): 5h and 7d API usage gauges (cached, from /api/oauth/usage)
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
# REASONING EFFORT (only emitted for models that support it)
# Rendered as the parenthesised suffix inside the model bracket, so it is
# computed before the model. Deliberately leaves the colour open — the model
# block re-opens blue for the closing bracket.
# Parity: tools/claude-tools/src/statusline.rs::format_effort_suffix
# ============================================================================
effort_suffix=""
# Trimmed at the edges only, matching Rust's str::trim — `tr -d '[:space:]'`
# would also collapse interior whitespace and diverge from the primary.
effort_level=$(echo "$input" | jq -r '.effort.level // empty' \
  | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
if [ -n "$effort_level" ]; then
  case "$effort_level" in
    # Yellow for the levels that cost enough to be worth noticing; dim otherwise
    xhigh|max) effort_suffix="$(printf '\033[33m')(${effort_level})" ;;
    *)         effort_suffix="$(printf '\033[2m')(${effort_level})" ;;
  esac
fi

# ============================================================================
# MODEL NAME (+ reasoning effort, when the model reports one): "[Opus 5 (high)]"
# Effort has no segment of its own, so a payload with an effort but no display
# name renders neither — which Claude Code never sends.
# Parity: tools/claude-tools/src/statusline.rs::format_model_str
# ============================================================================
model_info=""
model_name=$(echo "$input" | jq -r '.model.display_name // empty')
if [ -n "$model_name" ]; then
  if [ -n "$effort_suffix" ]; then
    model_info="$(printf '\033[34m')[${model_name} ${effort_suffix}$(printf '\033[34m')]$(printf '\033[0m')"
  else
    model_info="$(printf '\033[34m')[${model_name}]$(printf '\033[0m')"
  fi
fi

# ============================================================================
# CONTEXT USAGE (absolute tokens + %, color-coded by threshold)
# Parity: tools/claude-tools/src/statusline.rs::format_context_usage_str
# ============================================================================

# Compact token count: "845" under a thousand, "123k", "1.0M". The k branch
# stops below 999500 so a value that would round to "1000k" renders as "1.0M".
# Parity: tools/claude-tools/src/statusline.rs::format_tokens
format_tokens() {
  local n="$1"
  if [ "$n" -lt 1000 ]; then
    printf '%d' "$n"
  elif [ "$n" -lt 999500 ]; then
    printf '%dk' $(( (n + 500) / 1000 ))
  else
    # LC_ALL=C: the Rust primary always emits a '.' decimal point, so a
    # comma-decimal locale here would silently break parity ("1,5M" vs "1.5M").
    LC_ALL=C awk -v n="$n" 'BEGIN { printf "%.1fM", n / 1000000 }'
  fi
}

context_info=""
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
used_int=0
# Round rather than truncate — the Rust primary uses f64::round, and a
# truncating fallback would disagree with it on every fractional percentage.
[ -n "$used_pct" ] && used_int=$(LC_ALL=C awk -v p="$used_pct" 'BEGIN { printf "%d", int(p + 0.5) }')
# Gate on the ROUNDED value, not the raw string. 0.4 rounds to 0, and Rust's
# `.round() as u64` saturates a negative to 0 — both hide the segment there, so
# testing the raw string for "0" would render "ctx:0%" / "ctx:-4%" where the
# primary renders nothing.
if [ "$used_int" -gt 0 ] 2>/dev/null; then
  if [ "$used_int" -ge 90 ] 2>/dev/null; then
    ctx_color=$(printf '\033[31m')
  elif [ "$used_int" -ge 70 ] 2>/dev/null; then
    ctx_color=$(printf '\033[33m')
  else
    ctx_color=$(printf '\033[32m')
  fi

  ctx_tokens=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')
  ctx_size=$(echo "$input" | jq -r '.context_window.context_window_size // empty')
  if [ -n "$ctx_tokens" ] && [ "$ctx_tokens" -gt 0 ] 2>/dev/null; then
    ctx_body="$(format_tokens "$ctx_tokens")"
    if [ -n "$ctx_size" ] && [ "$ctx_size" -gt 0 ] 2>/dev/null; then
      ctx_body="${ctx_body}/$(format_tokens "$ctx_size")"
    fi
    # Parenthesised only when it qualifies a token count in front of it; the
    # bare-percentage branch below stays unadorned.
    ctx_body="${ctx_body} (${used_int}%)"
  else
    ctx_body="${used_int}%"
  fi

  context_info="${ctx_color}ctx:${ctx_body}$(printf '\033[0m')"
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
# APPROVAL CLASSIFIER (which backend last auto-approved, and on which key)
# Parity: tools/claude-tools/src/statusline.rs::format_classifier_str
# ============================================================================
classifier_info=""
classifier_health="$HOME/.cache/claude/approval-classifier-health.json"
if [ -f "$classifier_health" ]; then
  # Two age tiers. write_health() runs ONLY on the classify() path — fast-path
  # allows, denies and question-to-user surfaces never touch it — so a session
  # whose tool calls all hit a fast path leaves this file frozen at whatever the
  # last backend attempt saw. On 2026-08-05 that pinned `dead` for over two hours
  # on one transient API read timeout. Past 15m the entry is no longer evidence
  # of the current state, so report it as unknown; past 6h treat it as absent.
  health_ts=$(jq -r '.ts // 0' "$classifier_health" 2>/dev/null || echo 0)
  now_ts=$(date +%s)
  health_age=$((now_ts - health_ts))

  # Validate the backend BEFORE the age tiers, so a corrupt or future-versioned
  # file renders nothing at either age rather than an authoritative-looking
  # "stale" marker for a value we cannot interpret.
  backend=$(jq -r '.backend // ""' "$classifier_health" 2>/dev/null)
  case "$backend" in
    api | subscription | dead) ;;
    *) backend="" ;;
  esac

  if [ -n "$backend" ] && [ "$health_age" -gt 900 ] && [ "$health_age" -le 21600 ]; then
    # Applies to every backend, healthy included: past the window we don't know
    # that the API path still works either, and claiming otherwise is the same
    # error as the sticky `dead` in the opposite direction.
    classifier_info="$(printf '\033[2m')auto?$(printf '\033[0m')"
  elif [ -n "$backend" ] && [ "$health_age" -le 900 ]; then

    # Short label of the active ANTHROPIC_API_KEY, mirroring the resolver in
    # custom_bins/dotfiles-secrets: first line whose value is not `!`-blocked.
    key_label=""
    conf_root="${DOT_DIR:-}"
    [ -z "$conf_root" ] && conf_root=$(dirname "$(readlink "$HOME/.claude" 2>/dev/null)" 2>/dev/null)
    if [ -n "$conf_root" ] && [ -f "$conf_root/config/secrets-global.conf" ]; then
      key_label=$(awk -F= '
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
        {
          name = $1; sub(/^[[:space:]]+/, "", name); sub(/[[:space:]]+$/, "", name)
          # " [global]" marks the name resolvable outside a repo; it is part of
          # the NAME field, so it must come off before matching.
          sub(/[[:space:]]*\[global\]$/, "", name)
          if (name != "ANTHROPIC_API_KEY") next
          value = substr($0, index($0, "=") + 1)
          sub(/^[[:space:]]+/, "", value); sub(/[[:space:]]+$/, "", value)
          # A marker-only line ("NAME [global] =") declares no key.
          if (value == "") next
          if (value ~ /^!/) next
          idx = index(value, " - ")
          print (idx ? substr(value, idx + 3) : "")
          exit
        }' "$conf_root/config/secrets-global.conf" 2>/dev/null)
    fi

    # The suffix after `auto-` names the BACKEND, not the key: `-ant` is the
    # Anthropic API key path, `-sub` the subscription fallback. Keeping the two
    # in the same position means a key labelled "sub" can no longer read as the
    # degraded state.
    case "$backend" in
      api)
        if [ -n "$key_label" ]; then
          classifier_info="$(printf '\033[2m')auto-ant:${key_label}$(printf '\033[0m')"
        else
          classifier_info="$(printf '\033[2m')auto-ant$(printf '\033[0m')"
        fi
        ;;
      subscription)
        # Deliberately does NOT name a key — with-anthropic-key.sh defers to an
        # already-exported ANTHROPIC_API_KEY, so the conf's preferred key may not
        # be the one that failed. Naming the wrong key as down is worse than none.
        classifier_info="$(printf '\033[33m')auto-sub$(printf '\033[0m') $(printf '\033[2m')(api down)$(printf '\033[0m')"
        ;;
      dead)
        classifier_info="$(printf '\033[31m')🔴auto$(printf '\033[0m')"
        ;;
    esac
  fi
fi

# ============================================================================
# OUTPUT: Line 1 (location) + Line 2 (session)
# ============================================================================
# Line 1: location
printf "%s\033[2m\033[36m%s\033[0m%s" "$machine_prefix" "$dir" "$git_info"

# Line 2: session state (model+effort · ctx · duration · classifier)
session_parts=()
[ -n "$model_info" ] && session_parts+=("$model_info")
[ -n "$context_info" ] && session_parts+=("$context_info")
[ -n "$duration_info" ] && session_parts+=("$duration_info")
[ -n "$classifier_info" ] && session_parts+=("$classifier_info")
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

# Single-glyph usage gauge. Circle quadrants from the Geometric Shapes block —
# deliberately not moon-phase emoji, which are Emoji_Presentation: double-width,
# color-glyph, and immune to the ANSI pace colour that carries the signal.
# Must stay byte-identical to GAUGE_GLYPHS in tools/claude-tools/src/usage.rs.
GAUGE_GLYPHS=("○" "◔" "◑" "◕" "●")

# Helper: build a one-glyph usage gauge with an explicit color (color decision
# lives in color_for_pace/color_for_pct so gauge and label colors always agree).
# Quantisation is integer round-half-up over 4 steps — identical arithmetic to
# gauge_level() in tools/claude-tools/src/usage.rs, so the two renderers agree.
build_gauge() {
  local pct=$1 color=$2 steps=4
  [ "$pct" -lt 0 ] 2>/dev/null && pct=0
  [ "$pct" -gt 100 ] 2>/dev/null && pct=100
  local level=$(( (pct * steps + 50) / 100 ))

  printf "${color}%s %d%%\033[0m" "${GAUGE_GLYPHS[$level]}" "$pct"
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

# Render usage gauges
if [ -n "$usage_data" ] && echo "$usage_data" | jq -e . >/dev/null 2>&1; then
  # int(x + 0.5), not printf "%.0f". C's %.0f rounds half to EVEN, while the
  # Rust primary uses f64::round (half away from zero) — so a utilization of
  # 12.5 rendered "12 ○" here and "13 ◔" there, diverging in both the glyph and
  # the percentage. Utilization is never negative, so int(x + 0.5) matches Rust
  # over the whole range. Same fix, same reason, as the context percentage above.
  five_pct=$(echo "$usage_data" | jq -r '.five_hour.utilization // 0' | LC_ALL=C awk '{printf "%d", int($1 + 0.5)}')
  seven_pct=$(echo "$usage_data" | jq -r '.seven_day.utilization // 0' | LC_ALL=C awk '{printf "%d", int($1 + 0.5)}')

  # Snapshot this account into the persistent multi-account cache, keyed by
  # email, so the *other* (logged-out) account's last-known usage windows
  # (5h, 7d, weekly-scoped) can still be surfaced after switching away from
  # it. Only windows with data this tick are updated; others keep their
  # last-known value (jq's `+` merges the new snapshot over the old entry).
  current_account_email=$(get_account_email)
  if [ -n "$current_account_email" ]; then
    mkdir -p "$accounts_cache_dir" 2>/dev/null
    snapshot=$(echo "$usage_data" | jq -c \
      --argjson five_pct "$five_pct" \
      --argjson seven_pct "$seven_pct" \
      '{
        five_hour_resets_at: (.five_hour.resets_at // null),
        five_hour_pct: (if .five_hour.resets_at then $five_pct else null end),
        seven_day_resets_at: (.seven_day.resets_at // null),
        seven_day_pct: (if .seven_day.resets_at then $seven_pct else null end),
        weekly_scoped: (
          [.limits[]? | select(.kind == "weekly_scoped") | select(.scope.model.display_name != null) |
            {key: .scope.model.display_name, value: {resets_at: (.resets_at // null), pct: ((.percent // 0) | round)}}]
          | from_entries
        )
      } | with_entries(select(.value != null and .value != {}))')
    if [ -n "$snapshot" ] && [ "$snapshot" != "{}" ]; then
      existing_accounts="{}"
      [ -f "$accounts_cache_file" ] && existing_accounts=$(cat "$accounts_cache_file" 2>/dev/null)
      [ -n "$existing_accounts" ] || existing_accounts="{}"
      echo "$existing_accounts" | jq \
        --arg email "$current_account_email" \
        --argjson snapshot "$snapshot" \
        '.[$email] = ((.[$email] // {}) + $snapshot | .weekly_scoped = ((.[$email].weekly_scoped // {}) * ($snapshot.weekly_scoped // {})))' \
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
    build_gauge "$five_pct" "$five_color"
    if [ -n "$five_delta" ]; then
      if [ "$five_delta" -gt 0 ]; then printf " ${five_color}+%d%%\033[0m" "$five_delta"
      else printf " ${five_color}%d%%\033[0m" "$five_delta"; fi
    fi
    if [ -n "$five_epoch" ]; then
      five_time=$(format_epoch_time "$five_epoch")
      [ -n "$five_time" ] && printf " \033[2m⟳ %s\033[0m" "$five_time"
    fi

    printf " · "

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
    build_gauge "$seven_pct" "$seven_color"
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
      # int(x + 0.5) rather than printf '%.0f', matching Rust's f64::round —
      # see the five_pct/seven_pct note above for why half-to-even diverges.
      limit_pct=$(LC_ALL=C awk -v p="$limit_pct_raw" 'BEGIN { printf "%d", int(p + 0.5) }')
      printf " · "
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
      build_gauge "$limit_pct" "$limit_color"
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

  # Other account's last-known usage windows (5h, 7d, weekly-scoped) —
  # always-on compact indicator, visually separated with "|" since it's a
  # different account's data. Selects the entry with the most recently
  # synced 5h window, then renders every window it has data for.
  if [ -n "$current_account_email" ] && [ -f "$accounts_cache_file" ]; then
    other_entry=$(jq -c --arg email "$current_account_email" \
      'to_entries | map(select(.key != $email)) | sort_by(.value.five_hour_resets_at) | last.value // empty' \
      "$accounts_cache_file" 2>/dev/null)
    if [ -n "$other_entry" ] && [ "$other_entry" != "null" ]; then
      other_windows=$(echo "$other_entry" | jq -r '
        [{label: "5h", resets_at: .five_hour_resets_at}, {label: "7d", resets_at: .seven_day_resets_at}]
        + [(.weekly_scoped // {}) | to_entries[] | {label: .key, resets_at: .value.resets_at}]
        | .[] | select(.resets_at != null) | [.label, .resets_at] | @tsv')
      other_rendered=""
      now_epoch=$(date +%s)
      while IFS=$'\t' read -r other_label other_resets; do
        [ -z "$other_label" ] && continue
        other_epoch=$(parse_iso_epoch "$other_resets")
        [ -z "$other_epoch" ] && continue
        [ -n "$other_rendered" ] && other_rendered="${other_rendered} · "
        if [ "$other_epoch" -gt "$now_epoch" ]; then
          other_rendered="${other_rendered}\033[2m${other_label} $(format_countdown "$((other_epoch - now_epoch))")\033[0m"
        else
          other_rendered="${other_rendered}\033[32m${other_label} ready\033[0m"
        fi
      done <<< "$other_windows"
      [ -n "$other_rendered" ] && printf "  \033[2m⇄\033[0m %b" "$other_rendered"
    fi
  fi
else
  if [ -n "$token" ] || [ -z "$(get_oauth_token)" ]; then
    printf "\n\033[2m\033[31mno oauth token found\033[0m"
  else
    printf "\n\033[2m\033[31mapi request failed\033[0m"
  fi
fi
