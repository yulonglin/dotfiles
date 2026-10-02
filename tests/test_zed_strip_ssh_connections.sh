#!/usr/bin/env bash
# Pins scripts/git-filters/zed-strip-ssh-connections, the clean filter that
# keeps Zed's ssh_connections block out of every blob git stores for
# config/zed/settings.json while Zed keeps writing it to the working copy.
#
# Part 1 feeds fixtures straight to the filter: the key absent (byte-identical
# output), first / middle / last / only member, the key's name and brackets
# inside comments and strings, a nested key that must stay, trailing commas,
# malformed input passed through untouched, and idempotence on every case.
# Part 2 wires the filter into a throwaway repo the way deploy.sh does and
# checks what git status, git add and a pull actually do with it.
#
# Hostnames here are synthetic. Never paste a real host into a fixture: the
# fixture is committed, so it would leak what this filter protects.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILTER="${FILTER:-$REPO_ROOT/scripts/git-filters/zed-strip-ssh-connections}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/zed-strip-test.XXXXXX")"
WORK="${WORK//\/\///}"
trap 'rm -rf "$WORK"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
# An empty template: the Claude Code sandbox refuses writes under .git/hooks.
mkdir -p "$WORK/template"
export GIT_TEMPLATE_DIR="$WORK/template"

passed=0
fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "ok - $*"; passed=$((passed + 1)); }

# expect NAME: filters $WORK/in, compares with $WORK/want, then checks that a
# second pass changes nothing.
expect() {
    "$FILTER" <"$WORK/in" >"$WORK/out" || fail "$1: filter exited non-zero"
    if ! cmp -s "$WORK/out" "$WORK/want"; then
        diff "$WORK/want" "$WORK/out" >&2 || true
        fail "$1: output differs from expected (diff above: < want, > got)"
    fi
    "$FILTER" <"$WORK/out" >"$WORK/out2"
    cmp -s "$WORK/out" "$WORK/out2" || fail "$1: not idempotent"
    pass "$1"
}

# Unchanged: the output must be the input, byte for byte.
expect_same() {
    cp "$WORK/in" "$WORK/want"
    expect "$1"
}

# === Part 1: the filter on its own ===========================================

# The committed blob, not the working copy: in a live checkout the working copy
# is Zed's own file and may hold an ssh_connections block right now.
git -C "$REPO_ROOT" show HEAD:config/zed/settings.json >"$WORK/in"
expect_same "the committed Zed settings pass through byte-identical"

cat >"$WORK/in" <<'EOF'
{
  // Remote hosts belong in ~/.ssh/config, not "ssh_connections": [ { } ],
  /* "ssh_connections": [], { "a", } */
  "note": "ssh_connections",
  "brace_text": "}{][,:",
  "nested": { "ssh_connections": [{ "host": "nested.example" }] },
  "vim_mode": true,
}
EOF
expect_same "key only in comments, a string value and a nested object: unchanged"

cat >"$WORK/in" <<'EOF'
{
  // === Editor ===
  "vim_mode": true,
  "ssh_connections": [
    {
      "host": "dev-box.example.invalid",
      "projects": [{ "paths": ["/srv/project, with {braces}"] }],
      "args": ["-o", "ServerAliveInterval=30"], // trailing note
    },
  ],
  "buffer_font_size": 14,
}
EOF
cat >"$WORK/want" <<'EOF'
{
  // === Editor ===
  "vim_mode": true,
  "buffer_font_size": 14,
}
EOF
expect "middle member, with braces and commas inside strings and comments"

cat >"$WORK/in" <<'EOF'
{
  "ssh_connections": [{ "host": "first.example.invalid", "projects": [] }],
  // the comment above vim_mode stays
  "vim_mode": true
}
EOF
cat >"$WORK/want" <<'EOF'
{
  // the comment above vim_mode stays
  "vim_mode": true
}
EOF
expect "first member"

cat >"$WORK/in" <<'EOF'
{
  "vim_mode": true,
  "ssh_connections": [{ "host": "last.example.invalid", "projects": [] }]
}
EOF
cat >"$WORK/want" <<'EOF'
{
  "vim_mode": true
}
EOF
expect "last member, strict JSON: the dangling comma before it goes too"

