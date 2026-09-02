#!/usr/bin/env bash
# Tests the approval-classifier, context and reasoning-effort statusline segments.
#
# The Rust binary is the only implementation: claude/statusline.sh was retired on
# 2026-08-30. Until then this file compared the two renderers against each other,
# so a case whose expectation was "whatever the other one printed" needed no
# literal. Every such case is now pinned to an explicit expected string, ANSI
# included, derived from tools/claude-tools/src/statusline.rs and confirmed
# against the binary. Colour is part of the contract (dim vs yellow effort,
# green/yellow/red ctx), so the raw assertions must keep their escape codes.
#
# Hermetic: uses a fake HOME (the health file is read relative to $HOME) and an
# explicit DOT_DIR, so no real cache or machine conf is touched.
#
# Run: bash tests/test_statusline_classifier.sh

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# Deliberately the DEPLOYED dispatcher, not tools/claude-tools/target/release/.
# settings.json runs bare `claude-tools statusline`, which resolves to this path
# via custom_bins on PATH. Testing the fresh build instead let a stale committed
# asset ship with no classifier segment while this suite stayed green
# (2026-07-21 → 2026-08-03). If this fails, the committed asset is behind the
# source: rebuild it per scripts/check-claude-tools-fresh.sh.
RUST_BIN="$REPO/custom_bins/claude-tools"
PASS=0
FAIL=0

TMP_ROOT="$REPO/tmp"
mkdir -p "$TMP_ROOT"
FAKE=$(mktemp -d "$TMP_ROOT/statusline.XXXXXX") || {
    echo "could not create fixture dir under $TMP_ROOT" >&2; exit 1; }
[[ -n "$FAKE" && -d "$FAKE" ]] || exit 1
trap 'rm -rf "$FAKE"' EXIT

mkdir -p "$FAKE/.cache/claude" "$FAKE/dot/config" "$FAKE/tmp"
HEALTH="$FAKE/.cache/claude/approval-classifier-health.json"

# A machine conf with a blocked key ahead of the active one, so the label test
# also proves `!`-blocked entries are skipped rather than reported as active.
printf '%s\n' \
    '# machine conf' \
    'ANTHROPIC_API_KEY = !ANTHROPIC_API_KEY - blockedone' \
    'ANTHROPIC_API_KEY = ANTHROPIC_API_KEY - mats' \
    > "$FAKE/dot/config/secrets-global.conf"

STATUS_INPUT='{"model":{"display_name":"Opus"},"workspace":{"current_dir":"'"$FAKE"'"},"cost":{"total_duration_ms":0},"context_window":{"used_percentage":0}}'

# Session-line fixtures for the context/effort segments, swapped in for
# STATUS_INPUT by render_rust_with().
session_input() {  # extra_json (merged over the context_window/effort defaults)
    printf '{"model":{"display_name":"Opus"},"workspace":{"current_dir":"%s"},"cost":{"total_duration_ms":0},%s}' \
        "$FAKE" "$1"
}

write_health() {  # backend, age_seconds
    local backend="$1" age="${2:-0}"
    python3 - "$HEALTH" "$backend" "$age" <<'PY'
import json, sys, time
path, backend, age = sys.argv[1], sys.argv[2], int(sys.argv[3])
with open(path, "w") as f:
    json.dump({"backend": backend, "detail": "", "ts": int(time.time()) - age}, f)
PY
}

# Strip ANSI so text assertions read cleanly; the raw form is kept for the
# colour assertions. The ESC byte is embedded literally rather than written as
# `\x1b`, which GNU sed interprets but BSD sed passes through as the letter x —
# on Darwin the escapes would survive and every comparison below would mismatch.
ESC=$(printf '\033')
strip_ansi() { sed -e "s/${ESC}\[[0-9;]*m//g"; }

