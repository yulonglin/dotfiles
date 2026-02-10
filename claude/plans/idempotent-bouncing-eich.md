# Plan: Tiered Bash Output Handling (Per-Line Truncation + Gemini Summarization)

## Context

**Problem**: Claude Code's context gets polluted by long bash output in two ways:
1. **Long individual lines** — even `tail -20` on a log with 5KB JSON/base64 lines produces 100KB+
2. **Large total output** — the existing `truncate_output.sh` does dumb head+tail truncation, losing important information from the middle (errors, metrics, etc.)

**Current state**: `truncate_output.sh` (PostToolUse hook) truncates output >5000 chars to first 15 + last 30 lines. No per-line limits. No intelligent summarization. `BASH_MAX_OUTPUT_LENGTH` env var is unset.

## Approach: Three-Tier System

### Tier 1: Per-Line Truncation (enhance `truncate_output.sh`)
- Truncate lines >500 chars → `first_200 ... [N chars] ... last_100`
- Zero latency, pure jq, nested inside existing threshold check (no cost for <5K outputs)
- Handles the "tail still huge" problem

### Tier 2: Gemini Summarization (new branch in same script)
- Triggers when output >15K chars after Tier 1 truncation
- Feeds Gemini the **Tier 1 truncated output** (not raw original) — keeps input small (2-5K)
- **Summary hard-capped at 2000 chars** (`CLAUDE_GEMINI_MAX_SUMMARY`) — Gemini prompt explicitly says "respond in under 1500 characters"
- **Skips Gemini for stderr-dominated output** (>80% stderr) — error diagnostics need exact text
- Falls back to Tier 1 on any failure (Gemini missing, timeout, error, no `timeout` command)
- Temp files use `$$` PID for concurrency safety, cleaned up via `trap`

### Tier 3: PreToolUse Warnings (extend `check_pipe_buffering.sh`)
- Warn on known high-output patterns without limits:
  - `cat <large_file>` without pipe → suggest `head -100`
  - `docker logs` without `--tail` → suggest `--tail=200`
  - `journalctl` without `-n` → suggest `-n 200`
- Warn only (via stderr), never auto-modify commands

### Backstop: `BASH_MAX_OUTPUT_LENGTH=100000` in settings.json
- Absolute ceiling — Claude Code's built-in middle-truncation handles catastrophic cases
- Prevents jq from choking on 50MB inputs
- Ship first, independently (1-line change, zero risk)

## Key Design Decisions (from critiques)

### Fast path for small output
Before jq, write stdin to temp file and check byte count. If <6000 bytes, exit immediately. Avoids jq parsing for ~90% of Bash commands.

### Temp files instead of shell variables
Two-phase (jq decision → shell dispatch) uses temp files for all intermediate data. Avoids null-byte truncation, large-variable fragility in dash/sh, and is debuggable.

### Portable timeout
Check `timeout` → `gtimeout` → skip Gemini. macOS doesn't ship `timeout` natively.

### jq env var access
Use `--arg` parameters instead of `env.VARNAME` for portability with jq <1.6.

### Credential safety
Before sending to Gemini, strip lines matching secret patterns (`KEY=`, `Authorization:`, `Bearer `, `token=`, base64 blobs >100 chars). Document that bash output may be sent to Google's Gemini API.

### suppressOutput verification (Step 0 — plan-blocking)
Before implementing Tier 2, empirically verify that `suppressOutput: true` actually removes original output from Claude's context (not just UI suppression). Test by generating distinctive output, letting the hook truncate it, and asking Claude what it sees.

## Files to Modify

| File | Change |
|------|--------|
| `claude/hooks/truncate_output.sh` | Add fast path + Tier 1 per-line truncation + Tier 2 Gemini summarization |
| `claude/hooks/check_pipe_buffering.sh` | Add Tier 3 output-size warning patterns |
| `claude/settings.json` | Add `BASH_MAX_OUTPUT_LENGTH: "100000"` to `env` block |

## Configuration (env vars)

| Variable | Default | Purpose |
|----------|---------|---------|
| `CLAUDE_TRUNCATE_THRESHOLD` | 5000 | Overall truncation threshold (existing) |
| `CLAUDE_LINE_MAX_CHARS` | 500 | Per-line truncation threshold (new) |
| `CLAUDE_GEMINI_THRESHOLD` | 15000 | Char threshold to invoke Gemini (new) |
| `CLAUDE_GEMINI_TIMEOUT` | 30 | Seconds before Gemini timeout (new) |
| `CLAUDE_GEMINI_MAX_SUMMARY` | 2000 | Max chars for Gemini summary output (new) |

## Implementation Steps

