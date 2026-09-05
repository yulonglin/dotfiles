#!/usr/bin/env bash
# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
# On a TTY nobody types at, the installers show the menu, then finish anyway.
# ═══════════════════════════════════════════════════════════════════════════════
# On 2026-09-04 ./install.sh and ./deploy.sh "did nothing": the component menu
# binary had lost its --items flag in a June merge, read its items from the
# terminal, drew nothing, and waited for keystrokes nobody knew to type. Every
# stall check passed, because each asserted a DEADLINE — and the 60 s menu
# deadline fired, logged a warning, and continued. From the user's chair that
# is a stall; from the canary's it was a pass. CI's own pty step passed in
# 0.1 s because util-linux `script` forwards EOF from its closed stdin into
# the pty, and --minimal made "deployed nothing" look identical to success.
#
# So this suite runs the real scripts on the one harness that reproduces the
# report — a pty whose stdin stays OPEN and silent (tests/pty_drive.py) — with
# a non-minimal profile, and asserts what a deadline cannot:
#   - the menu DREW (alternate-screen bytes on the pty) within seconds
#   - the run finished, exit 0, inside a wall-clock bound far below any
#     internal fallback
#   - the profile's components were deployed, and counted
# plus the two interactive outcomes (Enter confirms, Esc keeps the set) and
# the empty-set refusal.
#
# --mutate replaces the platform binary in a scratch copy with a stub that
# reads stdin — the exact shape of the June regression — and requires red.
# --mutate=bounded plants a 25 s sleep on the deploy path instead: a wait that
# gives up eventually is still a stall from the chair, and this proves the
# wall-clock bound has teeth. A guard that cannot fail proves nothing.
#
# Usage: tests/test_installers_silent_pty.sh [--mutate | --mutate=bounded] [--verbose]
set -uo pipefail
DOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRIVE="$DOT_DIR/tests/pty_drive.py"
ALT_SCREEN='\x1b\[\?1049h'
# The menu's idle deadline for these runs; the wall bound must comfortably
# exceed it plus a symlink deploy (CI measures under 2 s for the deploy).
MENU_IDLE=4
DEPLOY_WALL_BOUND=20
MUTATE=false
MUTATE_KIND=""
VERBOSE=false
for a in "$@"; do
    case "$a" in
        --mutate) MUTATE=true; MUTATE_KIND=stdin-binary ;;
        --mutate=bounded) MUTATE=true; MUTATE_KIND=bounded ;;
        --verbose) VERBOSE=true ;;
    esac
done

PASS=0
FAIL=0
declare -a FAILURES=()
declare -a FAIL_DETAILS=()
pass() { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() {
    FAIL=$((FAIL + 1))
    FAILURES+=("$1")
    FAIL_DETAILS+=("$1 — ${2:-}")
    printf '  \033[31mFAIL\033[0m %s\n' "$1"
    [[ -n "${2:-}" ]] && printf '       %s\n' "$2"
}

case "$(uname -s)-$(uname -m)" in
    Darwin-arm64)  ASSET=claude-tools-darwin-arm64 ;;
    Darwin-x86_64) ASSET=claude-tools-darwin-x86_64 ;;
    Linux-x86_64)  ASSET=claude-tools-linux-x86_64 ;;
    Linux-aarch64) ASSET=claude-tools-linux-aarch64 ;;
    *) echo "FAIL: unsupported platform $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac

# ─── Preconditions: fail loudly, never skip ──────────────────────────────────
# A suite that passes because the menu binary was missing is the vacuous pass
# this file exists to end. CI builds the binary from source before this runs.
if ! python3 -c 'import pty' 2>/dev/null; then
    echo "FAIL: python3 with the pty module is required" >&2
    exit 1
fi
if ! "$DOT_DIR/custom_bins/$ASSET" --version >/dev/null 2>&1; then
    echo "FAIL: custom_bins/$ASSET is missing or does not run — build it first:" >&2
    echo "      (cd tools/claude-tools && cargo build --release --locked && cp target/release/claude-tools ../../custom_bins/$ASSET)" >&2
    exit 1
fi

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/silent-pty.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT
mkdir -p "$SCRATCH/home"

# The scripts under test. Under --mutate they are a scratch copy of the repo
# with the regression planted, so the checkout is never touched.
RUN_DIR="$DOT_DIR"
if [[ "$MUTATE" == true ]]; then
    RUN_DIR="$SCRATCH/repo"
    mkdir -p "$RUN_DIR"
    # Tracked files only. claude/ is symlinked to the live ~/.claude on a real
    # machine, so a blind copy of the tree would drag a gigabyte of session
    # state into TMPDIR; a tarball checkout has no .git and takes the fallback.
    if git -C "$DOT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
        git -C "$DOT_DIR" ls-files -z | tar -C "$DOT_DIR" --null -T - -cf - | tar -C "$RUN_DIR" -xf -
    else
        tar -C "$DOT_DIR" \
            --exclude=.git --exclude=tmp --exclude=target --exclude=.claude \
            --exclude=node_modules --exclude=__pycache__ \
            -cf - . | tar -C "$RUN_DIR" -xf -
    fi
    case "$MUTATE_KIND" in
        stdin-binary)
            # Answers --version, then reads ITEMS FROM STDIN ignoring --items:
            # on a terminal that blocks with nothing drawn. June's binary, exactly.
            cat > "$RUN_DIR/custom_bins/$ASSET" <<'STUB'
