#!/usr/bin/env bash
# SessionStart hook: say so when an LLM council seat is DEAD, or when the roster
# is overdue for review.
#
# The point of this hook is that a report nobody reads is not a reminder. The
# fortnightly council-roster.timer writes its finding to
# ~/.local/state/council-roster/ and stops there; without something that
# surfaces it at the start of a session, the roster would go stale exactly as
# silently as the model slugs it exists to keep fresh.
#
# The dead-seat branch exists because of 2026-09-16: `openrouter-cli council
# ask` hung for its full ten-minute timeout and returned nothing -- no output,
# no error, no row in the call log, nothing billed -- because `qwen/qwen3.8-max`
# had been retired from the OpenRouter catalogue. The fortnightly check HAD
# found it the day before and written it to a report file nothing reads, and
# this hook stayed silent because it compared one date: 11 days of a 14-day
# review period, so a retired seat could hang every council call for another
# three days without a word.
#
# Deliberately CHEAP and OFFLINE. It reads a date and a JSON verdict that the
# scheduled check already wrote. It does NOT fetch the catalogue or the
# capability index, and it never invokes `openrouter-cli`: a session-start hook
# that makes a network call delays every session for a check that is only
# actionable a couple of times a month.
#
# The verdict is reconciled against the CONFIGURED slugs before anything is
# said, so the nudge goes quiet the moment `council refresh --apply` reseats the
# roster, rather than repeating a fixed finding until the next scheduled run.
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

command -v python3 >/dev/null 2>&1 || exit 0

# COUNCIL_CONFIG overrides the path so the overdue branch can be tested without
# backdating the real config (which would fire the nudge in every live session).
# COUNCIL_LIVENESS is the same override on the other file, and is the variable
# the CLI writes through, so one name redirects both ends.
CONFIG="${COUNCIL_CONFIG:-$HOME/code/dotfiles/config/openrouter-models.toml}"
LIVENESS="${COUNCIL_LIVENESS:-${XDG_STATE_HOME:-$HOME/.local/state}/council-roster/liveness.json}"
[ -r "$CONFIG" ] || exit 0

# stdin is consumed so the hook never blocks a writer on a full pipe.
cat >/dev/null 2>&1 || true

MSG=$(CONFIG="$CONFIG" LIVENESS="$LIVENESS" python3 <<'PY' 2>/dev/null
import datetime, json, os, sys, tomllib

try:
    with open(os.environ["CONFIG"], "rb") as fh:
        cfg = tomllib.load(fh)
except (OSError, ValueError):
    sys.exit(0)
if not isinstance(cfg, dict):
    sys.exit(0)

council = cfg.get("council") or {}
seats = council.get("seats") or []
parts = []


def configured() -> dict[str, str]:
    """Every slug this config can spend money on, mapped to its alias.

    Seats, chair and off-roster `[[models]]` alike: the chair breaks every
    fusion call when it rots, which is how the old `judge` slug rotted
    unnoticed in the first place.
    """
    out = {}
    chair = council.get("chair")
    if isinstance(chair, str):
        out[chair] = "chair"
    for group in (seats, cfg.get("models") or []):
        if not isinstance(group, list):
            continue
        for m in group:
            if isinstance(m, dict) and isinstance(m.get("slug"), str):
                out[m["slug"]] = str(m.get("alias") or "")
    return out


def dead_seats() -> list[str]:
    """Recorded-dead slugs that are STILL configured, newest verdict first."""
    try:
        with open(os.environ["LIVENESS"]) as fh:
            rec = json.load(fh)
    except (OSError, ValueError):
        return []
    if not isinstance(rec, dict):
        return []
    live_cfg = configured()
    lines, roles = [], set()
    for d in rec.get("dead") or []:
        if not isinstance(d, dict):
            continue
        slug = d.get("slug")
        # Reconciled against the config, not reported as recorded. A verdict
        # naming a slug that has since been reseated is history, not a fault,
        # and repeating it for a fortnight is how a nudge trains its reader to
        # ignore it.
        if not isinstance(slug, str) or slug not in live_cfg:
            continue
        alias = d.get("alias") or live_cfg[slug] or "?"
        role = str(d.get("role") or "?")
        roles.add(role)
        lines.append(f"  - {role} `{alias}` -> {slug}")
    if not lines:
        return []

    # The fix differs by role, and telling a reader to run the wrong one wastes
    # the nudge: `council refresh --apply` rewrites ONLY the auto-managed seats
    # block and the `reviewed` stamp. A dead chair or a dead off-roster
    # `[[models]]` entry survives it untouched, and the command answers "roster
    # matches the indices" while the model is still unusable.
    fix = []
    if "seat" in roles:
        fix.append("  Fix now: `openrouter-cli council refresh --apply`, then"
                   " commit the config.")
    if roles - {"seat"}:
        fix.append("  The chair and the off-roster `[[models]]` entries are NOT"
                   " rewritten by a refresh -- edit the slug in"
                   " config/openrouter-models.toml by hand.")
    fix.append("  Confirm with `openrouter-cli models --check`.")

    when = ""
    stamp = rec.get("checked_at")
    if isinstance(stamp, str):
        try:
            seen = datetime.datetime.strptime(stamp, "%Y-%m-%dT%H:%M:%SZ").replace(
                tzinfo=datetime.timezone.utc)
            age = (datetime.datetime.now(datetime.timezone.utc) - seen).days
            when = f" (recorded {age}d ago)"
        except ValueError:
            when = ""
    return [
        f"LLM council: a configured model is no longer in the OpenRouter"
        f" catalogue{when}. The 2026-09-16 shape: `council ask` hung for its"
        " full ten-minute timeout and returned nothing -- no error, no row in"
        " the call log, nothing billed:",
        *lines,
        *fix,
    ]


parts += dead_seats()

stamp, due = council.get("reviewed"), int(council.get("review_days") or 14)
if stamp:
    try:
        when = datetime.date.fromisoformat(str(stamp))
    except ValueError:
        when = None
    if when is not None:
        age = (datetime.date.today() - when).days
        if age > due:
            # Read `basis`, not the score magnitude: with two indices the scores
            # are normalised, so a real measurement can legitimately be 0.0.
            # "newest-in-line" is the seat resting on recency alone -- the least
            # evidence on the roster.
            unscored = [s.get("alias", "?") for s in seats
                        if isinstance(s, dict) and s.get("basis") == "newest-in-line"]
            extra = (f" {len(unscored)} seat(s) unscored ({', '.join(unscored)})."
                     if unscored else "")
            parts.append(
                f"The LLM council roster was last reviewed {age} days ago (every"
                f" {due} days).{extra} Run `openrouter-cli council roster --check`"
                " to see whether the capability indices have moved, then"
                " `openrouter-cli council refresh --apply` and commit the result."
                " Do this only if the user's current task does not take priority."
            )

if not parts:
    sys.exit(0)
print("\n".join(parts))
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
