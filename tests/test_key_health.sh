#!/usr/bin/env bash
# Tests for custom_bins/key-health and the priority-fallback path in dotfiles-secrets.
# Run: bash tests/test_key_health.sh
#
# Hermetic: probes are stubbed (KEY_HEALTH_STUB), BWS is a fixture
# (KEY_HEALTH_DUMP_FILE / DOTFILES_SECRETS_BACKEND=fixture), the gateway file and
# restart command are temp stand-ins, and desktop notifications are off.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KH="$ROOT/custom_bins/key-health"
DS="$ROOT/custom_bins/dotfiles-secrets"
PASS=0
FAIL=0

mkdir -p "$ROOT/tmp"
T=$(mktemp -d "$ROOT/tmp/key-health.XXXXXX") || exit 1
trap 'rm -rf "$T"' EXIT

ok()   { PASS=$((PASS + 1)); echo "  ok   $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL $1"; [[ -n "${2:-}" ]] && printf '       %s\n' "$2"; }
has()  { [[ "$2" == *"$3"* ]] && ok "$1" || bad "$1" "expected to contain: $3 | got: ${2:0:400}"; }
hasnt(){ [[ "$2" != *"$3"* ]] && ok "$1" || bad "$1" "expected NOT to contain: $3 | got: ${2:0:400}"; }
eq()   { [[ "$2" == "$3" ]] && ok "$1" || bad "$1" "expected: $3 | got: $2"; }

b64() { printf '%s' "$1" | base64 | tr -d '\n'; }

# --- fixtures ----------------------------------------------------------------
{
    printf 'OPENROUTER_API_KEY - mats\t%s\n' "$(b64 fake-or-mats)"
    printf 'OPENROUTER_API_KEY - personal\t%s\n' "$(b64 fake-or-personal)"
    printf 'OPENAI_API_KEY - tomek\t%s\n' "$(b64 fake-oa-tomek)"
    printf 'OPENAI_API_KEY - mats\t%s\n' "$(b64 fake-oa-mats)"
} > "$T/dump.tsv"

PRIO=$'OPENROUTER_API_KEY = mats, personal\nOPENAI_API_KEY = tomek, mats, ghost'

export KEY_HEALTH_DUMP_FILE="$T/dump.tsv"
export KEY_HEALTH_PRIORITY="$PRIO"
export KEY_HEALTH_CACHE="$T/cache.tsv"
export KEY_HEALTH_NO_NOTIFY=1
export KEY_HEALTH_GATEWAY_SECRETS="$T/gateway.toml"
export KEY_HEALTH_GATEWAY_RESTART="touch $T/restarted"

hook() { KEY_HEALTH_STUB="$1" "$KH" --hook --force; }

echo "key-health: decisions"

# 1. Healthy top keys + one missing key in the list: missing is loud, no fallback banner.
out=$(hook '{}')
has   "missing key raises a loud alert" "$out" "❌ API KEY NEEDS FIXING"
has   "missing key is named by label" "$out" "OPENAI_API_KEY - ghost: missing from BWS"
hasnt "no fallback when top keys are healthy" "$out" "fallback this session"
hasnt "hook output carries no key material" "$out" "fake-"

# Remove the ghost so the remaining cases test fallback alone.
export KEY_HEALTH_PRIORITY=$'OPENROUTER_API_KEY = mats, personal\nOPENAI_API_KEY = tomek, mats'
out=$(hook '{}')
eq "all healthy -> no hook output at all" "$out" ""

# 2. Top out of credit -> switches, announced.
out=$(hook '{"OPENROUTER_API_KEY - mats": "no_credit"}')
has "out of credit switches to next" "$out" "OPENROUTER_API_KEY: using personal instead of mats"
has "reason names the state" "$out" "out of credit"
has "model is told too" "$out" "additionalContext"
grep -q $'^choice\tOPENROUTER_API_KEY\tOPENROUTER_API_KEY - personal\t' "$T/cache.tsv" \
    && ok "cache records the fallback choice" || bad "cache records the fallback choice" "$(cat "$T/cache.tsv")"

# 3. Next session with top replenished -> back to top (nothing sticky).
out=$(hook '{}')
eq "replenished top -> silent again" "$out" ""
grep -q $'^choice\tOPENROUTER_API_KEY\tOPENROUTER_API_KEY - mats\t' "$T/cache.tsv" \
    && ok "cache returns to the top key" || bad "cache returns to the top key"

# 4. Rate limit switches; revoked switches and is loud.
out=$(hook '{"OPENAI_API_KEY - tomek": "rate_limited"}')
has "429 switches" "$out" "OPENAI_API_KEY: using mats instead of tomek"
hasnt "429 alone is not loud" "$out" "❌"
out=$(hook '{"OPENAI_API_KEY - tomek": "revoked"}')
has "revoked switches" "$out" "using mats instead of tomek"
has "revoked is loud" "$out" "OPENAI_API_KEY - tomek: revoked or invalid"

# 5. Unknown (network) failure does not move spend.
out=$(hook '{"OPENROUTER_API_KEY - mats": "unknown"}')
eq "probe failure keeps the top key" "$out" ""