#!/usr/bin/env bash
[[ "${1:-}" == "--version" ]] && { echo "claude-tools 0.0.0-stub"; exit 0; }
cat > /dev/null
exit 0
STUB
            chmod +x "$RUN_DIR/custom_bins/$ASSET"
            ;;
        bounded)
            python3 - "$RUN_DIR/deploy.sh" <<'PY' || exit 1
import sys, pathlib
p = pathlib.Path(sys.argv[1]); s = p.read_text()
anchor = "guard_nonempty_components deploy\n"
assert anchor in s, "mutation anchor missing"
p.write_text(s.replace(anchor, anchor + "sleep 25\n", 1))
PY
            ;;
    esac
    echo "(mutation active: $MUTATE_KIND, in a scratch copy of the repo)"
fi

# drive <deadline> <send-or-empty> -- cmd...  → DRIVE_EXIT DRIVE_AT DRIVE_ELAPSED DRIVE_OUT
# DOTFILES_SKIP_LOCAL_CONFIG keeps this machine's config.local.sh out of the
# resolved set, so the standard profile means the same thing everywhere.
drive() {
    local deadline="$1" send="$2"; shift 2
    [[ "$1" == "--" ]] && shift
    local -a extra=()
    [[ -n "$send" ]] && extra=(--send-on-expect "$send")
    local json
    # ${extra[@]+"${extra[@]}"}: bash 3.2 (macOS /bin/bash) counts an empty
    # array expansion as unbound under set -u; this spelling is safe on both.
    json="$(python3 "$DRIVE" --deadline "$deadline" --expect "$ALT_SCREEN" ${extra[@]+"${extra[@]}"} \
        --env "HOME=$SCRATCH/home" --env "DOTFILES_PROMPT_TIMEOUT=5" \
        --env "DOTFILES_MENU_TIMEOUT=$MENU_IDLE" --env "DOTFILES_SKIP_LOCAL_CONFIG=1" -- "$@")"
    DRIVE_EXIT="$(printf '%s' "$json" | python3 -c 'import json,sys; v=json.load(sys.stdin)["exit"]; print("none" if v is None else v)')"
    DRIVE_AT="$(printf '%s' "$json" | python3 -c 'import json,sys; v=json.load(sys.stdin)["expect_at"]; print("none" if v is None else v)')"
    DRIVE_ELAPSED="$(printf '%s' "$json" | python3 -c 'import json,sys; print(int(json.load(sys.stdin)["elapsed"]))')"
    DRIVE_OUT="$(printf '%s' "$json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["output"])')"
    [[ "$VERBOSE" == true ]] && printf '%s\n' "$DRIVE_OUT" | tail -8
}
drew_within() { [[ "$DRIVE_AT" != none ]] && python3 -c "import sys; sys.exit(0 if $DRIVE_AT <= $1 else 1)"; }

# Non-minimal on purpose: with --minimal an empty run and a correct one print
# the same thing. Components that write outside the scratch HOME are switched
# off (claude-tools builds, git-hooks and codex write into the checkout).
DEPLOY_ARGS=(--allow-worktree-deploy --profile=standard --no-claude-tools --no-git-hooks --no-codex)

# Shared assertions for a deploy run that must have completed with the
# standard set. Appends to `why`; the caller adds the menu-outcome checks.
deploy_completed_with_profile() {
    [[ "$DRIVE_EXIT" == 0 ]] || why+="exit=$DRIVE_EXIT (none = stalled past the deadline); "
    (( DRIVE_ELAPSED <= DEPLOY_WALL_BOUND )) || why+="took ${DRIVE_ELAPSED}s, bound is ${DEPLOY_WALL_BOUND}s — something waited; "
    grep -q "^Components ([0-9]*):" <<< "$DRIVE_OUT" || why+="no resolved-set banner; "
    grep -q "Deploying tmux configuration" <<< "$DRIVE_OUT" || why+="profile components were not deployed; "
    grep -qE "Deployment complete! \([1-9][0-9]* components\)" <<< "$DRIVE_OUT" || why+="completion line missing or zero components; "
}

