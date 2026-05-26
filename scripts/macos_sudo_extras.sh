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

echo "✅ Security hardening complete!"
