#!/bin/bash
# macOS Sudo Extras
# Optional security hardening + persistent system tunables that require elevated privileges.
# Run manually: sudo ./scripts/macos_sudo_extras.sh

set -e

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "This script is only for macOS. Skipping..."
    exit 0
fi

if [[ $EUID -ne 0 ]]; then
    echo "This script requires sudo. Run: sudo $0"
    exit 1
fi

echo "Applying macOS security hardening..."

# Enable firewall
echo "  → Enabling firewall..."
/usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on 2>/dev/null || true
/usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on 2>/dev/null || true

# Let mosh-server accept its UDP sessions (60000-61000, one port per session).
# Without this the firewall silently drops the traffic, or raises a GUI prompt on
# the Mac's own screen — useless when the connection is coming from a phone. The
# symptom is mosh hanging at "Connecting..." AFTER the ssh handshake succeeds,
# which reads as a mosh bug rather than a firewall one. See docs/mosh-from-phone.md.
#
# Homebrew's prefix differs by architecture, so resolve rather than hardcode, and
# skip silently when mosh is not installed — this script runs on every Mac.
echo "  → Allowing mosh-server through the firewall..."
for mosh_server in /opt/homebrew/bin/mosh-server /usr/local/bin/mosh-server; do
    [[ -x "$mosh_server" ]] || continue
    /usr/libexec/ApplicationFirewall/socketfilterfw --add "$mosh_server" >/dev/null 2>&1 || true
    /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp "$mosh_server" >/dev/null 2>&1 || true
    echo "      allowed $mosh_server"
done

# Remove GarageBand (if installed)
if [[ -d "/Applications/GarageBand.app" ]]; then
    echo "  → Removing GarageBand..."
    if command -v trash &>/dev/null; then
        trash "/Applications/GarageBand.app" 2>/dev/null || rm -rf "/Applications/GarageBand.app"
    else
        rm -rf "/Applications/GarageBand.app"
    fi
fi

# Persistent sysctl tunables
# /etc/sysctl.conf is read at boot by com.apple.sysctl.plist.
# Idempotent: only appends each key if not already present.
echo "  → Configuring persistent sysctl tunables..."
SYSCTL_CONF="/etc/sysctl.conf"
touch "$SYSCTL_CONF"

set_sysctl() {
    local key="$1"
    local value="$2"
    local matching existing
    # Strip comment lines first so `# kern.tty.ptmx_max=999` doesn't count as set.
    # -F: fixed-string match so dots in keys (e.g. kern.tty.ptmx_max) aren't regex metachars.
    matching=$(grep -vE '^[[:space:]]*#' "$SYSCTL_CONF" 2>/dev/null | grep -F "${key}=" | tail -1)
    if [[ -n "$matching" ]]; then
        existing=$(echo "$matching" | cut -d= -f2- | tr -d '[:space:]')
        if [[ "$existing" == "$value" ]]; then
            echo "      ${key}=${value} already set in ${SYSCTL_CONF} — ok"
            # Safe to enforce live too: matches what's persisted.
            sysctl -w "${key}=${value}" >/dev/null 2>&1 || true
        else
            echo "      ⚠ ${key} present with value ${existing} (wanted ${value})"
            echo "      leaving ${SYSCTL_CONF} alone to preserve prior tuning"
            echo "      live value also left untouched (won't downgrade an intentionally tuned value)"
            echo "      to overwrite: edit ${SYSCTL_CONF} manually, then rerun"
        fi
    else
        echo "${key}=${value}" >> "$SYSCTL_CONF"
        echo "      added ${key}=${value} to ${SYSCTL_CONF}"
        # Apply now so it takes effect without a reboot
        sysctl -w "${key}=${value}" >/dev/null 2>&1 || true
    fi
}

# Raise pty device limit (default 511) — needed for heavy tmux / agent workloads
set_sysctl "kern.tty.ptmx_max" "999"

# ─── Sleep timer, so remote sessions survive ─────────────────────────────────
# macOS already keeps itself awake for remote logins: ttyskeepawake prevents idle
# system sleep while a tty is active. The catch, from man pmset, is that a tty
# counts as INACTIVE once its idle time exceeds the system sleep timer — so a
# short timer defeats the guard entirely. This machine shipped with `sleep 1`
# (set for screen lock, which pmset's sleep key took too), and a sixty-second
# pause to read output was enough to mark a live ssh session idle and suspend the
# Mac underneath it.
#
# Raising the AC timer is the whole fix: awake while a session is genuinely
# connected, asleep once nothing is. An always-on `caffeinate` was tried instead
# and reverted — it holds the assertion whether or not anyone is connected, so
# the machine never sleeps at all. Battery is deliberately left alone so an
# unplugged laptop still suspends promptly.
#
# Display sleep and lock are separate settings and are NOT touched here, so the
# screen still turns off and locks on its own schedule.
echo "  → Setting the AC sleep timer for remote sessions..."
configure_ac_sleep() {
    local want=30 current

    # `pmset -g custom` prints both profiles; take the sleep line under AC Power.
    current=$(pmset -g custom 2>/dev/null | awk '/AC Power/{f=1} f && $1=="sleep"{print $2; exit}')

    if [[ -z "$current" ]]; then
        echo "      could not read the current AC sleep value — leaving it alone"
        return
    fi

    # 0 means never sleep. That is already at least as awake as the target, so a
    # machine deliberately pinned to never-sleep is not quietly downgraded to 30.
    if [[ "$current" == "0" ]]; then
        echo "      AC sleep is 0 (never) — leaving prior tuning alone"
    elif (( current >= want )); then
        echo "      AC sleep is ${current}m, already >= ${want}m — ok"
    else
        pmset -c sleep "$want"
        echo "      raised AC sleep ${current}m → ${want}m"
    fi
}
configure_ac_sleep

echo "✅ Security hardening complete!"
