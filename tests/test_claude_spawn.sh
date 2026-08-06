#!/usr/bin/env bash
# Tests for custom_bins/claude-spawn.
#
# All assertions run through --dry-run, so no tmux session is ever created and
# the test is safe to run anywhere. The gates are the point of this file: if a
# refusal stops firing, a spawned agent gets more capability than intended.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPAWN="$SCRIPT_DIR/../custom_bins/claude-spawn"

pass=0
fail=0

ok()   { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  FAIL %s\n     %s\n' "$1" "$2"; fail=$((fail + 1)); }

# assert_contains <name> <expected-substring> <actual>
assert_contains() {
  if [[ "$3" == *"$2"* ]]; then ok "$1"; else bad "$1" "expected to contain: $2"; fi
}

# assert_not_contains <name> <forbidden-substring> <actual>
assert_not_contains() {
  if [[ "$3" != *"$2"* ]]; then ok "$1"; else bad "$1" "must not contain: $2"; fi
}

# assert_exit <name> <expected-code> <actual-code>
assert_exit() {
  if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1" "expected exit $2, got $3"; fi
}

printf 'claude-spawn\n'

# --- defaults ---------------------------------------------------------------

out=$("$SPAWN" --dry-run "seed prompt" 2>&1)
assert_contains     "default: builds a claude command"  "zsh -ic '" "$out"
assert_contains     "default: invokes claude"           "; claude " "$out"
# No retained shell: the pane exits with the agent so the tmux session ends
# rather than lingering as something that looks like a running agent.
assert_not_contains "default: no retained shell"        "exec zsh" "$out"
# The seed is lifted out of the environment before the agent starts, so it does
# not survive in /proc/<pid>/environ or reach the agent's children.
assert_contains     "default: unsets the seed env var"  "unset CLAUDE_SPAWN_PROMPT" "$out"
# Spawning from inside a Claude session exports CLAUDECODE=1; the pane inherits
# it and the child CLI refuses to start as a nested invocation.
assert_contains     "default: clears the nesting marker" "unset CLAUDECODE" "$out"
# The pane inherits the tmux SERVER's environment, fixed whenever that server
# started — so without this a spawn into one project can run with another
# project's API keys.
assert_contains     "default: loads target direnv env"  "direnv export zsh" "$out"

# The inner command is embedded in `zsh -ic '...'`, so a single apostrophe
# anywhere inside it terminates that string early and tmux receives a mangled
# command. Easy to reintroduce the moment someone writes a possessive in a
# diagnostic, so assert the invariant rather than trusting review to catch it.
inner_cmd=$(printf '%s\n' "$out" | sed -n "s/^command:[[:space:]]*zsh -ic '\(.*\)'\$/\1/p")
case "$inner_cmd" in
  *"'"*) bad "inner command contains no apostrophe" "found one: $inner_cmd" ;;
  *)     ok "inner command contains no apostrophe" ;;
esac
assert_contains     "default: remote control disabled"  "remote control: disabled" "$out"
assert_not_contains "default: no --remote-control flag" "--remote-control" "$out"
assert_not_contains "default: no skip-permissions"      "--dangerously-skip-permissions" "$out"

# The prompt must reach the command UNEXPANDED — if bash or sh expands it here,
# the seed text would be subject to two more rounds of word splitting.
# shellcheck disable=SC2016  # asserting the literal, unexpanded text
assert_contains "prompt is deferred, not interpolated" '"$CLAUDE_SPAWN_PROMPT"' "$out"
assert_not_contains "prompt text absent from command" "seed prompt\"; exec" "$out"

# Interactive zsh is required or the claude() wrapper is silently missing.
assert_contains "uses an interactive shell" "zsh -ic" "$out"

# --- remote control is opt-in ----------------------------------------------

out=$("$SPAWN" --dry-run -r "x" 2>&1)
assert_contains "-r enables remote control" "--remote-control" "$out"

# `--remote-control [name]` takes an OPTIONAL argument, so a bare
# `--remote-control` followed by the prompt would consume the prompt as the
# session name and start an agent with no seed at all. The name must always be
# supplied, and as ONE token — see the option-boundary section below for why the
# space-separated spelling this assertion used to require was a gate bypass.
# shellcheck disable=SC2016
assert_contains "remote control is never bare" '--remote-control="$CLAUDE_SPAWN_RC_NAME"' "$out"

out=$("$SPAWN" --dry-run -n my-rc-name "x" 2>&1)
assert_contains "-n implies remote control" "--remote-control" "$out"
assert_contains "-n sets the name"          "remote control: my-rc-name" "$out"

