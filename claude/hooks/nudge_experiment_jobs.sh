#!/bin/bash
set -euo pipefail

# PreToolUse(Bash) hook: nudge agents toward jexp/jagent for resource-heavy commands.
# NUDGE only (never blocks) — experiments can still run directly.
#
# Detects: python/uv-run commands that look like experiments or long compute.
# Skips: quick checks, pip/uv operations, pytest, python -c, --version, etc.

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // ""')
bg=$(echo "$input" | jq -r '.tool_input.run_in_background // false')

[[ -z "$command" ]] && exit 0

nudge=""

# Strip leading env vars (FOO=bar cmd...) to find the actual command
stripped=$(echo "$command" | sed -E 's/^([A-Z_]+=[^ ]+ )*//')

# Is this a python/uv-run-python invocation?
is_python=false
if [[ "$stripped" =~ ^(python3?|uv[[:space:]]+run[[:space:]]+(--no-sync[[:space:]]+)?python3?)[[:space:]] ]]; then
  is_python=true
fi

# Quick exit for non-python commands
$is_python || exit 0

# Skip patterns that are clearly not experiments
[[ "$stripped" =~ python3?[[:space:]]+(--version|-V|-c[[:space:]]) ]] && exit 0
[[ "$stripped" =~ (uv[[:space:]]+pip|pip[[:space:]]+install|pytest|ruff|ty[[:space:]]) ]] && exit 0

# Detect experiment signals (any match = nudge)
experiment_signals=false

# Hydra / config-driven runs
[[ "$command" =~ (--config[-_]name|--config[-_]dir|--multirun|hydra) ]] && experiment_signals=true

# Training / sweep patterns
[[ "$command" =~ (--epochs?|--train|--sweep|--batch[-_]size|--lr[[:space:]=]) ]] && experiment_signals=true

# Logging to file (tee to logs/)
[[ "$command" =~ \|[[:space:]]*tee[[:space:]] ]] && experiment_signals=true

# Module runs that look like experiments (run_sweep, train, evaluate, etc.)
[[ "$stripped" =~ python3?[[:space:]]+-m[[:space:]]+.*\.(run|train|sweep|evaluate|experiment|benchmark) ]] && experiment_signals=true

# Running in background = likely long-running
[[ "$bg" == "true" && "$is_python" == "true" ]] && experiment_signals=true

$experiment_signals || exit 0

# Build the nudge message with actionable help
msg="**Resource management:** This looks like an experiment. Consider using \`jexp\` for CPU/memory-capped execution."

# Check if pueue is available and running
if command -v pueue &>/dev/null; then
  if pueue status &>/dev/null; then
    msg="$msg
Usage: \`jexp uv run python -m ...\` (caps: ${EXPERIMENTS_CPU_QUOTA:-200%} CPU, ${EXPERIMENTS_MEMORY_MAX:-24G} mem)"
  else
    msg="$msg
**pueued not running.** Start it: \`systemctl --user start pueued\`"
  fi
else
  msg="$msg
pueue not installed. Install: \`cargo install pueue\` or \`brew install pueue\`"
fi

# pueue and systemctl are in sandbox excludedCommands — no special handling needed

jq -n --arg msg "$msg" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    message: $msg
  }
}'
