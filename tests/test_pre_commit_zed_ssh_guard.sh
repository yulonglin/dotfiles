#!/usr/bin/env bash
# Pins the Zed ssh_connections guard in config/git-hooks/pre-commit.
#
# config/zed/ is symlinked to ~/.config/zed/, and Zed writes the servers opened
# as remote projects into settings.json as ssh_connections. The zed-ssh clean
# filter strips them before git stores the file; this hook is the safety net
# for a clone without that filter, where a routine `git add` (or the daily
# dotfiles-sync) would publish personal hostnames and remote project paths.
#
# Both directions are asserted, and the fixtures use JSON with comments and
# trailing commas, because the real file does.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Overridable so the guard can be mutation-tested against a modified copy.
HOOKS_DIR="${HOOKS_DIR:-$REPO_ROOT/config/git-hooks}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/zed-ssh-guard-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

F=config/zed/settings.json

# Hostnames and paths here are synthetic. Never paste a real host into a
# fixture: the fixture is committed, so it would leak what this guard protects.
write_settings() {
    # $1 = extra top-level entries (may be empty); always JSONC with a comment
    cat > "$F" <<EOF
{
  // === Editor ===
  "vim_mode": true,
  "buffer_font_size": 14,
$1
}
EOF
}

cd "$WORK"
git init -q .
git config user.email test@example.com
git config user.name test
git config commit.gpgsign false
git config core.hooksPath "$HOOKS_DIR"
mkdir -p config/zed

write_settings ''
git add "$F"
git commit -qm baseline --no-verify
baseline_count="$(git rev-list --count HEAD)"

expect_blocked() {
    # $1 = case label; the file must already hold the content
    git add "$F"
    local out
    if out="$(git commit -qm "$1" 2>&1)"; then
        fail "$1: committed; guard did not fire"
    fi
    [ "$(git rev-list --count HEAD)" = "$baseline_count" ] \
        || fail "$1: commit count changed despite the guard firing"
    printf '%s\n' "$out" | grep -q 'ssh_connections block' \
        || fail "$1: rejected, but not by the ssh_connections guard: $out"
    printf '%s\n' "$out" | grep -q "git config --local filter.zed-ssh.clean scripts/git-filters/zed-strip-ssh-connections" \
        || fail "$1: error message does not give the filter setup command"
    printf '%s\n' "$out" | grep -q "git add --renormalize -- $F" \
        || fail "$1: error message does not say how to re-stage through the filter"
    git restore --staged "$F"
}

# --- Case 1: the block Zed writes, in a JSONC file with a trailing comma ----
write_settings '  // === SSH connections ===
  "ssh_connections": [
    { "host": "example-host", "args": [], "projects": [{ "paths": ["/home/example/code"] }] },
  ],'
expect_blocked zed-written-block

# --- Case 2: an empty list is still the key Zed fills in --------------------
write_settings '  "ssh_connections": []'
expect_blocked empty-list

# --- Case 3: unparseable JSONC falls back to the key match ------------------
write_settings '  "ssh_connections": [ { "host": "example-host" '
expect_blocked unparseable-fallback

# --- Case 4: other edits still commit, including the word in a comment -----
write_settings '  // ssh_connections is kept out of this file by the pre-commit hook
  "theme": "One Dark",'
git add "$F"
git commit -qm clean >/dev/null 2>&1 \
    || fail "clean settings.json was blocked (false positive)"
[ "$(git rev-list --count HEAD)" -gt "$baseline_count" ] \
    || fail "clean settings.json did not produce a commit"

# --- Case 5: the word as a string value is not the key ----------------------
write_settings '  "note": "ssh_connections live in ~/.ssh/config",'
git add "$F"
git commit -qm string-value >/dev/null 2>&1 \
    || fail "ssh_connections as a string value was blocked (false positive)"

# --- Case 6: only the index matters -----------------------------------------
write_settings '  "theme": "Ayu",'
git add "$F"
write_settings '  "ssh_connections": []'
git commit -qm index-only >/dev/null 2>&1 \
    || fail "an unstaged ssh_connections block blocked a clean staged blob"
git show "HEAD:$F" | grep -q '"ssh_connections"' \
    && fail "the unstaged ssh_connections block reached the commit"

# --- Case 7: with the clean filter configured, the guard never sees the block
# The real .gitattributes line and filter config, as deploy.sh --git-config
# sets them: the commit goes through, without the block, through the real hook.
mkdir -p scripts/git-filters
cp "$REPO_ROOT/scripts/git-filters/zed-strip-ssh-connections" scripts/git-filters/
grep -F 'filter=zed-ssh' "$REPO_ROOT/.gitattributes" > .gitattributes
git add .gitattributes scripts
git commit -qm filter-script --no-verify
git config filter.zed-ssh.clean scripts/git-filters/zed-strip-ssh-connections
write_settings '  "ssh_connections": [{ "host": "example-host", "projects": [] }],
  "theme": "Gruvbox",'
git add "$F"
git commit -qm filtered >/dev/null 2>&1 \
    || fail "a filtered settings.json was still blocked by the guard"
git show "HEAD:$F" | grep -q '"ssh_connections"' \
    && fail "ssh_connections reached the commit with the filter configured"
git show "HEAD:$F" | grep -q '"theme": "Gruvbox"' \
    || fail "the theme change did not reach the commit"
grep -q example-host "$F" || fail "the working copy lost its ssh_connections"

echo "PASS: zed guard blocks ssh_connections, allows clean settings.json, and agrees with the clean filter"