# --- gate: --yolo + --remote-control ----------------------------------------

out=$("$SPAWN" --dry-run -y -r "x" 2>&1); code=$?
assert_exit     "gate: yolo+rc refused"        4 "$code"
assert_contains "gate: yolo+rc explains why"   "drivable from off-machine" "$out"

out=$("$SPAWN" --dry-run -y -r --allow-remote-yolo "x" 2>&1); code=$?
assert_exit     "gate: yolo+rc overridable"    0 "$code"
assert_contains "gate: override actually yolos" "--dangerously-skip-permissions" "$out"

# The gate is a speed bump, not a guarantee: it refuses the one combination you
# can state explicitly, and does not neutralise capability your own settings
# grant. A spawned session is the session you would have started by hand.
out=$("$SPAWN" --dry-run -y "x" 2>&1)
assert_not_contains "yolo does not suppress channels" "NO_AUTO_CHANNELS" "$out"
assert_not_contains "yolo does not override settings" "remoteControlAtStartup" "$out"

# Either alone is ordinary and must not be blocked.
out=$("$SPAWN" --dry-run -y "x" 2>&1); code=$?
assert_exit     "yolo alone allowed"  0 "$code"
assert_contains "yolo alone skips perms" "--dangerously-skip-permissions" "$out"

# --- gate: option-shaped values must not become options ---------------------
#
# The bypass this guards: `--remote-control [name]` takes an OPTIONAL argument,
# so an optional-arg option does not consume a dash-prefixed token. Spelling the
# name as a separate word meant `-n --dangerously-skip-permissions` reached
# Claude as TWO options — Remote Control plus skip-permissions — while this
# script still believed yolo=false, so gate 2 never fired. The gate was checking
# its own variables, not the argv it was about to build.

# This is the attack verbatim: the name is an option, and yolo is never set.
out=$("$SPAWN" --dry-run -n --dangerously-skip-permissions "x" 2>&1)
assert_not_contains "rc name cannot smuggle a flag" "--dangerously-skip-permissions" "$out"
assert_contains     "rc name is defanged, not rejected" "remote control: dangerously-skip-permissions" "$out"

# The single-token form is what makes the above impossible: no value of the name
# can split into a second argument.
out=$("$SPAWN" --dry-run -r "x" 2>&1)
# shellcheck disable=SC2016  # asserting the literal, unexpanded text
assert_contains "rc name is one token" '--remote-control="$CLAUDE_SPAWN_RC_NAME"' "$out"

# The seed is passed positionally with no terminator, exactly as a hand-typed
# session would. `claude "--foo"` reads an option when you type it, so a spawned
# session gets the same behaviour rather than a safer one — the terminator that
# used to be here made the spawned session behave differently, and pushed the
# wrapper's --channels past it into prompt text.
out=$("$SPAWN" --dry-run "seed text" 2>&1)
# shellcheck disable=SC2016  # asserting the literal, unexpanded text
assert_contains     "seed is positional"      '; claude "$_seed"' "$out"
# shellcheck disable=SC2016  # asserting the literal, unexpanded text
assert_not_contains "no option terminator"    '-- "$_seed"' "$out"

# --- gate: unattended auto-resume is opt-in ---------------------------------
#
# tmux-resume decides purely on the window-name prefix and never sees our flags,
# so a name that merely starts with it enrolled the session in unattended
# rate-limit resumption without --auto ever being passed.

optin=$(tmux-resume --print-optin-prefix 2>/dev/null || echo "")
if [[ -z "$optin" ]]; then
  printf '  SKIP auto-resume prefix tests (tmux-resume reports no prefix)\n'
else
  out=$("$SPAWN" --dry-run -s "${optin}review" "x" 2>&1)
  assert_not_contains "prefixed name does not opt in without --auto" \
    "tmux window:    ${optin}review" "$out"
  assert_contains "prefixed name is reported, not silently changed" \
    "--auto was not passed" "$out"

  # --auto must still work, and must not double-prefix an already-prefixed name.
  out=$("$SPAWN" --dry-run --auto -s "${optin}review" "x" 2>&1)
  assert_contains     "--auto keeps the prefix"    "tmux window:    ${optin}review" "$out"
  assert_not_contains "--auto does not double it"  "${optin}${optin}" "$out"

  # An ordinary name gains the prefix under --auto.
  out=$("$SPAWN" --dry-run --auto -s plainname "x" 2>&1)
  assert_contains "--auto prefixes a plain name" "tmux window:    ${optin}plainname" "$out"
