#!/usr/bin/env zsh
# ═══════════════════════════════════════════════════════════════════════════════
# app-picker left unanswered under install.sh's deadline must hand the terminal
# back intact: canonical input, echo, and the alternate screen exited.
# ═══════════════════════════════════════════════════════════════════════════════
# install.sh runs app-picker under run_with_timeout "${DOTFILES_MENU_TIMEOUT:-60}".
# Until 2026-10-03 nothing inside app-picker knew about that deadline, so on
# expiry the outer kill landed while `claude-tools select` held the terminal in
# raw mode on the alternate screen. The selector's restore only ran after its
# event loop returned, so the installer carried on with no echo, no line
# editing and the menu still covering the screen. Completion time alone cannot
# catch this: the run finishes on schedule either way. So each case asserts on
# the terminal itself — `stty -a` read after app-picker returns, and the
# alternate-screen exit sequence in the pty transcript.
#
#   1. install.sh's path: the selector's own idle deadline fires first and exits
#      through its normal cleanup
#   2. the outer kill under timeout(1), with no idle deadline (a run spent
#      browsing): the selector is signalled and restores the terminal
#   3. the same under _watchdog_run, the fresh-Mac path without coreutils.
#      On macOS the selector currently fails there before the kill ("Failed to
#      initialize input reader": _watchdog_run reattaches stdin as /dev/tty,
#      which crossterm's kqueue cannot poll), so this case pins only that the
#      early exit also leaves the terminal intact.
#
# Needs a real pty, so it cannot run inside the Claude Code sandbox.
#
# Usage: tests/test_app_picker_unanswered_pty.zsh [path-to-claude-tools-binary]
# Defaults to the committed binary for this platform.
set -uo pipefail

REPO="${0:A:h:h}"
case "$(uname -s)-$(uname -m)" in
    Darwin-arm64)  ASSET=claude-tools-darwin-arm64 ;;
    Darwin-x86_64) ASSET=claude-tools-darwin-x86_64 ;;
    Linux-x86_64)  ASSET=claude-tools-linux-x86_64 ;;
    Linux-aarch64) ASSET=claude-tools-linux-aarch64 ;;
    *) print -ru2 -- "FAIL: unsupported platform $(uname -s)-$(uname -m)"; exit 1 ;;
esac
BIN="${1:-$REPO/custom_bins/$ASSET}"
BIN="${BIN:A}"
[[ -x "$BIN" ]] || { print -ru2 -- "FAIL: $BIN is not executable"; exit 1 }

