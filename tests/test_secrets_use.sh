#!/usr/bin/env bash
# Tests for secrets-use — the CLI that edits config/secrets-global.conf.
# Run: bash tests/test_secrets_use.sh
#
# Hermetic: runs dotfiles-secrets under DOTFILES_SECRETS_BACKEND=fixture and
# points secrets-use at a shim PATH, so no BWS token, no network and no real
# secret is involved.
#
# The assertion that matters most here is the byte-identical round trip:
# `--next` must only mark the active key blocked, never reorder or regenerate
# the block, so `--activate` reverses it exactly. A writer that regenerated the
# env name's lines would pass every "is the right key active" check and still
# quietly eat the user's comments and ordering.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
USE_BIN="$REPO/custom_bins/secrets-use"
PASS=0
FAIL=0

TMP_ROOT="$REPO/tmp"
mkdir -p "$TMP_ROOT"
FIXTURE=$(mktemp -d "$TMP_ROOT/secrets-use.XXXXXX") || {
    echo "could not create fixture dir under $TMP_ROOT" >&2; exit 1; }
[[ -n "$FIXTURE" && -d "$FIXTURE" ]] || exit 1
trap 'rm -rf "$FIXTURE"' EXIT

CONF="$FIXTURE/scope.conf"

# --- fixture backend data ----------------------------------------------------
cat > "$FIXTURE/secrets" <<'EOF'
ANTHROPIC_API_KEY=fake-anthropic
HF_TOKEN=fake-hf
EOF

printf '%s\n' \
    "ANTHROPIC_API_KEY	ANTHROPIC_API_KEY - alpha	alpha note	uuid-alpha" \
    "ANTHROPIC_API_KEY	ANTHROPIC_API_KEY - beta	 	uuid-beta" \
    "ANTHROPIC_API_KEY	ANTHROPIC_API_KEY - gamma	 	uuid-gamma" \
    "HF_TOKEN	HF_TOKEN	 	uuid-hf" \
    > "$FIXTURE/meta"
: > "$FIXTURE/raw"

# --- shim PATH ---------------------------------------------------------------
# secrets-use calls `dotfiles-secrets` off PATH. The shim pins the fixture
# backend and the fixture conf so the real machine conf is never touched.
mkdir -p "$FIXTURE/bin"
cat > "$FIXTURE/bin/dotfiles-secrets" <<EOF
#!/usr/bin/env bash
exec env DOTFILES_SECRETS_BACKEND=fixture \\
         DOTFILES_SECRETS_FIXTURE_DIR="$FIXTURE" \\
         DOTFILES_SECRETS_GLOBAL_CONF="$CONF" \\
         "$REPO/custom_bins/dotfiles-secrets" "\$@"
EOF
chmod +x "$FIXTURE/bin/dotfiles-secrets"
export PATH="$FIXTURE/bin:$PATH"

use() { "$USE_BIN" "$@" 2>&1; }

check() {
    local desc="$1" got="$2" want="$3"
    if [[ "$got" == *"$want"* ]]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL: %s\n  wanted to contain: %s\n  got: %s\n' \
            "$desc" "$want" "$(printf '%s' "$got" | head -8 | tr '\n' '|')"
    fi
}

check_eq() {
    local desc="$1" got="$2" want="$3"
    if [[ "$got" == "$want" ]]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL: %s\n  wanted exactly: [%s]\n  got:            [%s]\n' \
            "$desc" "$want" "$got"
    fi
}

check_not_contains() {
    local desc="$1" got="$2" unwanted="$3"
    if [[ "$got" != *"$unwanted"* ]]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL: %s\n  should NOT contain: %s\n  got: %s\n' \
            "$desc" "$unwanted" "$(printf '%s' "$got" | head -8 | tr '\n' '|')"
    fi
}

active() { dotfiles-secrets scope-entries "$1" | awk -F'\t' '$1=="active"{print $2; exit}'; }

is_global() { dotfiles-secrets scope-is-global "$1" && echo yes || echo no; }

