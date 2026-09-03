#!/usr/bin/env bash
# Tests for global-scope BWS key disambiguation in dotfiles-secrets.
# Run: bash tests/test_secrets_global_scope.sh
#
# Fully hermetic. The suite runs the helper under DOTFILES_SECRETS_BACKEND=fixture,
# a test-only backend that reads secrets/meta/raw from a fixture directory and
# never touches the network. No real secret is read or printed here, and no BWS
# token is required — this suite passes on a fresh clone with no credentials.
#
# It used to inject fixtures by pointing DOTFILES_SECRETS_CACHE_DIR at a temp
# directory. That cache no longer exists, and the mechanism was unsafe anyway:
# an empty value read as "unset" and fell back to the LIVE store. The fixture
# backend dies instead of falling back, which is asserted below.

set -uo pipefail

BIN="$(cd "$(dirname "$0")/.." && pwd)/custom_bins/dotfiles-secrets"
PASS=0
FAIL=0

# Repo-local tmp/ (gitignored): $TMPDIR is not reliably writable under the
# Claude Code sandbox, and this keeps the fixture portable either way.
TMP_ROOT="$(cd "$(dirname "$0")/.." && pwd)/tmp"
mkdir -p "$TMP_ROOT"
FIXTURE=$(mktemp -d "$TMP_ROOT/secrets-scope.XXXXXX") || {
    echo "could not create fixture dir under $TMP_ROOT" >&2; exit 1; }
[[ -n "$FIXTURE" && -d "$FIXTURE" ]] || {
    echo "fixture dir is not usable: ${FIXTURE:-<empty>}" >&2; exit 1; }
trap 'rm -rf "$FIXTURE"' EXIT

# --- fixture data ----------------------------------------------------------
# Two ANTHROPIC keys (ambiguous), one HF_TOKEN (unambiguous), and one key whose
# label contains both " - " and ":" to prove the parser handles real labels.
b64() { printf '%s' "$1" | base64 | tr -d '\n'; }

cat > "$FIXTURE/secrets" <<EOF
ANTHROPIC_API_KEY=fake-anthropic-alpha
HF_TOKEN=fake-hf
RUNPOD_API_KEY=fake-runpod-one
EOF

printf '%s\n' \
    "ANTHROPIC_API_KEY	ANTHROPIC_API_KEY - alpha		uuid-alpha" \
    "ANTHROPIC_API_KEY	ANTHROPIC_API_KEY - beta gamma		uuid-beta" \
    "HF_TOKEN	HF_TOKEN		uuid-hf" \
    "RUNPOD_API_KEY	RUNPOD_API_KEY - one:Two		uuid-rp1" \
    "RUNPOD_API_KEY	RUNPOD_API_KEY - three		uuid-rp3" \
    > "$FIXTURE/meta"

printf '%s\n' \
    "ANTHROPIC_API_KEY - alpha	$(b64 fake-anthropic-alpha)		uuid-alpha" \
    "ANTHROPIC_API_KEY - beta gamma	$(b64 fake-anthropic-beta)		uuid-beta" \
    "HF_TOKEN	$(b64 fake-hf)		uuid-hf" \
    "RUNPOD_API_KEY - one:Two	$(b64 fake-runpod-one)		uuid-rp1" \
    "RUNPOD_API_KEY - three	$(b64 fake-runpod-three)		uuid-rp3" \
    > "$FIXTURE/raw"

# Run the binary against the fixtures with a given secrets-global.conf body.
# Prints "<exit status>\n<stdout>\n---STDERR---\n<stderr>".
run_with_conf() {
    local conf_body="$1"; shift
    printf '%s\n' "$conf_body" > "$FIXTURE/scope.conf"
    local out err rc=0
    err="$FIXTURE/stderr.txt"
    out=$(DOTFILES_SECRETS_BACKEND=fixture \
          DOTFILES_SECRETS_FIXTURE_DIR="$FIXTURE" \
          DOTFILES_SECRETS_GLOBAL_CONF="$FIXTURE/scope.conf" \
          "$BIN" "$@" 2>"$err") || rc=$?
    printf '%s\n%s\n---STDERR---\n%s\n' "$rc" "$out" "$(cat "$err")"
}

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

