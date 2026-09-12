#!/usr/bin/env bash
# shellcheck shell=bash
# Pins the Markdown hard-wrap guard in config/git-hooks/pre-commit.
#
# The hook is global (core.hooksPath), so both directions matter: it must block
# a hard-wrapped paragraph staged under claude/, and it must stay out of the way
# everywhere else — Markdown outside claude/, non-Markdown files, and repos that
# do not carry custom_bins/md-unwrap at all.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="${HOOKS_DIR:-$REPO_ROOT/config/git-hooks}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/md-wrap-guard-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

cd "$WORK"
git init -q .
git config user.email test@example.com
git config user.name test
git config commit.gpgsign false
git config core.hooksPath "$HOOKS_DIR"

# The guard resolves the checker from the repo it is committing into, so give
# this scratch repo a copy at the same path the real one uses.
mkdir -p custom_bins claude/rules docs
cp "$REPO_ROOT/custom_bins/md-unwrap" custom_bins/md-unwrap
chmod +x custom_bins/md-unwrap

printf 'A single-line paragraph.\n' > claude/rules/clean.md
git add custom_bins/md-unwrap claude/rules/clean.md
git commit -qm baseline || fail "clean baseline was blocked"
baseline_count="$(git rev-list --count HEAD)"

# --- Case 1: a hard-wrapped paragraph under claude/ must be blocked ---------
printf 'This paragraph was hard wrapped\nacross two lines.\n' > claude/rules/wrapped.md
git add claude/rules/wrapped.md
if git commit -qm wrapped >/dev/null 2>&1; then
    fail "hard-wrapped Markdown under claude/ was committed; guard did not fire"
fi
[ "$(git rev-list --count HEAD)" = "$baseline_count" ] \
    || fail "commit count changed despite the guard firing"

# --- Case 2: the same wrapping outside claude/ must pass --------------------
git restore --staged claude/rules/wrapped.md
rm claude/rules/wrapped.md
printf 'This paragraph was hard wrapped\nacross two lines.\n' > docs/wrapped.md
git add docs/wrapped.md
git commit -qm outside-claude || fail "Markdown outside claude/ was blocked"

# --- Case 3: a fixed file must commit -------------------------------------
"$WORK/custom_bins/md-unwrap" --fix --quiet docs/wrapped.md
cp docs/wrapped.md claude/rules/fixed.md
git add claude/rules/fixed.md
git commit -qm fixed || fail "an unwrapped file under claude/ was blocked"

# --- Case 4: fixing the working tree without re-staging must STILL fail -----
# The gate reads staged content, which is the whole reason it is a pre-commit
# hook rather than a working-tree linter.
printf 'Wrapped again\nover two lines.\n' > claude/rules/stale.md
git add claude/rules/stale.md
"$WORK/custom_bins/md-unwrap" --fix --quiet claude/rules/stale.md
if git commit -qm stale-index >/dev/null 2>&1; then
    fail "a stale hard-wrapped index entry was committed"
fi

# --- Case 5: code fences and tables under claude/ must not trip the guard ---
git restore --staged claude/rules/stale.md
rm claude/rules/stale.md
cat > claude/rules/structured.md <<'MD'
# Heading

```python
x = (1
     + 2)
```

| a | b |
|---|---|
| 1 | 2 |
MD
git add claude/rules/structured.md
git commit -qm structured || fail "code fences or tables tripped the guard"

# --- Case 6: a repo with no checker present must not be gated --------------
OTHER="$(mktemp -d "${TMPDIR:-/tmp}/md-wrap-nocheck.XXXXXX")"
cd "$OTHER"
git init -q .
git config user.email test@example.com
git config user.name test
git config commit.gpgsign false
git config core.hooksPath "$HOOKS_DIR"
mkdir -p claude/rules
printf 'Wrapped\nlines.\n' > claude/rules/anything.md
PATH_WITHOUT_CHECKER="$(echo "$PATH" | tr ':' '\n' | grep -v custom_bins | paste -sd:)"
git add claude/rules/anything.md
PATH="$PATH_WITHOUT_CHECKER" git commit -qm no-checker \
    || fail "a repo without md-unwrap was gated anyway"
rm -rf "$OTHER"

echo "PASS: Markdown hard-wrap guard blocks wrapped claude/ Markdown and nothing else"
