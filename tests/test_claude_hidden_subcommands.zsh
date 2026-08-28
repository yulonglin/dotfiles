# shellcheck shell=bash
# Hidden subcommands must not get session flags injected ahead of them.
#
# The claude() wrapper decides "is this a session or a subcommand?" by scraping
# `claude --help`. Some real subcommands are HIDDEN — `daemon` appears nowhere
# in that help output — so the scrape misses them, the wrapper treats them as a
# session prompt, and prepends --settings=... The top-level parser then rejects
# the subcommand's own flags.
#
# Measured 2026-08-28: `claude daemon stop --any --keep-workers` failed with
# "error: unknown option '--any'" purely because --settings was injected before
# `daemon`, even though the binary implements both flags
# (case "stop": ... De(d,["--keep-workers","--any"])).
#
# Run from the repo root: zsh tests/test_claude_hidden_subcommands.zsh
set -u
root=${0:a:h:h}
cd "$root" || exit 1

scratch="$root/tmp/.hidden-subcmd-$$"
fakebin="$scratch/bin"
outfile="$scratch/out"
mkdir -p "$fakebin"
trap 'rm -rf "$scratch"' EXIT

# The wrapper calls `claude --help` / `--version` itself to build its
# subcommand list, and on PATH that reaches THIS fake. It must answer those two
# realistically or the list comes out empty and every case looks like a
# session — which would make the assertions below pass or fail for the wrong
# reason. Everything else just echoes argv.
{
  echo '#!/bin/sh'
  echo 'case "$1" in'
  echo '  --version) echo "2.1.250 (Claude Code)"; exit 0 ;;'
  echo '  --help) printf "  agents [options]   Manage background agents\\n  doctor   Check health\\n  mcp   Configure MCP\\n"; exit 0 ;;'
  echo 'esac'
  echo 'printf "ARGV:"; for a in "$@"; do printf " [%s]" "$a"; done; printf "\n"'
} > "$fakebin/claude"
chmod +x "$fakebin/claude"
export PATH="$fakebin:$PATH"

activate_venv() { :; }
unset DOTFILES_TELEGRAM_BOT_SECRET 2>/dev/null || true
unset CLAUDE_CODE_TASK_LIST_ID 2>/dev/null || true

source config/aliases/claude.sh || { echo "FAIL: could not source claude.sh"; exit 1; }
activate_venv() { :; }

pass=0; fail=0
refute() { if [[ "$3" == *"$2"* ]]; then echo "FAIL: $1 — [$2] should be absent from [$3]"; ((fail++))
  else echo "PASS: $1"; ((pass++)); fi }
check() { if [[ "$3" == *"$2"* ]]; then echo "PASS: $1"; ((pass++))
  else echo "FAIL: $1 — expected [$2] in [$3]"; ((fail++)); fi }

# `daemon` is hidden from --help but is a real subcommand: no --settings, and
# its own flags must survive to the binary untouched.
claude daemon stop --any --keep-workers >"$outfile" 2>&1
got=$(cat "$outfile")
refute "no --settings injected before a hidden subcommand" "--settings" "$got"
check "hidden subcommand reaches the binary first" "ARGV: [daemon] [stop]" "$got"
check "its own flags survive" "[--any] [--keep-workers]" "$got"

# A visible subcommand must keep behaving the same way.
claude doctor >"$outfile" 2>&1
refute "no --settings injected before a visible subcommand" "--settings" "$(cat "$outfile")"

echo "---"
echo "pass=$pass fail=$fail"
(( fail == 0 ))