check_not() {
    local desc="$1" got="$2" unwanted="$3"
    if [[ "$got" != *"$unwanted"* ]]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL: %s\n  should NOT contain: %s\n' "$desc" "$unwanted"
    fi
}

echo "=== ambiguous name, default declared -> resolves to the declared key ==="
R=$(run_with_conf 'ANTHROPIC_API_KEY = ANTHROPIC_API_KEY - beta gamma' shell ANTHROPIC_API_KEY)
check "exit 0"                "$R" $'0\n'
check "exports the beta value" "$R" "fake-anthropic-beta"

echo "=== ambiguous name, nothing declared -> dies, names the candidates ==="
R=$(run_with_conf '# nothing declared' shell ANTHROPIC_API_KEY)
check "non-zero exit"         "$R" $'1\n'
check "no value on stdout"    "$R" $'1\n\n---STDERR---'
check "says ambiguous"        "$R" "Ambiguous env name 'ANTHROPIC_API_KEY'"
check "lists candidate alpha" "$R" "ANTHROPIC_API_KEY - alpha"
check "lists candidate beta"  "$R" "ANTHROPIC_API_KEY - beta gamma"
check "points at the conf"    "$R" "scope.conf"
check "suggests secrets-use"  "$R" "secrets-use ANTHROPIC_API_KEY"

echo "=== declared key that does not exist -> dies, does not fall through ==="
R=$(run_with_conf 'ANTHROPIC_API_KEY = ANTHROPIC_API_KEY - typo' shell ANTHROPIC_API_KEY)
check "non-zero exit"      "$R" $'1\n'
check "names the bad map"  "$R" "which is not one of its BWS keys"

echo "=== unambiguous name -> unaffected by the map ==="
R=$(run_with_conf '# empty' shell HF_TOKEN)
check "exit 0"          "$R" $'0\n'
check "exports HF"      "$R" "fake-hf"

echo "=== a named key that is absent -> dies (used to warn and exit 0) ==="
R=$(run_with_conf '# empty' shell NOT_A_REAL_KEY)
check "non-zero exit"   "$R" $'1\n'
check "says not found"  "$R" "not found in encrypted secrets"

echo "=== --all is best-effort: skips undeclared-ambiguous, keeps the rest ==="
R=$(run_with_conf '# nothing declared' shell --all)
check "exit 0"                  "$R" $'0\n'
check "still exports HF_TOKEN"  "$R" "fake-hf"
check "warns about the skip"    "$R" "skipping ambiguous env name 'ANTHROPIC_API_KEY'"
check_not "did not export the ambiguous key" "$R" "export ANTHROPIC_API_KEY"

echo "=== --all with a declaration exports the declared one ==="
R=$(run_with_conf 'ANTHROPIC_API_KEY = ANTHROPIC_API_KEY - alpha' shell --all)
check "exit 0"            "$R" $'0\n'
check "exports alpha"     "$R" "fake-anthropic-alpha"

echo "=== get-value honours the map for a bare ambiguous name ==="
R=$(run_with_conf 'ANTHROPIC_API_KEY = ANTHROPIC_API_KEY - beta gamma' get-value ANTHROPIC_API_KEY)
check "exit 0"        "$R" $'0\n'
check "returns beta"  "$R" "fake-anthropic-beta"

echo "=== get-value with an exact key still bypasses the map entirely ==="
R=$(run_with_conf 'ANTHROPIC_API_KEY = ANTHROPIC_API_KEY - beta gamma' get-value 'ANTHROPIC_API_KEY - alpha')
check "exit 0"         "$R" $'0\n'
check "returns alpha"  "$R" "fake-anthropic-alpha"

echo "=== get-value on an ambiguous undeclared name still dies ==="
R=$(run_with_conf '# empty' get-value ANTHROPIC_API_KEY)
check "non-zero exit" "$R" $'1\n'
check "says ambiguous" "$R" "Ambiguous env name"

echo "=== conf parsing: labels with ':' and ' - ', comments, odd whitespace ==="
R=$(run_with_conf "$(printf '%s\n' \
        '# a comment' \
        '' \
        '   RUNPOD_API_KEY   =   RUNPOD_API_KEY - one:Two   ' \
        'HF_TOKEN = HF_TOKEN')" shell RUNPOD_API_KEY)
check "exit 0"                "$R" $'0\n'
check "colon label resolves"  "$R" "fake-runpod-one"

