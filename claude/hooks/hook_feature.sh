#!/usr/bin/env bash
# Fail-open launcher for advisory hook features. A broken nudge must never block
# the tool event that triggered it.
set -uo pipefail

HOOK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || {
    cat >/dev/null 2>&1 || true
    exit 0
}
FEATURE_PY="${CLAUDE_HOOK_FEATURE_PY:-$HOOK_DIR/hook_feature.py}"

if [[ ! -r "$FEATURE_PY" ]]; then
    cat >/dev/null 2>&1 || true
    exit 0
fi

python3 "$FEATURE_PY" "$@" || {
    cat >/dev/null 2>&1 || true
    exit 0
}
exit 0
