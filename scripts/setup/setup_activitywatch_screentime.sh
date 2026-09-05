#!/usr/bin/env bash
# Set up the iPhone/iPad Screen Time importer for ActivityWatch (no background agent).
#
# Clones and syncs the official importer (github.com/ActivityWatch/aw-import-screentime),
# which reads ~/Library/Biome/streams/restricted/App.InFocus/remote/<device>/ and pushes
# per-device buckets (aw-import-screentime_ios_ios-<device_id>) to aw-server on :5600.
# Imports run on demand via `aw-screentime-import` (custom_bins) from a terminal that has
# Full Disk Access. A LaunchAgent was tried and dropped on 2026-09-04: launchd would need
# Full Disk Access on the shared uv Python, which is far too broad a grant.
#
# Requirements: Screen Time "Share Across Devices" on both devices; uv; Full Disk Access
# for the terminal you run imports from.
set -euo pipefail

LABEL="com.yulonglin.aw-import-screentime"
REPO="${AW_IMPORT_SCREENTIME_DIR:-$HOME/code/aw-import-screentime}"
REPO_URL="https://github.com/ActivityWatch/aw-import-screentime.git"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
    echo "Usage: $(basename "$0")"
    exit 0
fi

[[ "$(uname -s)" == Darwin ]] || {
    echo "Screen Time import is macOS-only" >&2
    exit 1
}
command -v uv >/dev/null || {
    echo "uv not found on PATH; install it first" >&2
    exit 1
}

# Remove the LaunchAgent from the abandoned design, if this machine still has it.
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
for stale in "$HOME/Library/LaunchAgents/$LABEL.plist" "$HOME/Library/LaunchAgents/$LABEL.plist.disabled"; do
    [[ -f "$stale" ]] && { trash "$stale" 2>/dev/null || rm -f "$stale"; echo "Removed stale $stale"; }
done

if [[ ! -d "$REPO/.git" ]]; then
    git clone --quiet "$REPO_URL" "$REPO"
fi
(cd "$REPO" && uv sync --quiet)

if (cd "$REPO" && uv run --no-sync aw-import-screentime devices >/dev/null 2>&1); then
    echo "Screen Time importer ready at $REPO. Import with: aw-screentime-import [--since 7d]"
else
    echo "Importer installed, but Screen Time data is unreadable from this terminal: grant it Full Disk Access, and check Share Across Devices" >&2
    exit 1
fi
