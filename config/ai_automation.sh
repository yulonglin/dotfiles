#!/usr/bin/env bash
# Shared runtime policy for automated AI-agent actions (hooks/wrappers).
# This file is sourced by scripts; it should not execute side effects.

# Delegation and recursion limits
: "${AUTO_AGENT_MAX_DEPTH:=2}"
: "${AUTO_AGENT_COOLDOWN_SEC:=120}"
: "${AUTO_AGENT_MAX_PER_HOUR:=20}"

# Anomaly detection policy
: "${AUTO_AGENT_ANOMALY_ENABLED:=1}"
: "${AUTO_AGENT_WARN_MULTIPLIER:=1.8}"
: "${AUTO_AGENT_STOP_MULTIPLIER:=2.5}"
: "${AUTO_AGENT_RATE_WINDOW_DAYS:=7}"
: "${AUTO_AGENT_PERCENTILE_WINDOW_DAYS:=30}"
: "${AUTO_AGENT_WEEKLY_WARN_RATIO:=1.25}"
: "${AUTO_AGENT_WEEKLY_STOP_RATIO:=1.75}"

# Absolute guardrails (used when provider reports projected values)
: "${AUTO_AGENT_DAILY_COST_LIMIT_USD:=200}"
: "${AUTO_AGENT_DAILY_TOKEN_LIMIT:=100000000}"
: "${AUTO_AGENT_BLOCK_PROJECTED_COST_LIMIT_USD:=100}"
: "${AUTO_AGENT_BLOCK_PROJECTED_TOKEN_LIMIT:=50000000}"

# Paths and state
# Global emergency stop sentinel (hard-limit guardrails).
: "${AUTO_AGENT_DISABLED_SENTINEL:=$HOME/.claude/flags/auto-agent-disabled}"
# Repo-scoped stop sentinels (anomaly policy) are stored under this directory.
: "${AUTO_AGENT_REPO_DISABLED_DIR:=$HOME/.claude/state/repo-disabled}"
: "${AUTO_AGENT_APPROVAL_FILE:=$HOME/.claude/flags/auto-agent-approved-until}"
: "${AUTO_AGENT_APPROVAL_TTL_MIN:=120}"
: "${AUTO_AGENT_TRACE_DIR:=$HOME/.claude/diagnostics}"
: "${AUTO_AGENT_STATE_DIR:=$HOME/.claude/state}"
: "${AUTO_AGENT_LOG_DIR:=$HOME/.claude/logs/auto-commit}"

# Auto-commit policy
# Keep Claude fallback opt-in because it is usually the most expensive backend.
: "${AUTO_COMMIT_BACKEND_ORDER:=codex,gemini}"
: "${AUTO_COMMIT_ENABLE_CLAUDE_FALLBACK:=0}"
: "${AUTO_COMMIT_DRY_RUN:=0}"
: "${AUTO_COMMIT_USE_ASYNC:=1}"
: "${AUTO_AGENT_EXCLUDE_REGEX:=^\\.claude/worktrees/}"

# Optional user override (gitignored by convention).
if [[ -f "$HOME/.claude/ai_automation.local.sh" ]]; then
  # shellcheck disable=SC1090
  source "$HOME/.claude/ai_automation.local.sh"
fi
