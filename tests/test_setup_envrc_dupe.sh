#!/usr/bin/env bash
# Hermetic test for the setup-envrc / dotfiles-secrets duplicate-env-name flow.
#
# Two BWS keys legitimately share one env name (one per account). Every
# assertion here is about what happens at that fork: which lookups must fail
# loud, which must resolve, and which bindings are allowed to be written.
#
# Runs under DOTFILES_SECRETS_BACKEND=fixture — no BWS token, no network, no
# disk cache. (It used to synthesize ~/.cache/dotfiles-secrets/*.bws.cache;
# that cache no longer exists, so the fixture files are now the only injection
# point. A fake HOME alone would silently have fallen through to live BWS.)
set -euo pipefail

DOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$DOT_DIR/custom_bins/dotfiles-secrets"
export DOT_DIR

# Repo-local tmp/ (gitignored): $TMPDIR is not reliably writable under the
# Claude Code sandbox, and a fixture that silently fails to create turns the
# whole suite into an early mktemp abort.
TMP_ROOT="$DOT_DIR/tmp"
mkdir -p "$TMP_ROOT"
TEST_HOME=$(mktemp -d "$TMP_ROOT/envrc-dupe.XXXXXX")
trap 'rm -rf "$TEST_HOME"' EXIT
export HOME="$TEST_HOME"

# Pin the global-scope map at a path that does not exist. Without this the suite
# reads the real config/secrets-global.conf, so the moment a global default for
# OPENAI_API_KEY is declared there the ambiguity assertions below would start
# resolving and fail — a test that depends on the user's live config is not
# hermetic. The "declared" half is exercised explicitly further down.
export DOTFILES_SECRETS_GLOBAL_CONF="$TEST_HOME/no-such-scope.conf"

# --- fixture backend: two OPENAI_API_KEY records plus a unique HF_TOKEN -------
FIXTURE="$TEST_HOME/fixture"
mkdir -p "$FIXTURE"
export DOTFILES_SECRETS_BACKEND=fixture
export DOTFILES_SECRETS_FIXTURE_DIR="$FIXTURE"

printf 'OPENAI_API_KEY=sk-matsval\nOPENAI_API_KEY=sk-personalval\nHF_TOKEN=hf_xyz\n' \
    > "$FIXTURE/secrets"
# env_name \t bws_key \t note \t uuid
printf '%s\n' \
    $'OPENAI_API_KEY\tOPENAI_API_KEY - mats\tmats account\tuuid-mats' \
    $'OPENAI_API_KEY\tOPENAI_API_KEY - personal\tpersonal account\tuuid-personal' \
    $'HF_TOKEN\tHF_TOKEN\t\tuuid-hf' \
    > "$FIXTURE/meta"
# bws_key \t base64(value) \t note \t uuid
{
  printf '%s\t%s\t%s\t%s\n' "OPENAI_API_KEY - mats" \
      "$(printf sk-matsval | base64 | tr -d '\n')" "mats account" "uuid-mats"
  printf '%s\t%s\t%s\t%s\n' "OPENAI_API_KEY - personal" \
      "$(printf sk-personalval | base64 | tr -d '\n')" "personal account" "uuid-personal"
  printf '%s\t%s\t%s\t%s\n' "HF_TOKEN" \
      "$(printf hf_xyz | base64 | tr -d '\n')" "" "uuid-hf"
} > "$FIXTURE/raw"

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
    $'OPENAI_API_KEY\tOPENAI_API_KEY - mats\tmats account\tuuid-mats\nOPENAI_API_KEY\tOPENAI_API_KEY - personal\tpersonal account\tuuid-personal\nHF_TOKEN\tHF_TOKEN\t\tuuid-hf' \
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
# UUID bindings are what setup-envrc writes for a pin, so they must survive a
# BWS key rename. Exercised here because nothing else in the suite does.
check "get-value by uuid"  "sk-personalval" "$("$HELPER" get-value 'bws-id:uuid-personal')"
# Ambiguous env_name with nothing declared must fail (two OPENAI_API_KEY rows).
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
TG_STATE=$(mktemp -d "$TMP_ROOT/envrc-dupe-tg.XXXXXX")
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
# Match case-insensitively: the named-key path says "Ambiguous env name ...",
# the --all path says "skipping ambiguous env name ...". Asserting the lowercase
# spelling alone silently stopped matching when the named path became fail-loud.
if [[ -z "$shell_out" && "${shell_err,,}" == *"ambiguous"* ]]; then
  echo "  ok  shell OPENAI_API_KEY refuses ambiguous"
  pass=$((pass+1))
else
  echo "  FAIL shell dup: out=${shell_out@Q} err=${shell_err@Q}"
  fail=$((fail+1))
fi

