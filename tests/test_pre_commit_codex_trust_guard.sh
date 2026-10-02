#!/usr/bin/env bash
# Pins the Codex trust-table guard in config/git-hooks/pre-commit.
#
# Codex appends a [projects."<absolute path>"] table to config.toml for every
# directory it trusts, and codex/ is symlinked to ~/.codex/, so without this
# hook a routine `git add codex/config.toml` (or the daily dotfiles-sync)
# publishes the machine's private project paths.
#
# Both directions are asserted: a guard that blocks everything is as useless as
# one that blocks nothing. The STAGED content is what counts, so the last case
# proves a dirty working copy does not block a clean index.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Overridable so the guard can be mutation-tested against a modified copy.
HOOKS_DIR="${HOOKS_DIR:-$REPO_ROOT/config/git-hooks}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/codex-trust-guard-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# Paths in these fixtures are synthetic. Never paste a real trusted path here:
# the fixture is committed, so it would leak the very value this guard protects.
BASE='model = "gpt-5"
projects_dir = "~/code"

[features]
web_search = true
'

cd "$WORK"
git init -q .
git config user.email test@example.com
git config user.name test
git config commit.gpgsign false
git config core.hooksPath "$HOOKS_DIR"
mkdir -p codex

printf '%s' "$BASE" > codex/config.toml
git add codex/config.toml
git commit -qm baseline --no-verify
baseline_count="$(git rev-list --count HEAD)"

expect_blocked() {
    # $1 = case label; codex/config.toml must already hold the content
    git add codex/config.toml
    local out
    if out="$(git commit -qm "$1" 2>&1)"; then
        fail "$1: committed; guard did not fire"
    fi
    [ "$(git rev-list --count HEAD)" = "$baseline_count" ] \
        || fail "$1: commit count changed despite the guard firing"
    printf '%s\n' "$out" | grep -q 'Codex trust table' \
        || fail "$1: rejected, but not by the trust-table guard: $out"
    printf '%s\n' "$out" | grep -q 'git reset -p -- codex/config.toml' \
        || fail "$1: error message does not say how to unstage the hunk"
    git restore --staged codex/config.toml
}

# --- Case 1: the table Codex writes for a trusted directory -----------------
printf '%s\n[projects."/home/example/code/some-project"]\ntrust_level = "trusted"\n' "$BASE" > codex/config.toml
expect_blocked quoted-path-table

# --- Case 2: indented, several tables, single-quoted key --------------------
printf "%s\n  [projects.'/srv/a']\ntrust_level = \"trusted\"\n\n[projects.\"/srv/b\"]\ntrust_level = \"trusted\"\n" "$BASE" > codex/config.toml
expect_blocked indented-multi-table

# --- Case 3: a bare [projects] table ----------------------------------------
printf '%s\n[projects]\n"/srv/c" = { trust_level = "trusted" }\n' "$BASE" > codex/config.toml
expect_blocked bare-projects-table

# --- Case 4: other edits to the file still commit ---------------------------
# projects_dir and a comment naming the tables must not trip the guard.
printf '%s\n# [projects."..."] tables are kept local by the pre-commit hook\n[tui]\nnotifications = true\n' "$BASE" > codex/config.toml
git add codex/config.toml
git commit -qm clean >/dev/null 2>&1 \
    || fail "clean config.toml was blocked (false positive)"
[ "$(git rev-list --count HEAD)" -gt "$baseline_count" ] \
    || fail "clean config.toml did not produce a commit"
baseline_count="$(git rev-list --count HEAD)"

# --- Case 5: a similarly named table is not a trust table -------------------
printf '%s\n[projects_extra]\nenabled = true\n' "$BASE" > codex/config.toml
git add codex/config.toml
git commit -qm similar-name >/dev/null 2>&1 \
    || fail "[projects_extra] was blocked (false positive)"
baseline_count="$(git rev-list --count HEAD)"

# --- Case 6: only the index matters -----------------------------------------
# Stage a clean edit, then add a trust table to the working copy only.
printf '%s\n[tui]\nnotifications = false\n' "$BASE" > codex/config.toml
git add codex/config.toml
printf '\n[projects."/home/example/unstaged"]\ntrust_level = "trusted"\n' >> codex/config.toml
git commit -qm index-only >/dev/null 2>&1 \
    || fail "an unstaged trust table blocked a clean staged blob"
git show HEAD:codex/config.toml | grep -q 'projects\."' \
    && fail "the unstaged trust table reached the commit"

# --- Case 7: deleting the file is allowed -----------------------------------
git rm -q --cached codex/config.toml
git commit -qm delete >/dev/null 2>&1 \
    || fail "a staged deletion of config.toml was blocked"

echo "PASS: codex trust-table guard blocks [projects.*] tables and allows clean config.toml"
