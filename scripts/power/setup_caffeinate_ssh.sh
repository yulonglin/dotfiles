#!/usr/bin/env zsh
# Keeps this Mac awake for remote ssh/mosh sessions, on AC only (macOS).
#
# The 1-minute idle timer on this machine was set for screen LOCK, but pmset's
# `sleep` key took it too, so the whole machine suspended after a minute and cut
# off every ssh session. Display sleep and lock are configured separately, so
# holding the system awake costs nothing there — the screen still turns off and
# locks on its own schedule.
#
# macOS ships a guard for exactly this and it cannot work here: `ttyskeepawake`
# is already on, but man pmset defines a tty as inactive once its idle time
# exceeds the system sleep timer. With that timer at 1 minute, pausing to read
# output marks a live ssh session idle and the Mac sleeps underneath it — which
# is why sessions died while reading and survived while typing.
#
# `sudo pmset -c sleep 0` is the direct fix and needs root. This agent reaches
# the same end without it, which is the point: it can be deployed by deploy.sh
# on a machine where nobody is around to type a password.
#
# `caffeinate -s` is AC-only by construction (man caffeinate: "This assertion is
# valid only when system is running on AC power"), so the laptop still sleeps
# normally on battery. That is deliberate — do not swap it for -i, which would
# hold the machine awake unplugged and flatten the battery.
set -euo pipefail

LABEL="com.user.caffeinate-ssh"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

[[ "$(uname -s)" != "Darwin" ]] && exit 0

# Uninstall first, so a re-run always converges on the current definition.
# bootout is the modern spelling; unload covers an agent installed before the
# switch. Both are noisy when nothing is loaded, hence the redirects.
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl unload "$PLIST" 2>/dev/null || true
[[ -f "$PLIST" ]] && rm -f "$PLIST"

if [[ "${1:-}" == "--uninstall" ]]; then
    echo "caffeinate-ssh agent uninstalled; this Mac will sleep on its pmset schedule again."
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
        <string>/usr/bin/caffeinate</string>
        <string>-s</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/$LABEL.log</string>
</dict>
</plist>
EOF

# caffeinate holds its assertion only while the process lives, so KeepAlive is
# what makes this survive a kill; RunAtLoad covers login. Together they mean the
# assertion is present whenever the user is logged in.
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "caffeinate-ssh agent installed: this Mac stays awake on AC, still sleeps on battery."
