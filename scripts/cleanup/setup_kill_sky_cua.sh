#!/bin/bash
# Watchdog that kills OpenAI's Sky Computer Use helpers (macOS only).
#
# SkyComputerUseService (com.openai.sky.CUAService, bundled inside ChatGPT.app /
# Codex desktop and installed to ~/.codex/computer-use) bulk-copies app
# accessibility hierarchies (AXXMIGCopyHierarchy), forcing victim apps into
# synchronous main-thread work — system-wide typing lag at low CPU. Upstream
# bugs (openai/codex #25744, #29157, #37420) leak helpers and re-add the
# config.toml `notify` hook after removal, so source-level disabling regresses.
# This LaunchAgent is the guarantee: kill on load and every 30s.
#
# The plist invokes pkill directly (no repo-path dependency), so it keeps
# working if the dotfiles checkout moves. pkill exits 1 when nothing matched;
# that is the normal idle case, not a failure.
#
# THE PATTERN ROTS SILENTLY WHEN UPSTREAM RENAMES A HELPER, so it is pinned by
# tests/test_kill_sky_cua_pattern.sh. ChatGPT.app 26.915.31945 (installed
# 2026-09-18 17:28) moved the helper from SkyComputerUseService to
# Contents/Resources/cua_node/bin/node{,_repl}. The old pattern then matched
# nothing and the watchdog became a no-op: its log shows a last kill at
# 2026-09-18 16:42 PDT and zero kills afterwards, while eight cua_node
# processes ran free for two days.
#
# Found while investigating a whole-desktop freeze on 2026-09-20, but NOT its
# cause: the unified log for that window clears this helper entirely, showing
# an input-path stall in WindowServer whose sender the log never names. See
# ~/vault/tooling/dotfiles/desktop-freeze-2026-09-20.md. The exposure fixed
# here is real and independent of that incident.
#
# Nothing warns when pkill stops matching, so the test is the only guard: add
# a new path here AND to the test.
set -euo pipefail

LABEL="com.user.kill-sky-cua"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
# Matches, in order: the pre-2026-09-18 SkyComputerUseService/Client, the lock
# screen guardian, the current ChatGPT.app cua_node helpers, and the
# ~/.codex/computer-use install. Path fragments are slash-delimited so they
# cannot match ChatGPT.app's own binary or the codex CLI beside them.
PATTERN="SkyComputerUse|CUALockScreenGuardian|/cua_node/|/computer-use/"

[[ "$(uname -s)" != "Darwin" ]] && exit 0

# Uninstall first (idempotent)
launchctl unload "$PLIST" 2>/dev/null || true
[[ -f "$PLIST" ]] && rm -f "$PLIST"

if [[ "${1:-}" == "--uninstall" ]]; then
    echo "Sky Computer Use watchdog uninstalled."
    exit 0
fi

mkdir -p "$(dirname "$PLIST")"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/sh</string>
        <string>-c</string>
        <string>/usr/bin/pkill -f '$PATTERN' &amp;&amp; echo "\$(date -u +%Y-%m-%dT%H:%M:%SZ) killed Sky CUA helper(s)"; exit 0</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>30</integer>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/$LABEL.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/$LABEL.log</string>
</dict>
</plist>
EOF

launchctl load "$PLIST"
echo "Sky Computer Use watchdog installed (kills on login + every 30s)."