PASS=0 FAIL=0
pass() { (( PASS++ )); print -r -- "  ok   $1"; }
fail() { (( FAIL++ )); print -r -- "  FAIL $1"; [[ -n "${2:-}" ]] && print -r -- "       $2"; return 0; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/app-picker-pty.XXXXXX")" || { print -ru2 -- "FATAL: mktemp -d failed"; exit 1 }
trap 'rm -rf "${WORK:?}"' EXIT

# ─── Fixture: a two-row registry, a brew that knows nothing, the binary on PATH ──
DOT="$WORK/dot"; mkdir -p "$DOT/config" "$WORK/bin" "$WORK/apps"
cat > "$DOT/config/apps.conf" <<'EOF'
# method | id | category | tier | default | name | description | auth
cask|alpha|misc|1|true|Alpha|First|none
cask|beta|misc|2|false|Beta|Second|none
EOF
: > "$DOT/config/apps-excluded.conf"
print -r -- '#!/bin/sh' > "$WORK/bin/brew"; chmod +x "$WORK/bin/brew"
ln -s "$BIN" "$WORK/bin/claude-tools"
cp "$REPO/custom_bins/app-picker" "$WORK/bin/app-picker"

OUTER=4
# The command the pty runs: source the real helpers, run app-picker under the
# given invoker, then report the exit code and the terminal's line discipline.
driver() {  # driver <invoker words...>
    print -r -- "
        DOT_DIR='$REPO'
        source '$REPO/config.sh' >/dev/null 2>&1
        source '$REPO/scripts/shared/helpers.sh' >/dev/null 2>&1
        export PATH='$WORK/bin':\$PATH DOT_DIR='$DOT' APP_PICKER_APPS_DIR='$WORK/apps' \
            APP_PICKER_DEPS_DOC='$DOT/deps.md' NON_INTERACTIVE=false
        $* '$WORK/bin/app-picker' --conf '$DOT/config/apps.conf' --file '$DOT/config/Brewfile' --no-audit
        print -r -- \"PICKER_RC=\$?\"
        sleep 1
        print -r -- \"STTY<\$(stty -a)>STTY\"
        print -r -- PTY_DONE"
}

# check_case <label> <max seconds> <invoker words...>
check_case() {
    local label="$1" max="$2"; shift 2
    local json out exit_code elapsed
    json="$(python3 "$REPO/tests/pty_drive.py" --deadline 30 -- zsh -c "$(driver "$@")")"
    exit_code="$(print -r -- "$json" | python3 -c 'import json,sys; v=json.load(sys.stdin)["exit"]; print("none" if v is None else v)')"
    elapsed="$(print -r -- "$json" | python3 -c 'import json,sys; print(int(json.load(sys.stdin)["elapsed"]))')"
    out="$(print -r -- "$json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["output"])')"

    print -r -- "$label"
    if [[ "$exit_code" == 0 && "$out" == *PTY_DONE* ]] && (( elapsed <= max )); then
        pass "the installer carried on (${elapsed}s)"
    else
        fail "the installer did not carry on within ${max}s" "exit=$exit_code elapsed=${elapsed}s"
    fi

    local enter=$'\e[?1049h' leave=$'\e[?1049l'
    if [[ "$out" != *"$enter"* ]]; then
        fail "the menu never drew, so nothing below is meaningful"
        return
    fi
    local after_enter="${out##*$enter}"
    if [[ "$after_enter" == *"$leave"* ]]; then
        pass "the alternate screen was exited"
    else
        fail "the alternate screen was left on after the last menu draw"
    fi

    local stty_out="${${out#*STTY<}%%>STTY*}"
    if [[ "$out" != *"STTY<"* || -z "$stty_out" ]]; then
        fail "stty -a printed nothing after app-picker returned"
        return
    fi
    # The flags list prints `icanon`/`echo` when set and `-icanon`/`-echo` when cleared.
    if [[ " ${stty_out//$'\r'/ } " =~ '[[:space:]]-icanon[[:space:]]' ]]; then
        fail "canonical input is still off (raw mode leaked)"
    elif [[ " ${stty_out//$'\r'/ } " =~ '[[:space:]]icanon[[:space:]]' ]]; then
        pass "canonical input restored"
    else
        fail "stty -a output has no icanon flag at all" "${stty_out[1,200]}"
    fi
    if [[ " ${stty_out//$'\r'/ } " =~ '[[:space:]]-echo[[:space:]]' ]]; then
        fail "echo is still off (raw mode leaked)"
    elif [[ " ${stty_out//$'\r'/ } " =~ '[[:space:]]echo[[:space:]]' ]]; then
        pass "echo restored"
    else
        fail "stty -a output has no echo flag at all" "${stty_out[1,200]}"
    fi
}

print -r -- "app-picker unanswered under the install.sh deadline"
print -r -- "binary: $BIN"
print

# 1. What install.sh does: an idle deadline inside the selector, shorter than the outer kill.
check_case "1. install.sh path: selector idle deadline (2s) inside run_with_timeout ${OUTER}s" $(( OUTER + 4 )) \
    run_with_timeout "$OUTER" env APP_PICKER_IDLE_TIMEOUT=2
# 2. No idle deadline: the outer timeout(1) kill has to be survived.
if command -v timeout >/dev/null || command -v gtimeout >/dev/null; then
    check_case "2. outer kill via timeout(1), no idle deadline" $(( OUTER + 4 )) \
        run_with_timeout "$OUTER"
else
    print -r -- "2. skipped: no timeout(1) or gtimeout on this machine"
fi
# 3. The fresh-Mac fallback that sends TERM, then KILL a second later.
check_case "3. outer kill via _watchdog_run, no idle deadline" $(( OUTER + 5 )) \
    _watchdog_run "$OUTER"

print
print -r -- "PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
