#!/usr/bin/env bash
# SessionStart hook: surface what the daily dotfiles-sync job could not do.
#
# The job (custom_bins/dotfiles-sync) writes one JSON file per repo under
# ~/.local/state/dotfiles-sync/. A failed rebase, a rejected commit or a push
# that never landed sits there silently otherwise, and a machine quietly drifts
# from the others for weeks. This hook reads those files and says so.
#
# Reports:
#   - any repo whose last run failed (conflict, rejected commit, push error)
#   - a file held back from the sync commit by the pre-commit hook
#   - commits pulled in the last 24 h, since deploy.sh is NOT run by the job
#     (symlinked claude/ is live immediately; installed copies are not)
#
# Deliberately cheap and offline: it reads a directory of small files, no git,
# no network. Advisory only and always exits 0 -- a broken reminder must never
# stop a session from starting.
#
# Feature flag: nudges.dotfiles-sync (features.conf). features.conf sets
# `nudges = off` wholesale, so this flag must be listed explicitly to run.
set -uo pipefail

HOOK_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) || exit 0
if [ -r "$HOOK_DIR/hook_feature.py" ] && \
   ! python3 "$HOOK_DIR/hook_feature.py" enabled nudges.dotfiles-sync 2>/dev/null; then
    exit 0
fi

STATE_DIR="${DOTFILES_SYNC_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-sync}"
[ -d "$STATE_DIR" ] || exit 0

# stdin is consumed so the hook never blocks a writer on a full pipe.
cat >/dev/null 2>&1 || true

MSG=$(STATE_DIR="$STATE_DIR" python3 <<'PY' 2>/dev/null
import datetime, glob, json, os, sys

now = datetime.datetime.now(datetime.timezone.utc)
lines = []
for path in sorted(glob.glob(os.path.join(os.environ["STATE_DIR"], "*.json"))):
    try:
        with open(path) as fh:
            st = json.load(fh)
        ts = datetime.datetime.strptime(st["ts"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc)
    except (OSError, ValueError, KeyError):
        continue
    age_h = (now - ts).total_seconds() / 3600
    name = st.get("repo", os.path.basename(path)[:-5])
    if st.get("status") != "ok":
        lines.append(f"{name}: last dotfiles-sync FAILED {age_h:.0f} h ago: {st.get('message', '?')}."
                     " Fix it by hand (git status there), then `dotfiles-sync` to confirm.")
        continue
    if st.get("held_back"):
        lines.append(f"{name}: {st['held_back']} was held back from the sync commit"
                     " because the pre-commit hook rejected it; commit a stripped copy"
                     " by hand if its other changes should ship (.claude/rules/dotfiles-settings.md).")
    if age_h <= 24 and int(st.get("pulled") or 0) > 0:
        lines.append(f"{name}: dotfiles-sync pulled {st['pulled']} commit(s) {age_h:.0f} h ago;"
                     " run ./deploy.sh if an installed (non-symlinked) component changed.")
if lines:
    print(" ".join(lines) + " Do this only if the user's current task does not take priority.")
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
