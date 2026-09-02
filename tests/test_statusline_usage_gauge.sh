#!/usr/bin/env bash
# Tests the single-glyph usage gauge on line 3 of the statusline.
#
# The Rust binary is the only implementation: claude/statusline.sh was retired on
# 2026-08-30. The gauge quantises a percentage to one of five circle glyphs in
# tools/claude-tools/src/usage.rs::gauge_level, and every expectation below is a
# literal — asserting the renderer against its own glyph table would hold for any
# table the constant is changed to.
#
# Hermetic: a fake HOME (no .claude.json, no .credentials.json → no account
# lookup, no OAuth token, no network) plus a fake TMPDIR holding a fresh usage
# cache, which the renderer reads as the fast path. The fixtures carry no
# `resets_at`, so pace and countdown are absent and the rendered line is fully
# deterministic.
#
# Run: bash tests/test_statusline_usage_gauge.sh

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# Deliberately the DEPLOYED dispatcher, not tools/claude-tools/target/release/.
# settings.json runs bare `claude-tools statusline`; testing the fresh build
# instead would let a stale committed asset ship while this suite stayed green.
RUST_BIN="$REPO/custom_bins/claude-tools"
PASS=0
FAIL=0

TMP_ROOT="$REPO/tmp"
mkdir -p "$TMP_ROOT"
FAKE=$(mktemp -d "$TMP_ROOT/usagegauge.XXXXXX") || {
    echo "could not create fixture dir under $TMP_ROOT" >&2; exit 1; }
[[ -n "$FAKE" && -d "$FAKE" ]] || exit 1
trap 'rm -rf "$FAKE"' EXIT

mkdir -p "$FAKE/home" "$FAKE/tmp"
CACHE="$FAKE/tmp/claude-statusline-usage.json"

STATUS_INPUT='{"model":{"display_name":"Opus"},"workspace":{"current_dir":"'"$FAKE"'"},"cost":{"total_duration_ms":0},"context_window":{"used_percentage":0}}'

write_cache() {  # five_pct, seven_pct
    printf '{"five_hour":{"utilization":%s},"seven_day":{"utilization":%s},"limits":[]}\n' \
        "$1" "$2" > "$CACHE"
}

# Strip ANSI SGR sequences so comparisons are about text, not colour. Colour is
# covered by the pace/pct tests in the classifier suite. The ESC byte is embedded
# literally rather than written as `\x1b`, which GNU sed interprets but BSD sed
# passes through as the letter x — on Darwin the escapes would survive and every
# comparison below would mismatch.
ESC=$(printf '\033')
strip_ansi() { sed -E "s/${ESC}\[[0-9;]*m//g"; }

# Line 3 is the usage line (line 1 location, line 2 session).
usage_line() { sed -n '3p'; }

# CLAUDE_CODE_OAUTH_TOKEN is blanked rather than inherited, so "no network" is
# a property of this test rather than of whoever happens to run it. The renderer
# checks the env var before the keychain and the credentials file, and a real
# token here would let a live fetch replace the fixture.
render_rust() {
    printf '%s' "$STATUS_INPUT" | env HOME="$FAKE/home" TMPDIR="$FAKE/tmp" \
        CLAUDE_CODE_OAUTH_TOKEN="" "$RUST_BIN" statusline 2>/dev/null | strip_ansi | usage_line
}

check() {  # description, expected, actual
    # An empty expectation means the renderer produced no line 3 at all, which
    # would make every comparison below vacuously true. Fail instead.
    if [[ -z "$2" ]]; then
        FAIL=$((FAIL + 1))
        printf '  FAIL %s\n       rendered no usage line\n' "$1"
    elif [[ "$3" == "$2" ]]; then
        PASS=$((PASS + 1))
        printf '  ok   %s\n' "$1"
    else
        FAIL=$((FAIL + 1))
        printf '  FAIL %s\n       expected: %q\n       actual:   %q\n' "$1" "$2" "$3"
    fi
}

[[ -x "$RUST_BIN" ]] || {
    echo "FAIL: $RUST_BIN missing or not executable" >&2
    exit 1
}

echo "== gauge glyph boundaries =="
# Levels are round(pct/25) over ○ ◔ ◑ ◕ ● — boundaries at 12/13, 37/38,
# 62/63, 87/88. Each adjacent pair straddles one boundary.
#
# The 7d bucket is pinned at 50 (◑) throughout so a mistake in the 5h column
# cannot be masked by an identical mistake in the 7d column.
for case in "0:○" "12:○" "13:◔" "37:◔" "38:◑" "62:◑" "63:◕" "87:◕" "88:●" "100:●"; do
    pct="${case%%:*}"
    glyph="${case##*:}"
    write_cache "$pct" 50
    check "${pct}% renders $glyph" "5h $glyph ${pct}% · 7d ◑ 50%" "$(render_rust)"
done

echo "== mid-band percentages sit on the glyph they round to =="
# The boundary pairs above pin where the glyph CHANGES; these pin the interior
# of each band, so a level formula that drifted without moving a boundary — an
# off-by-one in the divisor, say — still fails. Previously these percentages
# were only compared against the retired bash renderer, with no literal.
for case in "1:○" "24:◔" "50:◑" "75:◕" "99:●"; do
    pct="${case%%:*}"
    glyph="${case##*:}"
    write_cache "$pct" 50
    check "${pct}% renders $glyph" "5h $glyph ${pct}% · 7d ◑ 50%" "$(render_rust)"
done

echo "== fractional utilization rounds half away from zero =="
# f64::round, not C's round-half-to-even: a utilization of 12.5 must render
# "13 ◔", not "12 ○". Half-integers are the only place the two rules differ, so
# these are the fixtures that pin which rule is in force — they caught a real
# divergence in the percentage AND the glyph together.
for case in "12.5:13:◔" "37.5:38:◑" "62.5:63:◕" "87.5:88:●" "0.5:1:○"; do
    raw="${case%%:*}"; rest="${case#*:}"
    want_pct="${rest%%:*}"; want_glyph="${rest##*:}"
    write_cache "$raw" 50
    check "${raw} → ${want_pct}% $want_glyph" \
        "5h $want_glyph ${want_pct}% · 7d ◑ 50%" "$(render_rust)"
done

echo "== the gauge is one glyph wide =="
# The point of the change: the usage line must not carry a 10-cell bar. Guards
# against a revert to the ●●●●●○○○○○ rendering, which the per-percentage
# assertions above would also catch — but only for the fixtures they name.
write_cache 24 50
line="$(render_rust)"
if [[ -z "$line" ]]; then
    FAIL=$((FAIL + 1))
    printf '  FAIL rendered no usage line\n'
elif [[ "$line" == *"●●"* || "$line" == *"○○"* ]]; then
    FAIL=$((FAIL + 1))
    printf '  FAIL line still contains a multi-cell bar: %q\n' "$line"
else
    PASS=$((PASS + 1))
    printf '  ok   line carries no multi-cell bar\n'
fi

echo
printf 'passed: %d  failed: %d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
