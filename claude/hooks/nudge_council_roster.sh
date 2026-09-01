#!/usr/bin/env bash
# SessionStart hook: say so when the LLM council roster is overdue for review.
#
# The point of this hook is that a report nobody reads is not a reminder. The
# fortnightly council-roster.timer writes its finding to
# ~/.local/state/council-roster/roster-report.txt and stops there; without
# something that surfaces it at the start of a session, the roster would go
# stale exactly as silently as the model slugs it exists to keep fresh.
#
# Deliberately CHEAP and OFFLINE. It reads the `reviewed` date out of the config
# and compares it to today. It does NOT fetch the catalogue or the capability
# index: a session-start hook that makes two network calls delays every session
# for a check that is only actionable a couple of times a month. The timer does
# the expensive comparison; this only reads a date.
#
# Advisory only, and silent whenever there is nothing to say. Always exits 0 --
# a broken reminder must never stop a session from starting.
#
# Feature flag: nudges.council-roster (features.conf). features.conf sets
# `nudges = off` wholesale, so this flag must be listed explicitly to run.
set -uo pipefail

HOOK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 0
if [ -r "$HOOK_DIR/hook_feature.py" ] && \
   ! python3 "$HOOK_DIR/hook_feature.py" enabled nudges.council-roster 2>/dev/null; then
    exit 0
fi

# COUNCIL_CONFIG overrides the path so the overdue branch can be tested without
# backdating the real config (which would fire the nudge in every live session).
CONFIG="${COUNCIL_CONFIG:-$HOME/code/dotfiles/config/openrouter-models.toml}"
[ -r "$CONFIG" ] || exit 0

# stdin is consumed so the hook never blocks a writer on a full pipe.
cat >/dev/null 2>&1 || true

MSG=$(CONFIG="$CONFIG" python3 <<'PY' 2>/dev/null
import datetime, os, sys, tomllib

try:
    with open(os.environ["CONFIG"], "rb") as fh:
        cfg = tomllib.load(fh)
except (OSError, ValueError):
    sys.exit(0)

council = cfg.get("council") or {}
stamp, due = council.get("reviewed"), int(council.get("review_days") or 14)
if not stamp:
    sys.exit(0)
try:
    when = datetime.date.fromisoformat(str(stamp))
except ValueError:
    sys.exit(0)

age = (datetime.date.today() - when).days
if age <= due:
    sys.exit(0)

seats = council.get("seats") or []
# A seat scored 0 is seated on recency alone -- the index has not reached it.
# Worth naming: it is the part of the roster resting on the least evidence.
unscored = [s.get("alias", "?") for s in seats if not s.get("score")]
extra = f" {len(unscored)} seat(s) unscored ({', '.join(unscored)})." if unscored else ""
print(
    f"The LLM council roster was last reviewed {age} days ago (every {due} days)."
    f"{extra} Run `openrouter-cli council roster --check` to see whether the"
    " capability indices have moved, then `openrouter-cli council refresh"
    " --apply` and commit the result. Do this only if the user's current task"
    " does not take priority."
)
PY
)

[ -n "$MSG" ] || exit 0

python3 -c '
import json, sys
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": sys.argv[1],
}}))
' "$MSG"
exit 0