R=$(run_with_conf 'ANTHROPIC_API_KEY=ANTHROPIC_API_KEY - alpha' shell ANTHROPIC_API_KEY)
check "no spaces around ="    "$R" "fake-anthropic-alpha"

echo "=== a commented-out declaration counts as undeclared ==="
R=$(run_with_conf '# ANTHROPIC_API_KEY = ANTHROPIC_API_KEY - alpha' shell ANTHROPIC_API_KEY)
check "non-zero exit"  "$R" $'1\n'
check "says ambiguous" "$R" "Ambiguous env name"

# --- R1: ordered preference lists with active/blocked state -----------------

echo "=== preference order: first ACTIVE line wins ==="
R=$(run_with_conf "$(printf '%s\n' \
        'ANTHROPIC_API_KEY = ANTHROPIC_API_KEY - alpha' \
        'ANTHROPIC_API_KEY = ANTHROPIC_API_KEY - beta gamma')" shell ANTHROPIC_API_KEY)
check "exit 0"             "$R" $'0\n'
check "resolves to alpha"  "$R" "fake-anthropic-alpha"

echo "=== a blocked first choice is skipped, next active is promoted ==="
R=$(run_with_conf "$(printf '%s\n' \
        'ANTHROPIC_API_KEY = !ANTHROPIC_API_KEY - alpha' \
        'ANTHROPIC_API_KEY = ANTHROPIC_API_KEY - beta gamma')" shell ANTHROPIC_API_KEY)
check "exit 0"                 "$R" $'0\n'
check "resolves to beta"       "$R" "fake-anthropic-beta"
check_not "did not use blocked alpha" "$R" "fake-anthropic-alpha"

echo "=== '!' with a space after it is still blocked ==="
R=$(run_with_conf "$(printf '%s\n' \
        'ANTHROPIC_API_KEY = ! ANTHROPIC_API_KEY - alpha' \
        'ANTHROPIC_API_KEY = ANTHROPIC_API_KEY - beta gamma')" shell ANTHROPIC_API_KEY)
check "resolves to beta"       "$R" "fake-anthropic-beta"
check_not "did not use blocked alpha" "$R" "fake-anthropic-alpha"

echo "=== every declared key blocked -> dies, tells you to unblock ==="
R=$(run_with_conf "$(printf '%s\n' \
        'ANTHROPIC_API_KEY = !ANTHROPIC_API_KEY - alpha' \
        'ANTHROPIC_API_KEY = !ANTHROPIC_API_KEY - beta gamma')" shell ANTHROPIC_API_KEY)
check "non-zero exit"        "$R" $'1\n'
check "says all blocked"     "$R" "Every declared key for 'ANTHROPIC_API_KEY' is blocked"
check "suggests --activate"  "$R" "--activate"
check_not "does not exit 0"  "$R" $'0\n'

echo "=== scope-entries reports order and state ==="
R=$(run_with_conf "$(printf '%s\n' \
        'ANTHROPIC_API_KEY = !ANTHROPIC_API_KEY - alpha' \
        'ANTHROPIC_API_KEY = ANTHROPIC_API_KEY - beta gamma')" scope-entries ANTHROPIC_API_KEY)
check "exit 0"           "$R" $'0\n'
check "alpha is blocked" "$R" $'blocked\tANTHROPIC_API_KEY - alpha'
check "beta is active"   "$R" $'active\tANTHROPIC_API_KEY - beta gamma'

echo "=== a blocked key is never auto-unblocked by resolution ==="
# Resolving through a blocked entry must leave the conf byte-identical:
# failover is a human action, never a side effect of a lookup.
CONF_BEFORE=$(cat "$FIXTURE/scope.conf")
run_with_conf "$CONF_BEFORE" shell ANTHROPIC_API_KEY >/dev/null
if [[ "$(cat "$FIXTURE/scope.conf")" == "$CONF_BEFORE" ]]; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1)); echo "FAIL: resolution mutated secrets-global.conf"
fi

# --- R6: the fixture backend must never fall through to a live store --------

echo "=== fixture backend with no fixture dir -> hard error, no live fallback ==="
err=$(DOTFILES_SECRETS_BACKEND=fixture "$BIN" shell HF_TOKEN 2>&1); rc=$?
check "non-zero exit"        "$rc" "1"
check "names the missing var" "$err" "DOTFILES_SECRETS_FIXTURE_DIR"
check "says it refuses to fall back" "$err" "refusing to fall back"

