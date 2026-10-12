#!/usr/bin/env bash
# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
# `--non-interactive` must not wait for a human it has already decided to skip.
# ═══════════════════════════════════════════════════════════════════════════════
# Four prompts used to gate on `[[ -t 0 ]]` alone — front_load_sudo, the chsh
# call (both scripts/shared/helpers.sh), deploy.sh's _vpn_sudo_ready and
# install.sh's mas sudo pre-warm. A tmux pane, an agent pty or `ssh host
# ./deploy.sh` HAS a TTY, so every one of them prompted, waited out
# DOTFILES_PROMPT_TIMEOUT (60 s by default), and then skipped the step anyway.
#
# Two things make the checks here non-vacuous, and both are load-bearing:
#
#   1. They run on a real pty whose stdin stays OPEN and silent
#      (tests/pty_drive.py). With `</dev/null` every `[[ -t 0 ]]` is already
#      false, so the old code would return instantly too and the whole suite
#      would pass against the bug it exists to catch.
#   2. They assert on ELAPSED TIME, not on the return value. Both the fixed and
#      the broken code end up skipping the step and returning the same status —
#      the only observable difference is the minute of silence in between. A
#      check on the exit code alone would pass even if the fix did nothing.
#
# sudo and chsh are stubbed on PATH, so nothing here touches real credentials,
# the machine's sudo timestamp, or the user's login shell — and the "nobody
# answers" case is reproduced deterministically instead of depending on whether
# this machine happens to have a cached sudo ticket.
#
# Coverage, stated plainly: three of the four sites are timed against the
# shipped code (front_load_sudo and set_zsh_default are sourced from
# helpers.sh; _vpn_sudo_ready is extracted verbatim from deploy.sh). The
# fourth, install.sh's mas sudo pre-warm, is inline in the Brewfile branch and
# would need a Homebrew fixture to time, so it is covered only by the static
# check at the end — which is the check that actually catches the realistic
# regression anyway, a new prompt gating on `[[ -t 0 ]]` alone.
#
# This suite is bash, not the house zsh, to match the pty-suite siblings it
# shares the harness with (test_installers_silent_pty.sh, test_no_stall.sh).
#
# --mutate reverts the four gates to `[[ -t 0 ]]` in a scratch copy of the repo
# and requires every check to go RED. A guard that cannot fail proves nothing.
#
# Usage: tests/test_noninteractive_prompts.sh [--mutate] [--verbose]
set -uo pipefail

DOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRIVE="$DOT_DIR/tests/pty_drive.py"

# The deadline under test. Deliberately NOT 60: a suite that takes a minute per
# check to go red is a suite nobody runs. It only has to be far enough above
# SKIP_BOUND that the two cannot be confused.
PROMPT_TIMEOUT=20
# What "did not wait" means. Sourcing helpers.sh plus a few stub execs is well
# under a second on a warm box; 6 s leaves room for a loaded CI runner while
# staying nowhere near PROMPT_TIMEOUT.
SKIP_BOUND=6
# Harness deadline: must exceed PROMPT_TIMEOUT so a genuine wait is reported as
# a slow completion rather than as a harness timeout we cannot tell apart.
DEADLINE=35

MUTATE=false
VERBOSE=false
for a in "$@"; do
    case "$a" in
        --mutate)  MUTATE=true ;;
        --verbose) VERBOSE=true ;;
    esac
done