fi

# --- gate: recursion depth --------------------------------------------------

out=$(CLAUDE_SPAWN_DEPTH=1 "$SPAWN" --dry-run "x" 2>&1); code=$?
assert_exit     "gate: nested spawn refused"    4 "$code"
assert_contains "gate: nested names the depth"  "depth=1" "$out"

out=$(CLAUDE_SPAWN_DEPTH=1 "$SPAWN" --dry-run --allow-nested "x" 2>&1); code=$?
assert_exit "gate: nested overridable" 0 "$code"

out=$(CLAUDE_SPAWN_DEPTH=0 "$SPAWN" --dry-run "x" 2>&1); code=$?
assert_exit "depth 0 is not nested" 0 "$code"

# --- argument handling ------------------------------------------------------

out=$("$SPAWN" --dry-run 2>&1); code=$?
assert_exit     "missing prompt is an error" 1 "$code"
assert_contains "missing prompt explains"    "no seed prompt" "$out"

out=$("$SPAWN" --dry-run -d /nonexistent-dir-xyz "x" 2>&1); code=$?
assert_exit     "bad --dir is an error" 1 "$code"
assert_contains "bad --dir explains"    "not a directory" "$out"

out=$("$SPAWN" --dry-run --bogus-flag "x" 2>&1); code=$?
assert_exit "unknown flag is an error" 1 "$code"

# A value-taking flag in final position used to fail `shift 2`, which under
# `set -e` exits 1 with nothing on stderr. The diagnostic is the point here.
out=$("$SPAWN" --dry-run --dir 2>&1); code=$?
assert_exit     "trailing --dir is an error"  1 "$code"
assert_contains "trailing --dir explains"     "needs a value" "$out"

out=$("$SPAWN" --dry-run -s 2>&1); code=$?
assert_contains "trailing -s explains"        "needs a value" "$out"

out=$(printf 'from stdin' | "$SPAWN" --dry-run - 2>&1); code=$?
assert_exit     "stdin prompt accepted" 0 "$code"
assert_contains "stdin prompt has length" "prompt bytes:   10" "$out"

# Session names must not contain tmux target separators.
out=$("$SPAWN" --dry-run -s 'has.dots:and:colons' "x" 2>&1)
assert_not_contains "session name strips dots"   "has.dots" "$out"
assert_not_contains "session name strips colons" ":and:" "$out"

out=$("$SPAWN" --dry-run -h 2>&1); code=$?
assert_exit     "--help exits 0" 0 "$code"
assert_contains "--help lists exit codes" "Exit codes:" "$out"

# --- dry-run must not have side effects -------------------------------------

log="${XDG_STATE_HOME:-$HOME/.local/state}/claude-spawn/spawn.log"
before=$( [[ -f "$log" ]] && wc -l <"$log" || echo 0 )
"$SPAWN" --dry-run "x" >/dev/null 2>&1
after=$( [[ -f "$log" ]] && wc -l <"$log" || echo 0 )
if [[ "$before" == "$after" ]]; then
  ok "dry-run writes no audit entry"
else
  bad "dry-run writes no audit entry" "audit log grew from $before to $after lines"
fi

# --- the emitted argv actually works ----------------------------------------
#
# Everything above greps a printed string, which only proves the script says the
# right thing. This runs what the script emits, with a stub on PATH standing in
# for the real agent, and reads back what the agent would have received. That
# closes the gap between "I believe it emits X" and "X does the right thing".
#
# Skipped without a reachable tmux server (CI, or a sandbox that denies the
# tmux socket) — skipping is reported, never silently passed.

# $TMPDIR is not always writable — under Claude Code's Linux sandbox it points at
# a read-only /run/user/<uid>, and mktemp with no -p fails outright. That used to
# skip the probe silently on exactly the machine this tool is developed on, which
# made the one test that runs real code the one test that never ran. Try the
# obvious roots in turn instead of giving up on the first.
probe_dir=""
for probe_root in "${TMPDIR:-}" /tmp/claude /tmp "$SCRIPT_DIR/../tmp"; do
  [[ -n "$probe_root" ]] || continue
  mkdir -p "$probe_root" 2>/dev/null || continue
  # A full template rather than `mktemp -d -p <dir>`: -p is GNU-only, so on
  # stock macOS every root failed and the probe skipped — silently, on a
  # platform this repo supports.
  probe_dir=$(mktemp -d "$probe_root/claude-spawn-probe.XXXXXX" 2>/dev/null || echo "")
  [[ -n "$probe_dir" && -d "$probe_dir" ]] && break
  probe_dir=""