# A second shim whose `keys-meta` always fails, standing in for a machine where
# BWS is not installed yet — the state the deploy migration runs in. Everything
# else is forwarded, so a command that reaches for the inventory dies here.
mkdir -p "$FIXTURE/nometa"
cat > "$FIXTURE/nometa/dotfiles-secrets" <<EOF
#!/usr/bin/env bash
[[ "\${1:-}" == keys-meta || "\${1:-}" == keys ]] && { echo "no BWS token" >&2; exit 1; }
exec "$FIXTURE/bin/dotfiles-secrets" "\$@"
EOF
chmod +x "$FIXTURE/nometa/dotfiles-secrets"

# A conf with comments and an unrelated env name, so we can prove they survive.
seed_conf() {
    cat > "$CONF" <<'EOF'
# machine conf — comments must survive every edit
HF_TOKEN = HF_TOKEN

# anthropic below
ANTHROPIC_API_KEY = ANTHROPIC_API_KEY - alpha
ANTHROPIC_API_KEY = ANTHROPIC_API_KEY - beta

# trailing comment
EOF
}

echo "=== --list shows preference order and marks the active key ==="
seed_conf
out=$(use ANTHROPIC_API_KEY --list)
check "lists alpha"   "$out" "ANTHROPIC_API_KEY - alpha"
check "lists beta"    "$out" "ANTHROPIC_API_KEY - beta"
check "marks active"  "$out" "* ANTHROPIC_API_KEY - alpha"

echo "=== --next blocks the active key and promotes the next ==="
seed_conf
out=$(use ANTHROPIC_API_KEY --next)
check "reports old -> new" "$out" "ANTHROPIC_API_KEY - alpha -> ANTHROPIC_API_KEY - beta"
check_eq "beta is now active" "$(active ANTHROPIC_API_KEY)" "ANTHROPIC_API_KEY - beta"

echo "=== --next then --activate restores the file BYTE FOR BYTE ==="
seed_conf
before=$(cat "$CONF")
use ANTHROPIC_API_KEY --next >/dev/null
mid=$(cat "$CONF")
use ANTHROPIC_API_KEY --activate alpha >/dev/null
after=$(cat "$CONF")
if [[ "$before" == "$mid" ]]; then
    FAIL=$((FAIL + 1)); echo "FAIL: --next did not change the conf at all"
else
    PASS=$((PASS + 1))
fi
check_eq "round trip is byte-identical" "$after" "$before"

echo "=== edits preserve comments and unrelated env names ==="
seed_conf
use ANTHROPIC_API_KEY gamma >/dev/null
out=$(cat "$CONF")
check "keeps header comment"   "$out" "# machine conf — comments must survive every edit"
check "keeps inline comment"   "$out" "# anthropic below"
check "keeps trailing comment" "$out" "# trailing comment"
check "keeps other env name"   "$out" "HF_TOKEN = HF_TOKEN"

echo "=== setting a key promotes it and keeps the others as fallbacks ==="
seed_conf
use ANTHROPIC_API_KEY gamma >/dev/null
check_eq "gamma active" "$(active ANTHROPIC_API_KEY)" "ANTHROPIC_API_KEY - gamma"
entries=$(dotfiles-secrets scope-entries ANTHROPIC_API_KEY | awk -F'\t' '{print $2}' | tr '\n' ',')
check_eq "order: gamma, alpha, beta" "$entries" \
    "ANTHROPIC_API_KEY - gamma,ANTHROPIC_API_KEY - alpha,ANTHROPIC_API_KEY - beta,"

echo "=== setting the already-active key is a no-op ==="
seed_conf
before=$(cat "$CONF")
out=$(use ANTHROPIC_API_KEY alpha)
check "says already active" "$out" "already active"
check_eq "conf untouched" "$(cat "$CONF")" "$before"

echo "=== a substring resolves; an ambiguous or unknown one is refused ==="
seed_conf
out=$(use ANTHROPIC_API_KEY beta)
check "substring works" "$out" "ANTHROPIC_API_KEY - beta"

seed_conf
out=$(use ANTHROPIC_API_KEY ANTHROPIC; rc=$?; echo "rc=$rc")
check "ambiguous substring refused" "$out" "matches 3 keys"
check "ambiguous exits non-zero"    "$out" "rc=1"