# TMPDIR points at an empty fixture dir and CLAUDE_CODE_OAUTH_TOKEN is blanked,
# so neither the usage cache nor a live fetch can vary with whoever runs this.
# TMPDIR must be a real directory rather than "": the renderer falls back to the
# shared /tmp/claude when the var is unset, which is another machine's state.
render_rust() {
    printf '%s' "$STATUS_INPUT" | \
        env HOME="$FAKE" DOT_DIR="$FAKE/dot" TMPDIR="$FAKE/tmp" \
        CLAUDE_CODE_OAUTH_TOKEN="" "$RUST_BIN" statusline 2>/dev/null
}

# The classifier segment is the only part of the line that mentions "auto".
classifier_segment() {
    strip_ansi | tr '·' '\n' | grep -o 'auto[^ ]*\( ([^)]*)\)\?' | head -1 | sed 's/[[:space:]]*$//'
}

# Same segment with ANSI intact. Stripping first would let a colour regression —
# a degraded state rendered dim instead of red — pass unnoticed.
classifier_segment_raw() {
    tr '·' '\n' | grep 'auto' | head -1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

check() {
    local desc="$1" got="$2" want="$3"
    if [[ "$got" == "$want" ]]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL: %s\n  wanted: [%s]\n  got:    [%s]\n' "$desc" "$want" "$got"
    fi
}

# Fail, never skip. An earlier version exited 0 here, so a missing binary read
# as a pass — the same silent-green failure mode as testing the wrong binary.
[[ -x "$RUST_BIN" ]] || {
    echo "FAIL: $RUST_BIN missing or not executable" >&2
    exit 1
}

echo "=== the deployed claude-tools is the platform dispatcher, not a raw binary ==="
# custom_bins/claude-tools must stay a text wrapper that execs the arch-suffixed
# asset. It has been clobbered with a raw ELF twice (e7c2de0 fixed it, eabeba2
# reintroduced it) by a rebuild copied to the wrong path. Two bytes catch it.
check "dispatcher is a shell wrapper" "$(head -c2 "$RUST_BIN")" '#!'

echo "=== healthy API renders a minimal segment naming the active key ==="
# `-ant` is the backend, not part of the key label: a key that happened to be
# called "sub" must not be confusable with the degraded subscription state.
write_health api
check "api shows the key label" "$(render_rust | classifier_segment)" "auto-ant:mats"

echo "=== degraded to subscription is visible but does NOT name a key ==="
write_health subscription
check "subscription" "$(render_rust | classifier_segment)" "auto-sub (api down)"

echo "=== both backends dead ==="
write_health dead
check "dead" "$(render_rust | classifier_segment)" "auto"

echo "=== a stale health file is treated as absent, not as news ==="
write_health subscription 25000   # ~7h, past the 6h cutoff
check "stale renders nothing" "$(render_rust | classifier_segment)" ""

echo "=== past 15m the recorded backend is reported as unknown, not as fact ==="
# The regression this guards: write_health() runs only on the classify() path, so
# a session of fast-path-only tool calls freezes this file. On 2026-08-05 one
# transient API read timeout left `dead` rendering red for over two hours.
for backend in api subscription dead; do
    write_health "$backend" 7200   # 2h — the actual incident duration
    check "$backend at 2h is unknown" "$(render_rust | classifier_segment)" "auto?"
done

echo "=== the 15m cutoff separates the two states, from both sides ==="
# Deliberately NOT 900/901. write_health stamps `now - age`, but the renderer
# reads the clock again a moment later, so an exact-boundary fixture flips to
# the wrong side whenever the two land in different wall-clock seconds — the
# assertion would fail a few times an hour for no reason. The renderer exposes
# no clock to inject, so the honest fix is margin, not precision: 60s either
# side is unambiguous while still pinning the cutoff between them.
write_health dead 840             # 14m — comfortably fresh
check "840s is fresh" "$(render_rust | classifier_segment)" "auto"
write_health dead 960             # 16m — comfortably stale
check "960s is stale" "$(render_rust | classifier_segment)" "auto?"

echo "=== every stale backend renders the same dim marker, never a loud one ==="
# Previously a cross-implementation comparison; now the expected bytes are
# spelled out. Stale must recede rather than shout like `dead`, and all three
# backends must collapse to the SAME marker — a stale `api` that kept its own
# colour would read as a live healthy state.
STALE_RAW=$'\033[2mauto?\033[0m'
for backend in api subscription dead; do
    write_health "$backend" 7200
    check "stale $backend is the dim marker" "$(render_rust | classifier_segment_raw)" "$STALE_RAW"
done

echo "=== an unrecognised backend renders nothing at EITHER age ==="
# Without this the staleness tier would happily print an authoritative-looking
# `auto?` for a value the renderer cannot interpret.
write_health someday-backend 60
check "unknown fresh" "$(render_rust | classifier_segment)" ""
write_health someday-backend 7200
check "unknown stale" "$(render_rust | classifier_segment)" ""

echo "=== no health file at all renders nothing ==="
rm -f "$HEALTH"
check "absent renders nothing" "$(render_rust | classifier_segment)" ""

echo "=== a conf with no description degrades to a bare marker ==="
printf 'ANTHROPIC_API_KEY = ANTHROPIC_API_KEY\n' > "$FAKE/dot/config/secrets-global.conf"
write_health api
check "bare marker" "$(render_rust | classifier_segment)" "auto-ant"

# --- the "[global]" name marker ---------------------------------------------
# The statusline matches the env name exactly, so a " [global]"-suffixed line
# would silently drop the account label — the failure would be a missing suffix
# on the statusline, which nobody would read as a bug. Assert every conf shape
# the marker can produce.

echo "=== tagged: a marked line still renders its label ==="
write_health api
printf 'ANTHROPIC_API_KEY [global] = ANTHROPIC_API_KEY - mats\n' \
    > "$FAKE/dot/config/secrets-global.conf"
check "tagged" "$(render_rust | classifier_segment)" "auto-ant:mats"

echo "=== blocked + tagged: the marker does not resurrect a blocked key ==="
printf '%s\n' \
    'ANTHROPIC_API_KEY [global] = !ANTHROPIC_API_KEY - blockedone' \
    'ANTHROPIC_API_KEY [global] = ANTHROPIC_API_KEY - mats' \
    > "$FAKE/dot/config/secrets-global.conf"
check "blocked+tagged" "$(render_rust | classifier_segment)" "auto-ant:mats"

echo "=== repeated: a partially-tagged name resolves by preference order ==="
printf '%s\n' \
    'ANTHROPIC_API_KEY = !ANTHROPIC_API_KEY - blockedone' \
    'ANTHROPIC_API_KEY [global] = ANTHROPIC_API_KEY - mats' \
    > "$FAKE/dot/config/secrets-global.conf"
check "repeated" "$(render_rust | classifier_segment)" "auto-ant:mats"

echo "=== a value-less marker line is skipped, not read as an empty label ==="
printf '%s\n' \
    'ANTHROPIC_API_KEY [global] =' \
    'ANTHROPIC_API_KEY = ANTHROPIC_API_KEY - mats' \
    > "$FAKE/dot/config/secrets-global.conf"
check "value-less marker skipped" "$(render_rust | classifier_segment)" "auto-ant:mats"

echo "=== untagged: unchanged behaviour ==="
printf 'ANTHROPIC_API_KEY = ANTHROPIC_API_KEY - mats\n' \
    > "$FAKE/dot/config/secrets-global.conf"
check "untagged" "$(render_rust | classifier_segment)" "auto-ant:mats"

echo "=== a conf naming no usable ANTHROPIC key still renders the bare marker ==="
# The two shapes that resolve to no label at all: a marker-only line standing
# alone, and a conf whose only entry is a different env name. Both must fall
# back to `auto-ant` rather than emitting a stray colon or an empty label.
printf 'ANTHROPIC_API_KEY [global] =\n' > "$FAKE/dot/config/secrets-global.conf"
check "lone value-less marker" "$(render_rust | classifier_segment)" "auto-ant"
printf 'OPENAI_API_KEY [global] = OPENAI_API_KEY - tomek\n' \
    > "$FAKE/dot/config/secrets-global.conf"
check "no ANTHROPIC entry" "$(render_rust | classifier_segment)" "auto-ant"

echo "=== each fresh backend renders its own colour, ANSI included ==="
# Healthy recedes (dim), subscription warns (yellow, with a dim parenthetical),
# dead shouts (red, with the marker emoji). Pinning the full byte sequence is
# what keeps a palette change from silently flattening the three states into
# one — the job the cross-implementation comparison used to do.
printf '%s\n' \
    'ANTHROPIC_API_KEY = !ANTHROPIC_API_KEY - blockedone' \
    'ANTHROPIC_API_KEY = ANTHROPIC_API_KEY - mats' \
    > "$FAKE/dot/config/secrets-global.conf"
write_health api
check "fresh api is dim" "$(render_rust | classifier_segment_raw)" \
    $'\033[2mauto-ant:mats\033[0m'
write_health subscription
check "fresh subscription is yellow" "$(render_rust | classifier_segment_raw)" \
    $'\033[33mauto-sub\033[0m \033[2m(api down)\033[0m'
write_health dead
check "fresh dead is red" "$(render_rust | classifier_segment_raw)" \
    $'\033[31m🔴auto\033[0m'


# ---------------------------------------------------------------------------
# Context-token and reasoning-effort segments
# ---------------------------------------------------------------------------
# Both read straight from the statusline input JSON, so they are driven by
# fixtures rather than by files on disk.

render_rust_with() {
    printf '%s' "$1" | env HOME="$FAKE" DOT_DIR="$FAKE/dot" TMPDIR="$FAKE/tmp" \
        CLAUDE_CODE_OAUTH_TOKEN="" "$RUST_BIN" statusline 2>/dev/null
}

# One ·-joined segment selected by prefix, ANSI stripped.
segment() { strip_ansi | tr '·' '\n' | grep -o "$1.*" | head -1 | sed 's/[[:space:]]*$//'; }

# Same, ANSI intact.
segment_raw() { tr '·' '\n' | grep "$1" | head -1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }

# The health file is gone by now, so no classifier segment interferes with these.
rm -f "$HEALTH"

# desc, json_body, prefix, expected
check_segment() {
    local desc="$1" body="$2" prefix="$3" want="$4"
    local input; input=$(session_input "$body")
    check "$desc" "$(render_rust_with "$input" | segment "$prefix")" "$want"
}

echo "=== context shows absolute tokens against the window size ==="
check_segment "tokens/size/pct" \
    '"context_window":{"used_percentage":61.7,"total_input_tokens":123456,"context_window_size":200000}' \
    'ctx:' 'ctx:123k/200k (62%)'

echo "=== percentage is rounded, not truncated ==="
check_segment "61.7 rounds to 62" \
    '"context_window":{"used_percentage":61.7,"total_input_tokens":1000,"context_window_size":200000}' \
    'ctx:' 'ctx:1k/200k (62%)'

echo "=== a million-token window renders as M, not as 1000k ==="
check_segment "1M window" \
    '"context_window":{"used_percentage":85,"total_input_tokens":850000,"context_window_size":1000000}' \
    'ctx:' 'ctx:850k/1.0M (85%)'

echo "=== the k→M boundary: nothing may ever render as '1000k' ==="
# 999500 is where the k branch stops. Below it the value still rounds to 999k;
# at and above it the k form would read "1000k", so it promotes to M instead.
check_segment "999499 stays k" \
    '"context_window":{"used_percentage":50,"total_input_tokens":999499,"context_window_size":2000000}' \
    'ctx:' 'ctx:999k/2.0M (50%)'
check_segment "999500 promotes to M" \
    '"context_window":{"used_percentage":50,"total_input_tokens":999500,"context_window_size":2000000}' \
    'ctx:' 'ctx:1.0M/2.0M (50%)'
check_segment "999999 promotes to M" \
    '"context_window":{"used_percentage":50,"total_input_tokens":999999,"context_window_size":2000000}' \
    'ctx:' 'ctx:1.0M/2.0M (50%)'
check_segment "exactly 1000000" \
    '"context_window":{"used_percentage":50,"total_input_tokens":1000000,"context_window_size":2000000}' \
    'ctx:' 'ctx:1.0M/2.0M (50%)'

echo "=== the thousand boundary and sub-thousand counts render raw ==="
check_segment "999 tokens stays raw" \
    '"context_window":{"used_percentage":1,"total_input_tokens":999,"context_window_size":200000}' \
    'ctx:' 'ctx:999/200k (1%)'
check_segment "845 tokens" \
    '"context_window":{"used_percentage":1,"total_input_tokens":845,"context_window_size":200000}' \
    'ctx:' 'ctx:845/200k (1%)'
check_segment "1499 rounds down to 1k" \
    '"context_window":{"used_percentage":1,"total_input_tokens":1499,"context_window_size":200000}' \
    'ctx:' 'ctx:1k/200k (1%)'
check_segment "1500 rounds up to 2k" \
    '"context_window":{"used_percentage":1,"total_input_tokens":1500,"context_window_size":200000}' \
    'ctx:' 'ctx:2k/200k (1%)'

echo "=== colour thresholds: green under 70, yellow at 70, red at 90 ==="
threshold_colour() {  # pct -> the ANSI colour code of the ctx segment
    render_rust_with "$(session_input "\"context_window\":{\"used_percentage\":$1,\"total_input_tokens\":1000,\"context_window_size\":200000}")" \
        | segment_raw 'ctx:' | grep -o $'\033\[[0-9;]*m' | head -1
}
check "green below 70"  "$(threshold_colour 69)" "$(printf '\033[32m')"
check "yellow at 70"    "$(threshold_colour 70)" "$(printf '\033[33m')"
check "yellow below 90" "$(threshold_colour 89)" "$(printf '\033[33m')"
check "red at 90"       "$(threshold_colour 90)" "$(printf '\033[31m')"

