"""Separate the gateway rewire from the CLI upgrade as the cause of the 09-06 failures.

Both changed on 2026-09-06: the model-router gateway was rewired, and 2.1.263
arrived. The gateway is a per-machine setting, so it was on for EVERY session
that day whatever its CLI version; the CLI version varies within the day. So if
the day's failures fall only on 2.1.263 sessions while 2.1.260/261 sessions made
bound calls and did not fail, the CLI upgrade is the better explanation and the
gateway story is confounded. If both versions fail at similar rates, the gateway
(or something else machine-wide) is.

Counts one failure per tool_use id and one bound call per tool_use id, grouped by
(day, cli_version, session_model). Session model is the newest assistant model
seen earlier in the same file, matching what claude-usage-audit records.
"""
import json
import re
from collections import Counter
from pathlib import Path

RE = re.compile(
    r"([A-Za-z0-9][A-Za-z0-9._-]{0,120}(?:\[1m\])?) is temporarily unavailable "
    r"\(([^()\r\n]+)\), so auto mode"
)
BOUND = {"Bash", "PowerShell", "Monitor", "Agent", "Task"}
DAYS = {"2026-09-05", "2026-09-06", "2026-09-07", "2026-09-08", "2026-09-09", "2026-09-10"}

calls = Counter()   # (day, version, model) -> n
fails = Counter()   # (day, version, model) -> n
hours = {}          # (day, version) -> [hour, ...] of bound calls
seen_calls, seen_fails = set(), set()

for path in Path.home().joinpath(".claude/projects").rglob("*.jsonl"):
    model = None
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
            day = (e.get("timestamp") or "")[:10]
            if day not in DAYS:
                if e.get("type") == "assistant":
                    m = e.get("message")
                    if isinstance(m, dict) and isinstance(m.get("model"), str):
                        model = m["model"]
                continue
            version = e.get("version") if isinstance(e.get("version"), str) else "unknown"
            msg = e.get("message")
            if not isinstance(msg, dict):
                continue
            if e.get("type") == "assistant":
                if isinstance(msg.get("model"), str):
                    model = msg["model"]
                for b in msg.get("content") or []:
                    if (isinstance(b, dict) and b.get("type") == "tool_use"
                            and b.get("name") in BOUND and b.get("id") not in seen_calls):
                        seen_calls.add(b.get("id"))
                        calls[(day, version, model)] += 1
                        hours.setdefault((day, version), []).append((e.get("timestamp") or "")[11:13])
            elif e.get("type") == "user":
                for b in msg.get("content") or []:
                    if (isinstance(b, dict) and b.get("type") == "tool_result"
                            and b.get("is_error") is True and isinstance(b.get("content"), str)):
                        if RE.match(b["content"]) and b.get("tool_use_id") not in seen_fails:
                            seen_fails.add(b.get("tool_use_id"))
                            fails[(day, version, model)] += 1

print(f"{'day':<12}{'cli':<10}{'session model':<26}{'bound':>7}{'fails':>7}{'per100':>8}")
for key in sorted(set(calls) | set(fails), key=lambda k: (k[0], str(k[1]), str(k[2]))):
    n, f = calls[key], fails[key]
    rate = f"{100 * f / n:.1f}" if n else "n/a"
    print(f"{key[0]:<12}{str(key[1]):<10}{str(key[2]):<26}{n:>7}{f:>7}{rate:>8}")

print()
print("Hour span of bound calls per (day, cli) — to check whether a version's calls")
print("all fall before or after an event within the day:")
for key in sorted(hours):
    hs = sorted(hours[key])
    print(f"  {key[0]}  {key[1]:<10} hours {hs[0]}..{hs[-1]}  distinct {len(set(hs))}  n {len(hs)}")

print()
print("Per day, collapsed over session model:")
by_dv_c, by_dv_f = Counter(), Counter()
for (d, v, _), n in calls.items():
    by_dv_c[(d, v)] += n
for (d, v, _), n in fails.items():
    by_dv_f[(d, v)] += n
for key in sorted(set(by_dv_c) | set(by_dv_f)):
    n, f = by_dv_c[key], by_dv_f[key]
    rate = f"{100 * f / n:.1f}" if n else "n/a"
    print(f"  {key[0]}  {key[1]:<10} bound {n:>6}  fails {f:>5}  per100 {rate:>6}")
