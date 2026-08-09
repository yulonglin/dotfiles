#!/usr/bin/env bash
# Tests for block_vault_structure.sh, inject_vault_layout.sh,
# nudge_vault_lint.sh (spec: vault/specs/2026-08-03-vault-cleanup-and-enforcement.md
# R8-R10). Runs against fixture trees via the VAULT_STRUCTURE_* env overrides,
# but reads the REAL conf/ files so the shipped allowlists are what's tested.
# shellcheck disable=SC2015  # ok() always succeeds, so `A && ok || fail` is safe
set -uo pipefail

HOOKS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../claude/hooks" && pwd)"
# sandbox trap: TMPDIR can point at a read-only /run/user/<uid>; prefer /tmp/claude
TMP=$(mktemp -d /tmp/claude/vault-hooks-test.XXXXXX 2>/dev/null \
  || mktemp -d "${TMPDIR:-/tmp}/vault-hooks-test.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT

VAULT="$TMP/vault"
CODE="$TMP/code"
mkdir -p "$VAULT/research/mytopic/specs" "$VAULT/writing/drafts" \
  "$VAULT/tooling/dotfiles/specs" "$VAULT/tooling/dotfiles/plans" \
  "$CODE/dotfiles"

PASS=0 FAIL=0
ok()   { PASS=$((PASS + 1)); echo "ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }
check() { local desc=$1; shift; if "$@" >/dev/null 2>&1; then ok "$desc"; else fail "$desc"; fi; }

run_block() {
  printf '{"tool_input":{"file_path":"%s"}}' "$1" |
    VAULT_STRUCTURE_VAULT="$VAULT" VAULT_STRUCTURE_CODE_DIR="$CODE" \
    bash "$HOOKS/block_vault_structure.sh"
}
denied()  { run_block "$1" | grep -q '"permissionDecision": *"deny"'; }
allowed() { [ -z "$(run_block "$1")" ]; }

run_lint() {
  printf '{"cwd":"%s"}' "${2:-$VAULT}" |
    VAULT_STRUCTURE_VAULT="$VAULT" VAULT_STRUCTURE_CODE_DIR="$CODE" \
    bash "$HOOKS/nudge_vault_lint.sh"
}
lint_flags() { run_lint | grep -qF "$1"; }

run_inject() {
  printf '{"cwd":"%s"}' "$1" |
    VAULT_STRUCTURE_VAULT="$VAULT" bash "$HOOKS/inject_vault_layout.sh"
}

echo "=== block_vault_structure.sh: vault root ==="
check "denies write into new root-level dir"        denied  "$VAULT/newdir/foo.md"
check "denies loose file at vault root"             denied  "$VAULT/loose.md"
check "allows dot-entry at vault root"              allowed "$VAULT/.obsidian/config.json"
check "allows deep write inside allowed root dir"   allowed "$VAULT/writing/drafts/deep/post.md"
run_block "$VAULT/newdir/foo.md" | grep -q 'research' \
  && ok "root deny message names allowed dirs" || fail "root deny message names allowed dirs"

echo "=== block_vault_structure.sh: research/<topic>/ ==="
check "denies loose file at topic level"            denied  "$VAULT/research/mytopic/notes.md"
check "denies new dir at topic level"               denied  "$VAULT/research/mytopic/experiments/x.md"
check "allows write inside specs/"                  allowed "$VAULT/research/mytopic/specs/2026-08-09-x.md"
check "allows sanctioned topic file README.md"      allowed "$VAULT/research/mytopic/README.md"
check "allows sanctioned topic file LOG.md"         allowed "$VAULT/research/mytopic/LOG.md"
check "allows docs/ (in allowlist)"                 allowed "$VAULT/research/mytopic/docs/runbook.md"
check "allows dot-entry at topic level"             allowed "$VAULT/research/mytopic/.claude/settings.json"
check "allows new topic started canonically"        allowed "$VAULT/research/newtopic/README.md"
check "denies new topic started non-canonically"    denied  "$VAULT/research/newtopic/scratch.md"
run_block "$VAULT/research/mytopic/notes.md" | grep -q 'docs/' \
  && ok "topic deny message names canonical homes" || fail "topic deny message names canonical homes"

echo "=== block_vault_structure.sh: repo symlink guard ==="
mkdir -p "$CODE/dotfiles/specs"
check "denies write under real repo dir that should be a symlink" \
  denied "$CODE/dotfiles/specs/new-spec.md"
run_block "$CODE/dotfiles/specs/new-spec.md" | grep -q 'tooling/dotfiles/specs' \
  && ok "repo deny message names the vault home" || fail "repo deny message names the vault home"
rmdir "$CODE/dotfiles/specs"
ln -s "$VAULT/tooling/dotfiles/specs" "$CODE/dotfiles/specs"
check "passes write through the intended symlink" \
  allowed "$CODE/dotfiles/specs/new-spec.md"
check "ignores unrelated paths outside vault and repos" \
  allowed "$TMP/elsewhere/scratch.md"

echo "=== nudge_vault_lint.sh ==="
[ -z "$(run_lint)" ] && ok "silent on clean fixture" || fail "silent on clean fixture"
[ -z "$(run_lint "" "$TMP/elsewhere")" ] && ok "silent when cwd outside vault" \
  || fail "silent when cwd outside vault"

mkdir -p "$VAULT/badroot" \
  "$VAULT/research/mytopic/loosedir" \
  "$VAULT/writing/node_modules/pkg" \
  "$VAULT/writing/__pycache__" \
  "$VAULT/writing/.cache" \
  "$VAULT/writing/archive"
touch "$VAULT/rootloose.md" \
  "$VAULT/research/mytopic/loose-note.md" \
  "$VAULT/writing/Untitled 3.md" \
  "$VAULT/writing/post (Conflicted copy 2026-08-01).md" \
  "$VAULT/writing/archive/Untitled.md"
truncate -s 2M "$VAULT/writing/build.log" 2>/dev/null \
  || dd if=/dev/zero of="$VAULT/writing/build.log" bs=1024 count=2048 2>/dev/null

check "flags unexpected root dir"        lint_flags "unexpected top-level dir: badroot/"
check "flags loose root file"            lint_flags "loose top-level file: rootloose.md"
check "flags topic-level dir drift"      lint_flags "research/mytopic/loosedir"
check "flags topic-level file drift"     lint_flags "research/mytopic/loose-note.md"
check "flags node_modules"               lint_flags "node_modules"
check "flags __pycache__"                lint_flags "__pycache__"
check "flags .cache"                     lint_flags ".cache"
check "flags oversized .log"             lint_flags "build.log"
check "flags Untitled*"                  lint_flags "Untitled 3.md"
check "flags Conflicted copy"            lint_flags "Conflicted copy"
run_lint | grep -qF "archive/Untitled.md" \
  && fail "does not flag artifacts inside archive/" \
  || ok "does not flag artifacts inside archive/"

rm -f "$CODE/dotfiles/specs"
mkdir -p "$CODE/dotfiles/specs"
check "flags repo dir that lost its symlink" lint_flags "code/dotfiles/specs"

echo "=== inject_vault_layout.sh ==="
INJ=$(run_inject "$VAULT/research/mytopic")
printf '%s' "$INJ" | grep -q 'research/<topic>/' \
  && ok "injects layout when cwd inside vault" || fail "injects layout when cwd inside vault"
printf '%s' "$INJ" | grep -q 'specs/' \
  && ok "layout lists conf-derived dirs" || fail "layout lists conf-derived dirs"
printf '%s' "$INJ" | grep -q 'docs/' \
  && ok "layout includes docs/ from conf" || fail "layout includes docs/ from conf"
[ -z "$(run_inject "$TMP/elsewhere")" ] \
  && ok "silent when cwd outside vault" || fail "silent when cwd outside vault"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
