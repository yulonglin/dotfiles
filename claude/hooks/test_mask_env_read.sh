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

# HOOK is overridable so the same suite can be pointed at an older revision:
#   git show <rev>:claude/hooks/mask_env_read.sh > /tmp/old_hook.sh
#   HOOK=/tmp/old_hook.sh bash claude/hooks/test_mask_env_read.sh
HOOK="${HOOK:-$(cd "$(dirname "$0")" && pwd)/mask_env_read.sh}"
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
# A symlink whose own name says nothing about what it points at. The basename
# check tests the link, so this walked straight past the hook.
ln -s .env "$FIXTURE/notes.txt"

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

# The 4th argument is the session cwd the hook is told about. It defaults to
# the fixture; the `cd` cases need it to be somewhere else, because a hook that
# resolves every relative path against the session cwd only looks correct while
# the two happen to be the same directory.
run_bash() {
    local desc="$1" cmd="$2" expect="$3" cwd="${4:-$FIXTURE}"
    local out
    out=$(python3 -c "
import json, sys
print(json.dumps({'tool_name': 'Bash', 'cwd': sys.argv[2],
                  'tool_input': {'command': sys.argv[1]}}))" \
        "$cmd" "$cwd" | bash "$HOOK" 2>/dev/null)
    check "$desc" "$expect" "$out"
}

run_grep() {
    local desc="$1" path="$2" expect="$3"
    local out
    out=$(python3 -c "
import json, sys
print(json.dumps({'tool_name': 'Grep', 'cwd': sys.argv[2],
                  'tool_input': {'pattern': 'KEY', 'path': sys.argv[1]}}))" \
        "$path" "$FIXTURE" | bash "$HOOK" 2>/dev/null)
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

# --- Bypasses measured live on 2026-09-12, ordered by how likely each is to
# --- happen by accident rather than by attack.

echo "=== SHOULD MASK: the path never appears literally (cd, variables, quotes) ==="
# PARENT is the fixture's parent, so a relative token resolved against the
# session cwd instead of the cd'd-into directory misses the file entirely.
PARENT="$(dirname "$FIXTURE")"
run_bash "cd then read"            "cd $FIXTURE && cat .env"        mask "$PARENT"
run_bash "cd then sed"             "cd $FIXTURE; sed -n 1p .env"    mask "$PARENT"
run_bash "variable path"           "V=$FIXTURE/.env; cat \"\$V\""   mask "$PARENT"
run_bash "braced variable path"    "V=$FIXTURE/.env; cat \"\${V}\"" mask "$PARENT"
run_bash "quoted absolute path"    "cat \"$FIXTURE/.env\""           mask "$PARENT"

echo "=== SHOULD MASK: symlink to an env file (basename says nothing) ==="
run_bash "cat a symlink"           'cat notes.txt'                  mask
run_read "read a symlink"          "$FIXTURE/notes.txt"             mask

echo "=== SHOULD MASK: readers the command list did not know about ==="
run_bash "sed"                     'sed -n 1p .env'                 mask
run_bash "awk"                     "awk 'NR==1' .env"               mask
run_bash "nl"                      'nl .env'                        mask
run_bash "tac"                     'tac .env'                       mask
run_bash "od"                      'od -c .env'                     mask
run_bash "xxd"                     'xxd .env'                       mask
run_bash "strings"                 'strings .env'                   mask
run_bash "cut"                     'cut -d= -f2 .env'               mask
run_bash "base64"                  'base64 .env'                    mask
run_bash "source"                  'source .envrc'                  mask
run_bash "dot builtin"             '. .envrc'                       mask

echo "=== SHOULD MASK: the read hides inside a substitution or a redirection ==="
run_bash "command substitution"    'echo "$(cat .env)"'             mask
run_bash "backtick substitution"   'echo `cat .env`'                mask
run_bash "export from xargs"       'export $(cat .env | xargs)'     mask
run_bash "redirection into while"  'while IFS= read -r l; do :; done < .env'  mask
run_bash "cp to stdout"            'cp .env /dev/stdout'            mask
run_bash "inline python"           'python3 -c "print(open(\".env\").read())"'  mask

echo "=== SHOULD MASK: the Grep tool reads files too ==="
run_grep "grep tool on .env"       "$FIXTURE/.env"                  mask

# --- False-positive guards. Widening the reader set is only safe if ordinary
# --- work still runs; each of these would be newly broken by a careless list.

echo "=== SHOULD ALLOW: the new readers on ordinary files ==="
run_bash "sed on a normal file"    "sed -i 's/a/b/' README.md"      allow
run_bash "awk on a normal file"    "awk '{print}' README.md"        allow
run_bash "cut on a normal file"    'cut -c1-3 README.md'            allow
run_bash "grep over a tree"        'grep -rn KEY .'                 allow
run_bash "inline python, no env"   'python3 -c "print(1)"'          allow
run_bash "venv dir called .env"    'source .env/bin/activate'       allow
# rg -g takes a glob, not a path, and --files/-l print names, never contents.
run_bash "rg glob argument"        "rg --files -g '.envrc'"         allow
run_bash "rg -l names only"        'rg -l KEY .env'                 allow
run_bash "grep -e pattern"         'grep -e .env README.md'         allow
# `source FILE args` reads only FILE. A prose sentence in a commit-message
# heredoc begins with ". ", which parses as the source builtin.
run_bash "source with extra args"  'source README.md .envrc'        allow
run_bash "prose starting with dot" '. Every call site, including .envrc, now names the verbs'  allow
# -f really does read the file as a pattern list, so it stays intercepted.
run_bash "grep -f reads the file"  'echo hi | grep -f .env'         mask

echo "=== SHOULD ALLOW: touching an env file without reading its values ==="
run_bash "git add"                 'git add .env'                   allow
run_bash "ls"                      'ls -la .env'                    allow
run_bash "rm"                      'rm -f .env'                     allow
run_bash "mv"                      'mv .env .env.bak'               allow
run_bash "cp to a backup"          'cp .env .env.bak'               allow
run_bash "append to it"            'echo "FOO=bar" >> .env'         allow
run_bash "write over it"           'cat > .env'                     allow
run_bash "editor"                  'vim .env'                       allow

echo "=== SHOULD ALLOW: variables and cd that do not lead to an env file ==="
run_bash "variable to normal file" 'V=README.md; cat "$V"'          allow
run_bash "cd then normal read"     "cd $FIXTURE && cat README.md"   allow "$PARENT"

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
