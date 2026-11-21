#!/usr/bin/env python3
"""Keep an agent working until the work budget it declared ends.

An agent declares a budget with `work-budget start 2h --goal ...` (custom_bins),
which prints "<ID> active until ..." and writes ~/.local/state/work-budget/<ID>.json.
This one script serves three events:

  PreToolUse(Bash)      a Bash call that IS a plain `work-budget start ...`
                        command (no pipes, lists, redirects or substitutions)
                        is noted by tool_use_id, with its start time and the
                        identity it runs under: session_id, plus agent_id
                        inside a subagent.
  PostToolUse(Bash)     that same call claims the budget whose start line it
                        printed, if the budget was created after the call
                        began and nobody owns it yet.
  Stop / SubagentStop   a stop is refused only when the stopping identity is the
                        owner, until the deadline passes, the budget is stopped
                        or `max_blocks` is spent.

Ownership is the identity of the call that created the budget, never text: a
session that sees the start line in a pasted log, a search result or a
subagent's report is not held, and a budget nobody claimed holds nobody.

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
import shlex
import sys
from datetime import datetime, timezone
from pathlib import Path

STATE = (
    Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "work-budget"
)
PENDING = STATE / "pending"
# No leading \b: the response is searched as JSON, where a line break before
# the ID is the two characters `\n`, and `n` then `w` is not a word boundary.
START_LINE = re.compile(r"(wb-[0-9a-f]{12}) active until\b")
ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")


def identity(event):
    return {"session_id": event.get("session_id"), "agent_id": event.get("agent_id")}


def is_start_call(command):
    """True only for a plain `[VAR=x ...] [path/]work-budget start ...` command:
    no pipes, lists, redirects or substitutions, so a search or a log dump that
    merely contains the words never counts."""
    if any(c in command for c in "`$\n"):
        return False
    lex = shlex.shlex(command, posix=True, punctuation_chars=True)
    lex.whitespace_split = True
    try:
        words = list(lex)
    except ValueError:
        return False
    if any(w and set(w) <= set(";&|<>()") for w in words):
        return False
    while words and ASSIGNMENT.match(words[0]):
        words.pop(0)
    return (
        len(words) >= 2 and Path(words[0]).name == "work-budget" and words[1] == "start"
    )


def mark_pending(event, now):
    """PreToolUse: note when this exact Bash call, run by this identity, began."""
    command = str((event.get("tool_input") or {}).get("command", ""))
    call = event.get("tool_use_id")
    if event.get("tool_name") != "Bash" or not call or not is_start_call(command):
        return
    if not event.get("session_id"):
        return
    PENDING.mkdir(parents=True, exist_ok=True)
    for old in PENDING.glob("*.json"):
        if now.timestamp() - old.stat().st_mtime > 86400:
            old.unlink(missing_ok=True)
    record = {"at": now.isoformat(), "owner": identity(event)}
    (PENDING / f"{Path(call).name}.json").write_text(json.dumps(record))


def claim(event):
    """PostToolUse: a budget created during that same call belongs to its caller."""
    call = event.get("tool_use_id")
    if event.get("tool_name") != "Bash" or not call:
        return
    pending = PENDING / f"{Path(call).name}.json"
    if not pending.is_file():
        return
    mark = json.loads(pending.read_text())
    pending.unlink(missing_ok=True)
    if mark["owner"] != identity(event):
        return
    began = datetime.fromisoformat(mark["at"])
    for bid in set(START_LINE.findall(json.dumps(event.get("tool_response")))):
        path = STATE / f"{bid}.json"
        if not path.is_file():
            continue
        rec = json.loads(path.read_text())
        # `created` has microseconds; `start` is rounded to the second for reading.
        if rec.get("owner") or datetime.fromisoformat(rec["created"]) < began:
            continue
        rec["owner"] = mark["owner"]
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
    if (STATE / "KILL").exists():
        return
    now = datetime.now(timezone.utc)
    kind = event.get("hook_event_name")
    if kind == "PreToolUse":
        mark_pending(event, now)
    elif kind == "PostToolUse":
        claim(event)
    elif kind in ("Stop", "SubagentStop"):
        hold(event, now)


if __name__ == "__main__":
    try:
        main()
    except Exception:  # noqa: BLE001, S110 - fail open: a broken guard must never trap a session
        pass
    sys.exit(0)