echo "=== fixture backend pointed at a nonexistent dir -> hard error ==="
err=$(DOTFILES_SECRETS_BACKEND=fixture DOTFILES_SECRETS_FIXTURE_DIR="$FIXTURE/nope" \
      "$BIN" shell HF_TOKEN 2>&1); rc=$?
check "non-zero exit"  "$rc" "1"
check "names the dir"  "$err" "fixture directory does not exist"

echo "=== no cache is written anywhere during a resolution ==="
# The whole point of R6: a resolution must not put a plaintext secret on disk.
# Assert on what this run DID, not on machine state — a leftover directory from
# the pre-R6 implementation is a deployment cleanup, and failing the suite for
# it would make a green run depend on which machine it happens to be on.
CACHE_DIR_OLD="$HOME/.cache/dotfiles-secrets"
[[ -d "$CACHE_DIR_OLD" ]] && EXISTED_BEFORE=true || EXISTED_BEFORE=false
run_with_conf 'ANTHROPIC_API_KEY = ANTHROPIC_API_KEY - alpha' shell ANTHROPIC_API_KEY >/dev/null
if [[ -d "$CACHE_DIR_OLD" && "$EXISTED_BEFORE" == false ]]; then
    FAIL=$((FAIL + 1))
    echo "FAIL: resolution created $CACHE_DIR_OLD (R6 requires no plaintext cache)"
else
    PASS=$((PASS + 1))
    [[ "$EXISTED_BEFORE" == true ]] && \
        echo "  note: $CACHE_DIR_OLD predates this run — remove it (pre-R6 leftover)"
fi

echo "=== a missing conf file is not an error for unambiguous names ==="
rm -f "$FIXTURE/scope.conf"
out=$(DOTFILES_SECRETS_BACKEND=fixture DOTFILES_SECRETS_FIXTURE_DIR="$FIXTURE" \
      DOTFILES_SECRETS_GLOBAL_CONF="$FIXTURE/nonexistent.conf" \
      "$BIN" shell HF_TOKEN 2>/dev/null)
check "exports HF without a conf" "$out" "fake-hf"

echo "=== the conf resolves to the MAIN checkout, not a worktree copy ==="
# R1 calls the conf the single per-machine authority "for every scope". The conf
# is gitignored, so a worktree never has one; a binary that resolved it relative
# to its own tree would find nothing and hard-error on every ambiguous name.
# setup-envrc also bakes this binary's absolute path into a repo's .envrc, so a
# worktree-relative answer outlives the worktree that produced it.
WT_ROOT="$FIXTURE/wt-test"
mkdir -p "$WT_ROOT/main"
(
    cd "$WT_ROOT/main" || exit 1
    git init -q .
    git config user.email t@example.com
    git config user.name t
    mkdir -p custom_bins scripts/helpers config
    cp "$BIN" custom_bins/dotfiles-secrets
    cp "$(dirname "$(dirname "$BIN")")/scripts/helpers/dotfiles_secrets.sh" scripts/helpers/
    git add -f custom_bins scripts >/dev/null 2>&1
    git commit -qm init >/dev/null 2>&1
    git worktree add -q ../wt -b wt-branch >/dev/null 2>&1
) >/dev/null 2>&1

if [[ -x "$WT_ROOT/wt/custom_bins/dotfiles-secrets" ]]; then
    got=$(DOTFILES_SECRETS_BACKEND=fixture \
          "$WT_ROOT/wt/custom_bins/dotfiles-secrets" scope-conf-path 2>/dev/null)
    # Resolve symlinks on the expectation: macOS /var -> /private/var.
    want="$(cd "$WT_ROOT/main" && pwd -P)/config/secrets-global.conf"
    check "worktree resolves to main checkout" "$got" "$want"

    got=$(DOTFILES_SECRETS_BACKEND=fixture \
          "$WT_ROOT/main/custom_bins/dotfiles-secrets" scope-conf-path 2>/dev/null)
    check "main checkout resolves to itself"   "$got" "$want"
else
    echo "  SKIP: could not create a git worktree fixture"
fi

