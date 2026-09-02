#!/usr/bin/env bash
# Tests claude-jobs-reap's --finished / --states filter, which is what the
# claude() wrapper uses to hide finished rows from `claude agents`.
#
# Why this exists: the agents view is compiled into the CLI and has no hide
# toggle, so the only way a finished row disappears is its job dir leaving
# ~/.claude/jobs. That makes the filter load-bearing in both directions — it
# must take done/failed/stopped, and it must NEVER take `blocked` (the "Needs
# you" row) or a working job, even at zero grace. Runs against a fixture jobs
# dir; nothing here touches the real ~/.claude/jobs.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAPER="${1:-$SCRIPT_DIR/../custom_bins/claude-jobs-reap}"

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n     %s\n' "$1" "$2"; fail=$((fail + 1)); }

printf 'claude-jobs-reap: --finished hides the done bucket and nothing else\n'

d=""
for root in /tmp/claude /tmp "${TMPDIR:-}"; do
  [[ -n "$root" ]] || continue
  mkdir -p "$root" 2>/dev/null || continue
  d=$(mktemp -d "$root/claude-jobs-reap-test.XXXXXX" 2>/dev/null) && [[ -d "$d" ]] && break
  d=""
done
if [[ -z "$d" ]]; then
  printf '  SKIP (no writable temp directory)\n'
  exit 0
fi
trap 'rm -rf "$d"' EXIT

# One job per state the view persists (measured on 2.1.258 from a real
# ~/.claude/jobs), plus the two protected shapes: no state.json, and the
# invoking session's own dir.
make_job() {  # <name> <state>
  mkdir -p "$d/jobs/$1"
  printf '{"state":"%s","updatedAt":"2026-01-01T00:00:00Z","detail":"x"}\n' "$2" >"$d/jobs/$1/state.json"
}
for s in 'done' failed stopped blocked working idle; do make_job "$s" "$s"; done
mkdir -p "$d/jobs/nostate"
make_job self 'done'

# Glob order is sorted, so this is a stable listing without ls.
listing() { (cd "$1" 2>/dev/null || exit 0; for f in *; do [[ -e "$f" ]] && printf '%s ' "$f"; done); }

# --- --finished at zero grace: exactly done/failed/stopped move -------------

out=$(CLAUDE_JOB_DIR="$d/jobs/self" "$REAPER" --jobs-dir "$d/jobs" --finished --hours 0 \
      --archive-to "$d/archive" 2>&1)
left=$(listing "$d/jobs")
moved=$(listing "$d/archive")
if [[ "$moved" == "done failed stopped " ]]; then
  ok "archive holds exactly done, failed, stopped"
else
  bad "archive holds exactly done, failed, stopped" "archive: ${moved:-<empty>}; output: $out"
fi
if [[ "$left" == "blocked idle nostate self working " ]]; then
  ok "blocked, working, idle, no-state and own-session dirs stay"
else
  bad "blocked, working, idle, no-state and own-session dirs stay" "left: ${left:-<empty>}; output: $out"
fi
case "$out" in
  *"reaped 3 job(s)"*", 3 other-state"*) ok "summary counts the reaped and the other-state keeps" ;;
  *) bad "summary counts the reaped and the other-state keeps" "output: $out" ;;
esac

# --- --quiet: silent when there is nothing to do --------------------------------

out=$(CLAUDE_JOB_DIR="$d/jobs/self" "$REAPER" --jobs-dir "$d/jobs" --finished --hours 0 \
      --archive-to "$d/archive" --quiet 2>&1)
if [[ -z "$out" ]]; then
  ok "--quiet prints nothing on a second, empty pass"
else
  bad "--quiet prints nothing on a second, empty pass" "output: $out"
fi

# --- grace: a job that finished inside the window is kept -----------------------

make_job fresh 'done'
touch "$d/jobs/fresh/state.json" "$d/jobs/fresh"
out=$("$REAPER" --jobs-dir "$d/jobs" --finished --hours 1 --archive-to "$d/archive" 2>&1)
if [[ -d "$d/jobs/fresh" ]]; then
  ok "--hours grace keeps a job that just finished"
else
  bad "--hours grace keeps a job that just finished" "output: $out"
fi

# --- --states must not name an active state -------------------------------------

if "$REAPER" --jobs-dir "$d/jobs" --states working --hours 0 --dry-run >/dev/null 2>&1; then
  bad "--states working is refused" "exit 0"
else
  ok "--states working is refused"
fi
if "$REAPER" --jobs-dir "$d/jobs" --days 1 --hours 1 --dry-run >/dev/null 2>&1; then
  bad "--days and --hours together are refused" "exit 0"
else
  ok "--days and --hours together are refused"
fi

# --- the default (no filter) is unchanged: age-only, active states get grace ----

rm -rf "$d/jobs" "$d/archive"
for s in 'done' blocked working idle; do make_job "$s" "$s"; done
out=$("$REAPER" --jobs-dir "$d/jobs" --days 0 --archive-to "$d/archive" 2>&1)
moved=$(listing "$d/archive")
if [[ "$moved" == "blocked done " ]]; then
  ok "without a filter, --days 0 still reaps blocked but never working or idle"
else
  bad "without a filter, --days 0 still reaps blocked but never working or idle" "archive: ${moved:-<empty>}; output: $out"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