# 6. Every key exhausted -> loud, CLI exits 1.
out=$(hook '{"OPENROUTER_API_KEY - mats": "no_credit", "OPENROUTER_API_KEY - personal": "no_credit"}')
has "all exhausted is loud" "$out" "every key in the priority list is unusable"
KEY_HEALTH_STUB='{"OPENROUTER_API_KEY - mats": "no_credit", "OPENROUTER_API_KEY - personal": "revoked"}' \
    "$KH" --force --no-gateway >/dev/null; eq "CLI exits 1 when a key needs fixing" "$?" "1"
KEY_HEALTH_STUB='{}' "$KH" --force --no-gateway >/dev/null; eq "CLI exits 0 when all healthy" "$?" "0"

# 7. Cache reuse within the window: a stub change is not seen without --force.
KEY_HEALTH_STUB='{}' "$KH" --force --no-gateway >/dev/null
out=$(KEY_HEALTH_STUB='{"OPENROUTER_API_KEY - mats": "no_credit"}' "$KH" --hook)
eq "recent cache is reused (no re-probe burst across sessions)" "$out" ""

echo "key-health: gateway"
printf '[openai-providers]\nopenrouter = "fake-or-mats"\n' > "$T/gateway.toml"
rm -f "$T/restarted"
out=$(hook '{"OPENROUTER_API_KEY - mats": "no_credit"}')
grep -q '^openrouter = "fake-or-personal"$' "$T/gateway.toml" && ok "gateway key rewritten to chosen key" \
    || bad "gateway key rewritten to chosen key" "$(cat "$T/gateway.toml")"
grep -q '^\[openai-providers\]$' "$T/gateway.toml" && ok "other gateway lines kept" || bad "other gateway lines kept"
[[ -f "$T/restarted" ]] && ok "router restarted after a change" || bad "router restarted after a change"
has "gateway switch is announced" "$out" "gateway (model-router) now uses OPENROUTER_API_KEY personal"
hasnt "announcement carries no key material" "$out" "fake-"
rm -f "$T/restarted"
hook '{"OPENROUTER_API_KEY - mats": "no_credit"}' >/dev/null
[[ ! -f "$T/restarted" ]] && ok "no restart when the key already matches" || bad "no restart when the key already matches"

echo "dotfiles-secrets: resolution through the cache"
F="$T/fixture"; mkdir -p "$F"
cat > "$F/secrets" <<EOF
OPENROUTER_API_KEY=fake-or-personal
EOF
{
    printf 'OPENROUTER_API_KEY\tOPENROUTER_API_KEY - mats\t\tid1\n'
    printf 'OPENROUTER_API_KEY\tOPENROUTER_API_KEY - personal\t\tid2\n'
} > "$F/meta"
{
    printf 'OPENROUTER_API_KEY - mats\t%s\t\tid1\n' "$(b64 fake-or-mats)"
    printf 'OPENROUTER_API_KEY - personal\t%s\t\tid2\n' "$(b64 fake-or-personal)"
} > "$F/raw"
printf 'OPENROUTER_API_KEY = OPENROUTER_API_KEY - mats\n' > "$T/conf"

ds() { DOTFILES_SECRETS_BACKEND=fixture DOTFILES_SECRETS_FIXTURE_DIR="$F" DOTFILES_SECRETS_GLOBAL_CONF="$T/conf" "$DS" "$@"; }

KEY_HEALTH_STUB='{"OPENROUTER_API_KEY - mats": "no_credit"}' "$KH" --force --no-gateway >/dev/null
out=$(ds shell OPENROUTER_API_KEY 2>"$T/err")
has "bare name follows the probed choice over the conf" "$out" "fake-or-personal"
has "fallback is announced on stderr" "$(cat "$T/err")" "OPENROUTER_API_KEY -> 'personal' (priority fallback"
hasnt "stderr carries no key material" "$(cat "$T/err")" "fake-"

out=$(ds shell-bindings "OPENROUTER_API_KEY=OPENROUTER_API_KEY - mats" 2>"$T/err")
has ".envrc exact pin follows the order" "$out" "fake-or-personal"
has "pin redirect is announced" "$(cat "$T/err")" "pinned to 'mats' -> 'personal'"
out=$(DOTFILES_SECRETS_EXACT=1 ds shell-bindings "OPENROUTER_API_KEY=OPENROUTER_API_KEY - mats" 2>/dev/null)
has "DOTFILES_SECRETS_EXACT keeps the pin" "$out" "fake-or-mats"

printf 'OPENROUTER_API_KEY = OPENROUTER_API_KEY - mats\nOPENROUTER_API_KEY = !OPENROUTER_API_KEY - personal\n' > "$T/conf"
out=$(ds shell OPENROUTER_API_KEY 2>/dev/null)
has "a hand-blocked key is never chosen from the cache" "$out" "fake-or-mats"
printf 'OPENROUTER_API_KEY = OPENROUTER_API_KEY - mats\n' > "$T/conf"

out=$(KEY_HEALTH_MAX_AGE=0 ds shell OPENROUTER_API_KEY 2>/dev/null)
sleep 1
out=$(KEY_HEALTH_MAX_AGE=0 ds shell OPENROUTER_API_KEY 2>/dev/null)
has "stale cache falls back to the conf" "$out" "fake-or-mats"

KEY_HEALTH_STUB='{}' "$KH" --force --no-gateway >/dev/null
out=$(ds shell OPENROUTER_API_KEY 2>"$T/err")
has "healthy top resolves to top" "$out" "fake-or-mats"
eq "no notice when top is used" "$(cat "$T/err")" ""

echo
echo "passed: $PASS  failed: $FAIL"
[[ $FAIL -eq 0 ]]