echo "=== the whole ctx segment is one colour span, opened and closed ==="
# threshold_colour reads only the FIRST escape code, so it would still pass if
# the segment gained a stray span or lost its reset. This pins the full bytes.
check "ctx segment bytes" \
    "$(render_rust_with "$(session_input '"context_window":{"used_percentage":61.7,"total_input_tokens":123456,"context_window_size":200000}')" | segment_raw 'ctx:')" \
    $'\033[32mctx:123k/200k (62%)\033[0m'

echo "=== degradation: missing window size drops the denominator ==="
check_segment "no window size" \
    '"context_window":{"used_percentage":30,"total_input_tokens":60000}' \
    'ctx:' 'ctx:60k (30%)'

echo "=== degradation: missing token count falls back to the percentage alone ==="
check_segment "no token count" \
    '"context_window":{"used_percentage":30,"context_window_size":200000}' \
    'ctx:' 'ctx:30%'

echo "=== zero percent still renders nothing at all ==="
check_segment "zero percent" \
    '"context_window":{"used_percentage":0,"total_input_tokens":123456,"context_window_size":200000}' \
    'ctx:' ''

# The gate is the ROUNDED percentage, not the raw JSON string: `.round() as u64`
# also saturates a negative to 0, so both 0.4 and -5 must render nothing rather
# than "ctx:0%" or "ctx:-4%". Both were live divergences before this.
check_segment "0.4 rounds to zero and hides" \
    '"context_window":{"used_percentage":0.4,"total_input_tokens":123456,"context_window_size":200000}' \
    'ctx:' ''
