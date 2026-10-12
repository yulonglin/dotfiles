#!/usr/bin/env zsh
# Stop macOS asking again for Documents, Downloads and Desktop after every Claude Code update.
# Builds tools/tcc-carry-claude to a fixed path and installs a LaunchAgent that runs it
# whenever ~/.local/share/claude/versions changes, plus every five minutes as a fallback.
# The helper needs Full Disk Access, which only you can grant: this script prints how.
# Background: docs/claude-code-tcc-prompts.md
#
#   setup_tcc_carry_claude.sh              build, install and load the agent
#   setup_tcc_carry_claude.sh --uninstall  unload the agent and move its plist aside
set -euo pipefail

DOT_DIR="${0:A:h:h:h}"
LABEL="com.user.tcc-carry-claude"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SRC="$DOT_DIR/tools/tcc-carry-claude/main.swift"
# Outside ~/code so a sandboxed agent cannot replace the binary that holds Full Disk Access.
# A rebuild changes its code hash, and macOS then drops the grant until you re-add it.
BIN="$HOME/.local/libexec/tcc-carry-claude/tcc-carry-claude"
STATE_DIR="$HOME/.local/state/tcc-carry-claude"
VERSIONS_DIR="$HOME/.local/share/claude/versions"

uninstall() {
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    if [[ -f "$PLIST" ]]; then
        mv "$PLIST" "$PLIST.disabled"
        print "Moved the LaunchAgent to $PLIST.disabled"
    fi
}

if [[ "$(uname -s)" != Darwin ]]; then
    print "tcc-carry-claude is macOS-only. Skipping."
    exit 0
fi

if [[ "${1:-}" == --uninstall ]]; then
    uninstall
    print "Remove $BIN from Full Disk Access in System Settings if you no longer want it there."
    exit 0
fi

mkdir -p "${BIN:h}" "$STATE_DIR" "${PLIST:h}"
rebuilt=false
if [[ ! -x "$BIN" || "$SRC" -nt "$BIN" ]]; then
    swiftc -O -o "$BIN" "$SRC"
    rebuilt=true
fi

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN</string>
    </array>
    <key>WatchPaths</key>
    <array>
        <string>$VERSIONS_DIR</string>
    </array>
    <key>StartInterval</key>
    <integer>300</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$STATE_DIR/agent.log</string>
    <key>StandardErrorPath</key>
    <string>$STATE_DIR/agent.log</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
print "Loaded $LABEL; it logs to $STATE_DIR/agent.log"

if [[ "$rebuilt" == true ]]; then
    print
    print "Grant Full Disk Access to the helper (needed once per build):"
    print "  1. System Settings > Privacy & Security > Full Disk Access"
    print "  2. Click +, press Cmd+Shift+G, paste: $BIN"
    print "  3. Then run: launchctl kickstart gui/$(id -u)/$LABEL"
fi