# --- duplicate-warning suppression follows the machine conf -----------------
# The warning lives in load_secrets_bws's parser, which the fixture backend
# bypasses, so these cases run the REAL bws path against a fake `bws` binary.

echo "=== duplicate env name, declared in conf -> no warning ==="
FAKE_BIN="$FIXTURE/fakebin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/bws" <<'FAKEBWS'
#!/usr/bin/env bash
# Fake bws: only supports `bws --color no secret list`.
cat <<'JSON'
[
  {"id": "uuid-alpha", "key": "ANTHROPIC_API_KEY - alpha", "value": "fake-a", "note": ""},
  {"id": "uuid-beta",  "key": "ANTHROPIC_API_KEY - beta gamma", "value": "fake-b", "note": ""},
  {"id": "uuid-rp1",   "key": "RUNPOD_API_KEY - one:Two", "value": "fake-r1", "note": ""},
  {"id": "uuid-rp3",   "key": "RUNPOD_API_KEY - three", "value": "fake-r3", "note": ""},
  {"id": "uuid-hf",    "key": "HF_TOKEN", "value": "fake-hf", "note": ""}
]
JSON
FAKEBWS
chmod +x "$FAKE_BIN/bws"

# Runs `keys` (any value-loading command works) on the real bws path with the
# fake binary. TMPDIR points into the fixture: the real path mktemps a stderr
# capture file, and the ambient TMPDIR may be unwritable under the sandbox.
# Streams are captured separately — warnings belong on stderr, and a warning
# leaking to stdout would corrupt the dotenv/meta/raw split — and the exit
# status is kept, so a case that warns must also prove `keys` still succeeded.
# Sets FAKE_RC / FAKE_OUT (stdout) / FAKE_ERR (stderr).
run_fake_bws() {
    local conf_body="$1"
    printf '%s\n' "$conf_body" > "$FIXTURE/scope.conf"
    PATH="$FAKE_BIN:$PATH" TMPDIR="$FIXTURE" \
        BWS_ACCESS_TOKEN=fake-token \
        DOTFILES_SECRETS_BACKEND=bws \
        DOTFILES_SECRETS_GLOBAL_CONF="$FIXTURE/scope.conf" \
        "$BIN" keys > "$FIXTURE/fake.out" 2> "$FIXTURE/fake.err"
    FAKE_RC=$?
    FAKE_OUT=$(<"$FIXTURE/fake.out")
    FAKE_ERR=$(<"$FIXTURE/fake.err")
}

run_fake_bws 'ANTHROPIC_API_KEY = ANTHROPIC_API_KEY - beta gamma'
check     "keys exits 0"                       "$FAKE_RC" "0"
check     "keys still lists the name"          "$FAKE_OUT" "ANTHROPIC_API_KEY"
check_not "no warning on stdout"               "$FAKE_OUT" "WARNING"
check_not "no warning for the declared name"   "$FAKE_ERR" "duplicate env name 'ANTHROPIC_API_KEY'"
check     "still warns for undeclared RUNPOD"  "$FAKE_ERR" "duplicate env name 'RUNPOD_API_KEY'"
check     "warning suggests secrets-use"       "$FAKE_ERR" "secrets-use RUNPOD_API_KEY"

echo "=== blocked-only conf entry does not suppress the warning ==="
run_fake_bws 'ANTHROPIC_API_KEY = !ANTHROPIC_API_KEY - beta gamma'
check "blocked-only name still warns" "$FAKE_ERR" "duplicate env name 'ANTHROPIC_API_KEY'"

echo "=== stale declaration (mapped key gone from BWS) still warns ==="
run_fake_bws 'ANTHROPIC_API_KEY = ANTHROPIC_API_KEY - deleted'
check "stale mapping warns but keys still exits 0" "$FAKE_RC" "0"
check "keys output survives the stale warning" "$FAKE_OUT" "ANTHROPIC_API_KEY"
check "stale mapping still warns"   "$FAKE_ERR" "duplicate env name 'ANTHROPIC_API_KEY'"
check "warning names the stale key" "$FAKE_ERR" "ANTHROPIC_API_KEY - deleted"
check "stale warning suggests re-pick" "$FAKE_ERR" "secrets-use ANTHROPIC_API_KEY"