cat >"$WORK/in" <<'EOF'
{
  "vim_mode": true,
  "ssh_connections": [{ "host": "last.example.invalid", "projects": [] }],
}
EOF
cat >"$WORK/want" <<'EOF'
{
  "vim_mode": true,
}
EOF
expect "last member with a trailing comma"

printf '{"ssh_connections":[{"host":"only.example.invalid"}]}' >"$WORK/in"
printf '{}' >"$WORK/want"
expect "only member, one line"

printf '{"a": 1, "ssh_connections": [], "b": [1, 2]}\n' >"$WORK/in"
printf '{"a": 1, "b": [1, 2]}\n' >"$WORK/want"
expect "middle member, one line"

printf '{"a": 1, "ssh_connections": {"x": "}"}}\n' >"$WORK/in"
printf '{"a": 1}\n' >"$WORK/want"
expect "last member, one line"

cat >"$WORK/in" <<'EOF'
{
  "ssh_connections": [],
  "vim_mode": true,
  "ssh_connections": [{ "host": "dup.example.invalid" }],
}
EOF
cat >"$WORK/want" <<'EOF'
{
  "vim_mode": true,
}
EOF
expect "duplicate top-level keys: every copy goes"

printf '{\n  "a": 1,\n  "ssh_connections": [\n' >"$WORK/in"
expect_same "truncated file: passed through untouched"

printf '{\n  "a": 1,\n  "ssh_connections": [ "unterminated ],\n}\n' >"$WORK/in"
expect_same "unterminated string: passed through untouched"

printf '[{"ssh_connections": []}]\n' >"$WORK/in"
expect_same "root is not an object: passed through untouched"

printf '{"a": 1 "ssh_connections": []}\n' >"$WORK/in"
expect_same "missing comma: passed through untouched"

printf '\xff\xfe{"ssh_connections": []}\n' >"$WORK/in"
expect_same "invalid UTF-8: passed through untouched"

: >"$WORK/in"
expect_same "empty input: empty output"

# === Part 2: the filter wired into git =======================================
#
# The filter is copied into the throwaway repo at its real repo-relative path
# and configured with that relative path, exactly as deploy.sh sets it, so this
# also proves git resolves the command from the top of the working tree.

R="$WORK/repo"
git init -q -b main "$R"
mkdir -p "$R/config/zed" "$R/scripts/git-filters" "$R/sub/dir"
cp "$FILTER" "$R/scripts/git-filters/zed-strip-ssh-connections"
printf 'config/zed/settings.json filter=zed-ssh\n' >"$R/.gitattributes"
S="$R/config/zed/settings.json"

base_settings() {
    cat >"$S" <<'EOF'
{
  // === Editor ===
  "vim_mode": true,
  "buffer_font_size": 14,
}
EOF
}
with_hosts() {
    # $1 = buffer_font_size value
    cat >"$S" <<EOF
{
  // === Editor ===
  "vim_mode": true,
  "ssh_connections": [{ "host": "remote.example.invalid", "projects": [{ "paths": ["/srv/app"] }] }],
  "buffer_font_size": $1,
}
EOF
}
dirty() { [ -n "$(git -C "$R" status --porcelain -- config/zed/settings.json)" ]; }

base_settings
git -C "$R" add .gitattributes config scripts
git -C "$R" commit -q -m base

# Negative control: without the filter configured, the same edit is dirty.
with_hosts 14
dirty || fail "control: ssh_connections edit should be dirty without the filter"
pass "control: without the filter, an ssh_connections-only edit shows as modified"

git -C "$R" config filter.zed-ssh.clean scripts/git-filters/zed-strip-ssh-connections
with_hosts 14
# git status trusts a size change without reading the file, so right after Zed
# writes the block the file is listed as modified even though its filtered
# content equals the index. git diff reads it and shows nothing; the next
# git add stages nothing and refreshes the cached stat, after which it is clean.
git -C "$R" diff --quiet -- config/zed/settings.json || fail "git diff shows an ssh_connections-only edit"
# Staged from a subdirectory: git runs the relative filter command from the top
# of the working tree, or it would warn, skip the filter and stage the block.
(cd "$R/sub/dir" && git add -- ../../config/zed/settings.json)
git -C "$R" diff --cached --quiet || fail "git add staged an ssh_connections-only edit"
dirty && fail "ssh_connections-only edit still listed after git add refreshed the stat"
[ -z "$(cd "$R/sub/dir" && git status --porcelain)" ] || fail "dirty when git status runs from a subdirectory"
[ -z "$(git -C "$R/sub" status --porcelain)" ] || fail "dirty when git status runs via git -C from a subdirectory"
pass "with the filter, an ssh_connections-only edit diffs empty, stages nothing, and status is clean after git add (top, subdir, git -C)"