out=$(use ANTHROPIC_API_KEY nosuchkey; rc=$?; echo "rc=$rc")
check "unknown key refused"   "$out" "no BWS key for 'ANTHROPIC_API_KEY' matches 'nosuchkey'"
check "unknown exits non-zero" "$out" "rc=1"

echo "=== an unknown env name is refused ==="
out=$(use NOT_A_REAL_ENV alpha; rc=$?; echo "rc=$rc")
check "refuses unknown env" "$out" "no BWS key uses env name 'NOT_A_REAL_ENV'"
check "exits non-zero"      "$out" "rc=1"

echo "=== blocking the last active key fails loud rather than leaving nothing ==="
cat > "$CONF" <<'EOF'
ANTHROPIC_API_KEY = ANTHROPIC_API_KEY - alpha
EOF
out=$(use ANTHROPIC_API_KEY --next; rc=$?; echo "rc=$rc")
check "warns no active key remains" "$out" "NO active key remains"
check "suggests the reversal"       "$out" "--activate"
check "exits non-zero"              "$out" "rc=1"

echo "=== declaring a name that had no line appends it ==="
cat > "$CONF" <<'EOF'
# only an unrelated name here
HF_TOKEN = HF_TOKEN
EOF
use ANTHROPIC_API_KEY alpha >/dev/null
check_eq "alpha active" "$(active ANTHROPIC_API_KEY)" "ANTHROPIC_API_KEY - alpha"
check "unrelated name kept" "$(cat "$CONF")" "HF_TOKEN = HF_TOKEN"

echo "=== the conf is written 0600 (it names real accounts) ==="
seed_conf
use ANTHROPIC_API_KEY gamma >/dev/null
mode=$(stat -c '%a' "$CONF" 2>/dev/null || stat -f '%Lp' "$CONF" 2>/dev/null)
check_eq "mode 600" "$mode" "600"

# --- the "[global]" name marker ---------------------------------------------
# The marker is per-NAME, not per-line, and orthogonal to which key is active.
# The assertion that matters most is preservation: switching accounts must not
# silently revoke a name's global exposure, because the revocation would only
# surface later, as a hook that stopped resolving.

echo "=== --global marks every line of the name ==="
seed_conf
out=$(use ANTHROPIC_API_KEY --global)
check "reports the change" "$out" "now [global]"
check "alpha line marked" "$(cat "$CONF")" "ANTHROPIC_API_KEY [global] = ANTHROPIC_API_KEY - alpha"
check "beta line marked"  "$(cat "$CONF")" "ANTHROPIC_API_KEY [global] = ANTHROPIC_API_KEY - beta"
check "unrelated name untouched" "$(cat "$CONF")" $'\nHF_TOKEN = HF_TOKEN'
check "comments survive"  "$(cat "$CONF")" "# trailing comment"
check_eq "active key unchanged" "$(active ANTHROPIC_API_KEY)" "ANTHROPIC_API_KEY - alpha"

echo "=== --global is idempotent ==="
before=$(cat "$CONF")
out=$(use ANTHROPIC_API_KEY --global)
check "says already marked" "$out" "already [global]"
check_eq "file byte-identical" "$(cat "$CONF")" "$before"

echo "=== --list displays the marker ==="
out=$(use ANTHROPIC_API_KEY --list)
check "header shows marker" "$out" "ANTHROPIC_API_KEY [global]"
check "still marks active"  "$out" "* ANTHROPIC_API_KEY - alpha"

echo "=== switching accounts PRESERVES the marker ==="
use ANTHROPIC_API_KEY beta >/dev/null
check_eq "beta now active" "$(active ANTHROPIC_API_KEY)" "ANTHROPIC_API_KEY - beta"
check "promoted line keeps the marker" "$(cat "$CONF")" \
    "ANTHROPIC_API_KEY [global] = ANTHROPIC_API_KEY - beta"
check_eq "name still global" "$(is_global ANTHROPIC_API_KEY)" "yes"

echo "=== --next preserves the marker too ==="
use ANTHROPIC_API_KEY --next >/dev/null
check "blocked line keeps the marker" "$(cat "$CONF")" \
    "ANTHROPIC_API_KEY [global] = !ANTHROPIC_API_KEY - beta"
