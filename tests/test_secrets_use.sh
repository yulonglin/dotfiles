#!/usr/bin/env bash
# Tests for secrets-use — the CLI that edits config/secrets-global.conf.
# Run: bash tests/test_secrets_use.sh
#
# Hermetic: runs dotfiles-secrets under DOTFILES_SECRETS_BACKEND=fixture and
# points secrets-use at a shim PATH, so no BWS token, no network and no real
# secret is involved.
#
# The "[global]" exposure marker this file used to test is deleted. What remains
# of it here is one case proving a legacy conf that still carries the suffix
# keeps resolving and sheds it on the next write.
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

echo "=== a legacy [global] marker is stripped on the next write ==="
# The exposure marker is retired. Nothing writes one, but a conf carried over
# from a machine that predates the deletion still has to keep resolving, and
# the first write of that name must clean it up rather than half-preserve it.
cat > "$CONF" <<'EOF'
ANTHROPIC_API_KEY [global] = ANTHROPIC_API_KEY - alpha
ANTHROPIC_API_KEY = ANTHROPIC_API_KEY - beta
EOF
check_eq "a marked line still reads as its name" \
    "$(active ANTHROPIC_API_KEY)" "ANTHROPIC_API_KEY - alpha"
use ANTHROPIC_API_KEY gamma >/dev/null
check_not_contains "marker gone after the write" "$(cat "$CONF")" "[global]"
check_eq "gamma is active" "$(active ANTHROPIC_API_KEY)" "ANTHROPIC_API_KEY - gamma"
check "beta survived as a fallback" "$(cat "$CONF")" "ANTHROPIC_API_KEY = ANTHROPIC_API_KEY - beta"

echo "=== an account switch needs the BWS inventory ==="
out=$(PATH="$FIXTURE/nometa:$FIXTURE/bin:$PATH" "$USE_BIN" ANTHROPIC_API_KEY alpha 2>&1) || true
check "switching without inventory dies" "$out" "could not list BWS keys"

echo "=== concurrent account writers produce a valid serial outcome ==="
# Every mutation is read-decide-rewrite. Locking only the write lets two
# processes snapshot the same order and land a result equal to neither serial
# ordering — silently discarding an account choice, which is a billing change.
#
# Forking two writers and hoping they collide is NOT a regression test: measured
# against a copy of secrets-use with the lock neutered, that catches the bug 1
# time in 40. So the interleaving is forced instead, via the test-only
# SECRETS_USE_TEST_PRE_MV_DELAY seam — --next takes its snapshot, stalls before
# the rename, and `set gamma` runs inside that window.
#
# Starting from alpha active, the two serial orderings are:
#   set-then-next: gamma promoted, then blocked  -> alpha active
#   next-then-set: alpha blocked, gamma promoted -> gamma active
# beta is reachable ONLY by --next writing a snapshot taken before `set` ran.
# It is the corruption signature, not a valid result.
active_key() { awk -F' = ' '!/^#/ && NF>1 {v=$2; if (substr(v,1,1)!="!") {print v; exit}}' "$CONF"; }
printf 'ANTHROPIC_API_KEY = ANTHROPIC_API_KEY - alpha\nANTHROPIC_API_KEY = ANTHROPIC_API_KEY - beta\nANTHROPIC_API_KEY = ANTHROPIC_API_KEY - gamma\n' > "$CONF"
SECRETS_USE_TEST_PRE_MV_DELAY=3 use ANTHROPIC_API_KEY --next >/dev/null 2>&1 &
# Barrier, not a guessed sleep: rewrite_env_lines stages "$CONF.tmp.<pid>"
# BEFORE the stall, so the file appearing proves --next has already taken its
# snapshot. A fixed sleep raced the fixture backend's startup and let `set` win
# the read — measured 0/8 detection that way, so this matters.
staged=no
for _ in $(seq 1 200); do
    if compgen -G "$CONF.tmp.*" >/dev/null; then staged=yes; break; fi
    sleep 0.05
done
check_eq "--next reached its stall (test barrier held)" "$staged" "yes"
use ANTHROPIC_API_KEY gamma >/dev/null 2>&1 &
wait
case "$(active_key)" in
    "ANTHROPIC_API_KEY - alpha"|"ANTHROPIC_API_KEY - gamma") outcome=serial ;;
    *) outcome="$(active_key)" ;;
esac
check_eq "outcome matches one of the two serial orderings" "$outcome" "serial"
check_eq "no lock left behind" "$([[ -d "$CONF.lock" ]] && echo stale || echo clean)" "clean"