done
probe_session="claude-spawn-argvprobe-$$"

# Without this guard an unwritable TMPDIR leaves probe_dir empty, and every
# "$probe_dir/..." below becomes an absolute path at the filesystem root — the
# stub would be written to /bin/claude. Refuse rather than build on an empty
# prefix.
if [[ -z "$probe_dir" || ! -d "$probe_dir" ]]; then
  printf '  SKIP argv probe (no writable temp directory)\n'
  printf '\n%d passed, %d failed\n' "$pass" "$fail"
  [[ "$fail" -eq 0 ]]
  exit $?
fi

# A private tmux server, so the probe cannot collide with, inherit from, or
# leave anything behind in the user's real one. TMUX_TMPDIR picks the socket
# directory, and the eval'd command inherits it, so it reaches this server too.
#
# TMUX must be unset first, and this is not cosmetic. Inside a tmux pane, $TMUX
# names the live server's socket and takes precedence over TMUX_TMPDIR — so a
# developer running this suite from their own tmux session would have had the
# probe attach to THAT server (where the real claude, not the stub, is on PATH)
# and then hit the unconditional `tmux kill-server` below, destroying every
# session they had open. The private server is only private once TMUX is gone.
unset TMUX TMUX_PANE
export TMUX_TMPDIR="$probe_dir/tmux"
mkdir -p "$TMUX_TMPDIR"
chmod 700 "$TMUX_TMPDIR"

# Stub `claude`, recording what the agent would actually have received.
mkdir -p "$probe_dir/bin"
{
  printf '#!/usr/bin/env bash\n'
  printf 'printf "ARG:%%s\\n" "$@" >"%s/argv.txt"\n' "$probe_dir"
  # shellcheck disable=SC2016  # writing a script; expansion happens when it runs
  printf 'printf "DEPTH:%%s\\n" "${CLAUDE_SPAWN_DEPTH:-unset}" >>"%s/argv.txt"\n' "$probe_dir"
  # The agent must NOT still have the seed in its environment: tmux -e exports
  # it, and `set-environment -u` does not reach an already-forked pane, so the
  # pane has to unset its own copy before exec'ing us.
  # shellcheck disable=SC2016
  printf 'printf "SEEDENV:%%s\\n" "${CLAUDE_SPAWN_PROMPT:-unset}" >>"%s/argv.txt"\n' "$probe_dir"
} >"$probe_dir/bin/claude"
chmod +x "$probe_dir/bin/claude"

# The real claude() is a zsh *function*, and a function beats a PATH entry. An
# empty ZDOTDIR means `zsh -ic` defines no such function, so the stub wins and
# the probe never launches a real agent.
mkdir -p "$probe_dir/zdot"
: >"$probe_dir/zdot/.zshrc"
: >"$probe_dir/zdot/.zshenv"

# EXPORTED, not set as a one-shot prefix on `tmux start-server`. A tmux server
# with no sessions exits almost immediately, so the prefixed server was usually
# gone by the time `eval "$argv"` ran; the eval then started a FRESH server from
# this shell's own environment, where the real claude() wrapper and the real
# binary both win. The "safe" probe could therefore launch a genuine detached
# agent, sit through its timeout, and report only that the stub was not invoked.
# Exporting means every server started from here inherits the stub, whichever
# one the eval'd command ends up talking to.
export PATH="$probe_dir/bin:$PATH"
export ZDOTDIR="$probe_dir/zdot"

# Belt and braces: if `claude` does not resolve to the stub, something about the
# shadowing assumption is wrong and the next step would start a real agent.
# Refuse to run rather than find out by launching one.
resolved_claude=$(command -v claude 2>/dev/null || echo "")
if [[ "$resolved_claude" != "$probe_dir/bin/claude" ]]; then
  bad "argv probe: stub shadows the real claude" \
      "claude resolves to '${resolved_claude:-<nothing>}', refusing to run the probe"
