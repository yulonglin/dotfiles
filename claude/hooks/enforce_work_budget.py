#!/usr/bin/env python3
"""Stop / SubagentStop hook: keep an agent working until its declared budget ends.

An agent declares a budget with `work-budget start 2h --goal ...` (custom_bins),
which prints an ID and writes ~/.local/state/work-budget/<ID>.json. When the
session stops, this hook looks for the line `start` printed ("<ID> active until")
in the stopping transcript (the subagent's own for SubagentStop). A match means
this session started it, so the stop is refused with a reason naming the time
left and the goal, until the deadline passes, the budget is stopped or
`max_blocks` is spent. A session that sees only the bare ID (a `status`
listing, a stop message) is not held; one that quotes the whole start line is.

Why: told to "work for N hours", agents mostly stop early or idle out the clock
(arXiv 2610.09944, AgentTime, Table 3 and section 4.1).

Never blocks while the session has running background tasks or crons: it will
be woken when they finish, and a forced turn would only busy-wait. Claude Code
also ends a turn after 8 consecutive stop-hook continuations with no tool call
in between, which bounds a stuck loop independently of this hook.

Fail-open: any error, a missing transcript or the KILL file exits 0. Gated by
`guards.work-budget` in features.conf through hook_feature.sh.
"""

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

STATE = (
    Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "work-budget"
)


def live_budgets(now):
    for p in sorted(STATE.glob("wb-*.json")):
        try:
            rec = json.loads(p.read_text())
            if (
                not rec.get("stopped")
                and datetime.fromisoformat(rec["until"]) > now
                and rec.get("blocks", 0) < rec.get("max_blocks", 0)
            ):
                yield p, rec
        except (OSError, ValueError, KeyError):
            continue


def transcript_has(path, needles):
    """The needles found in the transcript, read in chunks so a large file is cheap."""
    found, tail, width = set(), "", max(map(len, needles), default=0)
    with open(path, encoding="utf-8", errors="replace") as f:
        while chunk := f.read(1 << 20):
            text = tail + chunk
            found.update(n for n in needles if n in text)
            if found == set(needles):
                break
            tail = text[-width:]
    return found


def main():
    event = json.load(sys.stdin)
    if (STATE / "KILL").exists() or not STATE.is_dir():
        return
    if any(
        t.get("status") == "running" for t in event.get("background_tasks") or []
    ) or event.get("session_crons"):
        return
    transcript = event.get("agent_transcript_path") or event.get("transcript_path")
    if not transcript:
        return
    transcript = os.path.expanduser(transcript)
    now = datetime.now(timezone.utc)
    live = list(live_budgets(now))
    if not live:
        return
    mine = transcript_has(transcript, [rec["id"] + " active until" for _, rec in live])
    for path, rec in live:
        if rec["id"] + " active until" not in mine:
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


if __name__ == "__main__":
    try:
        main()
    except Exception:  # noqa: BLE001, S110 - fail open: a broken guard must never trap a session
        pass
    sys.exit(0)
