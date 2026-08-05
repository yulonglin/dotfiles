#!/usr/bin/env bash
# Tests the approval-classifier statusline segment in BOTH implementations.
#
# The Rust binary is what actually renders; claude/statusline.sh is the fallback.
# The point of this file is the final block: it asserts the two produce the same
# segment for the same health file. A test of only one of them would pass while
# the pair silently diverged — which is the exact failure the fallback exists to
# prevent.
#
# Hermetic: uses a fake HOME (both implementations read the health file relative
# to $HOME) and an explicit DOT_DIR, so no real cache or machine conf is touched.
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
BASH_SL="$REPO/claude/statusline.sh"
PASS=0
FAIL=0

TMP_ROOT="$REPO/tmp"
mkdir -p "$TMP_ROOT"
FAKE=$(mktemp -d "$TMP_ROOT/statusline.XXXXXX") || {
    echo "could not create fixture dir under $TMP_ROOT" >&2; exit 1; }
[[ -n "$FAKE" && -d "$FAKE" ]] || exit 1
trap 'rm -rf "$FAKE"' EXIT

mkdir -p "$FAKE/.cache/claude" "$FAKE/dot/config"
HEALTH="$FAKE/.cache/claude/approval-classifier-health.json"

# A machine conf with a blocked key ahead of the active one, so the label test
# also proves `!`-blocked entries are skipped rather than reported as active.
printf '%s\n' \
    '# machine conf' \
    'ANTHROPIC_API_KEY = !ANTHROPIC_API_KEY - blockedone' \
    'ANTHROPIC_API_KEY = ANTHROPIC_API_KEY - mats' \
    > "$FAKE/dot/config/secrets-global.conf"

STATUS_INPUT='{"model":{"display_name":"Opus"},"workspace":{"current_dir":"'"$FAKE"'"},"cost":{"total_duration_ms":0},"context_window":{"used_percentage":0}}'

# Session-line fixtures for the context/effort segments. Each is fed to both
# implementations by render_with(), which swaps it in for STATUS_INPUT.
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

# Strip ANSI so assertions read cleanly; keep the raw form for the parity check.
strip_ansi() { sed -e 's/\x1b\[[0-9;]*m//g'; }

render_rust() {
    printf '%s' "$STATUS_INPUT" | \
        env HOME="$FAKE" DOT_DIR="$FAKE/dot" "$RUST_BIN" statusline 2>/dev/null
}

render_bash() {
    printf '%s' "$STATUS_INPUT" | \
        env HOME="$FAKE" DOT_DIR="$FAKE/dot" bash "$BASH_SL" 2>/dev/null
}

# The classifier segment is the only part of the line that mentions "auto".
classifier_segment() {
    strip_ansi | tr '·' '\n' | grep -o 'auto[^ ]*\( ([^)]*)\)\?' | head -1 | sed 's/[[:space:]]*$//'
}

# Same segment with ANSI intact, so the parity check covers colour too. Stripping
# first would let the two implementations disagree on dim-vs-yellow and still pass.
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
check "rust: api shows the key label" "$(render_rust | classifier_segment)" "auto-ant:mats"
check "bash: api shows the key label" "$(render_bash | classifier_segment)" "auto-ant:mats"

echo "=== degraded to subscription is visible but does NOT name a key ==="
write_health subscription
check "rust: subscription" "$(render_rust | classifier_segment)" "auto-sub (api down)"
check "bash: subscription" "$(render_bash | classifier_segment)" "auto-sub (api down)"

echo "=== both backends dead ==="
write_health dead
check "rust: dead" "$(render_rust | classifier_segment)" "auto"
check "bash: dead" "$(render_bash | classifier_segment)" "auto"

echo "=== a stale health file is treated as absent, not as news ==="
write_health subscription 25000   # ~7h, past the 6h cutoff
check "rust: stale renders nothing" "$(render_rust | classifier_segment)" ""
check "bash: stale renders nothing" "$(render_bash | classifier_segment)" ""

echo "=== no health file at all renders nothing ==="
rm -f "$HEALTH"
check "rust: absent renders nothing" "$(render_rust | classifier_segment)" ""
check "bash: absent renders nothing" "$(render_bash | classifier_segment)" ""

echo "=== a conf with no description degrades to a bare marker ==="
printf 'ANTHROPIC_API_KEY = ANTHROPIC_API_KEY\n' > "$FAKE/dot/config/secrets-global.conf"
write_health api
check "rust: bare marker" "$(render_rust | classifier_segment)" "auto-ant"
check "bash: bare marker" "$(render_bash | classifier_segment)" "auto-ant"

echo "=== PARITY: both implementations agree byte for byte ==="
printf '%s\n' \
    'ANTHROPIC_API_KEY = !ANTHROPIC_API_KEY - blockedone' \
    'ANTHROPIC_API_KEY = ANTHROPIC_API_KEY - mats' \
    > "$FAKE/dot/config/secrets-global.conf"
for backend in api subscription dead; do
    write_health "$backend"
    r=$(render_rust | classifier_segment_raw)
    b=$(render_bash | classifier_segment_raw)
    check "parity ($backend, ANSI included)" "$b" "$r"
done


# ---------------------------------------------------------------------------
# Context-token and reasoning-effort segments
# ---------------------------------------------------------------------------
# Both read straight from the statusline input JSON, so they are driven by
# fixtures rather than by files on disk. Every case is asserted against BOTH
# implementations and then compared to each other with ANSI intact — the colour
# is part of the contract (dim vs yellow effort, green/yellow/red ctx).

