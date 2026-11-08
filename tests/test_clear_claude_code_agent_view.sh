#!/usr/bin/env bash
#
# Pins how custom_bins/clear-claude-code classifies the Claude Code agent view.
#
# The agent view (`claude agents`, or a bare `claude` when defaultToAgentsView is
# set) waits for keys at 0% CPU and holds no transcript, so the foreground rule
# (>=1h old, <1% CPU) read it as abandoned and the daily 17:00 launchd run killed
# it: 29 logged kills on 17 days between 2026-10-17 and 2026-11-07, 28 of them
# views. Sessions register ~/.claude/sessions/<pid>.json; the view does not.
#
# Each case sources the script in a subshell with the process probes stubbed,
# so the classifier runs on a fixed picture of one process.

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/custom_bins/clear-claude-code"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "ok   - $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL - $1"; }

# Sourcing a script without the guard runs its main body, which kills processes.
if ! grep -q '^\[\[ "\${BASH_SOURCE\[0\]}" != "\$0" \]\] && return 0' "$SCRIPT"; then
    echo "FATAL: $SCRIPT has no source guard; refusing to source it" >&2
    exit 1
fi

TMP_HOME="$(mktemp -d "${TMPDIR:-/tmp}/clear-claude-code-test.XXXXXX")" || exit 1
trap 'rm -rf "$TMP_HOME"' EXIT
mkdir -p "$TMP_HOME/.claude/sessions"

FAKE_PID=4242

# classify <tty> <stat> [session-file: yes|no]
classify() {
    local tty="$1" stat="$2" session="${3:-no}"
    rm -f "$TMP_HOME/.claude/sessions/$FAKE_PID.json"
    [[ "$session" == yes ]] && echo '{}' >"$TMP_HOME/.claude/sessions/$FAKE_PID.json"
    (
        HOME="$TMP_HOME"
        set --  # the script parses "$@" as its own flags
        # shellcheck source=/dev/null
        source "$SCRIPT"
        set +e
        is_bg_job_process() { return 1; }
        is_in_tmux() { return 1; }
        has_active_descendants() { return 1; }
        is_orphaned() { return 1; }
        is_process_old() { return 0; }
        last_activity_age() { :; }
        get_process_tty() { echo "$tty"; }
        ps_field() {
            case "$2" in
                stat) echo "$stat" ;;
                %cpu) echo "0.0" ;;
                *) echo "" ;;
            esac
        }
        get_process_status "$FAKE_PID"
    )
}

# /dev/null stands in for a live terminal device: the ghost check needs /dev/<tty>.
got=$(classify null "S+" no)
[[ "$got" == AGENT_VIEW ]] && pass "idle foreground view with no session file is AGENT_VIEW" \
    || fail "idle foreground view classified $got, want AGENT_VIEW"

got=$(classify null "S" no)
[[ "$got" == AGENT_VIEW ]] && pass "backgrounded view on a live terminal is AGENT_VIEW" \
    || fail "backgrounded view classified $got, want AGENT_VIEW"

got=$(classify null "S+" yes)
[[ "$got" == IDLE ]] && pass "abandoned foreground session with a session file is still IDLE" \
    || fail "abandoned foreground session classified $got, want IDLE"

# Rule 2 (old, no CPU) fires before the terminal checks, so this is IDLE; the
# point is that a terminal-less process without a session file is not spared.
got=$(classify "" "S" no)
[[ "$got" == IDLE ]] && pass "old process with no terminal is still IDLE, not spared as a view" \
    || fail "old no-terminal process classified $got, want IDLE"

got=$(classify s999999 "S+" no)
[[ "$got" == GHOST ]] && pass "view whose terminal device is gone is still GHOST" \
    || fail "view on a vanished terminal classified $got, want GHOST"

# The transcript fallback must not filter on /dev/null's mtime, which macOS
# bumps on every write, so `find -newer /dev/null` matched nothing.
if grep -qE -- 'find .*-newer /dev/null' "$SCRIPT"; then
    fail "last_activity_age still filters with -newer /dev/null"
else
    pass "last_activity_age does not filter with -newer /dev/null"
fi

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
