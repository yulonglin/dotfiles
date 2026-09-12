"""Failure onset on 2026-09-06, by hour and CLI version.

Two events fall on that day: CLI 2.1.263 sessions begin (hour 03) and the
model-router gateway comes up (09:07 UTC, wired at 09:25). If 2.1.263 sessions
made bound calls in hours 03-08 without failing and failures begin at hour 09,
the gateway is the trigger. If 2.1.263 fails from its first hour while 2.1.261
sessions run alongside it without failing, the CLI upgrade is.
"""
import json
import re
from collections import Counter
from pathlib import Path

RE = re.compile(
    r"[A-Za-z0-9][A-Za-z0-9._-]{0,120}(?:\[1m\])? is temporarily unavailable "
    r"\([^()\r\n]+\), so auto mode cannot determine the safety of ([^\r\n]+?) right now\."
)
# SendMessage is classifier-reviewed too (permission-modes docs), so it belongs in
# the denominator; a failure on any tool outside this set is counted separately
# rather than divided by a call count that never contained it.
BOUND = {"Bash", "PowerShell", "Monitor", "Agent", "Task", "SendMessage"}
DAY = "2026-09-06"
calls, fails = Counter(), Counter()
by_model_calls, by_model_fails = Counter(), Counter()
outside = Counter()
file_model = {}
seen_c, seen_f = set(), set()

for path in Path.home().joinpath(".claude/projects").rglob("*.jsonl"):
    try:
        fh = path.open(errors="replace")
    except OSError:
        continue
    with fh:
        for line in fh:
            try:
                e = json.loads(line)
            except ValueError:
                continue
            if not isinstance(e, dict):
                continue
            ts = e.get("timestamp") or ""
            if ts[:10] != DAY:
                continue
            hour = ts[11:13]
            ver = e.get("version") if isinstance(e.get("version"), str) else "unknown"
            msg = e.get("message")
            if not isinstance(msg, dict):
                continue
            if e.get("type") == "assistant":
                model = msg.get("model") if isinstance(msg.get("model"), str) else None
                for b in msg.get("content") or []:
                    if (isinstance(b, dict) and b.get("type") == "tool_use"
                            and b.get("name") in BOUND and b.get("id") not in seen_c):
                        seen_c.add(b.get("id"))
                        calls[(hour, ver)] += 1
                        if model:
                            by_model_calls[(hour, ver, model)] += 1
                            file_model[path] = model
            elif e.get("type") == "user":
                for b in msg.get("content") or []:
                    if not (isinstance(b, dict) and b.get("type") == "tool_result"
                            and b.get("is_error") is True and isinstance(b.get("content"), str)):
                        continue
                    hit = RE.match(b["content"])
                    if not hit or b.get("tool_use_id") in seen_f:
                        continue
                    seen_f.add(b.get("tool_use_id"))
                    if hit.group(1) not in BOUND:
                        outside[hit.group(1)] += 1
                        continue
                    fails[(hour, ver)] += 1
                    m = file_model.get(path)
                    if m:
                        by_model_fails[(hour, ver, m)] += 1

vers = sorted({v for _, v in set(calls) | set(fails)})
print(f"2026-09-06 UTC. Router came up 09:07, wired 09:25.")
print("hour  " + "  ".join(f"{v:>18}" for v in vers))
for hour in sorted({h for h, _ in set(calls) | set(fails)}):
    cells = []
    for v in vers:
        n, f = calls[(hour, v)], fails[(hour, v)]
        cells.append(f"{f:>4}/{n:<4}" if (n or f) else "     -   ")
    print(f"  {hour}  " + "  ".join(f"{c:>18}" for c in cells))
print()
print("cells are failures/bound-calls; '-' means no bound calls that hour")
for v in vers:
    pre = sum(n for (h, vv), n in calls.items() if vv == v and h < "09")
    pre_f = sum(n for (h, vv), n in fails.items() if vv == v and h < "09")
    post = sum(n for (h, vv), n in calls.items() if vv == v and h >= "09")
    post_f = sum(n for (h, vv), n in fails.items() if vv == v and h >= "09")
    print(f"{v}: before 09:00 {pre_f}/{pre}, from 09:00 {post_f}/{post}")

print()
print("Restricted to CLI 2.1.263, by session model, before vs from 09:00:")
models = sorted({m for _, v, m in set(by_model_calls) | set(by_model_fails) if v == "2.1.263"})
for m in models:
    pre = sum(n for (h, v, mm), n in by_model_calls.items() if v == "2.1.263" and mm == m and h < "09")
    pre_f = sum(n for (h, v, mm), n in by_model_fails.items() if v == "2.1.263" and mm == m and h < "09")
    post = sum(n for (h, v, mm), n in by_model_calls.items() if v == "2.1.263" and mm == m and h >= "09")
    post_f = sum(n for (h, v, mm), n in by_model_fails.items() if v == "2.1.263" and mm == m and h >= "09")
    print(f"  {m:<26} before {pre_f:>4}/{pre:<5}  from09 {post_f:>4}/{post:<5}")

print()
print(f"Failures on tools outside the denominator, excluded from every count above: "
      f"{sum(outside.values())} {dict(sorted(outside.items()))}")