# ─── 1. deploy.sh, nobody types: menu draws, idle deadline, profile deployed ──
test_deploy_menu_draws_then_deadline_keeps_profile() {
    drive 60 '' -- zsh "$RUN_DIR/deploy.sh" "${DEPLOY_ARGS[@]}"
    local why=""
    drew_within 3 || why+="menu never drew (drew_at=$DRIVE_AT); "
    grep -q "Component menu unanswered" <<< "$DRIVE_OUT" || why+="no idle-deadline warning; "
    deploy_completed_with_profile
    if [[ -z "$why" ]]; then
        pass "deploy.sh on a silent pty: menu drew at ${DRIVE_AT}s, deadline fired, profile deployed in ${DRIVE_ELAPSED}s"
    else
        fail "deploy.sh on a silent pty must draw the menu, time out, and deploy the profile" "$why"
    fi
}

# ─── 2. deploy.sh, Enter: confirms the pre-checked set ───────────────────────
test_deploy_enter_confirms_profile() {
    drive 60 '\r' -- zsh "$RUN_DIR/deploy.sh" "${DEPLOY_ARGS[@]}"
    local why=""
    drew_within 3 || why+="menu never drew (drew_at=$DRIVE_AT); "
    grep -q "Component menu unanswered" <<< "$DRIVE_OUT" && why+="deadline fired despite Enter; "
    grep -q "returned no selection" <<< "$DRIVE_OUT" && why+="selection came back empty; "
    deploy_completed_with_profile
    if [[ -z "$why" ]]; then
        pass "deploy.sh: Enter confirms the pre-checked profile (drew at ${DRIVE_AT}s)"
    else
        fail "deploy.sh: Enter on the menu must deploy the pre-checked profile" "$why"
    fi
}

# ─── 3. install.sh, Esc: cancels back to the profile, run completes ──────────
# --minimal here: a non-minimal install.sh installs packages, which is not
# this suite's business. The menu and the cancel path are what is under test.
test_install_menu_draws_and_esc_keeps_profile() {
    drive 60 '\x1b' -- zsh "$RUN_DIR/install.sh" --allow-worktree --minimal
    local why=""
    drew_within 3 || why+="menu never drew (drew_at=$DRIVE_AT); "
    [[ "$DRIVE_EXIT" == 0 ]] || why+="exit=$DRIVE_EXIT; "
    grep -q "Component menu cancelled" <<< "$DRIVE_OUT" || why+="no cancel message; "
    grep -q "Installation complete!" <<< "$DRIVE_OUT" || why+="run did not complete; "
    if [[ -z "$why" ]]; then
        pass "install.sh on a silent pty: menu drew at ${DRIVE_AT}s, Esc cancelled, run completed"
    else
        fail "install.sh must draw the menu and survive Esc" "$why"
    fi
}

# ─── 4. an empty resolved set is refused, not deployed ───────────────────────
# --only with a component this platform filters out resolves to nothing; the
# run must say so and exit nonzero rather than print "complete!".
test_empty_resolved_set_is_refused() {
    local other
    other="$( [[ "$(uname -s)" == Darwin ]] && echo pueue || echo bearcli )"
    drive 60 '\r' -- zsh "$RUN_DIR/deploy.sh" --allow-worktree-deploy --only "$other"
    if [[ "$DRIVE_EXIT" == 1 ]] && grep -q "refusing to run an empty deploy" <<< "$DRIVE_OUT"; then
        pass "deploy.sh refuses a run that resolved to zero components"
    else
        fail "deploy.sh must refuse an empty component set" "exit=$DRIVE_EXIT"
    fi
}

echo "Installers on a silent pty — the menu draws, and the run still finishes"
echo
test_deploy_menu_draws_then_deadline_keeps_profile
# Under mutation only the case that must go red runs: each extra case waits
# out the planted regression's full deadline for no additional signal.
if [[ "$MUTATE" != true ]]; then
    test_deploy_enter_confirms_profile
    test_install_menu_draws_and_esc_keeps_profile
    test_empty_resolved_set_is_refused
fi

echo
echo "─────────────────────────────────────────"
echo "passed: $PASS   failed: $FAIL"
if (( FAIL > 0 )); then
    echo "failures:"
    for f in "${FAILURES[@]}"; do echo "  - $f"; done
fi

if [[ "$MUTATE" == true ]]; then
    # Under mutation case 1 MUST be red, and red for the planted reason — any
    # other failure is a broken suite, not a working guard.
    case "$MUTATE_KIND" in
        stdin-binary) want="menu never drew" ;;
        bounded)      want="took " ;;
    esac
    if printf '%s\n' "${FAIL_DETAILS[@]+"${FAIL_DETAILS[@]}"}" \
        | grep "deploy.sh on a silent pty must draw the menu" | grep -q "$want"; then
        echo "Mutation caught: the suite goes red for the planted $MUTATE_KIND regression."
        exit 0
    fi
    echo "::error::The silent-pty suite did not go red for the planted $MUTATE_KIND regression — it is vacuous."
    exit 1
fi
(( FAIL == 0 ))
