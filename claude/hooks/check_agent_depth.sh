#!/usr/bin/env bash
set -euo pipefail

max_depth="${AUTO_AGENT_MAX_DEPTH:-2}"
depth="${AUTO_AGENT_DEPTH:-0}"

if [[ "$depth" =~ ^[0-9]+$ ]] && [[ "$max_depth" =~ ^[0-9]+$ ]]; then
  if (( depth >= max_depth )); then
    echo "BLOCKED: delegation depth limit reached (${depth}/${max_depth})" >&2
    exit 2
  fi
fi

exit 0

