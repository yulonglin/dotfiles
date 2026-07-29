#!/usr/bin/env bash
# Tests for the code-quality gate: quality_pr_gate.sh (denies `gh pr create`
# until the branch has been reviewed) and quality_mark_skill_ran.sh (writes the
# marker that clears it).
#
# Same contract as test_convention_nudges.sh: the hooks must (a) produce the
# expected decision, (b) stay silent on negatives, and (c) NEVER exit non-zero.
#
# The gate reads a real branch diff, so fixtures are real git repos. Every case
# runs with XDG_CACHE_HOME pointed at the temp dir, so markers never touch the
# user's real cache.
#
# SC2030/SC2031: each fixture exports GIT_DIR/GIT_WORK_TREE inside a ( ) group
# precisely SO THAT the change is subshell-local. Leaking them into the parent
# would repoint every later git command in this file — the exact failure the
# temp-root probe below exists to prevent.
# shellcheck disable=SC2030,SC2031
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0

# Picking the temp root is security-relevant, not just convenience.
#
# Fixtures are real git repos nested two levels deep. If `git init` fails part
# way (sandboxes commonly deny .git/config writes, or allow only ONE level
# below the temp root), every following git command in the fixture falls
# THROUGH to whatever repository encloses it — which, for a temp dir inside the
# checkout, is this repo. That is not hypothetical: an earlier version of this
# file placed fixtures under ./tmp and committed to the real repo.
#
# So: probe each candidate by actually creating a nested git repo, and never
# choose a candidate inside a repository.
TMP=""
for cand in "$HOME/scratch" "${TMPDIR:-}" /tmp/claude /tmp; do
    [ -n "$cand" ] || continue
    probe="$cand/quality-gate-tests.$$"
    if mkdir -p "$probe/a/b" 2>/dev/null \
       && git init -q "$probe/a/b" >/dev/null 2>&1 \
       && [ -f "$probe/a/b/.git/config" ]; then
        rm -rf "$probe/a"
        TMP="$probe"
        break
    fi
    rm -rf "$probe" 2>/dev/null || true
done
[ -n "$TMP" ] || {
    echo "no temp dir that supports nested git repos — refusing to run" >&2
    exit 1
}
trap 'rm -rf "$TMP"' EXIT

