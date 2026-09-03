#!/usr/bin/env bash
# shellcheck shell=bash
# Tests for custom_bins/claude-config-sync against fixture trees.
#
# The load-bearing blocks are the deletion ones. In 2026-06/07 a bidirectional
# Obsidian sync read an incomplete local vault as deletions and destroyed 135
# files -- so VAULT-side deletions are never propagated into the repo, ever.
# REPO-side deletions do propagate outbound (2026-09-01): quarantined rather
# than unlinked, refused in bulk without --allow-mass-delete, refused under an
# unscannable source dir, and refused when the vault copy carries a phone edit.
# shellcheck disable=SC2015  # ok() always succeeds, so `A && ok || fail` is safe
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/custom_bins/claude-config-sync"

# sandbox trap: TMPDIR can point at a read-only /run/user/<uid>; prefer /tmp/claude
TMP=$(mktemp -d /tmp/claude/ccsync-test.XXXXXX 2>/dev/null \
  || mktemp -d "${TMPDIR:-/tmp}/ccsync-test.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
VAULT="$TMP/vault"
DEST="$VAULT/tooling/claude-config"
STATE="$TMP/state.json"
OBDIR="$TMP/obsidian-headless"

PASS=0 FAIL=0
ok()   { PASS=$((PASS + 1)); echo "ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
check() { local desc=$1; shift; if "$@" >/dev/null 2>&1; then ok "$desc"; else fail "$desc"; fi; }
# pipefail makes `sync ... | grep` inherit the tool's non-zero exit, so a matched
# grep still reads as a failure. Output assertions capture first, then match.
says() {
  local desc=$1 want=$2; shift 2
  local out; out=$("$@" 2>&1 || true)
  if printf '%s' "$out" | grep -q "$want"; then ok "$desc"; else fail "$desc"; fi
}

# every run is pinned to the fixture: never the live vault, never the live repo
sync() { "$BIN" --repo-root "$REPO" --vault "$VAULT" --state "$STATE" --ob-config-dir "$OBDIR" "$@"; }
rc()   { "$@" >/dev/null 2>&1; echo $?; }

seed_repo() {
  mkdir -p "$REPO/claude/rules" "$REPO/claude/skills/demo" \
           "$REPO/claude/agents" "$REPO/claude/output-styles" \
           "$REPO/claude/checklists/results-analysis"
  echo "top" > "$REPO/claude/CLAUDE.md"
  echo "rule a" > "$REPO/claude/rules/a.md"
  echo "rule b" > "$REPO/claude/rules/b.md"
  echo "skill" > "$REPO/claude/skills/demo/SKILL.md"
  echo "agent" > "$REPO/claude/agents/x.md"
  echo "style" > "$REPO/claude/output-styles/y.md"
  echo "checklist" > "$REPO/claude/checklists/c.md"
  echo "nested checklist" > "$REPO/claude/checklists/results-analysis/n.md"
  # out of scope: must never be mirrored
  echo '{}' > "$REPO/claude/settings.json"
  mkdir -p "$REPO/claude/hooks"; echo "#!/bin/sh" > "$REPO/claude/hooks/h.sh"
}

register_vault() { # a vault that has completed a sync
  mkdir -p "$OBDIR/sync/abc"
  printf '{"vaultPath": "%s"}\n' "$VAULT" > "$OBDIR/sync/abc/config.json"
  printf 'Connected\nFully synced\n' > "$OBDIR/sync/abc/sync.log"
}

seed_repo
mkdir -p "$VAULT"

echo "=== preconditions: refuse to write into a vault that cannot be verified ==="
check "push refuses an unregistered vault"        test "$(rc sync push)" = 3
check "  ... and creates nothing"                 test ! -e "$DEST"
check "pull refuses an unregistered vault"        test "$(rc sync pull)" = 3
mkdir -p "$OBDIR/sync/abc"
printf '{"vaultPath": "%s"}\n' "$VAULT" > "$OBDIR/sync/abc/config.json"
printf 'Connected\nDisconnected from server\n' > "$OBDIR/sync/abc/sync.log"
check "push refuses a vault that never fully synced" test "$(rc sync push)" = 3
says "  ... and says why" "never finished a sync" sync push
register_vault
check "missing vault dir exits 3"                 test "$(rc "$BIN" --repo-root "$REPO" --vault "$TMP/nope" --state "$STATE" --ob-config-dir "$OBDIR" push)" = 3
check "  ... and status exits 3 too"              test "$(rc "$BIN" --repo-root "$REPO" --vault "$TMP/nope" --state "$STATE" --ob-config-dir "$OBDIR" status)" = 3

echo "=== dry run copies nothing ==="
says "dry run names each file" "would copy: rules/a.md" sync push --dry-run
check "dry run created no vault dir"              test ! -e "$DEST"
check "dry run wrote no state"                    test ! -e "$STATE"

echo "=== push: repo -> vault, scope respected ==="
check "push succeeds"                             test "$(rc sync push)" = 0
for f in CLAUDE.md rules/a.md rules/b.md skills/demo/SKILL.md agents/x.md output-styles/y.md \
         checklists/c.md checklists/results-analysis/n.md; do
  check "mirrored $f"                             test -f "$DEST/$f"
  check "  $f is a real file, not a symlink"      test ! -L "$DEST/$f"
done
check "settings.json NOT mirrored"                test ! -e "$DEST/settings.json"
check "hooks/ NOT mirrored"                       test ! -e "$DEST/hooks"
check "content matches"                           diff -q "$REPO/claude/rules/a.md" "$DEST/rules/a.md"
check "second push is a no-op"                    test "$(rc sync push)" = 0
says "  ... and says so" "nothing to copy" sync push

echo "=== one-sided edits flow the right way ==="
echo "rule a v2" > "$REPO/claude/rules/a.md"
sync push >/dev/null
check "repo edit reached the vault"               diff -q "$REPO/claude/rules/a.md" "$DEST/rules/a.md"
echo "rule b edited on phone" > "$DEST/rules/b.md"
says "status names the vault-side edit" "changed in vault.*rules/b.md" sync status
sync push >/dev/null
check "push does NOT clobber the vault-side edit" grep -q "phone" "$DEST/rules/b.md"
sync pull >/dev/null
check "pull applied the vault-side edit"          grep -q "phone" "$REPO/claude/rules/b.md"

echo "=== conflicts are listed and left alone ==="
echo "repo side" > "$REPO/claude/rules/a.md"
echo "vault side" > "$DEST/rules/a.md"
says "status reports the conflict" "CONFLICT.*rules/a.md" sync status
check "status exits 1 on conflict"                test "$(rc sync status)" = 1
sync push >/dev/null 2>&1
check "push left the vault side alone"            grep -q "vault side" "$DEST/rules/a.md"
sync pull >/dev/null 2>&1
check "pull left the repo side alone"             grep -q "repo side" "$REPO/claude/rules/a.md"
# resolve it by hand, the only way conflicts are ever resolved
cp "$REPO/claude/rules/a.md" "$DEST/rules/a.md"
sync push >/dev/null
check "conflict clears once both sides match"     test "$(rc sync status)" = 0

echo "=== VAULT deletions are NEVER propagated (the 2026-06 regression) ==="
rm "$DEST/rules/b.md"                             # a file vanishes on the vault side
sync push > "$TMP/push.out" 2>&1; push_rc=$?
sync pull > "$TMP/pull.out" 2>&1; pull_rc=$?
check "repo copy of the vanished file survives push+pull" test -f "$REPO/claude/rules/b.md"
check "push did NOT re-create it in the vault"    test ! -e "$DEST/rules/b.md"
grep -q "VANISHED from vault" "$TMP/push.out" \
  && ok "push reports the vanished file" || fail "push reports the vanished file"
check "push exits 1 (needs a human)"              test "$push_rc" = 1
check "pull exits 1 (needs a human)"              test "$pull_rc" = 1
# restore: recreating the same content clears the report
cp "$REPO/claude/rules/b.md" "$DEST/rules/b.md"
check "recreating the vault copy clears it"       test "$(rc sync push)" = 0

echo "=== REPO deletions propagate outbound, quarantined ==="
rm "$REPO/claude/agents/x.md"
says "dry run announces the removal" "would remove" sync push --dry-run
check "  ... and removed nothing"                 test -f "$DEST/agents/x.md"
check "a pending removal is not attention: status exits 0" test "$(rc sync status)" = 0
check "pull does not re-create a repo-deleted file" test "$(rc sync pull)" = 0
check "  ... in the repo"                         test ! -e "$REPO/claude/agents/x.md"
check "push exits 0"                              test "$(rc sync push)" = 0
check "vault copy removed"                        test ! -e "$DEST/agents/x.md"
Q=$(find "$TMP/removed" -type f -name "x.md" 2>/dev/null | head -1)
check "removed copy is quarantined, not unlinked" test -n "$Q"
check "  ... with its content intact"             grep -q "agent" "$Q"
check "state entry dropped"                       bash -c "! grep -q 'agents/x.md' '$STATE'"
check "next push is silent"                       test "$(rc sync push)" = 0
rm -rf "$REPO/claude/skills/demo"                 # a whole retired skill
sync push >/dev/null 2>&1
check "skill removal reaches the vault"           test ! -e "$DEST/skills/demo/SKILL.md"
check "  ... and prunes the empty skill dir"      test ! -e "$DEST/skills/demo"
check "  ... but never the mirror root"           test -d "$DEST"
# restore for later blocks
echo "agent" > "$REPO/claude/agents/x.md"
mkdir -p "$REPO/claude/skills/demo"; echo "skill" > "$REPO/claude/skills/demo/SKILL.md"
sync push >/dev/null 2>&1

echo "=== a phone edit shields a repo deletion ==="
echo "edited on phone after the deletion" > "$DEST/rules/b.md"
rm "$REPO/claude/rules/b.md"
sync push > "$TMP/push3.out" 2>&1; rc3=$?
check "edited vault copy is kept"                 test -f "$DEST/rules/b.md"
grep -q "EDITED in vault" "$TMP/push3.out" \
  && ok "push reports the edit-vs-deletion" || fail "push reports the edit-vs-deletion"
check "push exits 1 (needs a human)"              test "$rc3" = 1
cp "$DEST/rules/b.md" "$REPO/claude/rules/b.md"   # resolve by hand: keep the edit
check "restoring the repo copy resolves it"       test "$(rc sync push)" = 0

echo "=== the mass-delete guard refuses bulk removals without the flag ==="
for i in $(seq 1 12); do echo "bulk $i" > "$REPO/claude/rules/bulk$i.md"; done
sync push >/dev/null 2>&1
for i in $(seq 1 12); do rm "$REPO/claude/rules/bulk$i.md"; done
sync push > "$TMP/push4.out" 2>&1; rc4=$?
check "all 12 vault copies survive"               test "$(find "$DEST/rules" -name 'bulk*.md' | wc -l)" = 12
grep -q "mass-delete" "$TMP/push4.out" \
  && ok "the guard names itself" || fail "the guard names itself"
check "guarded push exits 1"                      test "$rc4" = 1
check "push --allow-mass-delete removes them"     test "$(rc sync push --allow-mass-delete)" = 0
check "  ... all 12"                              test "$(find "$DEST/rules" -name 'bulk*.md' | wc -l)" = 0

echo "=== an unscannable source dir is never read as deletions ==="
mv "$REPO/claude/agents" "$TMP/agents-real"
ln -s "$TMP/agents-real" "$REPO/claude/agents"    # deploy-transient symlink
sync push > "$TMP/push5.out" 2>&1; rc5=$?
check "vault copy under the symlinked dir survives" test -f "$DEST/agents/x.md"
grep -q "unscannable" "$TMP/push5.out" \
  && ok "push says why it kept the file" || fail "push says why it kept the file"
check "push exits 1"                              test "$rc5" = 1
says "status carries the same warning" "unscannable" sync status
rm "$REPO/claude/agents"; mv "$TMP/agents-real" "$REPO/claude/agents"
check "restoring the dir clears it"               test "$(rc sync push)" = 0

echo "=== inbound writes are validated before they touch the live config ==="
mkdir -p "$DEST/hooks"; echo "pwned" > "$DEST/hooks/evil.sh"
echo "pwned" > "$DEST/loose.md"
sync pull > "$TMP/pull3.out" 2>&1
check "out-of-shape vault file not written to repo" test ! -e "$REPO/claude/hooks/evil.sh"
grep -q "outside the mirrored shapes" "$TMP/pull3.out" \
  && ok "  ... and is reported as ignored" || fail "  ... and is reported as ignored"
ln -s /etc/passwd "$DEST/rules/link.md"
sync pull > "$TMP/pull4.out" 2>&1
check "symlink in vault is not followed into the repo" test ! -e "$REPO/claude/rules/link.md"
rm -f "$DEST/rules/link.md" "$DEST/loose.md"; rm -rf "$DEST/hooks"

echo "=== a wiped mirror reads as vanished files, not as work to redo ==="
rm -rf "$DEST"
check "push over a wiped mirror exits 1"          test "$(rc sync push)" = 1
check "  ... and re-creates nothing"              test ! -e "$DEST/rules/a.md"
says "  ... and reports every file as vanished" "VANISHED from vault" sync push
check "  ... and the repo is untouched"           test -f "$REPO/claude/rules/a.md"
rm -f "$STATE"                                    # the documented re-seed path
check "re-seeding after deleting the state works" test "$(rc sync push)" = 0
check "  ... and the mirror is back"              test -f "$DEST/rules/a.md"

echo "=== baselines do not leak between vaults ==="
# Reusing one state file against a different vault must not read as 50 deletions.
VAULT2="$TMP/vault2"
mkdir -p "$VAULT2" "$OBDIR/sync/def"
printf '{"vaultPath": "%s"}\n' "$VAULT2" > "$OBDIR/sync/def/config.json"
printf 'Fully synced\n' > "$OBDIR/sync/def/sync.log"
out=$("$BIN" --repo-root "$REPO" --vault "$VAULT2" --state "$STATE" --ob-config-dir "$OBDIR" push 2>&1 || true)
printf '%s' "$out" | grep -q "VANISHED" \
  && fail "a second vault does not inherit the first's baselines" \
  || ok "a second vault does not inherit the first's baselines"
check "  ... and it seeds normally"               test -f "$VAULT2/tooling/claude-config/rules/a.md"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
