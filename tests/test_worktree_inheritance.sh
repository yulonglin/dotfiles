#!/usr/bin/env bash
# shellcheck shell=bash
#
# What a new worktree inherits: the settings wiring, the .worktreeinclude
# guardrails, and the trust-propagation behaviour of worktree_direnv_allow.sh.

set -uo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SETTINGS="$REPO_ROOT/claude/settings.json"
WT_INCLUDE="$REPO_ROOT/.worktreeinclude"
HOOK="$REPO_ROOT/claude/hooks/worktree_direnv_allow.sh"

pass=0
fail=0

# TMPDIR is read-only under some sandboxes. Print the first base we can actually
# create a directory in, or nothing. Callers MUST treat "nothing" as a failure —
# a scratch dir that silently stayed empty turns assertions into vacuous passes.
scratch_dir() {
    local base d
    for base in "${TMPDIR:-}" /tmp/claude /tmp; do
        [[ -n "$base" && -d "$base" && -w "$base" ]] || continue
        d=$(mktemp -d "$base/${1:-wt-test}.XXXXXX" 2>/dev/null) || continue
        printf '%s\n' "$d"
        return 0
    done
    return 1
}

ok() { echo "  PASS  $1"; pass=$((pass + 1)); }
no() { echo "  FAIL  $1"; fail=$((fail + 1)); }

check() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then ok "$desc"; else no "$desc"; fi
}

echo "settings.json — global worktree wiring"

if python3 - "$SETTINGS" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(1 if [k for k in ("statusLine", "hooks", "permissions") if k not in d] else 0)
PY
then ok "settings.json parses and keeps statusLine/hooks/permissions"
else no "settings.json parses and keeps statusLine/hooks/permissions"
fi

# Artifact dirs must be SYMLINKED, never copied: .worktreeinclude copies file by
# file, so listing one of these there would duplicate an entire dataset.
if python3 - "$SETTINGS" <<'PY'
import json, sys
dirs = set(json.load(open(sys.argv[1]))["worktree"]["symlinkDirectories"])
required = {"data", "out", "outputs", "output", "results",
            "logs", "figures", "figs", "fig", "plots"}
sys.exit(0 if required <= dirs else 1)
PY
then ok "artifact dirs present in worktree.symlinkDirectories"
else no "artifact dirs present in worktree.symlinkDirectories"
fi

if python3 - "$SETTINGS" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
cmds = [h["command"] for e in d["hooks"]["SessionStart"] for h in e.get("hooks", [])]
sys.exit(0 if any("worktree_direnv_allow" in c for c in cmds) else 1)
PY
then ok "worktree_direnv_allow.sh wired into SessionStart"
else no "worktree_direnv_allow.sh wired into SessionStart"
fi

echo ""
echo ".worktreeinclude — guardrails"

check ".worktreeinclude exists" test -f "$WT_INCLUDE"
check ".envrc is included" grep -qx '\.envrc' "$WT_INCLUDE"

# A bare `.claude/` would match `.claude/worktrees/`, copying every existing
# worktree into each new one.
if grep -vE '^[[:space:]]*(#|$)' "$WT_INCLUDE" | grep -qE '^\.claude/?(\*\*)?$'; then
    no "no bare .claude/ entry (would recurse through .claude/worktrees/)"
else
    ok "no bare .claude/ entry (would recurse through .claude/worktrees/)"
fi

# Artifact dirs belong in symlinkDirectories, not here.
if grep -vE '^[[:space:]]*(#|$)' "$WT_INCLUDE" \
    | grep -qE '^(data|out|outputs|output|results|logs|figures|figs|fig|plots)/'; then
    no "no artifact directory copied via .worktreeinclude"
else
    ok "no artifact directory copied via .worktreeinclude"
fi

echo ""
echo "worktree_direnv_allow.sh — propagates trust, never creates it"

if ! command -v git >/dev/null 2>&1; then
    echo "  SKIP  git unavailable"
