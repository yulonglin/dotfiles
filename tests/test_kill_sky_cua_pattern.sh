#!/usr/bin/env bash
#
# Pins the pkill pattern in scripts/cleanup/setup_kill_sky_cua.sh.
#
# The watchdog kills ChatGPT's Computer Use helpers, which wedge every app on
# the machine by bulk-copying accessibility hierarchies. It matches by process
# name, so an upstream rename turns it into a silent no-op -- nothing logs, no
# error is raised, and the protection is simply gone. That happened on
# 2026-09-18 and was only noticed after a whole-desktop freeze two days later.
#
# The last test here is the guard against a repeat: it scans the installed
# ChatGPT.app for Computer Use helper paths and fails if the pattern misses
# any, or if it finds none at all (which means the naming moved somewhere this
# test no longer recognises, and both files need a human look).

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/cleanup/setup_kill_sky_cua.sh"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

if [[ ! -f "$SCRIPT" ]]; then
    echo "FATAL: $SCRIPT not found" >&2
    exit 1
fi

# Extract PATTERN exactly as the script defines it, rather than restating it.
PATTERN="$(sed -n 's/^PATTERN="\(.*\)"$/\1/p' "$SCRIPT")"

if [[ -z "$PATTERN" ]]; then
    echo "FATAL: could not extract PATTERN from $SCRIPT" >&2
    exit 1
fi
echo "# PATTERN = $PATTERN"

# matches <should_match: yes|no> <label> <command line>
matches() {
    local want="$1" label="$2" cmdline="$3"
    if printf '%s' "$cmdline" | grep -Eq "$PATTERN"; then
        if [[ "$want" == yes ]]; then pass "$label"; else fail "$label (matched, must not)"; fi
    else
        if [[ "$want" == no ]]; then pass "$label"; else fail "$label (did not match)"; fi
    fi
}

echo "## legacy helper names still covered"
matches yes "SkyComputerUseService" \
    "/Applications/ChatGPT.app/Contents/Resources/SkyComputerUseService"
matches yes "SkyComputerUseClient" \
    "/Users/x/.codex/computer-use/SkyComputerUseClient"
matches yes "CUALockScreenGuardian" \
    "/Applications/ChatGPT.app/Contents/Resources/CUALockScreenGuardian"

echo "## current (2026-09-18 onward) cua_node helpers covered"
matches yes "cua_node server.mjs" \
    "/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node ./server.mjs"
matches yes "cua_node node_repl" \
    "/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node_repl"
matches yes "codex computer-use install path" \
    "/Users/x/.codex/computer-use/bin/node ./server.mjs"

echo "## must NOT kill the host app or unrelated processes"
matches no "ChatGPT main binary" \
    "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT"
matches no "codex CLI beside the helpers" \
    "/Applications/ChatGPT.app/Contents/Resources/codex"
matches no "Codex framework helper" \
    "/Applications/ChatGPT.app/Contents/Frameworks/Codex Helper.app/Contents/MacOS/Codex Helper"
matches no "unrelated node process" \
    "/opt/homebrew/bin/node /Users/x/code/thing/server.mjs"
matches no "claude CLI" \
    "/Users/x/.local/bin/claude"

echo "## canary: the installed ChatGPT.app is still covered"
APP="/Applications/ChatGPT.app"
if [[ ! -d "$APP" ]]; then
    echo "skip - ChatGPT.app not installed; cannot verify pattern against a real bundle"
else
    # Executable files only: a directory or an asset never appears in a process
    # command line, so only these can be what pkill has to match.
    mapfile -t CANDIDATES < <(
        find "$APP/Contents" -maxdepth 5 -type f -perm -u+x 2>/dev/null \
            | grep -Ei '(cua|computer-?use)' \
            | grep -v '/Contents/MacOS/ChatGPT$' \
            | sort -u
    )
    if [[ ${#CANDIDATES[@]} -eq 0 ]]; then
        fail "found no Computer Use helper paths in $APP -- upstream likely renamed them again; review PATTERN and this test together"
    else
        missed=0
        for c in "${CANDIDATES[@]}"; do
            printf '%s' "$c" | grep -Eq "$PATTERN" || { echo "     unmatched: $c"; missed=$((missed + 1)); }
        done
        if [[ $missed -eq 0 ]]; then
            pass "all ${#CANDIDATES[@]} Computer Use path(s) in the installed bundle are matched"
        else
            fail "$missed of ${#CANDIDATES[@]} Computer Use path(s) in the installed bundle are NOT matched"
        fi
    fi
fi

echo
echo "passed: $PASS, failed: $FAIL"
[[ $FAIL -eq 0 ]]