check_segment "negative percentage hides" \
    '"context_window":{"used_percentage":-5,"total_input_tokens":123456,"context_window_size":200000}' \
    'ctx:' ''
check_segment "0.6 rounds up and shows" \
    '"context_window":{"used_percentage":0.6,"total_input_tokens":123456,"context_window_size":200000}' \
    'ctx:' 'ctx:123k/200k (1%)'

echo "=== M formatting rounds on the value, not on the decimal literal ==="
# 1.05 looks like a rounding tie but the nearest double is 1.05000000000000004,
# so a correctly-rounding {:.1} lands on 1.1M. This case catches a formatter
# that rounds the literal instead of the value it holds.
check_segment "1050000 tokens" \
    '"context_window":{"used_percentage":50,"total_input_tokens":1050000,"context_window_size":2000000}' \
    'ctx:' 'ctx:1.1M/2.0M (50%)'
check_segment "1500000 tokens" \
    '"context_window":{"used_percentage":50,"total_input_tokens":1500000,"context_window_size":2000000}' \
    'ctx:' 'ctx:1.5M/2.0M (50%)'
check_segment "1250000 tokens" \
    '"context_window":{"used_percentage":50,"total_input_tokens":1250000,"context_window_size":2000000}' \
    'ctx:' 'ctx:1.2M/2.0M (50%)'

