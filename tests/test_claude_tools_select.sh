#!/usr/bin/env bash
# shellcheck shell=bash
# ═══════════════════════════════════════════════════════════════════════════════
# `claude-tools select`: the contract the installers' component menu relies on.
# ═══════════════════════════════════════════════════════════════════════════════
# Since 2026-06-21 the binary has parsed only --title, ignored the --items that
# scripts/shared/helpers.sh passes, and read its items from the terminal
# instead — drawing nothing while it waits for keystrokes nobody types. Every
# deadline-based check stayed green throughout, because the menu's deadline
# (run_with_timeout "${DOTFILES_MENU_TIMEOUT:-60}", helpers.sh) does fire and
# the run does continue. Each case here pins one half of the contract that
# makes the silent failure impossible:
#   1. --items on a silent pty draws within 3 s; Enter prints the pre-checked names
#   2. an unknown flag exits 2 at once, drawing nothing
#   3. no --items with a terminal on stdin exits 2 at once, drawing nothing
#   4. Esc exits 1
#
# Not pinned here, deliberately: an in-binary --idle-timeout. The menu's
# deadline lives in the shell (helpers.sh), tests/test_no_stall.sh already
# asserts it, and test_deadline_holds_without_coreutils covers the macOS path
# where timeout(1) is absent. A flag no caller passes is not a contract.
#
# Case 2 looks pedantic and is not: silently ignoring an unrecognised argument
# is precisely how --items went missing for two and a half months while the
# shell kept passing it.
#
# Usage: tests/test_claude_tools_select.sh [path-to-claude-tools-binary]
# Defaults to the committed binary for this platform.
set -uo pipefail
DOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
case "$(uname -s)-$(uname -m)" in
    Darwin-arm64)  ASSET=claude-tools-darwin-arm64 ;;
    Darwin-x86_64) ASSET=claude-tools-darwin-x86_64 ;;
    Linux-x86_64)  ASSET=claude-tools-linux-x86_64 ;;
    Linux-aarch64) ASSET=claude-tools-linux-aarch64 ;;
    *) echo "FAIL: unsupported platform $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac
BIN="${1:-$DOT_DIR/custom_bins/$ASSET}"
[[ -x "$BIN" ]] || { echo "FAIL: $BIN is not executable" >&2; exit 1; }
ALT_SCREEN='\x1b\[\?1049h'

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; [[ -n "${2:-}" ]] && printf '       %s\n' "$2"; return 0; }

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
echo "binary: $BIN"
echo

ITEMS_HONOURED=true

# 1. draws, Enter confirms the pre-checked set (tmux yes, vim no)
drive 8 '\r' -- "$BIN" select --title test --items "$ITEMS"
if drew_within 3 && [[ "$J_EXIT" == 0 && "$J_OUT" == *tmux* && "$J_OUT" != *$'\r\nvim'* ]]; then
    pass "--items on a silent pty draws (at ${J_AT}s); Enter prints the pre-checked names"
else
    ITEMS_HONOURED=false
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
    fail "no --items on a terminal must be refused, not waited on (the menu stall)" "exit=$J_EXIT drew_at=$J_AT elapsed=${J_ELAPSED}s"
fi

# 4. Esc cancels
drive 8 '\x1b' -- "$BIN" select --items "$ITEMS"
if drew_within 3 && [[ "$J_EXIT" == 1 ]]; then
    pass "Esc exits 1"
else
    fail "Esc must exit 1" "exit=$J_EXIT drew_at=$J_AT"
fi

echo
echo "passed: $PASS   failed: $FAIL"
if [[ "$ITEMS_HONOURED" == false ]]; then
    cat <<'DIAGNOSIS'

Diagnosis: this binary does not honour --items. It reads its items from stdin,
so on a terminal it blocks with nothing drawn — the failure the installers show
today, and the reason every case above is red rather than just case 1.
Reproduce without this suite:

  printf 'A|x|d|true\n' > /tmp/i.txt
  claude-tools select --title t --items /tmp/i.txt   # draws nothing, waits
  printf 'A|x|d|true\n' | claude-tools select --title t   # draws immediately

The fix belongs in tools/claude-tools/src/select/mod.rs (read from --items when
given; refuse a terminal stdin; reject unknown arguments), followed by a
rebuild of the committed custom_bins/claude-tools-* assets.
DIAGNOSIS
fi
(( FAIL == 0 ))
