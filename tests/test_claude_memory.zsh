#!/usr/bin/env zsh
# shellcheck shell=bash
# Tests the global memory toggle: custom_bins/claude-memory renders the right
# claudeMdExcludes file per mode, and the claude() wrapper passes it as
# --settings only where that cannot clobber anything.
#
# Why the wrapper rules matter: Claude Code honours only the LAST --settings
# flag (measured 2.1.304), so a second one would silently drop the caller's
# file; and the wrapper probes `claude --version` recursively, so injecting
# ahead of --version would change what that probe sees.
#
# Real wrapper + real script, stubbed `claude` on PATH, fake HOME whose
# ~/.claude is a symlink as deploy.sh makes it.

emulate -L zsh 2>/dev/null || true
setopt no_nomatch 2>/dev/null || true

SCRIPT_DIR="${0:A:h}"
REPO="${SCRIPT_DIR:h}"
WRAPPER="$REPO/config/aliases/claude.sh"
MEM="$REPO/custom_bins/claude-memory"

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n     %s\n' "$1" "$2"; fail=$((fail + 1)); }

printf 'claude-memory: global memory toggle\n'

if ! command -v jq >/dev/null; then
  printf '  SKIP (jq not installed)\n'
  exit 0
fi

d=$(mktemp -d "${TMPDIR:-/tmp}/claude-memory-test.XXXXXX") || exit 1
trap 'rm -rf "$d"' EXIT

mkdir -p "$d/bin" "$d/dot/claude/rules" "$d/home"
printf '# global\n' >"$d/dot/claude/CLAUDE.md"
printf 'rule one\n' >"$d/dot/claude/rules/one.md"
printf '{"claudeMdExcludes":["**/node_modules/**"]}' >"$d/dot/claude/settings.json"
ln -s "$d/dot/claude" "$d/home/.claude"
real_claude=$(cd "$d/dot/claude" && pwd -P)

{
  printf '#!/usr/bin/env bash\n'
  # shellcheck disable=SC2016
  printf 'case "$1" in\n'
  printf '  --version) echo "9.9.9 (test stub)"; exit 0 ;;\n'
  printf '  --help)    printf "  doctor Check health\\n  mcp Manage\\n"; exit 0 ;;\n'
  printf 'esac\n'
  printf 'printf "ARG:%%s\\n" "$@" >"%s/argv.txt"\n' "$d"
} >"$d/bin/claude"
ln -s "$MEM" "$d/bin/claude-memory"
chmod +x "$d/bin/claude"

export PATH="$d/bin:$PATH"
export HOME="$d/home"
export XDG_CONFIG_HOME="$d/config"
export XDG_CACHE_HOME="$d/cache"
unset CLAUDE_MEMORY CLAUDE_RC_OVERRIDE DOTFILES_TELEGRAM_BOT_SECRET TELEGRAM_STATE_DIR

# --- the script ---------------------------------------------------------------

[[ -z "$(claude-memory settings-path)" ]] && ok "full (default) has no settings file" \
  || bad "full (default) has no settings file" "got a path"

f=$(claude-memory settings-path minimal)
ex=$(jq -c '.claudeMdExcludes' "$f")
[[ "$ex" == *"\"$HOME/.claude/rules/**\""* && "$ex" == *"\"$real_claude/rules/**\""* ]] \
  && ok "minimal excludes rules by both spellings" || bad "minimal excludes rules by both spellings" "$ex"
[[ "$ex" != *"CLAUDE.md"* ]] && ok "minimal keeps the global CLAUDE.md" || bad "minimal keeps the global CLAUDE.md" "$ex"
[[ "$ex" == *'"**/node_modules/**"'* ]] && ok "the user file's own excludes are carried" \
  || bad "the user file's own excludes are carried" "$ex"

f=$(claude-memory settings-path none)
ex=$(jq -c '.claudeMdExcludes' "$f")
[[ "$ex" == *"\"$HOME/.claude/CLAUDE.md\""* && "$(jq '.autoMemoryEnabled' "$f")" == false ]] \
  && ok "none excludes the global CLAUDE.md and auto memory" || bad "none excludes the global CLAUDE.md and auto memory" "$(cat "$f")"

claude-memory bogus >/dev/null 2>&1 && bad "an unknown mode is refused" "exit 0" || ok "an unknown mode is refused"

claude-memory stats | grep -q 'rules .*one.md' && ok "stats lists the rule files" \
  || bad "stats lists the rule files" "$(claude-memory stats 2>&1)"

# --- the wrapper --------------------------------------------------------------

activate_venv() { :; }
cd "$d" || exit 1
# shellcheck source=/dev/null
source "$WRAPPER"

run_case() {
  : >"$d/argv.txt"
  claude "$@" >/dev/null 2>&1 || true
  got=$(cat "$d/argv.txt" 2>/dev/null || echo "")
}
NONE_SETTINGS="$XDG_CONFIG_HOME/claude-memory/none.json"

claude-memory full >/dev/null
run_case
[[ "$got" != *"ARG:--settings"* ]] && ok "full mode adds nothing" || bad "full mode adds nothing" "$got"

claude-memory none >/dev/null
run_case
[[ "$got" == "ARG:--settings=$NONE_SETTINGS"* ]] && ok "none mode prepends its settings file" \
  || bad "none mode prepends its settings file" "${got:-<empty>}"

run_case -p 'say hi'
[[ "$got" == *"ARG:--settings=$NONE_SETTINGS"* ]] && ok "print mode gets it too" || bad "print mode gets it too" "${got:-<empty>}"

run_case --settings /tmp/mine.json
[[ "$got" != *"$NONE_SETTINGS"* && "$got" == *"ARG:/tmp/mine.json"* ]] \
  && ok "a caller's --settings wins, unstacked" || bad "a caller's --settings wins, unstacked" "$got"

run_case doctor
[[ "$got" != *"ARG:--settings"* ]] && ok "subcommands get nothing" || bad "subcommands get nothing" "$got"

claude-memory full >/dev/null
CLAUDE_MEMORY=minimal run_case
[[ "$got" == *"claude-memory/minimal.json"* ]] && ok "CLAUDE_MEMORY overrides the saved mode" \
  || bad "CLAUDE_MEMORY overrides the saved mode" "${got:-<empty>}"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
