#!/usr/bin/env bash
# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
# `claude-tools select`: the contract the installers' component menu relies on.
# ═══════════════════════════════════════════════════════════════════════════════
# From 2026-06-21 to 2026-09-04 the binary parsed only --title, ignored the
# --items the shell passed, read its items from the terminal instead, and drew
# nothing while it waited for keystrokes. Every deadline-based check passed.
# Each case here pins one half of the contract that makes that impossible:
#   1. --items on a silent pty draws within 3 s; Enter prints the pre-checked names
#   2. an unknown flag exits 2 at once, drawing nothing
#   3. no --items with a terminal on stdin exits 2 at once, drawing nothing
#   4. --idle-timeout N with no keystroke exits 3 after N s, printing nothing
#   5. Esc exits 1
# Runs in the binary build workflow against the binary just built from source,
# so it can never lag the source the way a committed binary does.
#
# Usage: tests/test_claude_tools_select.sh <path-to-claude-tools-binary>
set -uo pipefail
DOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${1:?usage: test_claude_tools_select.sh <binary>}"
[[ -x "$BIN" ]] || { echo "FAIL: $BIN is not executable" >&2; exit 1; }
ALT_SCREEN='\x1b\[\?1049h'

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; [[ -n "${2:-}" ]] && printf '       %s\n' "$2"; }

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/select-test.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT
ITEMS="$SCRATCH/items.txt"
printf 'Base|tmux|Tmux config|true\nBase|vim|Vim config|false\n' > "$ITEMS"

# drive <deadline> <send-or-empty> -- cmd...  → J_EXIT J_AT J_ELAPSED J_OUT
drive() {
    local deadline="$1" send="$2"; shift 2
    [[ "$1" == "--" ]] && shift
    local -a extra=()
    [[ -n "$send" ]] && extra=(--send-on-expect "$send")
    local json
    # ${extra[@]+"${extra[@]}"}: bash 3.2 (macOS /bin/bash) counts an empty
    # array expansion as unbound under set -u; this spelling is safe on both.
    json="$(python3 "$DOT_DIR/tests/pty_drive.py" --deadline "$deadline" --expect "$ALT_SCREEN" ${extra[@]+"${extra[@]}"} -- "$@")"
    J_EXIT="$(printf '%s' "$json" | python3 -c 'import json,sys; v=json.load(sys.stdin)["exit"]; print("none" if v is None else v)')"
    J_AT="$(printf '%s' "$json" | python3 -c 'import json,sys; v=json.load(sys.stdin)["expect_at"]; print("none" if v is None else v)')"
    J_ELAPSED="$(printf '%s' "$json" | python3 -c 'import json,sys; print(int(json.load(sys.stdin)["elapsed"]))')"
    J_OUT="$(printf '%s' "$json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["output"])')"
}
drew_within() { [[ "$J_AT" != none ]] && python3 -c "import sys; sys.exit(0 if $J_AT <= $1 else 1)"; }

echo "claude-tools select — the menu contract"
echo

# 1. draws, Enter confirms the pre-checked set (tmux yes, vim no)
drive 8 '\r' -- "$BIN" select --title test --items "$ITEMS"
if drew_within 3 && [[ "$J_EXIT" == 0 && "$J_OUT" == *tmux* && "$J_OUT" != *$'\r\nvim'* ]]; then
    pass "--items on a silent pty draws (at ${J_AT}s); Enter prints the pre-checked names"
else
    fail "--items must draw and Enter must print the pre-checked names" "drew_at=$J_AT exit=$J_EXIT"
fi

# 2. unknown flag: loud, instant, nothing drawn
drive 5 '' -- "$BIN" select --items "$ITEMS" --bogus
if [[ "$J_EXIT" == 2 && "$J_AT" == none && "$J_ELAPSED" -le 2 && "$J_OUT" == *"unknown argument"* ]]; then
    pass "an unknown flag exits 2 at once with a message, nothing drawn"
else
    fail "an unknown flag must exit 2 at once (this is how --items went missing unnoticed)" "exit=$J_EXIT drew_at=$J_AT elapsed=${J_ELAPSED}s"
fi

# 3. no --items with a terminal on stdin: refuse, never wait
drive 5 '' -- "$BIN" select --title test
if [[ "$J_EXIT" == 2 && "$J_AT" == none && "$J_ELAPSED" -le 2 && "$J_OUT" == *"stdin is a terminal"* ]]; then
    pass "no --items on a terminal exits 2 at once instead of reading the keyboard"
else
    fail "no --items on a terminal must be refused, not waited on (the 2026-09-04 stall)" "exit=$J_EXIT drew_at=$J_AT elapsed=${J_ELAPSED}s"
fi

# 4. idle deadline: drawn, then exit 3 with nothing on stdout
drive 10 '' -- "$BIN" select --items "$ITEMS" --idle-timeout 2
if drew_within 3 && [[ "$J_EXIT" == 3 && "$J_ELAPSED" -ge 2 && "$J_ELAPSED" -le 5 && "$J_OUT" != *$'\r\ntmux'* ]]; then
    pass "--idle-timeout 2 draws, then exits 3 after ${J_ELAPSED}s with no selection"
else
    fail "--idle-timeout must exit 3 shortly after the deadline, printing no selection" "exit=$J_EXIT drew_at=$J_AT elapsed=${J_ELAPSED}s"
fi

# 5. Esc cancels
drive 8 '\x1b' -- "$BIN" select --items "$ITEMS"
if drew_within 3 && [[ "$J_EXIT" == 1 ]]; then
    pass "Esc exits 1"
else
    fail "Esc must exit 1" "exit=$J_EXIT drew_at=$J_AT"
fi

echo
echo "passed: $PASS   failed: $FAIL"
(( FAIL == 0 ))
