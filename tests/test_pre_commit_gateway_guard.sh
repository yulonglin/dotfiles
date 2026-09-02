#!/usr/bin/env bash
# Pins the machine-local gateway guard in config/git-hooks/pre-commit.
#
# The guard exists because model-router writes a per-machine
# ANTHROPIC_BASE_URL=http://127.0.0.1:<port>/t/<token> into the user-level
# settings.json, which is symlinked into this public repo. gitleaks does not
# flag it (a bare hex token in a URL path has no adjacent secret keyword), so
# without this hook a routine `git add claude/settings.json` publishes it.
#
# Both directions are asserted: a guard that blocks everything is as useless as
# one that blocks nothing.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Overridable so the guard can be mutation-tested against a modified copy.
HOOKS_DIR="${HOOKS_DIR:-$REPO_ROOT/config/git-hooks}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/gateway-guard-test.XXXXXX")"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

write_settings() {
    # $1 = destination, $2 = extra env JSON entries (may be empty)
    local dest="$1" extra="$2"
    if [ -n "$extra" ]; then
        printf '{"env":{"TMPDIR":"/tmp/claude",%s},"statusLine":{},"hooks":{},"permissions":{}}\n' "$extra" > "$dest"
    else
        printf '{"env":{"TMPDIR":"/tmp/claude"},"statusLine":{},"hooks":{},"permissions":{}}\n' > "$dest"
    fi
}

cd "$WORK"
git init -q .
git config user.email test@example.com
git config user.name test
git config commit.gpgsign false
git config core.hooksPath "$HOOKS_DIR"
mkdir -p claude

# Baseline commit, hook bypassed so the starting point is unconditional.
write_settings claude/settings.json ""
git add claude/settings.json
git commit -qm baseline --no-verify
baseline_count="$(git rev-list --count HEAD)"

# --- Case 1: a model-router shaped value must be rejected -------------------
# The token here is synthetic. Never paste a live gateway token into a fixture:
# the fixture is committed, so it would leak the very value this guard protects.
write_settings claude/settings.json \
    '"ANTHROPIC_BASE_URL":"http://127.0.0.1:8787/t/0123456789abcdef0123456789abcdef"'
git add claude/settings.json
if git commit -qm with-token >/dev/null 2>&1; then
    fail "tokened ANTHROPIC_BASE_URL was committed; guard did not fire"
fi
[ "$(git rev-list --count HEAD)" = "$baseline_count" ] \
    || fail "commit count changed despite the guard firing"

# --- Case 2: a tokened loopback URL under any other key ---------------------
git restore --staged claude/settings.json
write_settings claude/settings.json \
    '"SOME_OTHER_GATEWAY":"http://localhost:9999/t/deadbeefcafebabe0123456789abcdef"'
git add claude/settings.json
if git commit -qm other-key >/dev/null 2>&1; then
    fail "tokened loopback URL under a non-ANTHROPIC key was committed"
fi

# --- Case 3: a clean settings.json must still commit -----------------------
git restore --staged claude/settings.json
write_settings claude/settings.json '"FOO":"bar"'
git add claude/settings.json
git commit -qm clean >/dev/null 2>&1 \
    || fail "clean settings.json was blocked (false positive)"
[ "$(git rev-list --count HEAD)" -gt "$baseline_count" ] \
    || fail "clean settings.json did not produce a commit"

# --- Case 4: a plain loopback URL with no token is not a credential --------
write_settings claude/settings.json '"HEALTH_URL":"http://127.0.0.1:18080/healthz"'
git add claude/settings.json
git commit -qm plain-loopback >/dev/null 2>&1 \
    || fail "untokened loopback URL was blocked (false positive)"

echo "PASS: gateway guard blocks tokened loopback endpoints and allows clean settings"