# Reasoning effort has no segment of its own — it renders as a parenthesised
# suffix inside the model bracket, so every case below is asserted against the
# model segment. MODEL is the prefix as a BRE: an unescaped "[" would open a
# bracket expression in grep and match the wrong thing.
MODEL='\[Opus'

echo "=== effort level is trimmed at the edges, matching Rust str::trim ==="
check_segment "padded effort level" \
    '"context_window":{"used_percentage":0},"effort":{"level":"  high  "}' \
    "$MODEL" '[Opus (high)]'
check_segment "whitespace-only effort level" \
    '"context_window":{"used_percentage":0},"effort":{"level":"   "}' \
    "$MODEL" '[Opus]'
check_segment "null effort level" \
    '"context_window":{"used_percentage":0},"effort":{"level":null}' \
    "$MODEL" '[Opus]'

echo "=== reasoning effort renders inside the model bracket ==="
check_segment "effort high" \
    '"context_window":{"used_percentage":0},"effort":{"level":"high"}' \
    "$MODEL" '[Opus (high)]'

check_segment "effort xhigh" \
    '"context_window":{"used_percentage":0},"effort":{"level":"xhigh"}' \
    "$MODEL" '[Opus (xhigh)]'

check_segment "effort max" \
    '"context_window":{"used_percentage":0},"effort":{"level":"max"}' \
    "$MODEL" '[Opus (max)]'

