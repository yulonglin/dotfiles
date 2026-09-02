#!/usr/bin/env zsh
# shellcheck shell=bash
# Tests that the claude() wrapper hides finished sessions before `claude agents`.
#
# Why this exists: the agents view is compiled into the CLI with no hide
# toggle, so the wrapper archives done/failed/stopped job dirs out of
# ~/.claude/jobs right before the view mounts. This drives the REAL wrapper
# with a stubbed `claude` and a stubbed `claude-jobs-reap` on PATH, reading the
# argv each actually received. Same harness as test_claude_wrapper_rc.sh: fake
# HOME, non-git temp dir, no tmux anywhere.

emulate -L zsh 2>/dev/null || true
setopt no_nomatch 2>/dev/null || true

SCRIPT_DIR="${0:A:h}"
WRAPPER="${1:-$SCRIPT_DIR/../config/aliases/claude.sh}"

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n     %s\n' "$1" "$2"; fail=$((fail + 1)); }

printf 'claude() wrapper: finished sessions are archived before the agents view\n'

d=""
for root in /tmp/claude /tmp "${TMPDIR:-}"; do
  [[ -n "$root" ]] || continue
  mkdir -p "$root" 2>/dev/null || continue
  d=$(mktemp -d "$root/claude-wrapper-agents-test.XXXXXX" 2>/dev/null) && [[ -d "$d" ]] && break
  d=""
done
if [[ -z "$d" ]]; then
  printf '  SKIP (no writable temp directory)\n'
  exit 0
fi

mkdir -p "$d/bin"

{
  printf '#!/usr/bin/env bash\n'
  # shellcheck disable=SC2016
  printf 'case "$1" in\n'
  printf '  --version) echo "9.9.9 (test stub)"; exit 0 ;;\n'
  printf '  --help)    printf "  doctor Check health\\n  daemon Run daemon\\n  agents Manage agents\\n  remote-control|rc Control sessions\\n"; exit 0 ;;\n'
  printf 'esac\n'
  printf 'printf "ARG:%%s\\n" "$@" >"%s/argv.txt"\n' "$d"
} >"$d/bin/claude"
chmod +x "$d/bin/claude"

# The reaper stub records its argv and exits with whatever REAP_EXIT says, so
# the "reaper failure never blocks the launch" case is under test control.
{
  printf '#!/usr/bin/env bash\n'
  printf 'printf "REAP:%%s\\n" "$@" >"%s/reap.txt"\n' "$d"
  # shellcheck disable=SC2016
  printf 'exit "${REAP_EXIT:-0}"\n'
} >"$d/bin/claude-jobs-reap"
chmod +x "$d/bin/claude-jobs-reap"

export PATH="$d/bin:$PATH"
export XDG_CACHE_HOME="$d/cache"
unset DOTFILES_TELEGRAM_BOT_SECRET TELEGRAM_STATE_DIR CLAUDE_RC_OVERRIDE \
      CLAUDE_AGENTS_HIDE_FINISHED CLAUDE_AGENTS_FINISHED_GRACE_HOURS REAP_EXIT

export HOME="$d/home"
mkdir -p "$HOME/.claude"

activate_venv() { :; }

cd "$d" || exit 1
# shellcheck source=/dev/null
source "$WRAPPER"

run_case() {
  : >"$d/argv.txt"
  : >"$d/reap.txt"
  claude "$@" >/dev/null 2>&1 || true
  got=$(cat "$d/argv.txt" 2>/dev/null || echo "")
  reap=$(cat "$d/reap.txt" 2>/dev/null || echo "")
}

# --- `claude agents` runs the reaper with the finished filter ------------------

run_case agents
case "$reap" in
  *"REAP:--finished"*"REAP:--hours"$'\n'"REAP:0"$'\n'*"REAP:--archive-to"$'\n'"REAP:$HOME/.claude/jobs-archive"*)
    ok "agents archives finished jobs at zero grace" ;;
  *) bad "agents archives finished jobs at zero grace" "reaper argv was: ${reap:-<not called>}" ;;
esac
case "$reap" in
  *"REAP:--quiet"*) ok "agents runs the reaper quietly" ;;
  *) bad "agents runs the reaper quietly" "reaper argv was: ${reap:-<not called>}" ;;
esac
case "$got" in
  *"ARG:agents"*) ok "agents view still launches" ;;
  *) bad "agents view still launches" "argv was: ${got:-<empty>}" ;;
esac

# --- the grace knob passes through ----------------------------------------------

: >"$d/reap.txt"
CLAUDE_AGENTS_FINISHED_GRACE_HOURS=6 claude agents >/dev/null 2>&1 || true
reap=$(cat "$d/reap.txt" 2>/dev/null || echo "")
case "$reap" in
  *"REAP:--hours"$'\n'"REAP:6"$'\n'*) ok "CLAUDE_AGENTS_FINISHED_GRACE_HOURS reaches the reaper" ;;
  *) bad "CLAUDE_AGENTS_FINISHED_GRACE_HOURS reaches the reaper" "reaper argv was: ${reap:-<not called>}" ;;
esac

# --- a reaper failure never blocks the view -------------------------------------

: >"$d/argv.txt"
REAP_EXIT=1 claude agents >/dev/null 2>&1 || true
got=$(cat "$d/argv.txt" 2>/dev/null || echo "")
case "$got" in
  *"ARG:agents"*) ok "a failing reaper still launches the view" ;;
  *) bad "a failing reaper still launches the view" "argv was: ${got:-<empty>}" ;;
esac

# --- and NOT for anything else --------------------------------------------------

run_case agents --help
if [[ -z "$reap" ]]; then
  ok "agents --help does not reap"
else
  bad "agents --help does not reap" "reaper argv was: $reap"
fi

run_case
if [[ -z "$reap" ]]; then
  ok "a plain session does not reap"
else
  bad "a plain session does not reap" "reaper argv was: $reap"
fi

run_case -p 'hello'
if [[ -z "$reap" ]]; then
  ok "print mode does not reap"
else
  bad "print mode does not reap" "reaper argv was: $reap"
fi

run_case doctor
if [[ -z "$reap" ]]; then
  ok "another subcommand does not reap"
else
  bad "another subcommand does not reap" "reaper argv was: $reap"
fi

# --- documented opt-out ---------------------------------------------------------

: >"$d/reap.txt"
CLAUDE_AGENTS_HIDE_FINISHED=0 claude agents >/dev/null 2>&1 || true
reap=$(cat "$d/reap.txt" 2>/dev/null || echo "")
if [[ -z "$reap" ]]; then
  ok "CLAUDE_AGENTS_HIDE_FINISHED=0 opts out"
else
  bad "CLAUDE_AGENTS_HIDE_FINISHED=0 opts out" "reaper argv was: $reap"
fi

# --- no reaper on PATH: the view launches as before -----------------------------

rm -f "$d/bin/claude-jobs-reap"
run_case agents
case "$got" in
  *"ARG:agents"*) ok "missing reaper is skipped silently" ;;
  *) bad "missing reaper is skipped silently" "argv was: ${got:-<empty>}" ;;
esac

cd / || true
rm -rf "$d"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