else
    tmp=$(scratch_dir wt-inherit) || tmp=""
    if [[ -z "$tmp" || ! -d "$tmp" ]]; then
        echo "  FAIL  could not create a writable scratch dir (tried TMPDIR, /tmp/claude, /tmp)"
        echo ""
        echo "passed: $pass  failed: $((fail + 1))"
        exit 1
    fi
    trap 'rm -rf "$tmp"' EXIT

    main="$tmp/main"
    mkdir -p "$main"
    git -C "$main" init -q
    git -C "$main" config user.email t@example.com
    git -C "$main" config user.name test
    echo "seed" > "$main/README"
    git -C "$main" add README
    git -C "$main" commit -qm init
    printf 'export TEST_VAR=1\n' > "$main/.envrc"

    wt="$tmp/wt"
    git -C "$main" worktree add -q -b wt-test "$wt" >/dev/null 2>&1

    # Stand in for direnv so the test asserts the decision, not direnv's state.
    shim="$tmp/bin"
    mkdir -p "$shim"
    cat > "$shim/direnv" <<SHIM
#!/usr/bin/env bash
echo "\$@" >> "$tmp/direnv-calls"
SHIM
    chmod +x "$shim/direnv"

    run_hook() { PATH="$shim:$PATH" bash "$HOOK" < /dev/null 2>&1; }

    # 1. No .envrc in the worktree — nothing to do.
    : > "$tmp/direnv-calls"
    (cd "$wt" && run_hook) >/dev/null
    check "no .envrc in worktree -> direnv not invoked" test ! -s "$tmp/direnv-calls"

    # 2. Identical copy — trust propagates.
    cp "$main/.envrc" "$wt/.envrc"
    : > "$tmp/direnv-calls"
    (cd "$wt" && run_hook) >/dev/null
    check "identical .envrc -> direnv allow called" grep -q "allow" "$tmp/direnv-calls"

    # 3. Edited copy — stays blocked. This is the property that matters: an
    #    edited .envrc is arbitrary shell nobody approved.
    printf 'export EVIL=1\n' >> "$wt/.envrc"
    : > "$tmp/direnv-calls"
    out=$(cd "$wt" && run_hook)
    check "edited .envrc -> direnv NOT called" test ! -s "$tmp/direnv-calls"
    check "edited .envrc -> user is told" grep -q "differs" <<< "$out"

    # 4. Main checkout is never touched, only worktrees.
    cp "$main/.envrc" "$main/.envrc.bak"
    : > "$tmp/direnv-calls"
    (cd "$main" && run_hook) >/dev/null
    check "main checkout -> direnv not invoked" test ! -s "$tmp/direnv-calls"

    git -C "$main" worktree remove --force "$wt" >/dev/null 2>&1
fi

echo ""
echo "cw helpers — a symlinked artifact dir is not worktree-local state"

ALIASES="$REPO_ROOT/config/aliases/claude.sh"

check "_cw_local_artifact_dir is defined" grep -q '_cw_local_artifact_dir()' "$ALIASES"

# The whole point of the helper is that the three call sites stopped using a
# bare -d test, which is true for a symlink to a directory.
if grep -nE "\\[\\[ -d \"\\\$(wt_path|wt)/\\\$dir\" \\]\\]" "$ALIASES" >/dev/null; then
    no "no call site still uses a bare -d test on an artifact dir"
else
    ok "no call site still uses a bare -d test on an artifact dir"
fi

callers=$(grep -c '_cw_local_artifact_dir "' "$ALIASES")
if [[ "$callers" -eq 3 ]]; then
    ok "all three call sites (cwport, cwrm, cwclean) use the helper"
else
    no "all three call sites use the helper (found $callers, expected 3)"
fi

# Behavioural check. The definition is EXTRACTED from claude.sh and eval'd, not
# retyped here — a locally redefined copy would pass no matter what the shipped
# function does, which is exactly the assertion shape that cannot fail.
helper_probe() {
    local def d
    def=$(sed -n '/^_cw_local_artifact_dir() {/,/^}/p' "$ALIASES")
    [[ -n "$def" ]] || return 2
    eval "$def" || return 2

    d=$(scratch_dir cw-helper) || return 2
    mkdir -p "$d/real"
    ln -s "$d/real" "$d/linked"

    local rc_real=1 rc_link=1
    _cw_local_artifact_dir "$d/real" && rc_real=0
    _cw_local_artifact_dir "$d/linked" && rc_link=0
    rm -rf "$d"

    [[ $rc_real -eq 0 && $rc_link -ne 0 ]]
}
check "shipped helper accepts a real dir and rejects a symlinked one" helper_probe

echo ""
echo "passed: $pass  failed: $fail"
[[ $fail -eq 0 ]]