check_eq "name still global" "$(is_global ANTHROPIC_API_KEY)" "yes"

echo "=== --no-global strips it from every line, blocked ones included ==="
out=$(use ANTHROPIC_API_KEY --no-global)
check "reports the change" "$out" "no longer [global]"
check_eq "name no longer global" "$(is_global ANTHROPIC_API_KEY)" "no"
check_not_contains "no marker anywhere" "$(cat "$CONF")" "[global]"
check "blocked state survives" "$(cat "$CONF")" "ANTHROPIC_API_KEY = !ANTHROPIC_API_KEY - beta"

echo "=== a hand-edited, partially-tagged name normalises on the next write ==="
cat > "$CONF" <<'EOF'
ANTHROPIC_API_KEY [global] = ANTHROPIC_API_KEY - alpha
ANTHROPIC_API_KEY = ANTHROPIC_API_KEY - beta
EOF
check_eq "partially tagged reads as global" \
    "$(is_global ANTHROPIC_API_KEY)" "yes"
use ANTHROPIC_API_KEY gamma >/dev/null
check "every line marked after the write" "$(cat "$CONF")" \
    "ANTHROPIC_API_KEY [global] = ANTHROPIC_API_KEY - beta"
check_eq "gamma is active" "$(active ANTHROPIC_API_KEY)" "ANTHROPIC_API_KEY - gamma"

echo "=== --global works with NO BWS inventory and writes a value-less line ==="
# The deploy migration runs before BWS is installed, so the marker write must
# never consult the key list. Under the no-inventory shim, any command that
# does reach for it fails — which is the control assertion below.
printf '# nothing declared\n' > "$CONF"
out=$(PATH="$FIXTURE/nometa:$FIXTURE/bin:$PATH" "$USE_BIN" HF_TOKEN --global 2>&1)
check "reports the change" "$out" "now [global]"
check_eq "value-less marker line written" "$(grep HF_TOKEN "$CONF")" "HF_TOKEN [global] ="
check_eq "name is global"  "$(is_global HF_TOKEN)" "yes"
check_eq "but declares no key" "$(dotfiles-secrets scope-entries HF_TOKEN)" ""

echo "=== control: an account switch DOES need the inventory ==="
out=$(PATH="$FIXTURE/nometa:$FIXTURE/bin:$PATH" "$USE_BIN" ANTHROPIC_API_KEY alpha 2>&1) || true
check "switching without inventory dies" "$out" "could not list BWS keys"

echo "=== --no-global removes a value-less marker line entirely ==="
"$USE_BIN" HF_TOKEN --no-global >/dev/null 2>&1
check_eq "name no longer global" "$(is_global HF_TOKEN)" "no"
# The decision sentinel is a comment and legitimately still names HF_TOKEN, so
# assert on the declaration lines rather than the whole file.
check_not_contains "declaration gone" "$(grep -v '^#' "$CONF")" "HF_TOKEN"

echo "=== the conf stays 0600 after a marker write ==="
seed_conf
use ANTHROPIC_API_KEY --global >/dev/null
mode=$(stat -c '%a' "$CONF" 2>/dev/null || stat -f '%Lp' "$CONF" 2>/dev/null)
check_eq "mode 600" "$mode" "600"

echo "=== the deploy migration marks ANTHROPIC_API_KEY on a bare machine ==="
# deploy.sh's secrets phase is the caller that keeps the two sanctioned hooks
# (approval classifier, SessionStart health probe) resolving a bare name once
# the scoping gate lands. It runs before bws is installed, so it is exercised
# here under the no-inventory shim, exactly as the deploy line invokes it.
DEPLOY_SH="$(cd "$(dirname "$0")/.." && pwd)/deploy.sh"
check "deploy.sh still performs the migration" "$(cat "$DEPLOY_SH")" \
    'secrets-use" ANTHROPIC_API_KEY --global-once'
migrate() { PATH="$FIXTURE/nometa:$FIXTURE/bin:$PATH" "$USE_BIN" ANTHROPIC_API_KEY --global-once; }
printf '# fresh machine\n' > "$CONF"
out=$(migrate 2>&1)
check "marks it without BWS" "$out" "now [global]"
check_eq "hook name is global" "$(is_global ANTHROPIC_API_KEY)" "yes"
before=$(cat "$CONF")
migrate >/dev/null 2>&1
check_eq "a redeploy changes nothing" "$(cat "$CONF")" "$before"
check "the comment survives" "$(cat "$CONF")" "# fresh machine"