elif ! tmux new-session -d -s "${probe_session}-holder" sleep 600 2>/dev/null; then
  # A holding session, not a bare `start-server`. tmux's `exit-empty` option
  # defaults to ON, so start-server returns success and then the server exits
  # again immediately for having no sessions — after which the socket check
  # below found nothing and recorded a FAILURE rather than falling back. Owning
  # one real session keeps the server up for the duration of the probe.
  # No tmux (CI, or a sandbox that denies the unix socket). Rather than skip
  # outright and report green, exercise the layer we still can: run the inner
  # `zsh -ic ...` string the script itself emits, with the prompt supplied the
  # way tmux would have supplied it. That covers the quoting claim — the part
  # most likely to break — and leaves only tmux's own -e delivery untested.
  printf '  NOTE tmux unavailable; running the zsh-layer fallback instead\n'

  # shellcheck disable=SC2016  # the unexpanded $var is the hostile input
  fallback_prompt='multi word "quoted" $notexpanded'
  # Read the inner command out of the script's own dry-run rather than
  # transcribing it, for the same anti-drift reason as the full probe.
  inner=$("$SPAWN" --dry-run -r -s fallback-sess -d "$probe_dir" "$fallback_prompt" 2>/dev/null \
          | sed -n 's/^command:[[:space:]]*//p')

  if [[ -z "$inner" ]]; then
    bad "zsh-layer probe: script emits an inner command" "dry-run printed no 'command:' line"
  else
    export CLAUDE_SPAWN_PROMPT="$fallback_prompt"
    export CLAUDE_SPAWN_RC_NAME="fallback-rc"
    export CLAUDE_SPAWN_DEPTH=1
    # </dev/null so the trailing `exec zsh` sees EOF and exits.
    eval "$inner </dev/null" >/dev/null 2>&1 || true

    got=$(cat "$probe_dir/argv.txt" 2>/dev/null || echo "")
    if [[ -z "$got" ]]; then
      bad "zsh-layer probe: the emitted command reaches the agent" "stub was never invoked"
    else
      assert_contains     "zsh-layer probe: prompt arrives verbatim" "ARG:$fallback_prompt" "$got"
      assert_contains     "zsh-layer probe: option terminator present" "ARG:--" "$got"
      assert_contains     "zsh-layer probe: rc name is one token" "ARG:--remote-control=" "$got"
      assert_not_contains "zsh-layer probe: no skip-permissions" "skip-permissions" "$got"
      # The seed must not survive in the agent's environment.
      assert_contains     "zsh-layer probe: seed cleared from env" "SEEDENV:unset" "$got"
    fi

    # A second run WITHOUT -r, which is the local-only path. The settings JSON
    # travels through bash and zsh quoting, and this is the only check that it
    # reaches the agent as valid JSON rather than a mangled string — the whole
    # point of it being there is that the deployed settings enable Remote
    # Control at startup, so a default spawn is not local-only without it.
    # --allow-nested because CLAUDE_SPAWN_DEPTH=1 is exported just above for the
    # depth-propagation check, and the recursion gate would otherwise refuse.
    inner_local=$("$SPAWN" --dry-run --allow-nested -s fallback-local -d "$probe_dir" "$fallback_prompt" 2>/dev/null \
                  | sed -n 's/^command:[[:space:]]*//p')
    if [[ -z "$inner_local" ]]; then
      bad "zsh-layer probe: local-only command emitted" "dry-run printed no 'command:' line"
    else
      : >"$probe_dir/argv.txt"
      export CLAUDE_SPAWN_PROMPT="$fallback_prompt"
      eval "$inner_local </dev/null" >/dev/null 2>&1 || true
      got_local=$(cat "$probe_dir/argv.txt" 2>/dev/null || echo "")
      # Nothing between the agent and its seed: no terminator, no settings
      # override. What a hand-typed session would have received.
      assert_contains     "zsh-layer probe: seed is the only argument" \
        "ARG:$fallback_prompt" "$got_local"
      assert_not_contains "zsh-layer probe: no settings override" \
        "remoteControlAtStartup" "$got_local"

      # `tmux new-session -d` only proves a pane exists: the `;` chain runs
      # `exec zsh` regardless, so an agent that dies on startup leaves a healthy
      # shell and used to be reported as a successful spawn. The pane must say
      # when the agent failed — and must stay quiet when it did not.
      export CLAUDE_SPAWN_STATUS_FILE="$probe_dir/status"

      # Armed: the file exists and is empty, which is how the launcher says it
      # is still listening.
      : >"$CLAUDE_SPAWN_STATUS_FILE"
      printf '#!/usr/bin/env bash\nexit 7\n' >"$probe_dir/bin/claude"
      chmod +x "$probe_dir/bin/claude"
      eval "$inner_local </dev/null" >/dev/null 2>&1 || true
      assert_contains "startup failure is reported" "7" \
        "$(cat "$CLAUDE_SPAWN_STATUS_FILE" 2>/dev/null || echo "")"

      : >"$CLAUDE_SPAWN_STATUS_FILE"
      printf '#!/usr/bin/env bash\nexit 0\n' >"$probe_dir/bin/claude"
      chmod +x "$probe_dir/bin/claude"
      eval "$inner_local </dev/null" >/dev/null 2>&1 || true
      if [[ -s "$CLAUDE_SPAWN_STATUS_FILE" ]]; then
        bad "healthy agent reports nothing" "status file written for a clean exit"
      else
        ok "healthy agent reports nothing"
      fi

      # Disarmed: the launcher has closed its window and removed the file. A
      # late nonzero exit — Ctrl-C hours later — must NOT recreate it, or the
      # leftover would outlive the run and, once the PID was reused, make a
      # healthy spawn report failure.
      rm -f "$CLAUDE_SPAWN_STATUS_FILE"
      printf '#!/usr/bin/env bash\nexit 7\n' >"$probe_dir/bin/claude"
      chmod +x "$probe_dir/bin/claude"
      eval "$inner_local </dev/null" >/dev/null 2>&1 || true
      if [[ -e "$CLAUDE_SPAWN_STATUS_FILE" ]]; then
        bad "late exit does not resurrect the status file" "file recreated after disarm"
      else
        ok "late exit does not resurrect the status file"
      fi
      unset CLAUDE_SPAWN_STATUS_FILE
    fi
    unset CLAUDE_SPAWN_PROMPT CLAUDE_SPAWN_RC_NAME CLAUDE_SPAWN_DEPTH
  fi
  printf '  NOTE tmux -e delivery is NOT covered by the fallback\n'
