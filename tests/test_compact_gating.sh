#!/usr/bin/env bash
# Verifies the display/side-effect split added for the compact quieting.
# Everything with a real side effect is stubbed: DOT_DIR points at an empty
# temp tree so the symlink-cleanup guard skips, and PATH is emptied of
# claude-tools so no sync is launched.
set -uo pipefail

HOOKS="$(cd "$(dirname "$0")/../claude/hooks" && pwd)"
WORK=$(mktemp -d) || { echo "mktemp failed"; exit 1; }
[[ -n "$WORK" && "$WORK" == /tmp/* ]] || { echo "bad WORK=$WORK"; exit 1; }
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

# compact + usage at 96% -> the live warning still fires, account line dropped
mkdir -p "$WORK/tmpdir_hot"
cat > "$WORK/tmpdir_hot/claude-statusline-usage.json" <<'JSON'
{"five_hour": {"utilization": 96}, "seven_day": {"utilization": 10}}
JSON
out=$(echo '{"source":"compact"}' | TMPDIR="$WORK/tmpdir_hot" bash "$HOOKS/show_auth_account.sh" 2>/dev/null)
check "compact still surfaces the near-limit warning" "Near limit" "$out"
check "and drops the static account line"             "<EMPTY>" "$(printf '%s' "$out" | grep -o 'Auth:' || true)"

# --- context_auto_apply.sh ------------------------------------------------
echo "context_auto_apply.sh"

mkdir -p "$WORK/repo" && git -C "$WORK/repo" init -q 2>/dev/null
mkdir -p "$WORK/nodot"   # DOT_DIR with no scripts/cleanup -> cleanup guard skips

# non-compact, no context.yaml, inside a git repo -> the advisory prints
out=$(cd "$WORK/repo" && echo '{"source":"startup"}' | \
      DOT_DIR="$WORK/nodot" PATH="/usr/bin:/bin" bash "$HOOKS/context_auto_apply.sh" 2>/dev/null)
check "startup prints the no-context advisory" "No context profiles configured" "$out"

# compact, same conditions -> silent
out=$(cd "$WORK/repo" && echo '{"source":"compact"}' | \
      DOT_DIR="$WORK/nodot" PATH="/usr/bin:/bin" bash "$HOOKS/context_auto_apply.sh" 2>/dev/null)
check "compact suppresses the advisory" "<EMPTY>" "$out"

# unreadable source -> falls back to previous behaviour, not to a silent skip
out=$(cd "$WORK/repo" && printf 'not json' | \
      DOT_DIR="$WORK/nodot" PATH="/usr/bin:/bin" bash "$HOOKS/context_auto_apply.sh" 2>/dev/null)
check "malformed hook input falls back to loud" "No context profiles configured" "$out"

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
