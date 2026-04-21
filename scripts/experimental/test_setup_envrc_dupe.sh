#!/usr/bin/env bash
# Hermetic test for setup-envrc / dotfiles-secrets duplicate-bws-key flow.
# Uses a fake HOME so the live secrets cache is untouched.
set -euo pipefail

DOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
HELPER="$DOT_DIR/custom_bins/dotfiles-secrets"
export DOT_DIR
export DOTFILES_SECRETS_BACKEND=bws

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT
export HOME="$TEST_HOME"
export BWS_ACCESS_TOKEN="test-token"   # avoids require_bws reading real token
mkdir -p "$TEST_HOME/.cache/dotfiles-secrets"

# Synthesize cache as if BWS returned two OPENAI_API_KEY entries plus HF_TOKEN
printf 'OPENAI_API_KEY=sk-matsval\nOPENAI_API_KEY=sk-personalval\nHF_TOKEN=hf_xyz\n' \
    > "$TEST_HOME/.cache/dotfiles-secrets/secrets.bws.cache"
printf '%s\n' \
    $'OPENAI_API_KEY\tOPENAI_API_KEY - mats\tmats account' \
    $'OPENAI_API_KEY\tOPENAI_API_KEY - personal\tpersonal account' \
    $'HF_TOKEN\tHF_TOKEN\t' \
    > "$TEST_HOME/.cache/dotfiles-secrets/meta.bws.cache"
{
  printf '%s\t%s\t%s\n' "OPENAI_API_KEY - mats" \
      "$(printf sk-matsval | base64 | tr -d '\n')" "mats account"
  printf '%s\t%s\t%s\n' "OPENAI_API_KEY - personal" \
      "$(printf sk-personalval | base64 | tr -d '\n')" "personal account"
  printf '%s\t%s\t%s\n' "HF_TOKEN" \
      "$(printf hf_xyz | base64 | tr -d '\n')" ""
} > "$TEST_HOME/.cache/dotfiles-secrets/raw.bws.cache"

pass=0; fail=0
check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "  ok  $name"
    pass=$((pass+1))
  else
    echo "  FAIL $name"
    echo "    expected: ${expected@Q}"
    echo "    actual:   ${actual@Q}"
    fail=$((fail+1))
  fi
}

echo "== keys-meta =="
meta=$("$HELPER" keys-meta)
check "keys-meta rows" \
    $'OPENAI_API_KEY\tOPENAI_API_KEY - mats\tmats account\nOPENAI_API_KEY\tOPENAI_API_KEY - personal\tpersonal account\nHF_TOKEN\tHF_TOKEN\t' \
    "$meta"

echo "== bws-dump =="
# Just check row count + first column sane
dump=$("$HELPER" bws-dump)
rows=$(printf '%s\n' "$dump" | wc -l | tr -d ' ')
check "bws-dump row count" "3" "$rows"

echo "== get-value =="
check "get-value mats"     "sk-matsval"     "$("$HELPER" get-value 'OPENAI_API_KEY - mats')"
check "get-value personal" "sk-personalval" "$("$HELPER" get-value 'OPENAI_API_KEY - personal')"
check "get-value HF_TOKEN" "hf_xyz"         "$("$HELPER" get-value 'HF_TOKEN')"
# Ambiguous env_name fallback must fail (two OPENAI_API_KEY rows).
if "$HELPER" get-value 'OPENAI_API_KEY' >/dev/null 2>&1; then
  echo "  FAIL get-value ambiguous env_name returned a value"; fail=$((fail+1))
else
  echo "  ok  get-value rejects ambiguous env_name"; pass=$((pass+1))
fi

echo "== get-value unknown =="
if "$HELPER" get-value 'DOES_NOT_EXIST' >/dev/null 2>&1; then
  echo "  FAIL unknown key returned success"
  fail=$((fail+1))
else
  echo "  ok  unknown key exits non-zero"
  pass=$((pass+1))
fi