# assert_fixture <repo> — abort the suite unless <repo> is its OWN git repo.
# This is the backstop for the fall-through described above: if a fixture did
# not initialise, we must never go on to run hooks (or git) against whatever
# repository happens to enclose it.
assert_fixture() {
    local repo="$1" top want
    want=$(cd "$repo" 2>/dev/null && pwd -P) || want=""
    top=$(cd "$repo" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || top=""
    if [ -z "$want" ] || [ "$top" != "$want" ]; then
        echo "FATAL: fixture '$repo' is not its own git repo (toplevel='$top')." >&2
        echo "Refusing to continue — tests would operate on the enclosing repository." >&2
        exit 1
    fi
}

export XDG_CACHE_HOME="$TMP/cache"

GIT="git -c user.email=test@example.com -c user.name=Test -c commit.gpgsign=false"

# make_repo <name> <branch> <file> — repo with one commit on main, then <branch>
# carrying <file>. Prints the repo path.
make_repo() {
    local name="$1" branch="$2" file="$3"
    local repo="$TMP/$name"
    mkdir -p "$repo"
    (
        cd "$repo" || exit 1
        git init -q . || exit 1
        # Pin GIT_DIR/GIT_WORK_TREE for the rest of setup so that even if a
        # later command fails, git cannot discover — and write to — a parent
        # repository. Belt to assert_fixture's braces.
        export GIT_DIR="$repo/.git" GIT_WORK_TREE="$repo"
        git symbolic-ref HEAD refs/heads/main
        printf 'base\n' > README.md
        $GIT add README.md
        $GIT commit -qm base
        $GIT checkout -q -b "$branch"
        mkdir -p "$(dirname "$file")"
        printf 'x = 1\n' > "$file"
        $GIT add "$file"
        $GIT commit -qm change
    ) >/dev/null 2>&1
    assert_fixture "$repo"
    printf '%s' "$repo"
}

bash_json() {
    python3 -c "
import json, sys
print(json.dumps({'tool_name': 'Bash', 'tool_input': {'command': sys.argv[1]}}))
" "$1"
}

skill_json() {
    python3 -c "
import json, sys
print(json.dumps({'tool_name': 'Skill', 'tool_input': {'skill': sys.argv[1]}}))
" "$1"
}

# run_gate <desc> <repo> <command> <expect: deny|allow>
run_gate() {
    local desc="$1" repo="$2" cmd="$3" expect="$4"
    local out rc=0
    out=$(cd "$repo" && bash_json "$cmd" | bash "$DIR/quality_pr_gate.sh" 2>/dev/null) || rc=$?

    if [ "$rc" -ne 0 ]; then
        FAIL=$((FAIL + 1))
        printf 'FAIL: %s (hook exited %d — must always be 0)\n' "$desc" "$rc"
        return
    fi

    local got=allow
    case "$out" in *'"deny"'*) got=deny ;; esac

    if [ "$got" = "$expect" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL: %s (expected %s, got %s)\n' "$desc" "$expect" "$got"
    fi
}

echo "=== quality_pr_gate.sh ==="

CODE_REPO=$(make_repo code-branch feature src/app.py)
DOCS_REPO=$(make_repo docs-branch feature docs/notes.md)

run_gate "code branch, unreviewed -> deny"   "$CODE_REPO" "gh pr create --draft" deny
run_gate "code branch, plain create -> deny" "$CODE_REPO" "gh pr create"         deny
run_gate "docs-only branch -> allow"         "$DOCS_REPO" "gh pr create --draft" allow
run_gate "unrelated bash -> allow"           "$CODE_REPO" "ls -la"               allow
run_gate "gh pr list is not create -> allow" "$CODE_REPO" "gh pr list"           allow
run_gate "gh pr view is not create -> allow" "$CODE_REPO" "gh pr view 3"         allow

# --help is recognised by whole-string equality, never by searching for the
# token. Each of the three cases below was a real bypass in an earlier version:
# the token appeared inside a title, as the value of another flag, or ahead of a
# second create on the same line.
run_gate "bare --help -> allow"          "$CODE_REPO" "gh pr create --help"   allow
run_gate "--help with odd spacing -> allow" "$CODE_REPO" "  gh  pr   create   --help  " allow
run_gate "--help inside a title -> deny" "$CODE_REPO" \
    'gh pr create --title "fix --help output"' deny
run_gate "--help as a flag value -> deny" "$CODE_REPO" \
    "gh pr create --title x --body --help" deny
run_gate "--help then a real create -> deny" "$CODE_REPO" \
    "gh pr create --help && gh pr create --draft" deny

# Nothing may PRECEDE the create: the hook runs first, so a prefix that moves
# or mutates the repo makes it inspect a different commit than the PR contains.
# One rule, rather than a list of known mutators — the list is what `git -c`,
# `git pull` and `pushd` each walked straight through.
run_gate "cd before create -> deny"      "$CODE_REPO" "cd /elsewhere && gh pr create" deny
run_gate "commit before create -> deny"  "$CODE_REPO" "git commit -m x && gh pr create" deny
run_gate "git -c commit before -> deny"  "$CODE_REPO" \
    "git -c commit.gpgsign=false commit -am fix && gh pr create" deny
run_gate "git pull before create -> deny" "$CODE_REPO" "git pull --rebase && gh pr create" deny
run_gate "pushd before create -> deny"   "$CODE_REPO" "pushd /elsewhere && gh pr create" deny
run_gate "subshell around create -> deny" "$CODE_REPO" "(gh pr create)" deny
# Even a harmless-looking push is refused: distinguishing it means classifying
# arbitrary shell, which is the unsound step this design removes.
run_gate "push before create -> deny"    "$DOCS_REPO" "git push && gh pr create" deny
# Suffixes are fine — they run after the PR exists, from the inspected state.
run_gate "suffix after create -> allow"  "$DOCS_REPO" "gh pr create --draft && echo done" allow

# --head publishes a branch other than the checked-out one, which the marker
# cannot vouch for. Refused without reading the value.
run_gate "--head -> deny"          "$CODE_REPO" "gh pr create --head other"  deny
run_gate "-H short form -> deny"   "$CODE_REPO" "gh pr create -H other"      deny
run_gate "attached -Hvalue -> deny" "$CODE_REPO" "gh pr create -Hother"      deny

# An explicit base is refused rather than parsed. `--base "main" --draft` is the
# exact form that used to strip the quotes, capture `--draft` as the base, fail
# to resolve it, and ALLOW.
run_gate "--base main -> deny"      "$CODE_REPO" "gh pr create --base main"   deny
run_gate "quoted base -> deny"      "$CODE_REPO" 'gh pr create --base "main" --draft' deny
run_gate "--base=value -> deny"     "$CODE_REPO" "gh pr create --base=main"   deny
run_gate "-B short form -> deny"    "$CODE_REPO" "gh pr create -B main"       deny
run_gate "attached -Bvalue -> deny" "$CODE_REPO" "gh pr create -Bmain"        deny

# Extensionless executables are code too. This repo tracks dozens of them under
# custom_bins/, so a suffix-only check would wave through exactly the files most
# worth reviewing.
BIN_REPO="$TMP/bin-branch"
mkdir -p "$BIN_REPO"
(
    cd "$BIN_REPO" || exit 1
    git init -q . || exit 1
    export GIT_DIR="$BIN_REPO/.git" GIT_WORK_TREE="$BIN_REPO"
    git symbolic-ref HEAD refs/heads/main
    printf 'base\n' > README.md
    $GIT add README.md
    $GIT commit -qm base
    $GIT checkout -q -b feature
    mkdir -p custom_bins
    printf '#!/usr/bin/env bash\necho hi\n' > custom_bins/tool
    chmod +x custom_bins/tool
    $GIT add custom_bins/tool
    $GIT commit -qm tool
) >/dev/null 2>&1
assert_fixture "$BIN_REPO"
run_gate "extensionless executable counts as code" "$BIN_REPO" "gh pr create" deny

# A DELETED extensionless executable is still a code change. Probing only HEAD
# classified every removal as non-code, because a deleted path has no blob
# there — so `git rm custom_bins/foo` could ship unreviewed.
DEL_REPO="$TMP/del-branch"
mkdir -p "$DEL_REPO"
(
    cd "$DEL_REPO" || exit 1
    git init -q . || exit 1
    export GIT_DIR="$DEL_REPO/.git" GIT_WORK_TREE="$DEL_REPO"
    git symbolic-ref HEAD refs/heads/main
    mkdir -p custom_bins
    printf '#!/usr/bin/env bash\necho hi\n' > custom_bins/tool
    chmod +x custom_bins/tool
    $GIT add custom_bins/tool
    $GIT commit -qm base
    $GIT checkout -q -b feature
    $GIT rm -q custom_bins/tool
    $GIT commit -qm drop
) >/dev/null 2>&1
assert_fixture "$DEL_REPO"
run_gate "deleted extensionless executable counts as code" "$DEL_REPO" "gh pr create" deny

# Marker present -> allow. Written via the real marker hook so the test also
# proves the two hooks agree on the key (the failure mode that would wedge the
# gate permanently).
(cd "$CODE_REPO" && skill_json "superpowers:requesting-code-review" \
    | bash "$DIR/quality_mark_skill_ran.sh") >/dev/null 2>&1 || true
run_gate "after review skill ran -> allow" "$CODE_REPO" "gh pr create --draft" allow

# Ordering of the two flag refusals against the marker, which is the whole
# reason they sit on opposite sides of it:
#   --base is about the DIFF, and a reviewed branch may target any base.
#   --head is about WHICH BRANCH, and the marker vouches only for this one.
run_gate "reviewed branch may set --base" "$CODE_REPO" "gh pr create --base develop" allow
run_gate "reviewed branch still refuses --head" "$CODE_REPO" "gh pr create --head other" deny

# Base unresolvable: no origin, no main/master anywhere -> fail open.
NOBASE="$TMP/nobase"
mkdir -p "$NOBASE"
(
    cd "$NOBASE" || exit 1
    git init -q . || exit 1
    export GIT_DIR="$NOBASE/.git" GIT_WORK_TREE="$NOBASE"
    git symbolic-ref HEAD refs/heads/feature
    printf 'x = 1\n' > app.py
    $GIT add app.py
    $GIT commit -qm only
) >/dev/null 2>&1
assert_fixture "$NOBASE"
run_gate "no resolvable base -> allow" "$NOBASE" "gh pr create" allow

# Not a git repo at all -> fail open.
NOGIT="$TMP/nogit"
mkdir -p "$NOGIT"
run_gate "outside a git repo -> allow" "$NOGIT" "gh pr create" allow

run_gate "empty command -> allow" "$CODE_REPO" "" allow

echo "=== quality_mark_skill_ran.sh ==="

# marker_case <desc> <repo> <skill> <expect: marker|none> [marker-skill]
marker_case() {
    local desc="$1" repo="$2" skill="$3" expect="$4" mskill="${5:-}"
    local rc=0 marker
    [ -n "$mskill" ] || mskill="${skill##*:}"

    rm -rf "$XDG_CACHE_HOME/claude/quality-gate" 2>/dev/null || true
    (cd "$repo" && skill_json "$skill" | bash "$DIR/quality_mark_skill_ran.sh") >/dev/null 2>&1 || rc=$?

    if [ "$rc" -ne 0 ]; then
        FAIL=$((FAIL + 1))
        printf 'FAIL: %s (hook exited %d — must always be 0)\n' "$desc" "$rc"
        return
    fi

    marker=$(cd "$repo" && bash -c ". '$DIR/lib/quality_gate_lib.sh'; quality_gate_marker '$mskill'")

    local got=none
    [ -n "$marker" ] && [ -f "$marker" ] && got=marker

    if [ "$got" = "$expect" ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL: %s (expected %s, got %s)\n' "$desc" "$expect" "$got"
    fi
}

marker_case "plugin-qualified review skill" "$CODE_REPO" "superpowers:requesting-code-review" marker
marker_case "bare review skill"             "$CODE_REPO" "requesting-code-review"             marker
marker_case "verification skill tracked"    "$CODE_REPO" "superpowers:verification-before-completion" marker
marker_case "untracked skill ignored"       "$CODE_REPO" "brainstorming" none requesting-code-review
marker_case "outside git repo, no marker"   "$NOGIT"     "requesting-code-review"             none

# A marker set on one branch must NOT clear the gate on another branch.
rm -rf "$XDG_CACHE_HOME/claude/quality-gate" 2>/dev/null || true
(cd "$CODE_REPO" && skill_json "requesting-code-review" \
    | bash "$DIR/quality_mark_skill_ran.sh") >/dev/null 2>&1 || true
(cd "$CODE_REPO" && $GIT checkout -q -b second-feature) >/dev/null 2>&1
run_gate "marker does not leak across branches" "$CODE_REPO" "gh pr create" deny

# Branch names that fold to the same filesystem-safe slug must still get
# separate markers, or reviewing one silently clears the gate on the other.
rm -rf "$XDG_CACHE_HOME/claude/quality-gate" 2>/dev/null || true
(cd "$CODE_REPO" && $GIT checkout -q -b topic/foo) >/dev/null 2>&1
(cd "$CODE_REPO" && skill_json "requesting-code-review" \
    | bash "$DIR/quality_mark_skill_ran.sh") >/dev/null 2>&1 || true
(cd "$CODE_REPO" && $GIT checkout -q -b topic-foo) >/dev/null 2>&1
run_gate "slug-colliding branches keep separate markers" "$CODE_REPO" "gh pr create" deny

echo
TOTAL=$((PASS + FAIL))
echo "Results: $PASS passed, $FAIL failed (total $TOTAL)"
[ "$FAIL" -eq 0 ] && echo "All tests passed!"
[ "$FAIL" -eq 0 ]
