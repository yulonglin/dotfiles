#!/usr/bin/env bash
# Pins the always-on guard in config/git-hooks/pre-commit.
#
# The byte budget and the bundled-skills check used to run only in CI, where a
# red push to main blocks nothing; main stayed red for 19 days. The hook now
# runs them on the STAGED content. Both directions are asserted: a clean commit
# passes, an over-budget rule file and a protected skill switched off are each
# blocked, and a dirty working tree does not block a clean index.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="${HOOKS_DIR:-$REPO_ROOT/config/git-hooks}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/always-on-guard-test.XXXXXX")"
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

# A minimal copy of the files the guard reads, taken from this checkout.
mkdir -p tests claude/rules claude/output-styles
cp "$REPO_ROOT/tests/test_memory_tier_budget.py" "$REPO_ROOT/tests/test_validate_claude_settings.py" tests/
cp "$REPO_ROOT"/claude/rules/*.md claude/rules/
cp "$REPO_ROOT"/claude/output-styles/*.md claude/output-styles/
cp "$REPO_ROOT/claude/CLAUDE.md" "$REPO_ROOT/claude/settings.json" claude/
cp "$REPO_ROOT/CLAUDE.md" CLAUDE.md
git add -A
git commit -qm baseline --no-verify
baseline="$(git rev-parse HEAD)"

expect_blocked() {
    local label="$1" marker="$2" out
    if out="$(git commit -qm "$label" 2>&1)"; then
        fail "$label: committed; guard did not fire"
    fi
    [ "$(git rev-parse HEAD)" = "$baseline" ] || fail "$label: HEAD moved"
    printf '%s\n' "$out" | grep -q "always-on guard failed" \
        || fail "$label: rejected, but not by the always-on guard: $out"
    printf '%s\n' "$out" | grep -q "$marker" \
        || fail "$label: message does not name the failing check ($marker): $out"
    git reset -q
}

# 1. A small rule edit within budget commits.
printf '\nA short clause.\n' >> claude/rules/experiments.md
git add claude/rules/experiments.md
git commit -qm within-budget || fail "within-budget: blocked a commit under the ceiling"
baseline="$(git rev-parse HEAD)"

# 2. A new 8,000-byte rule file is blocked.
python3 -c "open('claude/rules/zz-probe.md','w').write('x'*8000)"
git add claude/rules/zz-probe.md
expect_blocked over-budget "always-on tier is"

# 3. The same file left unstaged does not block an unrelated clean commit.
printf '\nOther.\n' >> claude/rules/experiments.md
git add claude/rules/experiments.md
git commit -qm dirty-tree-clean-index || fail "dirty-tree: an unstaged over-budget file blocked a clean index"
baseline="$(git rev-parse HEAD)"
rm -f claude/rules/zz-probe.md

# 4. Switching off a skill the Artifact tool needs is blocked.
python3 - <<'PY'
import json
p = "claude/settings.json"
d = json.load(open(p))
d["skillOverrides"]["artifact-design"] = "off"
json.dump(d, open(p, "w"), indent=2)
PY
git add claude/settings.json
expect_blocked protected-skill-off "required skills switched off"
git checkout -q -- claude/settings.json

# 5. Switching off an unprotected skill commits.
python3 - <<'PY'
import json
p = "claude/settings.json"
d = json.load(open(p))
d["skillOverrides"]["zz-unprotected-probe"] = "off"
json.dump(d, open(p, "w"), indent=2)
PY
git add claude/settings.json
git commit -qm unprotected-skill-off || fail "unprotected-skill-off: blocked a deliberate toggle"

echo "PASS: always-on guard blocks over-budget and protected-skill commits, passes clean ones"
