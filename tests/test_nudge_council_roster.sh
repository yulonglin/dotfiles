#!/usr/bin/env bash
# Checks nudge_council_roster.sh reports a DEAD council seat as well as an
# overdue review date, and stays quiet otherwise.
#
# The incident, 2026-09-16: `openrouter-cli council ask` hung for its full
# ten-minute timeout because `qwen/qwen3.8-max` had been retired from the
# OpenRouter catalogue. The fortnightly check had found it the day before and
# written it to a report file nothing reads; this hook compared one date (11
# days of a 14-day period) and said nothing.
#
# This hook runs at EVERY session start, so the quiet cases carry more weight
# than the loud one. Two of them are the whole design:
#
#   - a recorded-dead slug that has since been RESEATED must be silent, or the
#     nudge repeats a fixed finding for a fortnight and trains its reader to
#     ignore it;
#   - every degraded input (absent, unreadable, malformed, wrong shape) must be
#     silent AND exit 0, because a broken reminder must never stop a session.

set -uo pipefail

DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../claude/hooks" && pwd)
HOOK="$DIR/nudge_council_roster.sh"
WORK=""
for base in "${TMPDIR:-}" /tmp/claude /tmp; do
    if [ -z "$base" ] || [ ! -d "$base" ] || [ ! -w "$base" ]; then
        continue
    fi
    WORK=$(mktemp -d -p "$base" 2>/dev/null) && break
done
[ -n "$WORK" ] || { echo "cannot make a temp dir"; exit 1; }
trap 'chmod -R u+rwX "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT

FEATURES="$WORK/features.conf"
printf 'nudges.council-roster = on\n' > "$FEATURES"
export CLAUDE_HOOK_FEATURES_FILE="$FEATURES"

fails=0
TODAY=$(date -u +%Y-%m-%d)
FRESH=$(date -u +%Y-%m-%dT%H:%M:%SZ)
LONG_AGO=$(date -u -d '90 days ago' +%Y-%m-%d 2>/dev/null || date -u -v-90d +%Y-%m-%d)

# A config the hook can read: $1 is the `reviewed` stamp, $2 the seat slug.
write_config() {
    cat > "$WORK/config.toml" <<EOF
[council]
chair = "anthropic/claude-fable-5"
review_days = 14
reviewed = "$1"
seats = [
  { alias = "gpt", slug = "openai/gpt-6-astra", family = "openai", score = 166.3, basis = "eci" },
  { alias = "qwen", slug = "$2", family = "qwen", score = 155.2, basis = "eci" },
]

[[models]]
alias = "extra"
slug = "vendor/off-roster"
EOF
}

# A liveness verdict: every argument is a "role:alias:slug" dead entry.
write_liveness() {
    local first=1 entry role alias slug
    {
        printf '{\n  "checked_at": "%s",\n  "catalog": 412,\n  "dead": [' "$FRESH"
        for entry in "$@"; do
            IFS=: read -r role alias slug <<< "$entry"
            [ "$first" = 1 ] || printf ','
            first=0
            printf '\n    {"role": "%s", "alias": "%s", "slug": "%s"}' \
                "$role" "$alias" "$slug"
        done
        printf '\n  ]\n}\n'
    } > "$WORK/liveness.json"
}

# Both paths are ALWAYS overridden. An unset COUNCIL_LIVENESS reads this box's
# real state file, so "missing file" has to mean a path inside $WORK, never an
# unset variable -- otherwise the test passes or fails on local state.
run_hook() {
    local out status
    out=$(COUNCIL_CONFIG="${CFG_PATH:-$WORK/config.toml}" \
          COUNCIL_LIVENESS="${LIVE_PATH:-$WORK/liveness.json}" \
          "$HOOK" < /dev/null 2>/dev/null)
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'FAIL  exit %d, a nudge must always exit 0\n' "$status"
        fails=$((fails + 1))
    fi
    printf '%s' "$out"
}

expect_fires() {
    local label=$1 needle=$2 out
    out=$(run_hook)
    if printf '%s' "$out" | grep -q -- "$needle"; then
        printf 'ok    fires:  %s\n' "$label"
    else
        printf 'FAIL  expected a nudge naming %s: %s\n' "$needle" "$label"
        printf '      got: %s\n' "${out:-<silence>}"
        fails=$((fails + 1))
    fi
}

expect_silent() {
    local label=$1 out
    out=$(run_hook)
    if [ -z "$out" ]; then
        printf 'ok    silent: %s\n' "$label"
    else
        printf 'FAIL  fired, expected silence: %s\n' "$label"
        printf '      got: %s\n' "$out"
        fails=$((fails + 1))
    fi
}

echo "--- healthy ---"
write_config "$TODAY" "qwen/qwen3.8-max-0902"
write_liveness
expect_silent 'fresh review date, no dead slug'

echo "--- the incident: a seat retired from the catalogue ---"
write_liveness "seat:qwen:qwen/qwen3.8-max-0902"
expect_fires 'dead seat is named' 'qwen/qwen3.8-max-0902'
expect_fires 'dead seat says what to run' 'council refresh --apply'
expect_fires 'dead seat names its alias' 'qwen'
# A fresh review date must not suppress the dead seat: the whole failure was a
# date saying "reviewed recently" while a seat was unusable.
expect_fires 'dead seat fires inside the review window' 'no longer in the OpenRouter'