PASS=0
FAIL=0
declare -a FAILURES=()
pass() { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() {
    FAIL=$((FAIL + 1))
    FAILURES+=("$1")
    printf '  \033[31mFAIL\033[0m %s\n' "$1"
    [[ -n "${2:-}" ]] && printf '       %s\n' "$2"
}

# ─── Preconditions: fail loudly, never skip ──────────────────────────────────
if ! python3 -c 'import pty' 2>/dev/null; then
    echo "FAIL: python3 with the pty module is required" >&2
    exit 1
fi
if [[ ! -f "$DRIVE" ]]; then
    echo "FAIL: $DRIVE is missing — the pty harness is what makes this suite real" >&2
    exit 1
fi

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/ni-prompts.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT

# ─── Stubs: a sudo and a chsh that behave like an unanswered prompt ──────────
# `sudo -n` fails (no cached ticket), and any prompting form blocks. That is
# exactly the state the guards are supposed to notice and refuse to enter.
mkdir -p "$SCRATCH/bin" "$SCRATCH/home"
cat > "$SCRATCH/bin/sudo" <<'STUB'
#!/usr/bin/env bash
# STUB_SUDO_CACHED=1 makes `sudo -n` succeed. set_zsh_default only reaches the
# gate in front of chsh when sudo is already cached, so without this mode the
# chsh check would return early at the sudo probe and never test its own gate.
if [[ "${1:-}" == "-n" ]]; then
    [[ "${STUB_SUDO_CACHED:-0}" == "1" ]] && exit 0
    exit 1                         # no cached credentials
fi
sleep 300                          # a password prompt nobody answers
STUB
cat > "$SCRATCH/bin/chsh" <<'STUB'
#!/usr/bin/env bash
sleep 300                          # PAM prompt nobody answers
STUB
chmod +x "$SCRATCH/bin/sudo" "$SCRATCH/bin/chsh"

# ─── The tree under test ─────────────────────────────────────────────────────
# --mutate needs a writable copy; the normal run reads the repo in place.
TREE="$DOT_DIR"
if [[ "$MUTATE" == true ]]; then
    TREE="$SCRATCH/tree"
    mkdir -p "$TREE"
    # Only the files the checks source. A full copy would drag in .git and the
    # build trees for no benefit.
    cp -R "$DOT_DIR/scripts" "$TREE/scripts"
    cp "$DOT_DIR/config.sh" "$TREE/config.sh" 2>/dev/null || true
    cp "$DOT_DIR/install.sh" "$DOT_DIR/deploy.sh" "$TREE/" 2>/dev/null || true
    # Put the bug back: the gate forgets NON_INTERACTIVE and tests only the TTY.
    python3 - "$TREE/scripts/shared/helpers.sh" <<'MUT'
import io, sys
p = sys.argv[1]
s = io.open(p, encoding='utf-8').read()
old = 'can_prompt() {\n    [[ "${NON_INTERACTIVE:-false}" == "true" ]] && return 1\n    [[ -t 0 ]]\n}'
new = 'can_prompt() {\n    [[ -t 0 ]]\n}'
if old not in s:
    sys.exit("mutation target not found — the helper was renamed or rewritten; "
             "update tests/test_noninteractive_prompts.sh")
io.open(p, 'w', encoding='utf-8').write(s.replace(old, new))
MUT
    [[ $? -eq 0 ]] || { echo "FAIL: could not plant the mutation" >&2; exit 1; }
fi

# Run one expression against a sourced helpers.sh, on a silent pty, and print
# the elapsed seconds. NON_INTERACTIVE=true is the whole point: it is what
# `--non-interactive` exports, and what the gate must honour.
probe_elapsed() {
    local expr="$1" json
    json=$(python3 "$DRIVE" --deadline "$DEADLINE" \
        --env "PATH=$SCRATCH/bin:$PATH" \
        --env "HOME=$SCRATCH/home" \
        --env "STUB_SUDO_CACHED=${STUB_SUDO_CACHED:-0}" \
        --env "SHELL=/bin/bash" \
        --env "NON_INTERACTIVE=true" \
        --env "DOTFILES_PROMPT_TIMEOUT=$PROMPT_TIMEOUT" \
        --env "DOTFILES_MENU_TIMEOUT=$PROMPT_TIMEOUT" \
        -- zsh -c "
            DOT_DIR='$TREE'
            source '$TREE/config.sh' >/dev/null 2>&1
            source '$TREE/scripts/shared/helpers.sh' >/dev/null 2>&1
            $expr
        " 2>/dev/null)
    [[ "$VERBOSE" == true ]] && printf '%s\n' "$json" | head -c 600
    python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["elapsed"])' <<<"$json" 2>/dev/null \
        || echo 999
}

check_skips_fast() {
    local label="$1" expr="$2" elapsed verdict
    elapsed=$(probe_elapsed "$expr")
    verdict=$(python3 -c "import sys; print('fast' if float(sys.argv[1]) < $SKIP_BOUND else 'slow')" "$elapsed" 2>/dev/null || echo slow)
    if [[ "$verdict" == fast ]]; then
        pass "$label returns in ${elapsed}s (< ${SKIP_BOUND}s) under NON_INTERACTIVE on a live TTY"
    else
        fail "$label waited ${elapsed}s on a prompt an unattended run had already decided to skip" \
             "the gate is testing the TTY only; it must also honour NON_INTERACTIVE"
    fi
}

echo "── NON_INTERACTIVE must suppress the prompt, not wait it out ──"
[[ "$MUTATE" == true ]] && echo "   (--mutate: the gate has been reverted to \`[[ -t 0 ]]\`; every check must go RED)"

# 1. The sudo pre-warm, shared by install.sh and deploy.sh.
check_skips_fast "front_load_sudo" "front_load_sudo"

# 2. The REAL set_zsh_default from helpers.sh, not a reconstruction of it.
#    It only reaches the gate in front of chsh once `sudo -n` succeeds, hence
#    STUB_SUDO_CACHED — the gate under test is the one before chsh, not the
#    sudo probe ahead of it. Under NON_INTERACTIVE it returns before touching
#    /etc/shells, so nothing on this machine is modified.
#    SHELL is forced to /bin/bash in probe_elapsed for the same reason: the
#    function's first line returns early when SHELL already contains "zsh",
#    which is true on the machine most likely to run this suite. --mutate
#    caught that as a check which stayed green with the gate reverted.
STUB_SUDO_CACHED=1 check_skips_fast "set_zsh_default (the chsh guard)" "set_zsh_default || true"

# 3. deploy.sh's VPN gate. Extracted verbatim from the shipped file and eval'd,
#    so this tests deploy.sh's own code rather than a copy of it that could
#    drift — while running none of the deploy around it.
VPN_FN=$(sed -n '/^_vpn_sudo_ready()/,/^}/p' "$TREE/deploy.sh")
if [[ -z "$VPN_FN" ]]; then
    fail "could not extract _vpn_sudo_ready from deploy.sh" "the function was renamed — update this suite"
else
    check_skips_fast "_vpn_sudo_ready (deploy.sh)" "$VPN_FN
_vpn_sudo_ready || true"
fi

# 4. The component menu: same gate, and the one an attended user actually sees.
check_skips_fast "show_component_menu" "show_component_menu deploy || true"

# ─── The gate is not duplicated back into a second spelling ──────────────────
# The four sites were fixed by routing them through one helper. A new prompt
# that reintroduces the bare `[[ -t 0 ]]` test would be invisible to the timing
# checks above until someone happened to hit it, so check the class too.
echo "── one spelling of the gate ──"
# Two functions legitimately test fd 0, and both are named here: can_prompt IS
# the gate, and _watchdog_run re-attaches /dev/tty to a backgrounded child
# rather than guarding any prompt. Anything else is a new prompt that will
# ignore --non-interactive. The check tracks the ENCLOSING function rather than
# pattern-matching the line, because matching the line is what made the first
# version of this check flag the gate's own definition.
strays=$(awk '
    /^[A-Za-z_][A-Za-z0-9_]*\(\) \{/ { fn = $1; sub(/\(\).*/, "", fn) }
    /\[\[ -t 0 \]\]/ {
        if (fn != "can_prompt" && fn != "_watchdog_run")
            printf "%s:%d: (in %s)%s\n", FILENAME, FNR, (fn == "" ? "top level" : fn), $0
    }
' "$DOT_DIR/install.sh" "$DOT_DIR/deploy.sh" "$DOT_DIR/scripts/shared/helpers.sh" 2>/dev/null)
if [[ -z "$strays" ]]; then
    pass "no prompt gates on a bare [[ -t 0 ]] — they all route through can_prompt"
else
    fail "a prompt gates on the TTY alone and will ignore --non-interactive" "$strays"
fi

# ─── Report ──────────────────────────────────────────────────────────────────
echo ""
if [[ "$MUTATE" == true ]]; then
    # Under --mutate the timing checks must fail. The static check above reads
    # the pristine repo on purpose, so it stays green and is excluded here.
    if (( FAIL >= 4 )); then
        echo "MUTATION OK: $FAIL checks went red with the gate reverted"
        exit 0
    fi
    echo "MUTATION FAILED: only $FAIL checks went red — the timing checks cannot" >&2
    echo "  detect the bug they exist to catch, so they prove nothing." >&2
    exit 1
fi

echo "passed: $PASS   failed: $FAIL"
if (( FAIL > 0 )); then
    printf '  - %s\n' "${FAILURES[@]}"
    exit 1
fi
exit 0