echo "== write-telegram-env (duplicate refusal, exact ok) =="
TG_STATE=$(mktemp -d)
# Unambiguous env_name writes successfully.
if "$HELPER" write-telegram-env HF_TOKEN "$TG_STATE" >/dev/null 2>&1; then
  if [[ "$(cat "$TG_STATE/.env")" == "TELEGRAM_BOT_TOKEN=hf_xyz" ]]; then
    echo "  ok  telegram write HF_TOKEN"; pass=$((pass+1))
  else
    echo "  FAIL telegram write HF_TOKEN content: $(cat "$TG_STATE/.env")"; fail=$((fail+1))
  fi
else
  echo "  FAIL telegram write HF_TOKEN"; fail=$((fail+1))
fi
# Ambiguous env_name must fail.
rm -f "$TG_STATE/.env"
if "$HELPER" write-telegram-env OPENAI_API_KEY "$TG_STATE" >/dev/null 2>&1; then
  echo "  FAIL telegram accepted ambiguous OPENAI_API_KEY"; fail=$((fail+1))
else
  echo "  ok  telegram rejects ambiguous env_name"; pass=$((pass+1))
fi
# Exact BWS key must write the right tenant.
if "$HELPER" write-telegram-env 'OPENAI_API_KEY - personal' "$TG_STATE" >/dev/null 2>&1; then
  if [[ "$(cat "$TG_STATE/.env")" == "TELEGRAM_BOT_TOKEN=sk-personalval" ]]; then
    echo "  ok  telegram write exact bws key"; pass=$((pass+1))
  else
    echo "  FAIL telegram exact: $(cat "$TG_STATE/.env")"; fail=$((fail+1))
  fi
else
  echo "  FAIL telegram exact key failed"; fail=$((fail+1))
fi
rm -rf "$TG_STATE"

echo "== shell (duplicate refusal, single ok) =="
# Single-record env should still export cleanly via `shell`.
shell_hf=$("$HELPER" shell HF_TOKEN 2>/dev/null || true)
if [[ "$shell_hf" == "export HF_TOKEN="* ]]; then
  echo "  ok  shell HF_TOKEN exports"
  pass=$((pass+1))
else
  echo "  FAIL shell HF_TOKEN: ${shell_hf@Q}"
  fail=$((fail+1))
fi
# Duplicate env should NOT export; stderr should mention ambiguity.
shell_err=$("$HELPER" shell OPENAI_API_KEY 2>&1 >/dev/null || true)
shell_out=$("$HELPER" shell OPENAI_API_KEY 2>/dev/null || true)
if [[ -z "$shell_out" && "$shell_err" == *"ambiguous"* ]]; then
  echo "  ok  shell OPENAI_API_KEY refuses ambiguous"
  pass=$((pass+1))
else
  echo "  FAIL shell dup: out=${shell_out@Q} err=${shell_err@Q}"
  fail=$((fail+1))
fi

echo "== setup-envrc canonicalize (bws_key binding) =="
# Source canonicalize_binding and supporting fns
{ sed -n '/^is_bws_key() {/,/^}/p; /^canonicalize_binding() {/,/^}/p; /^binding_env_key() {/,/^}/p; /^binding_secret_key() {/,/^}/p; /^validate_env_name() {/,/^}/p; /^die() {/,/^}/p; /^has_line() {/,/^}/p; /^normalize_export_bindings() {/,/^}/p' \
    "$DOT_DIR/custom_bins/setup-envrc"; } > "$TEST_HOME/_fns.sh"
SECRETS_HELPER="$HELPER"
export SECRETS_HELPER
# shellcheck source=/dev/null
source "$TEST_HOME/_fns.sh"

check "canonicalize plain"  "HF_TOKEN" "$(canonicalize_binding 'HF_TOKEN')"
check "canonicalize rename" "MY_KEY=OTHER_KEY" "$(canonicalize_binding 'MY_KEY=OTHER_KEY')"
check "canonicalize bws"    "OPENAI_API_KEY=OPENAI_API_KEY - mats" \
    "$(canonicalize_binding 'OPENAI_API_KEY=OPENAI_API_KEY - mats')"