# The whole point of the machine switch: the SAME ambiguous name resolves once
# the conf declares one, through the same `shell` path a follow-mode .envrc uses.
DECLARED_CONF="$TEST_HOME/declared.conf"
printf 'OPENAI_API_KEY = OPENAI_API_KEY - personal\n' > "$DECLARED_CONF"
shell_declared=$(DOTFILES_SECRETS_GLOBAL_CONF="$DECLARED_CONF" \
    "$HELPER" shell OPENAI_API_KEY 2>/dev/null || true)
check "shell resolves declared ambiguous name" \
    'export OPENAI_API_KEY=sk-personalval' "$shell_declared"

echo "== setup-envrc canonicalize (bws_key binding) =="
# Source canonicalize_binding and supporting fns
{ sed -n '/^is_bws_key() {/,/^}/p; /^canonicalize_binding() {/,/^}/p; /^binding_env_key() {/,/^}/p; /^binding_secret_key() {/,/^}/p; /^validate_env_name() {/,/^}/p; /^die() {/,/^}/p; /^has_line() {/,/^}/p; /^env_name_is_declared() {/,/^}/p; /^normalize_export_bindings() {/,/^}/p' \
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

echo "== normalize_export_bindings (follow-mode vs pin) =="
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

# A plain binding for an ambiguous env_name is now a FOLLOW-MODE binding: it
# resolves through config/secrets-global.conf at load time, so it must be
# ACCEPTED rather than refused. This used to die, back when the batch `shell`
# path silently picked one tenant by list order; that path is conf-consulted and
# fail-loud now, so refusing the binding would only force every repo to pin.
if norm=$( ( normalize_export_bindings 'OPENAI_API_KEY' ) 2>/dev/null ); then
  check "normalize accepts follow-mode plain" "OPENAI_API_KEY" "$norm"
else
  echo "  FAIL normalize rejected follow-mode plain binding"; fail=$((fail+1))
fi

# ...but it must WARN while the machine has not chosen, because the binding
# cannot resolve until then, and name the command that fixes it.
norm_err=$( ( normalize_export_bindings 'OPENAI_API_KEY' ) 2>&1 >/dev/null || true )
if [[ "$norm_err" == *"secrets-use OPENAI_API_KEY"* ]]; then
  echo "  ok  undeclared follow-mode binding names secrets-use"; pass=$((pass+1))
else
  echo "  FAIL no secrets-use hint for undeclared follow-mode: ${norm_err@Q}"; fail=$((fail+1))
fi

# Once the machine HAS chosen, the same binding is silent — a warning that never
# goes away is a warning people stop reading.
norm_err=$( ( DOTFILES_SECRETS_GLOBAL_CONF="$DECLARED_CONF" \
              normalize_export_bindings 'OPENAI_API_KEY' ) 2>&1 >/dev/null || true )
if [[ -z "$norm_err" ]]; then
  echo "  ok  declared follow-mode binding is silent"; pass=$((pass+1))
else
  echo "  FAIL declared follow-mode still warned: ${norm_err@Q}"; fail=$((fail+1))
fi

# A rename onto an ambiguous secret (LOCAL_OPENAI=OPENAI_API_KEY) is follow-mode
# too. write_envrc routes any non-"ENV - desc" secret key through the SAME batch
# `shell` call and then aliases it (export LOCAL_OPENAI="$OPENAI_API_KEY"), so it
# is conf-consulted and fail-loud exactly like the unrenamed form. Only a literal
# "ENV - desc" / bws-id: binding takes the `get-value` pin path.
if norm=$( ( normalize_export_bindings 'LOCAL_OPENAI=OPENAI_API_KEY' ) 2>/dev/null ); then
  check "normalize accepts renamed follow-mode" "LOCAL_OPENAI=OPENAI_API_KEY" "$norm"
else
  echo "  FAIL normalize rejected renamed follow-mode binding"; fail=$((fail+1))
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
# shellcheck disable=SC2034  # read by the sourced setup-envrc functions
SECRETS_CACHE=""
# shellcheck disable=SC2034  # read by the sourced setup-envrc functions
KEY_PATTERN='API.?KEY|TOKEN|SECRET|PASSWORD|CREDENTIAL'
avail=$(managed_available_keys)
# HF_TOKEN (single record) must be in the managed list.
if grep -qxF 'HF_TOKEN' <<< "$avail"; then
  echo "  ok  HF_TOKEN counted as managed"; pass=$((pass+1))
else
  echo "  FAIL HF_TOKEN missing from managed keys: ${avail@Q}"; fail=$((fail+1))
fi
# OPENAI_API_KEY (two records) must be EXCLUDED so cleanup can't silently match.
# Cleanup compares raw VALUES, and the dotenv view still holds both records with
# no way to tell which one a repo-local .env was copied from — unlike resolution,
# which the conf disambiguates. So follow-mode does not make this safe.
if grep -qxF 'OPENAI_API_KEY' <<< "$avail"; then
  echo "  FAIL OPENAI_API_KEY (duplicate) still counted as managed"; fail=$((fail+1))
else
  echo "  ok  ambiguous OPENAI_API_KEY excluded from managed keys"; pass=$((pass+1))
fi

echo "== end-to-end: a generated follow-mode .envrc tracks the machine switch =="
# The acceptance criterion in prose: flip the switch, and a follow-mode repo
# picks up the new key on next direnv load with NO setup-envrc re-run. Asserting
# it on the generated file is the only way to catch a regression where the
# binding is accepted but the .envrc still bakes in one tenant's key.
E2E_REPO="$TEST_HOME/follow-repo"
E2E_CONF="$TEST_HOME/e2e.conf"
mkdir -p "$E2E_REPO"
# `git init` is required, not cosmetic: setup-envrc scopes to the enclosing git
# root, and TEST_HOME lives under the dotfiles repo's own tmp/. Without its own
# root the fixture would resolve to the dotfiles checkout and write a real
# .envrc there — the test would corrupt the working tree it is testing.
git -C "$E2E_REPO" init -q 2>/dev/null || true
printf 'OPENAI_API_KEY = OPENAI_API_KEY - mats\n' > "$E2E_CONF"

( cd "$E2E_REPO" && DOTFILES_SECRETS_GLOBAL_CONF="$E2E_CONF" \
    "$DOT_DIR/custom_bins/setup-envrc" OPENAI_API_KEY ) >/dev/null 2>&1 || true

if [[ ! -f "$E2E_REPO/.envrc" ]]; then
  echo "  FAIL setup-envrc wrote no .envrc"; fail=$((fail+1))
else
  # No exact BWS key may appear anywhere in the file — that is what "follow" means.
  if grep -q 'OPENAI_API_KEY - ' "$E2E_REPO/.envrc"; then
    echo "  FAIL .envrc pinned an exact BWS key"; fail=$((fail+1))
  else
    echo "  ok  .envrc binds the bare env name, not a tenant"; pass=$((pass+1))
  fi

  # setup-envrc bakes the MAIN checkout's helper path (correct in production,
  # and covered by tests/test_secrets_global_scope.sh). Repoint it at the helper
  # under test so this assertion is about follow-mode, not about which binary a
  # worktree resolves.
  sed -i.bak "s|^DOTFILES_SECRETS_BIN=.*|DOTFILES_SECRETS_BIN=${HELPER}|" "$E2E_REPO/.envrc"

  # Stand in for direnv: watch_file is a direnv builtin, nothing else is.
  load_envrc() {
    ( cd "$E2E_REPO" && DOTFILES_SECRETS_GLOBAL_CONF="$E2E_CONF" bash -c \
        'watch_file() { :; }; source ./.envrc >/dev/null 2>&1; printf %s "${OPENAI_API_KEY:-}"' )
  }

  check "follow-mode .envrc resolves the active key" "sk-matsval" "$(load_envrc)"

  # Flip the machine switch. No setup-envrc re-run, no edit to .envrc.
  printf 'OPENAI_API_KEY = OPENAI_API_KEY - personal\n' > "$E2E_CONF"
  check "flipping the switch propagates with no re-run" "sk-personalval" "$(load_envrc)"

  # Blocking the active key must promote the fallback, still with no re-run.
  printf '%s\n' \
      'OPENAI_API_KEY = !OPENAI_API_KEY - personal' \
      'OPENAI_API_KEY = OPENAI_API_KEY - mats' > "$E2E_CONF"
  check "a blocked key falls through to the next" "sk-matsval" "$(load_envrc)"

  # And with every key blocked, resolution fails LOUD — never a silent empty
  # export. An empty ANTHROPIC_API_KEY is what caused ~349 auto-mode denials.
  printf '%s\n' \
      'OPENAI_API_KEY = !OPENAI_API_KEY - personal' \
      'OPENAI_API_KEY = !OPENAI_API_KEY - mats' > "$E2E_CONF"
  e2e_err=$( ( cd "$E2E_REPO" && DOTFILES_SECRETS_GLOBAL_CONF="$E2E_CONF" bash -c \
      'watch_file() { :; }; source ./.envrc' ) 2>&1 >/dev/null || true )
  all_blocked_state=$( ( cd "$E2E_REPO" && \
      OPENAI_API_KEY=synthetic-inherited-value \
      DOTFILES_SECRETS_GLOBAL_CONF="$E2E_CONF" bash -c '
        watch_file() { :; }
        source ./.envrc >/dev/null 2>&1
        if [[ ${OPENAI_API_KEY+x} != x ]]; then
          printf unset
        elif [[ -n $OPENAI_API_KEY ]]; then
          printf set-nonempty
        else
          printf set-empty
        fi
      ' ) )
  check "all-blocked clears inherited destination" "unset" "$all_blocked_state"
  if [[ -n "$e2e_err" ]]; then
    echo "  ok  all-blocked fails loudly on stderr"; pass=$((pass+1))
  else
    echo "  FAIL all-blocked was silent"; fail=$((fail+1))
  fi
fi

echo
echo "Passed: $pass  Failed: $fail"
exit "$fail"
