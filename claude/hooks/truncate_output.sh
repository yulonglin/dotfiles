#!/bin/sh
# PostToolUse hook: Tiered bash output handling
#
# Tier 1: Per-line truncation (long lines) + head/tail truncation (large output)
# Tier 2: Gemini AI summarization for very large outputs (with fallback to Tier 1)
#
# Configuration (env vars):
#   CLAUDE_TRUNCATE_THRESHOLD  - Overall truncation threshold in chars (default: 5000)
#   CLAUDE_LINE_MAX_CHARS      - Per-line truncation threshold (default: 500)
#   CLAUDE_GEMINI_THRESHOLD    - Char threshold to invoke Gemini (default: 15000)
#   CLAUDE_GEMINI_TIMEOUT      - Seconds before Gemini timeout (default: 30)
#   CLAUDE_GEMINI_MAX_SUMMARY  - Max chars for Gemini summary (default: 2000)
#
# Note: Bash output exceeding CLAUDE_GEMINI_THRESHOLD may be sent to Google's
# Gemini API for summarization. Credentials and secrets are stripped first.

command -v jq >/dev/null 2>&1 || exit 0

TMPDIR="${TMPDIR:-/tmp/claude}"
INPUT_FILE="$TMPDIR/hook_input_$$.json"
DECISION_FILE="$TMPDIR/hook_decision_$$.json"
SANITIZED_FILE="$TMPDIR/hook_sanitized_$$.txt"
MSG_FILE="$TMPDIR/hook_msg_$$.txt"
trap 'rm -f "$INPUT_FILE" "$DECISION_FILE" "$SANITIZED_FILE" "$MSG_FILE"' EXIT
mkdir -p "$TMPDIR"

# Fast path: skip jq for small output (<6KB covers ~90% of bash commands)
cat > "$INPUT_FILE"
INPUT_SIZE=$(wc -c < "$INPUT_FILE" | tr -d ' ')
[ "$INPUT_SIZE" -lt 6000 ] && exit 0

