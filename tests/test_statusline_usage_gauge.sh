#!/usr/bin/env bash
# Tests the single-glyph usage gauge on line 3, in BOTH implementations.
#
# The Rust binary is what actually renders; claude/statusline.sh is the fallback.
# The gauge quantises a percentage to one of five circle glyphs, and the two
# implementations compute that level independently — Rust in
# tools/claude-tools/src/usage.rs::gauge_level, bash in build_bar(). A test of
# only one would pass while the pair silently disagreed at a boundary, which is
# precisely the drift the fallback exists to survive.
#
# Hermetic: a fake HOME (no .claude.json, no .credentials.json → no account
# lookup, no OAuth token, no network) plus a fake TMPDIR holding a fresh usage
# cache, which both implementations read as the fast path. The fixtures carry
# no `resets_at`, so pace and countdown are absent and the rendered line is
# fully deterministic.
#
# Two known divergences are deliberately NOT exercised here, both predating the
# gauge and both outside its scope: bash renders an absolute reset datetime
# where Rust renders a countdown, and a genuine 0%/0% account em-dashes in bash
# while Rust renders "5h ○ 0% · 7d ○ 0%". Every fixture below pins 7d at 50 —
# which also keeps a mistake in the 5h column from being masked by an identical
# mistake in the 7d one.
#
# Run: bash tests/test_statusline_usage_gauge.sh

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
# Deliberately the DEPLOYED dispatcher, not tools/claude-tools/target/release/.
# settings.json runs bare `claude-tools statusline`; testing the fresh build
# instead would let a stale committed asset ship while this suite stayed green.
RUST_BIN="$REPO/custom_bins/claude-tools"
BASH_SL="$REPO/claude/statusline.sh"
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
# covered by the pace/pct tests in the classifier suite.
strip_ansi() { sed -E 's/\x1b\[[0-9;]*m//g'; }

# Line 3 is the usage line (line 1 location, line 2 session).
usage_line() { sed -n '3p'; }

# CLAUDE_CODE_OAUTH_TOKEN is blanked rather than inherited, so "no network" is
# a property of this test rather than of whoever happens to run it. Both
# implementations check the env var before the keychain and the credentials
# file, and a real token here would let a live fetch replace the fixture.
render_rust() {
    printf '%s' "$STATUS_INPUT" | env HOME="$FAKE/home" TMPDIR="$FAKE/tmp" \
        CLAUDE_CODE_OAUTH_TOKEN="" "$RUST_BIN" statusline 2>/dev/null | strip_ansi | usage_line
}

render_bash() {
    printf '%s' "$STATUS_INPUT" | env HOME="$FAKE/home" TMPDIR="$FAKE/tmp" \
        CLAUDE_CODE_OAUTH_TOKEN="" bash "$BASH_SL" 2>/dev/null | strip_ansi | usage_line
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

echo "== gauge glyph boundaries =="
# Literal glyphs on both sides. Asserting the renderer against its own glyph
# table would hold for any table the constant is changed to.
# Levels are round(pct/25) over ○ ◔ ◑ ◕ ● — boundaries at 12/13, 37/38,
# 62/63, 87/88. Each pair straddles one boundary.
#
# The 7d bucket is pinned at 50 (◑) throughout so a mistake in the 5h column
# cannot be masked by an identical mistake in the 7d column.
for case in "0:○" "12:○" "13:◔" "37:◔" "38:◑" "62:◑" "63:◕" "87:◕" "88:●" "100:●"; do
    pct="${case%%:*}"
    glyph="${case##*:}"
    write_cache "$pct" 50
    expected="5h $glyph ${pct}% · 7d ◑ 50%"
    check "rust  ${pct}% renders $glyph" "$expected" "$(render_rust)"
    check "bash  ${pct}% renders $glyph" "$expected" "$(render_bash)"
done

echo "== the two implementations agree =="
# Same fixtures again, compared to each other rather than to a literal. This is
# the assertion that survives a deliberate change to the glyph table: if someone
# repoints GAUGE_GLYPHS in one file only, the literals above and this both fail.
for pct in 0 1 12 13 24 37 38 50 62 63 75 87 88 99 100; do
    write_cache "$pct" 50
    check "parity at ${pct}%" "$(render_rust)" "$(render_bash)"
done

echo "== fractional utilization rounds the same way on both sides =="
# The formulas agreed all along; the INPUTS did not. Bash used to normalise with
# printf "%.0f" — C round-half-to-EVEN — while Rust uses f64::round, half away
# from zero. A utilization of 12.5 rendered "12 ○" in bash and "13 ◔" in Rust,
# diverging in the glyph AND the percentage. Half-integers are the only place
# the two rules differ, so these are the fixtures that would have caught it.
for case in "12.5:13:◔" "37.5:38:◑" "62.5:63:◕" "87.5:88:●" "0.5:1:○"; do
    raw="${case%%:*}"; rest="${case#*:}"
    want_pct="${rest%%:*}"; want_glyph="${rest##*:}"
    write_cache "$raw" 50
    expected="5h $want_glyph ${want_pct}% · 7d ◑ 50%"
    check "rust  ${raw} → ${want_pct}% $want_glyph" "$expected" "$(render_rust)"
    check "bash  ${raw} → ${want_pct}% $want_glyph" "$expected" "$(render_bash)"
done

echo "== the gauge is one glyph wide =="
# The point of the change: the usage line must not carry a 10-cell bar. Guards
# against a revert to the ●●●●●○○○○○ rendering, which the parity checks alone
# would happily accept if both sides reverted together.
write_cache 24 50
line="$(render_rust)"
if [[ -z "$line" ]]; then
    FAIL=$((FAIL + 1))
    printf '  FAIL rust rendered no usage line\n'
elif [[ "$line" == *"●●"* || "$line" == *"○○"* ]]; then
    FAIL=$((FAIL + 1))
    printf '  FAIL rust line still contains a multi-cell bar: %q\n' "$line"
else
    PASS=$((PASS + 1))
    printf '  ok   rust line carries no multi-cell bar\n'
fi
line="$(render_bash)"
if [[ -z "$line" ]]; then
    FAIL=$((FAIL + 1))
    printf '  FAIL bash rendered no usage line\n'
elif [[ "$line" == *"●●"* || "$line" == *"○○"* ]]; then
    FAIL=$((FAIL + 1))
    printf '  FAIL bash line still contains a multi-cell bar: %q\n' "$line"
else
    PASS=$((PASS + 1))
    printf '  ok   bash line carries no multi-cell bar\n'
fi

echo
printf 'passed: %d  failed: %d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