echo "=== an unwritable conf dir is a permissions error, not a busy lock ==="
# mkdir fails identically for contention and for an unwritable parent. Inferring
# the difference from whether the lock dir exists is itself racy — the holder can
# release in between — so the cause is tested directly. Without this the sandbox
# case spins 10s and blames a nonexistent second writer.
if [[ "$EUID" -eq 0 ]]; then
    echo "  (skipped: root ignores the mode bits)"
else
    RO="$FIXTURE/ro"
    mkdir -p "$RO" "$FIXTURE/robin"
    printf 'ANTHROPIC_API_KEY = ANTHROPIC_API_KEY - alpha\n' > "$RO/conf"
    # secrets-use learns the conf path from `dotfiles-secrets scope-conf-path`,
    # so pointing it elsewhere needs its own shim — an inherited env var is
    # overridden by the main shim's `env ...` line.
    cat > "$FIXTURE/robin/dotfiles-secrets" <<EOF
#!/usr/bin/env bash
exec env DOTFILES_SECRETS_BACKEND=fixture \\
         DOTFILES_SECRETS_FIXTURE_DIR="$FIXTURE" \\
         DOTFILES_SECRETS_GLOBAL_CONF="$RO/conf" \\
         "$REPO/custom_bins/dotfiles-secrets" "\$@"
EOF
    chmod +x "$FIXTURE/robin/dotfiles-secrets"
    chmod a-w "$RO"
    out=$(PATH="$FIXTURE/robin:$PATH" "$USE_BIN" ANTHROPIC_API_KEY beta 2>&1)
    chmod u+w "$RO"
    check "names the permissions problem" "$out" "not writable"
    check_eq "does not blame a second writer" \
        "$(printf '%s' "$out" | grep -c 'Another secrets-use')" "0"
fi

echo "=== a lock released mid-wait is acquired, not misreported ==="
# HONEST SCOPE: smoke coverage. It confirms the ordinary contention path -- wait,
# then proceed when the holder releases -- but it does NOT detect the
# misclassification it was written for. Measured 0/8 against a copy with the old
# post-failure `[[ -d "$CONF_LOCK" ]]` inference restored, because that window is
# only microseconds wide: by the time the releaser runs, mkdir simply succeeds
# and the diagnosis is never reached. The structural check below is the detector.
printf 'ANTHROPIC_API_KEY = ANTHROPIC_API_KEY - alpha\n' > "$CONF"
mkdir "$CONF.lock"
( sleep 0.5; rmdir "$CONF.lock" ) &
out=$(use ANTHROPIC_API_KEY beta 2>&1)
wait
check_eq "the mutation lands after the holder releases" \
    "$(active ANTHROPIC_API_KEY)" "ANTHROPIC_API_KEY - beta"
check_eq "no permissions error was reported" \
    "$(printf '%s' "$out" | grep -c 'not writable')" "0"
check_eq "no lock left behind" \
    "$([[ -d "$CONF.lock" ]] && echo stale || echo clean)" "clean"

echo "=== a non-directory at the lock path is not read as a permissions error ==="
# The real regression test for the misclassification, with no race in it. The
# old code inferred "unwritable parent" whenever mkdir failed and the lock path
# was not a directory -- normally reachable only in the microseconds between a
# failed mkdir and the holder's release, which is why forcing it via a release
# race detects nothing (0/8). A REGULAR FILE at the lock path puts the process in
# exactly that state deterministically: mkdir fails EEXIST, `-d` is false. The
# old build dies at once blaming a writable directory; this one checks the cause
# directly, finds it fine, and waits like any other contention.
if command -v timeout >/dev/null 2>&1; then
    printf 'ANTHROPIC_API_KEY = ANTHROPIC_API_KEY - alpha\n' > "$CONF"
    rm -rf "$CONF.lock"
    : > "$CONF.lock"          # a FILE, not a directory
    out=$(timeout 2 "$USE_BIN" ANTHROPIC_API_KEY beta 2>&1); rc=$?
    rm -f "$CONF.lock"        # never acquired, so no trap cleans it up
    check_eq "does not blame the parent directory" \
        "$(printf '%s' "$out" | grep -c 'not writable')" "0"
    check_eq "treats it as contention and keeps waiting" "$rc" "124"
else
    echo "  (skipped: no timeout(1) — GNU coreutils, absent on stock macOS)"
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