echo "=== blocked lines then a stale active line still warns ==="
run_fake_bws "$(printf '%s\n' \
        'ANTHROPIC_API_KEY = !ANTHROPIC_API_KEY - alpha' \
        'ANTHROPIC_API_KEY = ANTHROPIC_API_KEY - deleted')"
check "stale-after-blocked warns" "$FAKE_ERR" "duplicate env name 'ANTHROPIC_API_KEY'"

echo "=== both names declared -> silent ==="
run_fake_bws "$(printf '%s\n' \
        'ANTHROPIC_API_KEY = ANTHROPIC_API_KEY - alpha' \
        'RUNPOD_API_KEY = RUNPOD_API_KEY - three')"
check     "all-declared keys exits 0"      "$FAKE_RC" "0"
check     "all-declared still lists names" "$FAKE_OUT" "HF_TOKEN"
check_not "no ANTHROPIC warning" "$FAKE_ERR" "duplicate env name 'ANTHROPIC_API_KEY'"
check_not "no RUNPOD warning"    "$FAKE_ERR" "duplicate env name 'RUNPOD_API_KEY'"

# --- the RETIRED "[global]" name marker --------------------------------------
# The marker is deleted: no command writes one and nothing reads its meaning.
# A conf carried over from a machine that predates the deletion still has it,
# though, so every parser must keep stripping the suffix. These cases pin that
# tolerance — a reader that stopped stripping would hard-error on every
# ambiguous name in such a conf, which is the ~349-denial failure again.

echo "=== a legacy marked name resolves to exactly the same key as an unmarked one ==="
R=$(run_with_conf 'ANTHROPIC_API_KEY [global] = ANTHROPIC_API_KEY - beta gamma' shell ANTHROPIC_API_KEY)
check "exit 0"                  "$R" $'0\n'
check "marker does not change the resolved value" "$R" "fake-anthropic-beta"
check_not "marker never reaches stdout"           "$R" "[global]"

echo "=== scope-entries strips the marker ==="
R=$(run_with_conf "$(printf '%s\n' \
        'ANTHROPIC_API_KEY [global] = !ANTHROPIC_API_KEY - alpha' \
        'ANTHROPIC_API_KEY [global] = ANTHROPIC_API_KEY - beta gamma')" \
    scope-entries ANTHROPIC_API_KEY)
check "exit 0"                "$R" $'0\n'
check "blocked entry listed"  "$R" $'blocked\tANTHROPIC_API_KEY - alpha'
check "active entry listed"   "$R" $'active\tANTHROPIC_API_KEY - beta gamma'

echo "=== a legacy value-less marker line declares nothing and disturbs nothing ==="
# The retired migration wrote these on a machine where the name was unambiguous,
# so a real conf can still hold one. It must parse as no declaration at all.
R=$(run_with_conf 'HF_TOKEN [global] =' scope-entries HF_TOKEN)
check "value-less marker declares no entry" "$R" $'0\n\n---STDERR---'
R=$(run_with_conf 'HF_TOKEN [global] =' shell HF_TOKEN)
check "unambiguous name still resolves" "$R" $'0\n'
check "and exports its value"           "$R" "fake-hf"

echo "=== a legacy value-less marker does not satisfy an ambiguous name ==="
R=$(run_with_conf 'ANTHROPIC_API_KEY [global] =' shell ANTHROPIC_API_KEY)
check "still dies as undeclared" "$R" $'1\n'
check "still says ambiguous"     "$R" "Ambiguous env name 'ANTHROPIC_API_KEY'"

echo "=== duplicate-warning suppression survives a legacy marker ==="
run_fake_bws "$(printf '%s\n' \
        'ANTHROPIC_API_KEY [global] = ANTHROPIC_API_KEY - alpha' \
        'RUNPOD_API_KEY = RUNPOD_API_KEY - three')"
check     "exits 0"                 "$FAKE_RC" "0"
check_not "marked name stays quiet" "$FAKE_ERR" "duplicate env name 'ANTHROPIC_API_KEY'"
check_not "unmarked name too"       "$FAKE_ERR" "duplicate env name 'RUNPOD_API_KEY'"

echo "=== a legacy-marked but STALE declaration still warns ==="
run_fake_bws 'ANTHROPIC_API_KEY [global] = ANTHROPIC_API_KEY - deleted'
check "stale marked mapping still warns" "$FAKE_ERR" "duplicate env name 'ANTHROPIC_API_KEY'"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