echo "=== xhigh is yellow while high is dim — the whole point of the colour rule ==="
# The bracket is blue and reopens blue at normal intensity after the effort span,
# which is what
# makes "[Opus " and "]" share a colour while the suffix does not. Pinning the
# full bytes covers both the effort colour and the bracket it sits inside.
check "xhigh effort bytes" \
    "$(render_rust_with "$(session_input '"context_window":{"used_percentage":0},"effort":{"level":"xhigh"}')" | segment_raw "$MODEL")" \
    $'\033[34m[Opus \033[33m(xhigh)\033[22;34m]\033[0m'
check "high effort bytes" \
    "$(render_rust_with "$(session_input '"context_window":{"used_percentage":0},"effort":{"level":"high"}')" | segment_raw "$MODEL")" \
    $'\033[34m[Opus \033[2m(high)\033[22;34m]\033[0m'
# `max` shares the yellow arm with `xhigh` in format_effort_suffix, and shared
# arms are where an untested sibling hides: the level list could be narrowed to
# xhigh alone and every other assertion here would still pass.
check "max effort bytes" \
    "$(render_rust_with "$(session_input '"context_window":{"used_percentage":0},"effort":{"level":"max"}')" | segment_raw "$MODEL")" \
    $'\033[34m[Opus \033[33m(max)\033[22;34m]\033[0m'

echo "=== a model without reasoning effort keeps a bare bracket and no stray space ==="
no_effort=$(session_input '"context_window":{"used_percentage":0}')
check_segment "effort absent" '"context_window":{"used_percentage":0}' "$MODEL" '[Opus]'
check "no trailing separator" "$(render_rust_with "$no_effort" | strip_ansi | sed -n 2p | sed 's/[[:space:]]*$//')" "[Opus]"
check "bare bracket bytes" "$(render_rust_with "$no_effort" | segment_raw "$MODEL")" \
    $'\033[34m[Opus]\033[0m'

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
