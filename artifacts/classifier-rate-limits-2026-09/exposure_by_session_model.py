"""Bound calls and native failures by (day, session model) for 2026-09-05..09-09.

Discriminates "gateway causes 429s for every session" from "Fable sessions'
Opus classifier is what gets throttled": if Opus/GPT sessions made many bound
calls with few failures while Fable sessions failed at a high rate, the session
model is the lever. Ad hoc; reads the same rows the audit tool reads.
"""
import json
import re
from collections import Counter, defaultdict
from pathlib import Path

RE = re.compile(r"([A-Za-z0-9][A-Za-z0-9._-]{0,120}(?:\[1m\])?) is temporarily unavailable \(([^()\r\n]+)\), so auto mode")
BOUND = {"Bash", "PowerShell", "Monitor", "Agent", "Task"}
import sys
from datetime import date, timedelta

if len(sys.argv) == 3:  # start end (inclusive), aggregated as one bucket
    start, end = date.fromisoformat(sys.argv[1]), date.fromisoformat(sys.argv[2])
    DAYS = {(start + timedelta(days=i)).isoformat() for i in range((end - start).days + 1)}
    LABEL = f"{sys.argv[1]}..{sys.argv[2]}"
else:
    DAYS = {"2026-09-05", "2026-09-06", "2026-09-07", "2026-09-08", "2026-09-09"}
    LABEL = None
calls = defaultdict(Counter)   # (day, session_model) -> tool -> n
fails = defaultdict(Counter)   # (day, session_model) -> classifier -> n
seen_calls, seen_fails = set(), set()
for path in Path.home().joinpath(".claude/projects").rglob("*.jsonl"):
    model = None
    try:
        lines = path.open(errors="replace")
    except OSError:
        continue
    with lines:
        for line in lines:
            try:
                e = json.loads(line)
            except ValueError:
                continue
            if not isinstance(e, dict):
                continue
            ts = e.get("timestamp") or ""
            day = ts[:10]
            if LABEL and day in DAYS:
                day = LABEL
            msg = e.get("message")
            if not isinstance(msg, dict):
                continue
            if e.get("type") == "assistant":
                if isinstance(msg.get("model"), str):
                    model = msg["model"]
                if (day in DAYS or day == LABEL) and isinstance(msg.get("content"), list):
                    for b in msg["content"]:
                        if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("name") in BOUND:
                            if b.get("id") in seen_calls:
                                continue
                            seen_calls.add(b.get("id"))
                            calls[(day, model)][b["name"]] += 1
            elif e.get("type") == "user" and (day in DAYS or day == LABEL) and isinstance(msg.get("content"), list):
                for b in msg["content"]:
                    if isinstance(b, dict) and b.get("type") == "tool_result" and b.get("is_error") is True and isinstance(b.get("content"), str):
                        m = RE.match(b["content"])
                        if m and b.get("tool_use_id") not in seen_fails:
                            seen_fails.add(b.get("tool_use_id"))
                            fails[(day, model)][m.group(1)] += 1

print(f"{'day':<11}{'session model':<24}{'bound':>7}{'fails':>7}{'per100':>8}  classifier")
for key in sorted(set(calls) | set(fails), key=lambda k: (k[0], str(k[1]))):
    n = sum(calls[key].values()); f = sum(fails[key].values())
    rate = f"{100*f/n:.1f}" if n else "n/a"
    print(f"{key[0]:<11}{str(key[1]):<24}{n:>7}{f:>7}{rate:>8}  {dict(fails[key])}")
