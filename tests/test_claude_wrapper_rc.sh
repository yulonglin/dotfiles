#!/usr/bin/env zsh
# shellcheck shell=bash
# Tests that the claude() wrapper adds the Remote Control settings override.
#
# Why this exists: the model-router plugin sets a global ANTHROPIC_BASE_URL
# redirect, and Claude Code refuses Remote Control on any base URL other than
# api.anthropic.com (_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL is explicitly
# exempted from RC). A CLI --settings file outranks the user-settings env
# block, so the wrapper prepends --settings=$HOME/.claude/rc-direct-settings.json
# to interactive sessions — and must NOT add it for print mode, subcommands,
# a caller-supplied --settings, a GPT main model (which needs the router),
# CLAUDE_RC_OVERRIDE=0, or a machine where the file is not deployed.
#
# This drives the REAL wrapper with a stubbed `claude` on PATH and a fake HOME,
# so it reads the argv actually handed to the binary rather than asserting on a
# printed string, and the deployed-file guard is under test control. No tmux is
# involved anywhere — nothing here can touch a live server.

emulate -L zsh 2>/dev/null || true
setopt no_nomatch 2>/dev/null || true

SCRIPT_DIR="${0:A:h}"
WRAPPER="${1:-$SCRIPT_DIR/../config/aliases/claude.sh}"

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n     %s\n' "$1" "$2"; fail=$((fail + 1)); }

printf 'claude() wrapper: Remote Control settings override\n'

# A NON-git temp dir, so the wrapper's auto-cd-to-git-root does not relocate us.
d=""
for root in /tmp/claude /tmp "${TMPDIR:-}"; do
  [[ -n "$root" ]] || continue
  mkdir -p "$root" 2>/dev/null || continue
  # Full template, not `-p`: that flag is GNU-only and this must run on macOS.
  d=$(mktemp -d "$root/claude-wrapper-rc-test.XXXXXX" 2>/dev/null) && [[ -d "$d" ]] && break
  d=""
done
if [[ -z "$d" ]]; then
  printf '  SKIP (no writable temp directory)\n'
  exit 0
fi

mkdir -p "$d/bin"

# The stub answers --version/--help (the wrapper probes those to build its
# subcommand cache) and records argv for everything else.
{
  printf '#!/usr/bin/env bash\n'
  # shellcheck disable=SC2016  # writing a script; expansion happens when it runs
  printf 'case "$1" in\n'
  printf '  --version) echo "9.9.9 (test stub)"; exit 0 ;;\n'
  # A realistic subcommand list, so the "subcommand gets no override" assertion
  # below can actually fail — an empty cache would classify nothing.
  printf '  --help)    printf "  doctor Check health\\n  daemon Run daemon\\n  remote-control|rc Control sessions\\n  update Update\\n  mcp Manage\\n"; exit 0 ;;\n'
  printf 'esac\n'
  printf 'printf "ARG:%%s\\n" "$@" >"%s/argv.txt"\n' "$d"
} >"$d/bin/claude"
chmod +x "$d/bin/claude"

export PATH="$d/bin:$PATH"
export XDG_CACHE_HOME="$d/cache"
# The wrapper reads these; a leaked value from the invoking environment would
# change which branches run.
unset DOTFILES_TELEGRAM_BOT_SECRET TELEGRAM_STATE_DIR CLAUDE_RC_OVERRIDE

# Fake HOME with the override file deployed, so [[ -f ]] in the wrapper is
# under test control rather than reflecting this machine's ~/.claude.
export HOME="$d/home"
mkdir -p "$HOME/.claude"
printf '{"env":{}}' >"$HOME/.claude/rc-direct-settings.json"
RC_SETTINGS="$HOME/.claude/rc-direct-settings.json"

activate_venv() { :; }   # the wrapper calls this; keep the output clean

cd "$d" || exit 1
# shellcheck source=/dev/null
source "$WRAPPER"

run_case() {
  : >"$d/argv.txt"
  claude "$@" >/dev/null 2>&1 || true
  got=$(cat "$d/argv.txt" 2>/dev/null || echo "")
}

# --- plain interactive launch gets the override -------------------------------

run_case
case "$got" in
  *"ARG:--settings=$RC_SETTINGS"*) ok "interactive launch gets the override" ;;
  *) bad "interactive launch gets the override" "argv was: ${got:-<empty>}" ;;
esac

# Prepended, not appended: with a caller-supplied `--` terminator the flag must
# land BEFORE it, or it stops being an option and becomes prompt text — the
# same trap the appended --channels fell into.
run_case --dangerously-skip-permissions -- 'seed text'
if [[ "$got" == *"ARG:--settings=$RC_SETTINGS"*"ARG:--"$'\n'* ]]; then
  ok "override lands before the -- terminator"
else
  bad "override lands before the -- terminator" "argv was: ${got:-<empty>}"
