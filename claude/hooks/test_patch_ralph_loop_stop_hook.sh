#!/usr/bin/env bash
# Regression test: Ralph Loop success paths must emit valid Stop-hook JSON.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
PATCHER="$DIR/patch_ralph_loop_stop_hook.py"
TMP_BASE="${TMPDIR:-/tmp}"
WORK="$(mktemp -d "${TMP_BASE%/}/ralph-stop-json-test.XXXXXX")"

cleanup() {
    if command -v trash >/dev/null 2>&1; then
        trash "$WORK" >/dev/null 2>&1 || true
    else
        case "$WORK" in
            "${TMP_BASE%/}"/ralph-stop-json-test.*) rm -rf -- "$WORK" ;;
        esac
    fi
}
trap cleanup EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

FIXTURE="$WORK/stop-hook.sh"
cat > "$FIXTURE" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
    max)
        MAX_ITERATIONS=5
  echo "🛑 Ralph loop: Max iterations ($MAX_ITERATIONS) reached."
        ;;
    promise)
        COMPLETION_PROMISE=DONE
        echo "✅ Ralph loop: Detected <promise>$COMPLETION_PROMISE</promise>"
        ;;
esac
SH
chmod +x "$FIXTURE"
cp "$FIXTURE" "$WORK/original-stop-hook.sh"

for branch in max promise; do
    output=$("$FIXTURE" "$branch")
    if printf '%s' "$output" | jq -e . >/dev/null 2>&1; then
        fail "known-bad $branch fixture unexpectedly emitted JSON"
    fi
done

mode_before=$(stat -f '%Lp' "$FIXTURE" 2>/dev/null || stat -c '%a' "$FIXTURE")
python3 "$PATCHER" --path "$FIXTURE" >/dev/null
mode_after=$(stat -f '%Lp' "$FIXTURE" 2>/dev/null || stat -c '%a' "$FIXTURE")
[ "$mode_before" = "$mode_after" ] || fail "patch changed executable mode"

for branch in max promise; do
    output=$("$FIXTURE" "$branch")
    if [ "$branch" = max ]; then
        want='🛑 Ralph loop: Max iterations (5) reached.'
    else
        want='✅ Ralph loop: Detected <promise>DONE</promise>'
    fi
    printf '%s' "$output" | jq -e --arg want "$want" '
        type == "object"
        and (keys == ["systemMessage"])
        and (.systemMessage == $want)
    ' >/dev/null || fail "$branch branch did not emit one valid systemMessage object"
done

before=$(shasum -a 256 "$FIXTURE" | awk '{print $1}')
python3 "$PATCHER" --path "$FIXTURE" >/dev/null
after=$(shasum -a 256 "$FIXTURE" | awk '{print $1}')
[ "$before" = "$after" ] || fail "second patch changed an already-patched hook"

DRIFTED="$WORK/drifted-stop-hook.sh"
sed 's/✅ Ralph loop/✅ Future Ralph/' "$WORK/original-stop-hook.sh" > "$DRIFTED"
before=$(shasum -a 256 "$DRIFTED" | awk '{print $1}')
if diagnostic=$(python3 "$PATCHER" --path "$DRIFTED" 2>&1 >/dev/null); then
    fail "unknown plugin source was accepted"
fi
printf '%s' "$diagnostic" | rg -qi 'unsupported|drift' \
    || fail "unknown plugin source did not produce a drift diagnostic"
after=$(shasum -a 256 "$DRIFTED" | awk '{print $1}')
[ "$before" = "$after" ] || fail "unknown plugin source was modified"

printf 'PASS: Ralph Loop Stop-hook JSON repair\n'
