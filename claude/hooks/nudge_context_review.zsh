#!/usr/bin/env zsh
# SessionStart hook: say so when the monthly context review has a report nobody
# has reviewed yet, or when the review has stopped running.
#
# The monthly context-review.timer runs `context-review run`, which writes
# ~/.local/state/context-review/<YYYY-MM-DD>/summary.json and stops there. A
# report nobody reads is not a reminder, so this surfaces it. The report is
# acknowledged when `context-review ack` writes acknowledged.json beside it
# (the context-review skill does this at the end of a review); an ack older
# than the summary's generated_at does not count, so a re-run re-opens it.
#
# Deliberately CHEAP and OFFLINE: it reads one small JSON file. It never scans
# transcripts or runs the review itself -- that takes seconds and would delay
# every session for a check that is actionable once a month.
#
# At most one line. Precedence: overdue (last run older than 40 days, so the
# timer is not firing) over unreviewed. Silent when there is no run at all
# (the timer is not deployed on this machine), and silent once acknowledged.
#
# Advisory only. Always exits 0 -- a broken reminder must never stop a session.
#
# Feature flag: nudges.context-review (features.conf). features.conf sets
# `nudges = off` wholesale, so this flag must be listed explicitly to run.

emulate -L zsh
setopt no_unset pipe_fail

HOOK_DIR=${0:A:h}
if [[ -r $HOOK_DIR/hook_feature.py ]] && \
   ! python3 $HOOK_DIR/hook_feature.py enabled nudges.context-review 2>/dev/null; then
    exit 0
fi
(( $+commands[python3] )) || exit 0

# stdin is consumed so the hook never blocks a writer on a full pipe.
cat >/dev/null 2>&1 || true

# The same variable the command writes through, so one override redirects both
# ends. CONTEXT_REVIEW_TODAY lets the tests pin the date.
STATE=${CONTEXT_REVIEW_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/context-review}
[[ -d $STATE ]] || exit 0

MSG=$(STATE=$STATE python3 - <<'PY' 2>/dev/null
import json, os, re, sys
from datetime import date
from pathlib import Path

OVERDUE_DAYS = 40
state = Path(os.environ["STATE"])
today = (date.fromisoformat(os.environ["CONTEXT_REVIEW_TODAY"])
         if os.environ.get("CONTEXT_REVIEW_TODAY") else date.today())
runs = sorted((p for p in state.iterdir()
               if re.fullmatch(r"\d{4}-\d{2}-\d{2}", p.name) and (p / "summary.json").is_file()),
              reverse=True)
if not runs:
    sys.exit(0)
run = runs[0]
try:
    s = json.loads((run / "summary.json").read_text())
    ran = date.fromisoformat(s["date"])
except (OSError, ValueError, KeyError, TypeError):
    sys.exit(0)
if not isinstance(s, dict):
    sys.exit(0)

acked = False
try:
    a = json.loads((run / "acknowledged.json").read_text())
    acked = isinstance(a, dict) and str(a.get("acked_at", "")) >= str(s.get("generated_at", ""))
except (OSError, ValueError):
    pass

age = (today - ran).days
if age > OVERDUE_DAYS:
    tail = " Its report is still unreviewed: run /context-review." if not acked else ""
    print(f"Context review last ran {ran} ({age} days ago) but runs monthly, so the timer is"
          " not firing: check `systemctl --user status context-review.timer`, or run"
          f" `context-review run`.{tail}")
    sys.exit(0)
if acked:
    sys.exit(0)

n = s.get("nudge") if isinstance(s.get("nudge"), dict) else {}
d = n.get("always_on_delta_bytes")
growth = f"always-on {d:+,} B" if isinstance(d, int) else "always-on: first run, no baseline"
parts = [f"{n.get('unused', '?')} unused skills/agents", growth,
         f"{n.get('stale_handoffs', '?')} stale handoffs"]
if n.get("stale_learnings"):
    parts.append(f"{n['stale_learnings']} Learnings past two weeks")
vc = s.get("vault_copy") if isinstance(s.get("vault_copy"), dict) else {}
if str(vc.get("status", "ok")).startswith("error"):
    parts.append("vault copy FAILED")
print(f"Context review {ran}: {', '.join(parts)} -- run /context-review"
      " (only if the user's current task does not take priority).")
PY
)

[[ -n $MSG ]] || exit 0

python3 -c '
import json, sys
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": sys.argv[1],
}}))
' "$MSG"
exit 0
