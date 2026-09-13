#!/usr/bin/env bash
# shellcheck shell=bash
# Pins the zsh syntax gate in config/git-hooks/pre-commit.
#
# The case that matters is the one the first version got wrong: when `zsh` is not
# on PATH the gate must REFUSE the commit, not wave it through. Wrapping the whole
# check in `if command -v zsh` fails open — exit 0, no diagnostic — so a machine
# without zsh silently stops checking the only files zsh can check. That is the
# same shape as the two inert hooks found on 2026-09-12, so it gets a test.
#
# Both directions are pinned: the gate must fire on broken zsh (interpreter
# present or absent), and it must stay out of the way of everything else.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="${HOOKS_DIR:-$REPO_ROOT/config/git-hooks}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/zsh-guard-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

command -v zsh >/dev/null 2>&1 || {
    echo "SKIP: zsh is not installed, so the interpreter-present cases cannot run" >&2
    exit 0
}

# A PATH with every executable the machine has EXCEPT zsh. Masking the interpreter
# this way (rather than stubbing one command) keeps git, bash and sed reachable, so
# a failure is the gate's doing and not a broken environment.
NOZSH_BIN="$WORK/nozsh-bin"
mkdir -p "$NOZSH_BIN"
IFS=':' read -r -a _path_dirs <<< "$PATH"
for _dir in "${_path_dirs[@]}"; do
    [ -d "$_dir" ] || continue
    for _exe in "$_dir"/*; do
        [ -x "$_exe" ] || continue
        _name="${_exe##*/}"
        [ "$_name" = zsh ] && continue
        [ -e "$NOZSH_BIN/$_name" ] && continue
        ln -s "$_exe" "$NOZSH_BIN/$_name" 2>/dev/null || true
    done
done
[ -x "$NOZSH_BIN/git" ] || fail "the masked PATH lost git; the test environment is broken"
if PATH="$NOZSH_BIN" command -v zsh >/dev/null 2>&1; then
    fail "zsh is still reachable on the masked PATH; the mask does not work"
fi

cd "$WORK"
git init -q .
git config user.email test@example.com
git config user.name test
git config commit.gpgsign false
git config core.hooksPath "$HOOKS_DIR"

mkdir -p config/aliases
printf 'alias ll="ls -l"\n' > config/aliases/good.sh
git add config/aliases/good.sh
git commit -qm baseline || fail "a valid zsh file was blocked from the baseline commit"
baseline_count="$(git rev-list --count HEAD)"

# A parse error zsh -n catches: `if` with no `fi`.
BROKEN='if true; then
  echo unterminated
'

# --- Case 1: zsh present, broken zsh file -> blocked -------------------------
printf '%s' "$BROKEN" > config/aliases/broken.sh
git add config/aliases/broken.sh
if git commit -qm broken >/dev/null 2>&1; then
    fail "broken zsh was committed while zsh was on PATH; the gate did not fire"
fi
[ "$(git rev-list --count HEAD)" = "$baseline_count" ] \
    || fail "case 1 created a commit"

# --- Case 2: zsh ABSENT, broken zsh file -> still blocked --------------------
# This is the regression. The first version exited 0 here with no output.
set +e
out="$(PATH="$NOZSH_BIN" git commit -qm broken-nozsh 2>&1)"
rc=$?
set -e
[ "$rc" -eq 0 ] && fail "broken zsh was COMMITTED with zsh off PATH — the gate failed open"
case "$out" in
    *"zsh is not on PATH"*) : ;;
    *) fail "gate blocked with zsh off PATH but gave no actionable message. Got: $out" ;;
esac
[ "$(git rev-list --count HEAD)" = "$baseline_count" ] \
    || fail "case 2 created a commit"

git restore --staged config/aliases/broken.sh
rm -f config/aliases/broken.sh

# --- Case 3: zsh ABSENT, no zsh file staged -> out of the way ----------------
mkdir -p docs
printf 'Some prose.\n' > docs/note.md
git add docs/note.md
PATH="$NOZSH_BIN" git commit -qm docs-only \
    || fail "a commit staging no zsh files was blocked while zsh was off PATH"

# --- Case 4: a non-zsh interpreter is not run through zsh -n -----------------
# Valid bash that zsh -n would also accept is no test; use a shebang that takes
# the classifier down the "other interpreter" branch and give it zsh-invalid text.
mkdir -p scripts
printf '#!/usr/bin/env python3\nd = {1: 2}\nprint(d[1])\n' > scripts/tool.py
git add scripts/tool.py
PATH="$NOZSH_BIN" git commit -qm python-file \
    || fail "a python file was run through the zsh gate"

# --- Case 5: zsh present, valid zsh file -> allowed --------------------------
printf 'alias gs="git status"\n' > config/aliases/more.sh
git add config/aliases/more.sh
git commit -qm valid-zsh || fail "a valid zsh file was blocked"

echo "PASS: 5 cases (gate fires with zsh present and absent, stays out of the way otherwise)"