# The regression this guards: deploy runs on every deployment, so an
# unconditional --global would silently undo a deliberate revocation and
# reopen bare non-TTY resolution for the name the user just closed.
echo "=== a redeploy does NOT undo an explicit --no-global ==="
use ANTHROPIC_API_KEY --no-global >/dev/null
check_eq "user revoked it" "$(is_global ANTHROPIC_API_KEY)" "no"
out=$(migrate 2>&1)
check "the migration stands down" "$out" "already decided"
check_eq "revocation survives the redeploy" "$(is_global ANTHROPIC_API_KEY)" "no"

# The sharper version of the same hole: on a conf that predates the migration
# the name is ALREADY unmarked, so --no-global changes no bytes. If it recorded
# nothing, the next deploy would mark it and the user's explicit revocation
# would be silently reversed.
echo "=== --no-global sticks even when it changes nothing ==="
printf '# pre-migration conf\nANTHROPIC_API_KEY = ANTHROPIC_API_KEY - alpha\n' > "$CONF"
check_eq "starts unmarked" "$(is_global ANTHROPIC_API_KEY)" "no"
out=$(use ANTHROPIC_API_KEY --no-global)
check "reports the no-op" "$out" "already not [global]"
out=$(migrate 2>&1)
check "the migration still stands down" "$out" "already decided"
check_eq "still not global after a deploy" "$(is_global ANTHROPIC_API_KEY)" "no"

echo "=== an altered or deleted sentinel lets deploy decide again ==="
# Documented escape hatch: the sentinel is the record, so removing it restores
# the pre-decision state rather than failing closed in some hidden way.
grep -v 'global-scope-decided' "$CONF" > "$CONF.tmp" && mv "$CONF.tmp" "$CONF"
migrate >/dev/null 2>&1
check_eq "deploy marks it once more" "$(is_global ANTHROPIC_API_KEY)" "yes"

echo "=== the sentinel survives the operations that rewrite the name ==="
printf '# fresh machine\n' > "$CONF"
migrate >/dev/null 2>&1
use ANTHROPIC_API_KEY beta >/dev/null
check "account switch keeps the sentinel" "$(cat "$CONF")" \
    "# global-scope-decided: ANTHROPIC_API_KEY"
check_eq "switching still preserves the marker" "$(is_global ANTHROPIC_API_KEY)" "yes"
check_eq "conf stays 0600 after recording" "$(stat -c '%a' "$CONF" 2>/dev/null || stat -f '%Lp' "$CONF")" "600"

echo "=== concurrent writers serialise on the conf lock ==="
# rewrite_env_lines replaces the file via mv, so an unserialised second writer
# could rename a pre-sentinel snapshot back over the record.
printf '# fresh machine\nANTHROPIC_API_KEY = ANTHROPIC_API_KEY - alpha\nANTHROPIC_API_KEY = ANTHROPIC_API_KEY - beta\n' > "$CONF"
migrate >/dev/null 2>&1 &
use ANTHROPIC_API_KEY beta >/dev/null 2>&1 &
wait
check "sentinel survived the race" "$(cat "$CONF")" \
    "# global-scope-decided: ANTHROPIC_API_KEY"
check_eq "marker survived the race" "$(is_global ANTHROPIC_API_KEY)" "yes"
check_eq "no lock left behind" "$([[ -d "$CONF.lock" ]] && echo stale || echo clean)" "clean"

echo "=== the migration preserves an already-pinned account ==="
printf 'ANTHROPIC_API_KEY = ANTHROPIC_API_KEY - alpha\n' > "$CONF"
use ANTHROPIC_API_KEY --global-once >/dev/null
check "pin kept, marker added" "$(cat "$CONF")" \
    "ANTHROPIC_API_KEY [global] = ANTHROPIC_API_KEY - alpha"
check "decision recorded" "$(cat "$CONF")" "# global-scope-decided: ANTHROPIC_API_KEY"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
