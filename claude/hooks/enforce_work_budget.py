#!/usr/bin/env python3
"""Keep an agent working until the work budget it declared ends.

An agent declares a budget with `work-budget start 2h --goal ...` (custom_bins),
which prints "<ID> active until ..." and writes ~/.local/state/work-budget/<ID>.json.
This one script serves two events:

  PostToolUse(Bash)     the Bash call that ran `work-budget start` claims the new
                        budget for the identity it ran under: session_id, plus
                        agent_id inside a subagent. First claim wins, and only
                        within ten minutes of the start.
  Stop / SubagentStop   a stop is refused only when the stopping identity is the
                        owner, until the deadline passes, the budget is stopped
                        or `max_blocks` is spent.

Ownership is the recorded identity, never transcript text: a session that sees
the start line in a pasted log or a subagent's report is not held, and a budget
nobody claimed holds nobody.

Why: told to "work for N hours", agents mostly stop early or idle out the clock
(arXiv 2610.09944, AgentTime, Table 3 and section 4.1).

Never blocks while the session has running background tasks or crons: it will
be woken when they finish, and a forced turn would only busy-wait. Claude Code
also ends a turn after 8 consecutive stop-hook continuations with no tool call
in between, which bounds a stuck loop independently of this hook.

Fail-open: any error or the KILL file exits 0 with no output. Gated by
`guards.work-budget` in features.conf through hook_feature.sh.
"""

import json
import os
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

STATE = (
    Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "work-budget"
)
CLAIM_WINDOW = timedelta(minutes=10)
START_LINE = re.compile(r"\b(wb-[0-9a-f]{12}) active until\b")


def identity(event):
    return {"session_id": event.get("session_id"), "agent_id": event.get("agent_id")}


def claim(event, now):
    if event.get("tool_name") != "Bash":
        return
    if "work-budget start" not in str(
        (event.get("tool_input") or {}).get("command", "")
    ):
        return
    owner = identity(event)
    if not owner["session_id"]:
        return
    for bid in set(START_LINE.findall(json.dumps(event.get("tool_response")))):
        path = STATE / f"{bid}.json"
        if not path.is_file():
            continue
        rec = json.loads(path.read_text())
        if (
            rec.get("owner")
            or now - datetime.fromisoformat(rec["start"]) > CLAIM_WINDOW
        ):
            continue
        rec["owner"] = owner
        path.write_text(json.dumps(rec, indent=2) + "\n")


def live_budgets(now):
    for p in sorted(STATE.glob("wb-*.json")):
        try:
            rec = json.loads(p.read_text())
            if (
                rec.get("owner")
                and not rec.get("stopped")
                and datetime.fromisoformat(rec["until"]) > now
                and rec.get("blocks", 0) < rec.get("max_blocks", 0)
            ):
                yield p, rec
        except (OSError, ValueError, KeyError):
            continue


def hold(event, now):
    if any(
        t.get("status") == "running" for t in event.get("background_tasks") or []
    ) or event.get("session_crons"):
        return
    me = identity(event)
    if not me["session_id"]:
        return
    for path, rec in live_budgets(now):
        if rec["owner"] != me:
            continue
        rec["blocks"] = rec.get("blocks", 0) + 1
        path.write_text(json.dumps(rec, indent=2) + "\n")
        left = int((datetime.fromisoformat(rec["until"]) - now).total_seconds() // 60)
        goal = f" Goal: {rec['goal']}." if rec.get("goal") else ""
        reason = (
            f"Work budget {rec['id']} runs for {left} more min (until {rec['until']}); "
            f"stop refused {rec['blocks']} of {rec['max_blocks']}.{goal} "
            "Do not stop yet. Take the next most informative step toward the goal: a new run, "
            "a new condition, or the analysis that decides between hypotheses. Do not sleep, poll "
            "or re-check finished work to pass time. If the goal is done, or blocked on something "
            f'only the user can give, run `work-budget stop {rec["id"]} "<why>"` and then stop.'
        )
        print(json.dumps({"decision": "block", "reason": reason}))
        return


def main():
    event = json.load(sys.stdin)
    if (STATE / "KILL").exists() or not STATE.is_dir():
        return
    now = datetime.now(timezone.utc)
    kind = event.get("hook_event_name")
    if kind == "PostToolUse":
        claim(event, now)
    elif kind in ("Stop", "SubagentStop"):
        hold(event, now)


if __name__ == "__main__":
    try:
        main()
    except Exception:  # noqa: BLE001, S110 - fail open: a broken guard must never trap a session
        pass
    sys.exit(0)