# Bad env key should die (non-zero). Wrap in subshell because die calls exit.
if ( canonicalize_binding '123BAD=FOO' ) >/dev/null 2>&1; then
  echo "  FAIL canonicalize accepted invalid env key"; fail=$((fail+1))
else
  echo "  ok  canonicalize rejects invalid env key"; pass=$((pass+1))
fi

echo "== normalize_export_bindings (ambiguity detection) =="
# Non-duplicate plain binding should pass (HF_TOKEN has only one record).
if norm=$( ( normalize_export_bindings 'HF_TOKEN' ) 2>/dev/null ); then
  check "normalize unambiguous plain" "HF_TOKEN" "$norm"
else
  echo "  FAIL normalize unambiguous plain rejected"; fail=$((fail+1))
fi

# Explicit BWS binding should pass even when the env_name has duplicates.
if norm=$( ( normalize_export_bindings 'OPENAI_API_KEY=OPENAI_API_KEY - mats' ) 2>/dev/null ); then
  check "normalize explicit bws binding" "OPENAI_API_KEY=OPENAI_API_KEY - mats" "$norm"
else
  echo "  FAIL normalize explicit bws binding rejected"; fail=$((fail+1))
fi

# Plain binding for ambiguous env_name (two OPENAI_API_KEY rows) must die.
if ( normalize_export_bindings 'OPENAI_API_KEY' ) >/dev/null 2>&1; then
  echo "  FAIL normalize accepted ambiguous plain env_name"; fail=$((fail+1))
else
  echo "  ok  normalize rejects ambiguous plain env_name"; pass=$((pass+1))
fi

# Renamed binding for ambiguous secret_key (LOCAL=OPENAI_API_KEY) must also die.
if ( normalize_export_bindings 'LOCAL_OPENAI=OPENAI_API_KEY' ) >/dev/null 2>&1; then
  echo "  FAIL normalize accepted renamed ambiguous secret"; fail=$((fail+1))
else
  echo "  ok  normalize rejects renamed ambiguous secret"; pass=$((pass+1))
fi

echo "== managed_available_keys (cleanup classification) =="
# Source additional helpers for managed_available_keys.
{ sed -n '/^list_sensitive_keys() {/,/^}/p; /^managed_available_keys() {/,/^}/p; /^load_secrets_cache() {/,/^}/p' \
    "$DOT_DIR/custom_bins/setup-envrc"; } >> "$TEST_HOME/_fns.sh"
# shellcheck source=/dev/null
source "$DOT_DIR/scripts/helpers/dotfiles_secrets.sh"
# shellcheck source=/dev/null
source "$TEST_HOME/_fns.sh"
# Initialise top-level state that the functions expect (not captured by sed).
SECRETS_CACHE=""
KEY_PATTERN='API.?KEY|TOKEN|SECRET|PASSWORD|CREDENTIAL'
avail=$(managed_available_keys)
# HF_TOKEN (single record) must be in the managed list.
if grep -qxF 'HF_TOKEN' <<< "$avail"; then
  echo "  ok  HF_TOKEN counted as managed"; pass=$((pass+1))
else
  echo "  FAIL HF_TOKEN missing from managed keys: ${avail@Q}"; fail=$((fail+1))
fi
# OPENAI_API_KEY (two records) must be EXCLUDED so cleanup can't silently match.
if grep -qxF 'OPENAI_API_KEY' <<< "$avail"; then
  echo "  FAIL OPENAI_API_KEY (duplicate) still counted as managed"; fail=$((fail+1))
else
  echo "  ok  ambiguous OPENAI_API_KEY excluded from managed keys"; pass=$((pass+1))
fi

echo
echo "Passed: $pass  Failed: $fail"
exit "$fail"
