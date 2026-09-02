#!/usr/bin/env bash
# Checks nudge_uncapped_reader.sh fires on an uncapped heavy log read and stays
# quiet otherwise. A nudge that fires on everything gets ignored, so the quiet
# cases matter as much as the loud one.
set -uo pipefail

DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../claude/hooks" && pwd)
HOOK="$DIR/nudge_uncapped_reader.sh"
WORK=""
for base in "${TMPDIR:-}" /tmp/claude /tmp; do
    if [ -z "$base" ] || [ ! -d "$base" ] || [ ! -w "$base" ]; then
        continue
    fi
    WORK=$(mktemp -d -p "$base" 2>/dev/null) && break
done
[ -n "$WORK" ] || { echo "cannot make a temp dir"; exit 1; }
trap 'rm -rf "$WORK"' EXIT
FEATURES="$WORK/features.conf"
printf 'nudges.uncapped-reader = on\n' > "$FEATURES"
export CLAUDE_HOOK_FEATURES_FILE="$FEATURES"

fails=0

run_hook() {
    printf '{"tool_input":{"command":%s}}' "$(jq -Rn --arg c "$1" '$c')" | "$HOOK"
}

expect_fires() {
    local out
    out=$(run_hook "$1")
    if printf '%s' "$out" | grep -q "capped --mem"; then
        printf 'ok    fires: %s\n' "$1"
    else
        printf 'FAIL  silent, expected a nudge: %s\n' "$1"
        fails=$((fails + 1))
    fi
}

expect_silent() {
    local out
    out=$(run_hook "$1")
    if [ -z "$out" ]; then
        printf 'ok    quiet: %s\n' "$1"
    else
        printf 'FAIL  nudged, expected silence: %s\n' "$1"
        fails=$((fails + 1))
    fi
}

expect_fires 'uv run python -m impossiblebench_analysis.jlens_dryrun tmp/run/logs/x.eval'
expect_fires 'python3 -c "from inspect_ai.log import read_eval_log; read_eval_log(p)"'
expect_fires 'uv run python -m v2_rerun.agreement_analysis'

expect_silent 'capped --mem 18G -- uv run python -m impossiblebench_analysis.jlens_dryrun x.eval'
expect_silent 'systemd-run --user --scope -p MemoryMax=8G -- python read.py logs/x.eval'
expect_silent 'scripts/run-impossiblebench.sh --no-resource-caps --label smoke'
expect_silent 'ls tmp/run/eval_logs/'
expect_silent 'du -sh tmp/run/eval_logs/'
expect_silent 'git status'
expect_silent 'uv run pytest tests/'

# The feature flag must actually gate it, or turning nudges off does nothing.
printf 'nudges.uncapped-reader = off\n' > "$FEATURES"
expect_silent 'uv run python -m impossiblebench_analysis.jlens_dryrun tmp/run/logs/x.eval'

if [ "$fails" -ne 0 ]; then
    printf '\n%d check(s) failed\n' "$fails"
    exit 1
fi
printf '\nall checks passed\n'