else
  # Deliberately hostile: spaces, double quotes, and a `$var` that must survive
  # every shell layer unexpanded.
  # shellcheck disable=SC2016
  probe_prompt='multi word "quoted" $notexpanded'

  # Ask the script for its own tmux invocation, then run exactly that. This is
  # the whole point: no hand-transcribed copy sits between test and artifact.
  argv=$("$SPAWN" --print-tmux-command -s "$probe_session" -d "$probe_dir" "$probe_prompt" 2>&1)

  # Prove the server we are about to drive is the private one before evaluating
  # anything on it — and, more importantly, before the kill-server at the end of
  # this block. If the socket is not under the probe directory, something has
  # re-pointed tmux at a server we do not own, and killing it would take the
  # user's sessions with it.
  socket_path=$(tmux display-message -p '#{socket_path}' 2>/dev/null || echo "")

  if [[ "$argv" != tmux\ * ]]; then
    bad "argv probe: script emits a tmux command" "got: $argv"
  elif [[ "$socket_path" != "$probe_dir"/* ]]; then
    bad "argv probe: server is the private one" \
        "socket is '${socket_path:-<unknown>}', not under $probe_dir; refusing to touch it"
  else
    ok "argv probe: server is the private one"
    eval "$argv" 2>/dev/null

    for _ in 1 2 3 4 5 6 7 8 9 10; do
      [[ -s "$probe_dir/argv.txt" ]] && break
      sleep 0.5
    done

    got=$(cat "$probe_dir/argv.txt" 2>/dev/null || echo "")

    if [[ -z "$got" ]]; then
      bad "argv probe: the emitted command reaches the agent" "stub was never invoked"
    else
      assert_contains     "argv probe: prompt arrives verbatim" "ARG:$probe_prompt" "$got"
      assert_contains     "argv probe: depth propagates"        "DEPTH:1" "$got"
      # `--` is deliberate (it protects a dash-leading prompt), so the check is
      # not "no dashes" but "none of the capability flags we did not ask for".
      assert_contains     "argv probe: option terminator present" "ARG:--" "$got"
      assert_not_contains "argv probe: no skip-permissions" "skip-permissions" "$got"
      assert_not_contains "argv probe: no remote control"   "remote-control" "$got"
      assert_contains     "argv probe: seed cleared from env" "SEEDENV:unset" "$got"
    fi
  fi
  # Scoped deliberately: only tear down a server we positively identified as
  # ours. An unconditional kill-server here is what would have destroyed the
  # user's sessions in the TMUX-inherited case.
  if [[ -n "$socket_path" && "$socket_path" == "$probe_dir"/* ]]; then
    tmux -S "$socket_path" kill-server 2>/dev/null || true
  fi
fi

rm -rf "$probe_dir"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
