#!/usr/bin/env bash
# Tests for warn_spec_outside_vault.sh (spec: vault/specs/
# 2026-08-09-spec-driven-agent-workflow.md, detect-only hook requirement).
# Fixture trees via VAULT_STRUCTURE_VAULT; mirrors test_vault_structure_hooks.sh.
# The hook must NEVER block: exit 0 and no permissionDecision in every case.
# shellcheck disable=SC2015  # ok() always succeeds, so `A && ok || fail` is safe
set -uo pipefail

HOOKS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../claude/hooks" && pwd)"
# sandbox trap: TMPDIR can point at a read-only /run/user/<uid>; prefer /tmp/claude
TMP=$(mktemp -d /tmp/claude/spec-hook-test.XXXXXX 2>/dev/null \
  || mktemp -d "${TMPDIR:-/tmp}/spec-hook-test.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT

VAULT="$TMP/vault"
CODE="$TMP/code"
mkdir -p "$VAULT/specs" "$VAULT/tooling/dotfiles/specs" \
  "$VAULT/research/mytopic/specs" "$CODE/myrepo/specs" "$CODE/dotfiles" \
  "$CODE/elsewhere"
ln -s "$VAULT/tooling/dotfiles/specs" "$CODE/dotfiles/specs"

PASS=0 FAIL=0
ok()   { PASS=$((PASS + 1)); echo "ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

run_hook() {
  printf '{"tool_input":{"file_path":"%s"}}' "$1" |
    VAULT_STRUCTURE_VAULT="$VAULT" bash "$HOOKS/warn_spec_outside_vault.sh"
}

# Every invocation must exit 0 and never emit a permissionDecision.
# The output must be what the hook contract requires: EXACTLY ONE JSON
# object (slurp mode counts documents — an extra debug emission would break
# Claude's parse) with a non-empty string systemMessage and no
# permissionDecision key.
valid_warning_json() {
  jq -e -s 'length == 1 and (.[0] | (type=="object") and (.systemMessage|type=="string" and length>0) and (has("permissionDecision")|not))' >/dev/null 2>&1
}
check_warns() {
  local desc=$1 path=$2 out rc
  out=$(run_hook "$path"); rc=$?
  if [ "$rc" -eq 0 ] \
     && printf '%s' "$out" | valid_warning_json \
     && printf '%s' "$out" | jq -r -s '.[0].systemMessage' | grep -q 'outside the vault'; then
    ok "$desc"
  else
    fail "$desc (rc=$rc out=$out)"
  fi
}
check_silent() {
  local desc=$1 path=$2 out rc
  out=$(run_hook "$path"); rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    ok "$desc"
  else
    fail "$desc (rc=$rc out=$out)"
  fi
}

echo "=== warns: new spec outside the vault ==="
check_warns "new .md under an outside specs/ dir" "$CODE/myrepo/specs/new-thing.md"
check_warns "relative specs/ path outside the vault" "specs/new-thing.md"

echo "=== silent: existing file ==="
touch "$CODE/myrepo/specs/existing.md"
check_silent "existing .md under an outside specs/ dir" "$CODE/myrepo/specs/existing.md"

echo "=== silent: inside the vault (real layout shapes) ==="
check_silent "new .md under \$VAULT/specs/"                 "$VAULT/specs/new.md"
check_silent "new .md under tooling/<repo>/specs/"          "$VAULT/tooling/dotfiles/specs/new.md"
check_silent "new .md under research/<topic>/specs/"        "$VAULT/research/mytopic/specs/new.md"
check_silent "write through repo specs/ symlink into vault" "$CODE/dotfiles/specs/new.md"

echo "=== silent: not a new spec ==="
check_silent "non-md under an outside specs/ dir"  "$CODE/myrepo/specs/data.json"
check_silent "new .md outside any specs/ dir"      "$CODE/elsewhere/notes.md"
check_silent "file merely NAMED specs.md"          "$CODE/elsewhere/specs.md"

echo "=== fail-open ==="
BASH_BIN=$(command -v bash)
out=$(printf '{"tool_input":{"file_path":"%s"}}' "$CODE/myrepo/specs/other.md" |
  VAULT_STRUCTURE_VAULT="$VAULT" PATH=/nonexistent "$BASH_BIN" "$HOOKS/warn_spec_outside_vault.sh"); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "missing jq: silent exit 0" \
  || fail "missing jq: silent exit 0 (rc=$rc out=$out)"

out=$(printf 'not json' | VAULT_STRUCTURE_VAULT="$VAULT" bash "$HOOKS/warn_spec_outside_vault.sh"); rc=$?
[ "$rc" -eq 0 ] && [ -z "$out" ] && ok "unparseable input: silent exit 0" \
  || fail "unparseable input: silent exit 0 (rc=$rc out=$out)"

echo "=== assertion self-checks (mutations the predicate must reject) ==="
printf '{"debug":1}\n{"systemMessage":"outside the vault: x"}' | valid_warning_json \
  && fail "predicate rejects a two-document stream" \
  || ok "predicate rejects a two-document stream"
printf '"systemMessage": "outside the vault"' | valid_warning_json \
  && fail "predicate rejects a bare non-object fragment" \
  || ok "predicate rejects a bare non-object fragment"
printf '{"systemMessage":"outside the vault","permissionDecision":"deny"}' | valid_warning_json \
  && fail "predicate rejects output carrying permissionDecision" \
  || ok "predicate rejects output carrying permissionDecision"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
