#!/usr/bin/env bash
# SessionStart hook: detect stale VIRTUAL_ENV after repo moves.
# Pure bash built-ins only — no subprocesses. Runs in <5ms.

[[ -d .venv ]] || exit 0

expected="$PWD/.venv"

# Check 1: VIRTUAL_ENV env var points to wrong path
if [[ -n "${VIRTUAL_ENV:-}" && "$VIRTUAL_ENV" != "$expected" ]]; then
    echo "WARNING: VIRTUAL_ENV mismatch. Got $VIRTUAL_ENV, expected $expected."
    echo "  Fix: unset VIRTUAL_ENV, or run: uv venv && uv sync"
    exit 0
fi

# Check 2: activate script has stale baked path
if [[ -f .venv/bin/activate ]]; then
    while IFS= read -r line; do
        if [[ "$line" == VIRTUAL_ENV=* ]]; then
            baked="${line#VIRTUAL_ENV=}"
            baked="${baked//\"/}"
            [[ "$baked" != "$expected" ]] && echo "WARNING: .venv has stale path (repo moved). Run: uv venv && uv sync"
            break
        fi
    done < .venv/bin/activate
fi
