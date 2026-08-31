#!/usr/bin/env bash
# Verifies the display/side-effect split added for the compact quieting.
# Everything with a real side effect is stubbed: DOT_DIR points at an empty
# temp tree so the symlink-cleanup guard skips, and PATH is emptied of
# claude-tools so no sync is launched.
set -uo pipefail

# HOOKS_DIR override exists so the suite can be pointed at mutated copies to
# confirm the assertions below actually fail when the quieting logic is broken.
HOOKS="${HOOKS_DIR:-$(cd "$(dirname "$0")/../claude/hooks" && pwd)}"

# Pick a writable scratch base. Under the Claude Code sandbox $TMPDIR is
# /run/user/1000, which is mounted read-only, so an unqualified `mktemp -d`
# fails there; /tmp/claude is the sandbox-writable path. Probe rather than
# assume, so the test also runs unsandboxed and on macOS.
TMPBASE=""
for cand in "${TMPDIR:-}" /tmp/claude /tmp; do
    [[ -n "$cand" && -d "$cand" && -w "$cand" ]] && { TMPBASE="$cand"; break; }
done
[[ -n "$TMPBASE" ]] || { echo "no writable temp base"; exit 1; }
WORK=$(mktemp -d "${TMPBASE%/}/compact-gating.XXXXXX") || { echo "mktemp failed"; exit 1; }
[[ -n "$WORK" && "$WORK" == "$TMPBASE"/* ]] || { echo "bad WORK=$WORK"; exit 1; }
trap 'rm -rf "$WORK"' EXIT

PASS=0; FAIL=0
check() { # desc expected_empty_or_substr actual
    local desc="$1" want="$2" got="$3"
    if [[ "$want" == "<EMPTY>" ]]; then
        if [[ -z "${got//[[:space:]]/}" ]]; then PASS=$((PASS+1)); echo "  ok   $desc"
        else FAIL=$((FAIL+1)); echo "  FAIL $desc -- expected no output, got: $got"; fi
    elif [[ "$got" == *"$want"* ]]; then PASS=$((PASS+1)); echo "  ok   $desc"
    else FAIL=$((FAIL+1)); echo "  FAIL $desc -- expected to find: $want -- got: $got"; fi
}

# --- show_auth_account.sh -------------------------------------------------
echo "show_auth_account.sh"

# compact + no usage cache -> silent (does not even call `claude auth status`)
mkdir -p "$WORK/tmpdir_empty"
out=$(echo '{"source":"compact"}' | TMPDIR="$WORK/tmpdir_empty" bash "$HOOKS/show_auth_account.sh" 2>/dev/null)
check "compact with no near-limit warning is silent" "<EMPTY>" "$out"

# compact + usage at 96% -> the account line is dropped. The near-limit warning
# this block once also asserted was deliberately removed from the hook on
# 2026-08-13; the 96% fixture stays because it is the loudest input the hook can
# get, so silence here is the strongest form of the claim.
mkdir -p "$WORK/tmpdir_hot"
cat > "$WORK/tmpdir_hot/claude-statusline-usage.json" <<'JSON'
{"five_hour": {"utilization": 96}, "seven_day": {"utilization": 10}}
JSON
out=$(echo '{"source":"compact"}' | TMPDIR="$WORK/tmpdir_hot" bash "$HOOKS/show_auth_account.sh" 2>/dev/null)
check "and drops the static account line"             "<EMPTY>" "$(printf '%s' "$out" | grep -o 'Auth:' || true)"

# --- stdin safety ---------------------------------------------------------
# The hook reads stdin where it previously did not. `[ -t 0 ]` catches a
# terminal but NOT a pipe with no writer, so a `cat` that blocks would stall
# every session start - a worse regression than the noise this change removes.
# Timeout-guarded so a hang fails the suite instead of hanging it.
echo "stdin safety"

# PATH stubbed because closed stdin leaves QUIET false, which reaches the
# `claude auth status` call - the suite must not query the real auth state.
out=$(TMPDIR="$WORK/tmpdir_hot" PATH="/usr/bin:/bin" \
      timeout 5 bash "$HOOKS/show_auth_account.sh" </dev/null 2>/dev/null); rc=$?
if [[ $rc -eq 124 ]]; then FAIL=$((FAIL+1)); echo "  FAIL show_auth_account timed out on closed stdin"
else PASS=$((PASS+1)); echo "  ok   show_auth_account exits on closed stdin (rc=$rc)"; fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