# Phase 1: jq extracts fields, applies Tier 1 truncation, and decides routing
jq -c --arg line_max "${CLAUDE_LINE_MAX_CHARS:-500}" \
      --arg threshold "${CLAUDE_TRUNCATE_THRESHOLD:-5000}" \
      --arg gemini_threshold "${CLAUDE_GEMINI_THRESHOLD:-15000}" '
  if .tool_name != "Bash" then empty
  else
    .tool_response as $r |
    .tool_input.command as $cmd |
    ($r.stdout // "") as $stdout |
    ($r.stderr // "") as $stderr |
    ($r.exit_code // 0) as $exit |
    (($stdout | length) + ($stderr | length)) as $total |
    ($line_max | tonumber) as $lmax |
    ($threshold | tonumber) as $thresh |
    ($gemini_threshold | tonumber) as $gthresh |

    if $total < $thresh then empty
    else
      # Per-line truncation: collapse lines longer than $lmax chars
      def truncate_line:
        if length > $lmax then
          .[:200] + " ... [" + (length | tostring) + " chars] ... " + .[-100:]
        else . end;

      # Truncate stdout: per-line + head 15 / tail 30 for large output
      (if ($stdout | length) > 1500 then
        ($stdout | split("\n") | map(truncate_line)) as $lines |
        if ($lines | length) <= 45 then ($lines | join("\n"))
        else
          ([$lines[:15][], "",
            "... [" + ($stdout | length | tostring) + " chars, " +
            (($stdout | split("\n") | length) | tostring) + " lines truncated] ...",
            "", $lines[-30:][]] | join("\n"))
        end
      else
        ($stdout | split("\n") | map(truncate_line) | join("\n"))
      end) as $trunc_stdout |

      # Truncate stderr: per-line + last 20 lines
      (if ($stderr | length) > 500 then
        "... [stderr truncated] ...\n\n" +
        (($stderr | split("\n"))[-20:] | map(truncate_line) | join("\n"))
      else
        ($stderr | split("\n") | map(truncate_line) | join("\n"))
      end) as $trunc_stderr |

      # Stderr percentage for Gemini skip decision
      (if $total > 0 then (($stderr | length) * 100 / $total) else 0 end) as $stderr_pct |

      # Build truncated message
      ("Command: " + $cmd + "\nExit code: " + ($exit | tostring) +
       "\nOutput (truncated from " + ($total | tostring) + " chars):\n\n" +
       $trunc_stdout +
       (if ($trunc_stderr | length) > 0 then
         "\n\n--- stderr ---\n" + $trunc_stderr
       else "" end)) as $truncated_msg |

      # Routing: if truncated output still exceeds Gemini threshold, try Tier 2
      (($trunc_stdout | length) + ($trunc_stderr | length)) as $trunc_total |
      (if $trunc_total > $gthresh then "gemini" else "truncate" end) as $action |

      {action: $action, truncated_msg: $truncated_msg,
       stderr_pct: ($stderr_pct | floor), command: $cmd, exit_code: $exit}
    end
  end
' < "$INPUT_FILE" > "$DECISION_FILE"

# No output means small/non-bash — pass through
[ ! -s "$DECISION_FILE" ] && exit 0

ACTION=$(jq -r '.action' < "$DECISION_FILE")

# Tier 1: simple truncation (most common path)
if [ "$ACTION" = "truncate" ]; then
  jq -c '{suppressOutput: true, systemMessage: .truncated_msg}' < "$DECISION_FILE"
  exit 0
fi

# Tier 2: Gemini summarization
# Skip if stderr-dominated (>80%) — error diagnostics need exact text
STDERR_PCT=$(jq -r '.stderr_pct' < "$DECISION_FILE")
if [ "$ACTION" = "gemini" ] && [ "$STDERR_PCT" -lt 80 ]; then
  # Portable timeout: timeout (Linux/brew) or gtimeout (macOS coreutils)
  TIMEOUT_CMD=""
  if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_CMD="timeout"
  elif command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT_CMD="gtimeout"
  fi

  if [ -n "$TIMEOUT_CMD" ] && command -v gemini >/dev/null 2>&1; then
    # Sanitize: strip potential credentials and long base64 blobs
    jq -r '.truncated_msg' < "$DECISION_FILE" | \
      grep -v -E '(KEY=|SECRET=|PASSWORD=|TOKEN=|Authorization:|Bearer |token=|api_key=)' | \
      grep -v -E '[A-Za-z0-9+/=]{100,}' > "$SANITIZED_FILE"

    COMMAND=$(jq -r '.command' < "$DECISION_FILE")
    EXIT_CODE=$(jq -r '.exit_code' < "$DECISION_FILE")
    GEMINI_TIMEOUT="${CLAUDE_GEMINI_TIMEOUT:-30}"
    MAX_SUMMARY="${CLAUDE_GEMINI_MAX_SUMMARY:-2000}"

    PROMPT=$(printf 'Summarize this command output for an AI coding assistant (Claude Code). The command was: %s (exit code: %s). Respond in under 1500 characters. Focus on: errors, warnings, key metrics, final status, actionable information. Omit boilerplate and repetitive lines. Format as concise bullet points.' "$COMMAND" "$EXIT_CODE")

    SUMMARY=$($TIMEOUT_CMD "$GEMINI_TIMEOUT" gemini -p "$PROMPT" < "$SANITIZED_FILE" 2>/dev/null)
    GEMINI_EXIT=$?

    if [ "$GEMINI_EXIT" -eq 0 ] && [ -n "$SUMMARY" ]; then
      # Hard-cap summary length
      SUMMARY=$(printf '%s' "$SUMMARY" | head -c "$MAX_SUMMARY")
      ORIG_LEN=$(jq -r '.truncated_msg | length' < "$DECISION_FILE")

      # Build message via file to avoid shell quoting issues
      printf '[Gemini summary of %s chars | cmd: %s | exit: %s]\n\n' \
        "$ORIG_LEN" "$COMMAND" "$EXIT_CODE" > "$MSG_FILE"
      printf '%s\n\n' "$SUMMARY" >> "$MSG_FILE"
      printf '[Original output suppressed. Note: bash output may be sent to Google Gemini API for summarization.]' >> "$MSG_FILE"

      jq -Rsc '{suppressOutput: true, systemMessage: .}' < "$MSG_FILE"
      exit 0
    fi
  fi
fi

# Fallback: Tier 1 result (Gemini unavailable, timed out, or stderr-dominated)
jq -c '{suppressOutput: true, systemMessage: .truncated_msg}' < "$DECISION_FILE"