fi
case "$got" in
  *"ARG:seed text"*) ok "seed prompt still arrives intact" ;;
  *) bad "seed prompt still arrives intact" "argv was: ${got:-<empty>}" ;;
esac

# --- print mode: no session, no Remote Control, no override -------------------

run_case -p 'say hi'
case "$got" in
  *"ARG:--settings="*) bad "-p gets no override" "argv was: $got" ;;
  *) ok "-p gets no override" ;;
esac

run_case --print 'say hi'
case "$got" in
  *"ARG:--settings="*) bad "--print gets no override" "argv was: $got" ;;
  *) ok "--print gets no override" ;;
esac

# --- a GPT main model needs the router, so the redirect must survive ----------

run_case --model gpt-5.6-sol
case "$got" in
  *"ARG:--settings="*) bad "--model gpt-5.6-sol gets no override" "argv was: $got" ;;
  *) ok "--model gpt-5.6-sol gets no override" ;;
esac

run_case --model=gpt-5.6-luna
case "$got" in
  *"ARG:--settings="*) bad "--model=gpt-5.6-luna gets no override" "argv was: $got" ;;
  *) ok "--model=gpt-5.6-luna gets no override" ;;
esac

# A Claude main model has no router dependency: the override must stay.
run_case --model opus
case "$got" in
  *"ARG:--settings=$RC_SETTINGS"*) ok "--model opus keeps the override" ;;
  *) bad "--model opus keeps the override" "argv was: ${got:-<empty>}" ;;
esac

# --- an explicit --settings wins; the wrapper must not stack a second one -----

run_case --settings /tmp/user-settings.json
case "$got" in
  *"ARG:--settings=$RC_SETTINGS"*) bad "explicit --settings suppresses the override" "argv was: $got" ;;
  *) ok "explicit --settings suppresses the override" ;;
esac
case "$got" in
  *"ARG:/tmp/user-settings.json"*) ok "the caller's settings file survives" ;;
  *) bad "the caller's settings file survives" "argv was: ${got:-<empty>}" ;;
esac

run_case --settings=/tmp/user-settings.json
case "$got" in
  *"ARG:--settings=$RC_SETTINGS"*) bad "explicit --settings= suppresses the override" "argv was: $got" ;;
  *) ok "explicit --settings= suppresses the override" ;;
esac

# --- subcommands are not sessions ---------------------------------------------

run_case doctor
case "$got" in
  *"ARG:--settings="*) bad "a subcommand gets no override" "argv was: $got" ;;
  *) ok "a subcommand gets no override" ;;
esac

run_case daemon
case "$got" in
  *"ARG:--settings="*) bad "daemon gets no override" "argv was: $got" ;;
  *) ok "daemon gets no override" ;;
esac

# --- except remote-control itself: that launcher cannot work without it -------

run_case remote-control
case "$got" in
  *"ARG:--settings=$RC_SETTINGS"*) ok "remote-control subcommand gets the override" ;;
  *) bad "remote-control subcommand gets the override" "argv was: ${got:-<empty>}" ;;
esac

run_case rc
case "$got" in
  *"ARG:--settings=$RC_SETTINGS"*) ok "rc alias gets the override" ;;
  *) bad "rc alias gets the override" "argv was: ${got:-<empty>}" ;;
esac

# The help/version suppress (which protects the wrapper's recursive --version
# probe) must not reach the RC subcommand: `claude remote-control --help` on a
# redirected base URL printed the base-URL error instead of RC usage.
run_case remote-control --help
case "$got" in
  *"ARG:--settings=$RC_SETTINGS"*) ok "remote-control --help keeps the override" ;;
  *) bad "remote-control --help keeps the override" "argv was: ${got:-<empty>}" ;;
esac

# Bare `claude --help` has no subcommand, so the suppress still applies there.
run_case --help
case "$got" in
  *"ARG:--settings="*) bad "bare --help gets no override" "argv was: $got" ;;
  *) ok "bare --help gets no override" ;;
esac

# --- documented opt-out -------------------------------------------------------

: >"$d/argv.txt"
CLAUDE_RC_OVERRIDE=0 claude >/dev/null 2>&1 || true
got=$(cat "$d/argv.txt" 2>/dev/null || echo "")
case "$got" in
  *"ARG:--settings="*) bad "CLAUDE_RC_OVERRIDE=0 opts out" "argv was: $got" ;;
  *) ok "CLAUDE_RC_OVERRIDE=0 opts out" ;;
esac

# --- a machine without the deployed file must behave exactly as before --------

rm -f "$RC_SETTINGS"
run_case
case "$got" in
  *"ARG:--settings="*) bad "missing file is skipped silently" "argv was: $got" ;;
  *) ok "missing file is skipped silently" ;;
esac

cd / || true
rm -rf "$d"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