1. **Step 0 (plan-blocking)**: Verify `suppressOutput: true` removes output from context, not just display
2. **Step 1**: Add `BASH_MAX_OUTPUT_LENGTH` to `settings.json` env block
3. **Step 2**: Add fast path (byte-count check before jq) to `truncate_output.sh`
4. **Step 3**: Add Tier 1 per-line truncation inside the existing jq threshold branch
5. **Step 4**: Refactor to two-phase (jq decision → shell dispatch) with temp files
6. **Step 5**: Add Tier 2 Gemini summarization with: portable timeout, credential sanitization, summary cap, stderr-skip, fallback
7. **Step 6**: Extend `check_pipe_buffering.sh` with Tier 3 warning patterns
8. **Step 7**: Test all tiers end-to-end

## Script Structure (pseudocode)

```sh
#!/bin/sh
command -v jq >/dev/null 2>&1 || exit 0

TMPDIR="${TMPDIR:-/tmp/claude}"
INPUT_FILE="$TMPDIR/hook_input_$$.json"
DECISION_FILE="$TMPDIR/hook_decision_$$.json"
trap 'rm -f "$INPUT_FILE" "$DECISION_FILE"' EXIT
mkdir -p "$TMPDIR"

# Fast path: skip jq for small output
cat > "$INPUT_FILE"
INPUT_SIZE=$(wc -c < "$INPUT_FILE")
[ "$INPUT_SIZE" -lt 6000 ] && exit 0

# Phase 1: jq does extraction + Tier 1 truncation + routing decision
jq -c --arg line_max "${CLAUDE_LINE_MAX_CHARS:-500}" \
      --arg threshold "${CLAUDE_TRUNCATE_THRESHOLD:-5000}" \
      --arg gemini_threshold "${CLAUDE_GEMINI_THRESHOLD:-15000}" '
  ... Tier 1 logic (head+tail + per-line truncation) ...
  ... output: {action, truncated_msg, original_length, command, exit_code, stderr_pct}
' < "$INPUT_FILE" > "$DECISION_FILE"

[ ! -s "$DECISION_FILE" ] && exit 0

ACTION=$(jq -r '.action' < "$DECISION_FILE")

# Tier 1 only
if [ "$ACTION" = "truncate" ]; then
  jq -c '{suppressOutput: true, systemMessage: .truncated_msg}' < "$DECISION_FILE"
  exit 0
fi

# Tier 2: Gemini (skip if stderr-dominated or no gemini/timeout)
STDERR_PCT=$(jq -r '.stderr_pct' < "$DECISION_FILE")
if [ "$ACTION" = "gemini" ] && [ "$STDERR_PCT" -lt 80 ]; then
  # Check for timeout command (macOS portability)
  TIMEOUT_CMD=""
  command -v timeout >/dev/null 2>&1 && TIMEOUT_CMD="timeout"
  command -v gtimeout >/dev/null 2>&1 && TIMEOUT_CMD="gtimeout"

  if [ -n "$TIMEOUT_CMD" ] && command -v gemini >/dev/null 2>&1; then
    # Sanitize and send to Gemini
    TRUNCATED=$(jq -r '.truncated_msg' < "$DECISION_FILE" | grep -v -E '(KEY=|Authorization:|Bearer |token=)')
    SUMMARY=$(echo "$TRUNCATED" | $TIMEOUT_CMD "${CLAUDE_GEMINI_TIMEOUT:-30}" \
      gemini -p "Summarize for an AI coding assistant in under 1500 chars. ..." 2>/dev/null)

    MAX_SUMMARY="${CLAUDE_GEMINI_MAX_SUMMARY:-2000}"
    if [ $? -eq 0 ] && [ -n "$SUMMARY" ]; then
      SUMMARY=$(echo "$SUMMARY" | head -c "$MAX_SUMMARY")
      jq -nc --arg msg "..." '{suppressOutput: true, systemMessage: $msg}'
      exit 0
    fi
  fi
fi

# Fallback: Tier 1 result
jq -c '{suppressOutput: true, systemMessage: .truncated_msg}' < "$DECISION_FILE"
```

## Verification

1. **Step 0**: Distinctive output test → confirm `suppressOutput` removes from context
2. **Regression**: Small output (<5K) → no output from hook (fast path)
3. **Tier 1 per-line**: 6K output with 1000-char lines → lines truncated to ~300 chars
4. **Tier 2 Gemini**: 20K+ output → Gemini summary returned, capped at 2K chars
5. **Tier 2 fallback**: `CLAUDE_GEMINI_TIMEOUT=1` → falls back to Tier 1
6. **Tier 2 no-gemini**: Rename `gemini` binary → falls back to Tier 1
7. **Tier 2 stderr-skip**: stderr >80% of output → Tier 1 only (no Gemini)
8. **Tier 3**: `check_pipe_buffering.sh` with `docker logs container` → warning about `--tail`
9. **Live test**: In session, run verbose command → verify appropriate tier fires