render_rust_with() {
    printf '%s' "$1" | env HOME="$FAKE" DOT_DIR="$FAKE/dot" "$RUST_BIN" statusline 2>/dev/null
}

render_bash_with() {
    printf '%s' "$1" | env HOME="$FAKE" DOT_DIR="$FAKE/dot" bash "$BASH_SL" 2>/dev/null
}

# One ·-joined segment selected by prefix, ANSI stripped.
segment() { strip_ansi | tr '·' '\n' | grep -o "$1.*" | head -1 | sed 's/[[:space:]]*$//'; }

# Same, ANSI intact, for the parity comparison.
segment_raw() { tr '·' '\n' | grep "$1" | head -1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }

# The health file is gone by now (removed above), so no classifier segment
# interferes with these.
rm -f "$HEALTH"

# desc, json_body, prefix, expected
check_segment() {
    local desc="$1" body="$2" prefix="$3" want="$4"
    local input; input=$(session_input "$body")
    check "rust: $desc" "$(render_rust_with "$input" | segment "$prefix")" "$want"
    check "bash: $desc" "$(render_bash_with "$input" | segment "$prefix")" "$want"
    check "parity: $desc (ANSI included)" \
        "$(render_bash_with "$input" | segment_raw "$prefix")" \
        "$(render_rust_with "$input" | segment_raw "$prefix")"
}

echo "=== context shows absolute tokens against the window size ==="
check_segment "tokens/size/pct" \
    '"context_window":{"used_percentage":61.7,"total_input_tokens":123456,"context_window_size":200000}' \
    'ctx:' 'ctx:123k/200k (62%)'

echo "=== percentage is rounded, not truncated (the bash fallback used to truncate) ==="
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

# The gate is the ROUNDED percentage, not the raw JSON string. Rust reaches zero
# via `.round() as u64` — which also saturates a negative to 0 — so a fallback
# that tested the raw value for "0" would render "ctx:0%" and "ctx:-4%" where
# the primary renders nothing. Both cases were live divergences before this.
check_segment "0.4 rounds to zero and hides" \
    '"context_window":{"used_percentage":0.4,"total_input_tokens":123456,"context_window_size":200000}' \
    'ctx:' ''
check_segment "negative percentage hides" \
    '"context_window":{"used_percentage":-5,"total_input_tokens":123456,"context_window_size":200000}' \
    'ctx:' ''
check_segment "0.6 rounds up and shows" \
    '"context_window":{"used_percentage":0.6,"total_input_tokens":123456,"context_window_size":200000}' \
    'ctx:' 'ctx:123k/200k (1%)'

echo "=== M formatting agrees across the two float formatters ==="
# Rust's {:.1} and awk's %.1f must round the same double the same way.
# 1.05 looks like a rounding tie but the nearest double is 1.05000000000000004,
# so correctly-rounding formatters both land on 1.1M. This case exists to catch
# one of them rounding on the decimal literal instead of the value it holds.
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

echo "=== xhigh is yellow while high is dim — the whole point of the colour rule ==="
# The bracket itself is blue, so these count the effort colour specifically; the
# closing bracket re-opens blue, which is what makes "[Opus " and "]" match.
xhigh_raw=$(render_rust_with "$(session_input '"context_window":{"used_percentage":0},"effort":{"level":"xhigh"}')" | segment_raw "$MODEL")
high_raw=$(render_rust_with "$(session_input '"context_window":{"used_percentage":0},"effort":{"level":"high"}')" | segment_raw "$MODEL")
check "rust: xhigh is yellow" "$(printf '%s' "$xhigh_raw" | grep -c $'\033\[33m')" "1"
check "rust: high is dim"    "$(printf '%s' "$high_raw"  | grep -c $'\033\[2m')"  "1"

echo "=== the model bracket matches an absolute byte golden, not just the other impl ==="
# Every other assertion here is either ANSI-stripped or a rust-vs-bash
# comparison, so both implementations can be identically wrong and stay green.
# These pin the exact escape sequence. The closing "22;34" is load-bearing: SGR
# 34 alone sets the foreground without clearing the faint attribute, which left
# the closing bracket dim blue against a normal-blue opening one.
golden_bracket() {  # effort_json, expected_raw
    got_r=$(render_rust_with "$(session_input "\"context_window\":{\"used_percentage\":0}$1")" | segment_raw "$MODEL")
    got_b=$(render_bash_with "$(session_input "\"context_window\":{\"used_percentage\":0}$1")" | segment_raw "$MODEL")
    check "rust: raw bracket golden ${1:-<no effort>}" "$got_r" "$2"
    check "bash: raw bracket golden ${1:-<no effort>}" "$got_b" "$2"
}
golden_bracket ',"effort":{"level":"high"}'  "$(printf '\033[34m[Opus \033[2m(high)\033[22;34m]\033[0m')"
golden_bracket ',"effort":{"level":"xhigh"}' "$(printf '\033[34m[Opus \033[33m(xhigh)\033[22;34m]\033[0m')"
golden_bracket ''                            "$(printf '\033[34m[Opus]\033[0m')"

echo "=== a model without reasoning effort keeps a bare bracket and no stray space ==="
no_effort=$(session_input '"context_window":{"used_percentage":0}')
check_segment "effort absent" '"context_window":{"used_percentage":0}' "$MODEL" '[Opus]'
check "rust: no trailing separator" "$(render_rust_with "$no_effort" | strip_ansi | sed -n 2p | sed 's/[[:space:]]*$//')" "[Opus]"
check "bash: no trailing separator" "$(render_bash_with "$no_effort" | strip_ansi | sed -n 2p | sed 's/[[:space:]]*$//')" "[Opus]"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
