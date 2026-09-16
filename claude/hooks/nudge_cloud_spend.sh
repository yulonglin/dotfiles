#!/usr/bin/env bash
# SessionStart hook: surface sustained flat cloud spend found by the daily
# cloud-spend-check timer.
#
# A report under ~/.local/state that no session ever reads is not a reminder.
# The 2026-08/09 Modal incident cost $3,060 because one idle H100 billed ~$96
# a day for 30 days and nothing said so; the timer finds it, this makes it
# visible.
#
# NUDGE only -- never blocks, never exits non-zero. Silent when the report is
# clean, missing, or unreadable.
#
# Feature flag: nudges.cloud-spend (features.conf). features.conf sets
# `nudges = off` wholesale, so this flag must be listed explicitly to run.

set -uo pipefail

cat >/dev/null 2>&1 || true

HOOK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 0
if [ -r "$HOOK_DIR/hook_feature.py" ] && \
   ! python3 "$HOOK_DIR/hook_feature.py" enabled nudges.cloud-spend 2>/dev/null; then
    exit 0
fi

# Overridable so the firing branch is testable without a real report.
REPORT="${CLOUD_SPEND_REPORT:-$HOME/.local/state/cloud-spend/latest.json}"
[ -r "$REPORT" ] || exit 0

command -v python3 >/dev/null 2>&1 || exit 0

MSG=$(python3 - "$REPORT" <<'PY' 2>/dev/null
import json, sys

try:
    with open(sys.argv[1]) as fh:
        report = json.load(fh)
except (OSError, ValueError):
    raise SystemExit(0)

findings = report.get("findings") or []
if not findings:
    raise SystemExit(0)

lines = [
    "Sustained flat cloud spend -- confirm this is still intended "
    "(flat daily cost is the idle-resource signature; real work varies):"
]
for f in findings[:5]:
    lines.append(
        "  - {provider}/{profile} {resource}: ${mean}/day flat for {days}d, "
        "${total} so far, ${proj} per 30d (last billed {last})".format(
            provider=f.get("provider", "?"),
            profile=f.get("profile", "?"),
            resource=f.get("resource", "?"),
            mean=f.get("mean_daily_usd", "?"),
            days=f.get("flat_days", "?"),
            total=f.get("run_total_usd", "?"),
            proj=f.get("projected_30d_usd", "?"),
            last=f.get("last_billed_day", "?"),
        )
    )
extra = len(findings) - 5
if extra > 0:
    lines.append(f"  - ...and {extra} more")
lines.append(
    "  Check it is wanted, then stop the resource and whatever is keeping it "
    "warm. A poller faster than the scaledown window is a keep-alive."
)
print("\n".join(lines))
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