with_hosts 16
dirty || fail "a real settings change was hidden by the filter"
git -C "$R" add config/zed/settings.json
git -C "$R" diff --cached -- config/zed/settings.json >"$WORK/staged.diff"
grep -q '^+  "buffer_font_size": 16,$' "$WORK/staged.diff" || fail "the font-size change was not staged"
[ "$(grep -c '^[-+] ' "$WORK/staged.diff")" = 2 ] || fail "staged diff carries more than the font-size line: $(cat "$WORK/staged.diff")"
git -C "$R" show :config/zed/settings.json | grep -q ssh_connections && fail "ssh_connections reached the index"
grep -q remote.example.invalid "$S" || fail "the working copy lost its ssh_connections"
git -C "$R" commit -q -m font
dirty && fail "dirty after committing the filtered file"
pass "another setting changed too: only that line is staged, the working copy keeps its hosts"

# Filter configured after the block was already staged: a plain `git add` of an
# unchanged file does not re-run the filter, `git add --renormalize` does. The
# pre-commit guard's message names the second command because of this.
R2="$WORK/repo2"
git init -q -b main "$R2"
mkdir -p "$R2/config/zed" "$R2/scripts/git-filters"
cp "$FILTER" "$R2/scripts/git-filters/zed-strip-ssh-connections"
printf 'config/zed/settings.json filter=zed-ssh\n' >"$R2/.gitattributes"
cp "$S" "$R2/config/zed/settings.json"
# An old mtime keeps the index entry out of git's racy window, where it would
# re-read the file anyway and make the plain-add case pass by timing alone.
touch -t 202001010000 "$R2/config/zed/settings.json"
git -C "$R2" add .gitattributes config scripts
git -C "$R2" show :config/zed/settings.json | grep -q ssh_connections || fail "setup: block should be staged before the filter exists"
git -C "$R2" config filter.zed-ssh.clean scripts/git-filters/zed-strip-ssh-connections
git -C "$R2" add config/zed/settings.json
git -C "$R2" show :config/zed/settings.json | grep -q ssh_connections || fail "plain git add re-filtered an unchanged file; the guard message can drop --renormalize"
git -C "$R2" add --renormalize config/zed/settings.json
git -C "$R2" show :config/zed/settings.json | grep -q ssh_connections && fail "git add --renormalize left ssh_connections staged"
pass "already staged before the filter: plain git add keeps the block, git add --renormalize strips it"

# A pull that changes the file rewrites the working copy from the stripped
# blob. git sees the file as clean, so nothing protects the local block, and
# there is no smudge filter to restore it. Pinned so the trade-off stays visible.
git init -q --bare -b main "$WORK/remote.git"
git -C "$R" remote add origin "$WORK/remote.git"
git -C "$R" push -q -u origin main
git clone -q "$WORK/remote.git" "$WORK/other" 2>/dev/null
sed -i.bak 's/"vim_mode": true/"vim_mode": false/' "$WORK/other/config/zed/settings.json"
git -C "$WORK/other" commit -q -am "vim off"
git -C "$WORK/other" push -q
grep -q remote.example.invalid "$S" || fail "setup: working copy should hold the block before the pull"
git -C "$R" pull -q --rebase
grep -q '"vim_mode": false' "$S" || fail "the pulled change did not land"
if grep -q remote.example.invalid "$S"; then
    fail "pull kept the local ssh_connections; update this case and the docs, the trade-off is gone"
fi
pass "known trade-off: a pull that changes the file drops the local ssh_connections"

echo "All $passed zed-strip-ssh-connections checks passed."
