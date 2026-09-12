#!/usr/bin/env bash
# Tests for mask_env_read.sh
# Run: bash claude/hooks/test_mask_env_read.sh
#
# The hook always exits 0 and signals its verdict as JSON on stdout, so these
# tests assert on the JSON, not on the exit code.
#
# They assert the KEY, not the substring. Until 2026-09-12 this file checked
# only that the string "deny" appeared somewhere in the output, which is true
# of both the shape Claude Code obeys (hookSpecificOutput.permissionDecision)
# and the nested decision.behavior shape it silently ignores — so the suite was
# green against a hook that blocked nothing. A substring check here can never
# tell a working hook from a decorative one; keep the jq key assertions.

HOOK="$(cd "$(dirname "$0")" && pwd)/mask_env_read.sh"
PASS=0
FAIL=0

# Fixture dir with a real .env, because the hook only masks files that exist.
# Repo-local tmp/ (gitignored): $TMPDIR is not reliably writable under the
# Claude Code sandbox, and a fixture that silently fails to write turns every
# "should mask" case into a false pass-looking allow.
TMP_ROOT="$(cd "$(dirname "$0")/../.." && pwd)/tmp"
mkdir -p "$TMP_ROOT"
FIXTURE=$(mktemp -d "$TMP_ROOT/mask_env_test.XXXXXX")
trap 'rm -rf "$FIXTURE"' EXIT
printf 'API_KEY=supersecretvalue\nPLAIN=hello\n' > "$FIXTURE/.env"
printf 'export TOKEN=anothersecret\n' > "$FIXTURE/.envrc"
printf 'not an env file\n' > "$FIXTURE/README.md"

# Read the verdict out of the hook's JSON by KEY. Anything that is not a
# well-formed object carrying hookSpecificOutput.permissionDecision == "deny"
# is an allow, however much of the word "deny" it contains.
verdict() {
    printf '%s' "$1" \
        | jq -e -r 'if .hookSpecificOutput.permissionDecision == "deny"
                    then "mask" else "allow" end' 2>/dev/null \
        || echo allow
}

check() {
    local desc="$1" expect="$2" out="$3"
    local got
    got=$(verdict "$out")
    if [ "$got" != "$expect" ]; then
        FAIL=$((FAIL + 1))
        printf 'FAIL: %s (expected %s, got %s)\n' "$desc" "$expect" "$got"
        return
    fi
    # A deny that leaks the raw value is worse than no deny at all: it puts the
    # secret in the transcript AND claims to have protected it.
    if [ "$expect" = mask ]; then
        if [[ "$out" != *'API_KEY=supe****'* && "$out" != *'TOKEN=anot****'* ]]; then
            FAIL=$((FAIL + 1))
            printf 'FAIL: %s (denied, but the reason carries no masked content)\n' "$desc"
            return
        fi
        if [[ "$out" == *supersecretvalue* || "$out" == *anothersecret* ]]; then
            FAIL=$((FAIL + 1))
            printf 'FAIL: %s (denied, but the raw value is in the output)\n' "$desc"
            return
        fi
    fi
    PASS=$((PASS + 1))
}

run_bash() {
    local desc="$1" cmd="$2" expect="$3"
    local out
    out=$(python3 -c "
import json, sys
print(json.dumps({'tool_name': 'Bash', 'cwd': sys.argv[2],
                  'tool_input': {'command': sys.argv[1]}}))" \
        "$cmd" "$FIXTURE" | bash "$HOOK" 2>/dev/null)
    check "$desc" "$expect" "$out"
}

run_read() {
    local desc="$1" path="$2" expect="$3"
    local out
    out=$(python3 -c "
import json, sys
print(json.dumps({'tool_name': 'Read', 'tool_input': {'file_path': sys.argv[1]}}))" \
        "$path" | bash "$HOOK" 2>/dev/null)
    check "$desc" "$expect" "$out"
}

echo "=== SHOULD MASK: Read tool ==="
run_read "read .env"               "$FIXTURE/.env"    mask
run_read "read .envrc"             "$FIXTURE/.envrc"  mask

echo "=== SHOULD MASK: simple Bash reads ==="
run_bash "cat .env"                'cat .env'                 mask
run_bash "head .envrc"             'head .envrc'              mask
run_bash "grep in .env"            'grep API_KEY .env'        mask
run_bash "path-qualified cat"      '/bin/cat .env'            mask

echo "=== SHOULD MASK: reads hidden behind shell operators (the fixed bypass) ==="
run_bash "piped to head"           'cat .env | head -1'       mask
run_bash "piped to wc"             'cat .env | wc -l'         mask
run_bash "grep piped"              'grep KEY .env | cut -d= -f1'  mask
run_bash "behind &&"               'ls -la && cat .env'       mask
run_bash "behind ;"                'pwd; cat .env'            mask
run_bash "behind ||"               'false || cat .envrc'      mask
run_bash "second in a pipeline"    'echo hi | grep -f .env'   mask

echo "=== SHOULD ALLOW: no env file involved ==="
run_bash "cat a normal file"       'cat README.md'            allow
run_bash "normal file piped"       'cat README.md | head -1'  allow
run_bash "git status"              'git status --short'       allow
run_bash "ls with pipe"            'ls -la | wc -l'           allow
run_read "read a normal file"      "$FIXTURE/README.md"       allow
run_bash "nonexistent env file"    'cat .env.missing'         allow

echo "=== SHOULD MASK: the deny is carried by permissionDecision, not decision.behavior ==="
SHAPE=$(python3 -c "
import json, sys
print(json.dumps({'tool_name': 'Read', 'tool_input': {'file_path': sys.argv[1]}}))" \
    "$FIXTURE/.env" | bash "$HOOK" 2>/dev/null)
if printf '%s' "$SHAPE" | jq -e '.hookSpecificOutput | has("permissionDecision") and has("permissionDecisionReason")' >/dev/null 2>&1; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
    echo 'FAIL: hookSpecificOutput lacks permissionDecision/permissionDecisionReason (Claude Code ignores any other deny key)'
fi
if printf '%s' "$SHAPE" | jq -e '.hookSpecificOutput | has("decision")' >/dev/null 2>&1; then
    FAIL=$((FAIL + 1))
    echo 'FAIL: hookSpecificOutput still carries a nested decision object, which is silently ignored'
else
    PASS=$((PASS + 1))
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