echo "--- reconciled against the live config ---"
# Reseated: the verdict still names the retired slug, the config no longer does.
write_config "$TODAY" "qwen/qwen3.8-max-0902"
write_liveness "seat:qwen:qwen/qwen3.8-retired"
expect_silent 'a recorded-dead slug that is no longer configured'
write_liveness "chair:chair:anthropic/claude-fable-5"
expect_fires 'a dead CHAIR is reported too' 'anthropic/claude-fable-5'
# `council refresh --apply` rewrites only the auto-managed seats block, so
# telling a reader to run it for the chair sends them to a command that answers
# "roster matches the indices" and leaves the chair dead.
expect_fires 'a dead chair says to hand-edit the config' 'openrouter-models.toml'
write_liveness "models:extra:vendor/off-roster"
expect_fires 'a dead off-roster model is reported too' 'vendor/off-roster'
expect_fires 'a dead off-roster model says to hand-edit' 'openrouter-models.toml'
write_liveness "seat:qwen:qwen/qwen3.8-max-0902"
expect_fires 'a dead SEAT says to refresh' 'council refresh --apply'
out=$(run_hook)
if printf '%s' "$out" | grep -q 'openrouter-models.toml'; then
    printf 'FAIL  a dead seat should not send the reader to a hand edit\n'
    fails=$((fails + 1))
else
    printf 'ok    advice: a dead seat gets the refresh, not the hand edit\n'
fi

echo "--- the overdue-date branch still works ---"
write_config "$LONG_AGO" "qwen/qwen3.8-max-0902"
write_liveness
expect_fires 'overdue review date' 'last reviewed 9'
expect_fires 'overdue names the check command' 'council roster --check'
write_liveness "seat:qwen:qwen/qwen3.8-max-0902"
expect_fires 'overdue AND dead: the dead seat is reported' 'qwen/qwen3.8-max-0902'
expect_fires 'overdue AND dead: the date is reported' 'last reviewed 9'
out=$(run_hook)
if [ "$(printf '%s' "$out" | grep -bo 'no longer in the OpenRouter' | head -1 | cut -d: -f1)" \
     -lt "$(printf '%s' "$out" | grep -bo 'last reviewed' | head -1 | cut -d: -f1)" ]; then
    printf 'ok    order:  the dead seat leads, the date follows\n'
else
    printf 'FAIL  the overdue date came before the dead seat\n'
    fails=$((fails + 1))
fi

echo "--- degraded inputs are silent ---"
write_config "$TODAY" "qwen/qwen3.8-max-0902"
LIVE_PATH="$WORK/absent.json" expect_silent 'missing liveness file'
printf 'not json at all {' > "$WORK/liveness.json"
expect_silent 'malformed liveness JSON'
printf '[1, 2, 3]\n' > "$WORK/liveness.json"
expect_silent 'liveness JSON of the wrong shape'
printf '{"dead": "qwen/qwen3.8-max-0902"}\n' > "$WORK/liveness.json"
expect_silent 'liveness dead field is not a list'
printf '{"checked_at": "not-a-date", "dead": [{"slug": "qwen/qwen3.8-max-0902"}]}\n' \
    > "$WORK/liveness.json"
expect_fires 'an unparseable checked_at still names the seat' 'qwen/qwen3.8-max-0902'

if [ "$(id -u)" = 0 ]; then
    printf 'skip  unreadable liveness file (running as root)\n'
else
    write_liveness "seat:qwen:qwen/qwen3.8-max-0902"
    chmod 000 "$WORK/liveness.json"
    expect_silent 'unreadable liveness file'
    chmod 644 "$WORK/liveness.json"
fi

write_liveness "seat:qwen:qwen/qwen3.8-max-0902"
CFG_PATH="$WORK/absent.toml" expect_silent 'missing config'
printf 'this is [not toml\n' > "$WORK/broken.toml"
CFG_PATH="$WORK/broken.toml" expect_silent 'malformed config TOML'
printf '[council]\nseats = []\n' > "$WORK/nostamp.toml"
CFG_PATH="$WORK/nostamp.toml" expect_silent 'config with no reviewed stamp and no seats'

echo "--- no python3 on PATH ---"
# A PATH holding everything the hook shells out to EXCEPT python3. Emptying
# PATH outright would only prove that `#!/usr/bin/env bash` cannot find bash.
mkdir -p "$WORK/bin"
for tool in dirname cat; do
    ln -sf "$(command -v "$tool")" "$WORK/bin/$tool"
done
# An absolute interpreter path, because bash applies the PATH assignment to the
# lookup of the very command it prefixes -- a bare `bash` here exits 127 without
# the hook ever running, which reads exactly like the failure being tested for.
BASH_BIN=$(command -v bash)
out=$(PATH="$WORK/bin" COUNCIL_CONFIG="$WORK/config.toml" \
      COUNCIL_LIVENESS="$WORK/liveness.json" "$BASH_BIN" "$HOOK" < /dev/null 2>/dev/null)
status=$?
if [ -z "$out" ] && [ "$status" -eq 0 ]; then
    printf 'ok    silent: no python3 on PATH, exit 0\n'
else
    printf 'FAIL  no python3: exit %d, output %s\n' "$status" "${out:-<silence>}"
    fails=$((fails + 1))
fi

echo "--- the feature flag gates the whole hook ---"
printf 'nudges.council-roster = off\n' > "$FEATURES"
write_config "$LONG_AGO" "qwen/qwen3.8-max-0902"
write_liveness "seat:qwen:qwen/qwen3.8-max-0902"
expect_silent 'flag off, with both a dead seat and an overdue date'
printf 'nudges = off\n' > "$FEATURES"
expect_silent 'the nudges family is off wholesale'
printf 'nudges.council-roster = on\n' > "$FEATURES"

echo
if [ "$fails" -eq 0 ]; then
    echo "all checks passed"
else
    echo "$fails check(s) failed"
fi
exit "$fails"
