# aliases/net.sh — network/SSH/system utilities, DNS, VPN, diagnostics, server helpers

#-------------------------------------------------------------
# System utilities
#-------------------------------------------------------------

# Flush DNS cache
if [[ "$(uname)" == "Darwin" ]]; then
    alias flush='dscacheutil -flushcache && killall -HUP mDNSResponder'
    alias afk='pmset displaysleepnow'
else
    alias flush='sudo resolvectl flush-caches'
fi

# ISO week number
alias week='date +%V'

# Fix corrupted terminal state (preserves scrollback, unlike `reset`)
alias fix-term='_reset_terminal_modes'

# VPN split tunneling
alias vpn-status='tailscale-route-fix status'
alias vpn-fix='sudo tailscale-route-fix once'

# Supply chain: manual dependency audit
alias dep-audit='"$DOT_DIR/scripts/security/audit_dependencies.sh"'

# Supply chain defense: socket wraps npm/npx with security scanning
if command -v socket &>/dev/null; then
    alias npm="socket npm"
    alias npx="socket npx"
fi

# Mosh: preserve scrollback by skipping alternate screen init
alias mosh='mosh --no-init'

# SSH wrapper: nudge towards et/mosh for interactive sessions
# Neither is a drop-in replacement (different ports, tunnel syntax, no -i/-L/-D flags),
# so we only nudge when it looks like a plain interactive connection.
ssh() {
    if [[ -t 1 && $# -ge 1 ]]; then
        # Check for flags that indicate non-interactive use (forwarding, proxy, etc.)
        local interactive=true
        local arg
        for arg in "$@"; do
            case "$arg" in
                -N|-W|-L|-D|-R|-f|-G) interactive=false; break ;;
                -[A-Za-z]*[NWLDRF]*) interactive=false; break ;;  # combined flags like -fNL
            esac
        done
        if $interactive; then
            local host="${@: -1}"
            local alts=()
            command -v mosh &>/dev/null && alts+=("mosh $host")
            command -v et &>/dev/null && alts+=("et $host")
            if [[ ${#alts[@]} -gt 0 ]]; then
                local IFS=', '
                printf '\033[33m⚠ Persistent session? %s\033[0m\n' "${alts[*]}" >&2
            fi
        fi
    fi
    command ssh "$@"
}

# SSH theme switching moved to config/ssh_themes.sh (sourced by zshrc.sh)

#-------------------------------------------------------------
# Network diagnostics — video/audio call troubleshooting
#-------------------------------------------------------------

# Quick connectivity + saturation snapshot. Run when a call is choppy.
netcheck() {
    echo "=== Connectivity (ping 1.1.1.1) ==="
    ping -c 5 -i 0.2 1.1.1.1 2>/dev/null | tail -3
    echo
    echo "=== VPN tunnels / processes ==="
    local _vpn_tunnels
    if [[ "$(uname)" == "Darwin" ]]; then
        _vpn_tunnels=$(ifconfig 2>/dev/null | grep -E "^(utun|ipsec|tun)" | sed 's/:.*//' | sort -u)
    else
        _vpn_tunnels=$(ip -o link show 2>/dev/null | awk -F': ' '/(tun|wg|nordlynx)/ {print $2}')
    fi
    [[ -n "$_vpn_tunnels" ]] && echo "$_vpn_tunnels" || echo "  (no tunnels)"
    pgrep -lf -i "nordvpn|nordlynx|wireguard|openvpn|tailscale" 2>/dev/null \
        || echo "  (no VPN processes)"
    echo
    if [[ "$(uname)" == "Darwin" ]]; then
        echo "=== Top network talkers (1s sample) ==="
        # -P per-process; -L CSV output; -j include only these columns; -t per interface.
        # Output: time,interface,bytes_in,bytes_out — sort by bytes_in desc.
        nettop -P -L 1 -j bytes_in,bytes_out -t wifi -t wired 2>/dev/null \
            | sort -t, -k3 -h -r 2>/dev/null | head -12
        echo
        echo "=== Wi-Fi link ==="
        # airport -I deprecated in macOS 14.4+. Try it first (fast), fall back to system_profiler.
        local airport=/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport
        if [[ -x "$airport" ]] && "$airport" -I 2>/dev/null | grep -qE "agrCtlRSSI|state:"; then
            "$airport" -I 2>/dev/null | grep -E "agrCtlRSSI|agrCtlNoise|lastTxRate|channel|state"
        else
            system_profiler SPAirPortDataType 2>/dev/null \
                | grep -E "Channel|Signal / Noise|Tx Rate|PHY Mode" | head -8
        fi
    fi
}

# Live latency monitor — run in a side pane during a call.
# Timeouts/spikes correlate with audio drops → confirmed network.
# Clean ping but bad audio → mic, Bluetooth, or the other end.
alias netwatch='ping -i 0.5 1.1.1.1'
alias netwatch-google='ping -i 0.5 8.8.8.8'

#-------------------------------------------------------------
# srv — Hetzner server (hn) helpers: mount, sync, remote git
#-------------------------------------------------------------
# rclone mount for ad-hoc browsing of server files; rsync for bulk
# data pulls (no FUSE overhead); ssh exec for git on server-side clones.
# Requires: brew install --cask macos-fuse-t && brew install rclone
# Setup once: rclone config  (create sftp remote named 'hn' pointing at ~/.ssh/config Host hn)

srv() {
    local cmd="${1:-help}"
    [ $# -gt 0 ] && shift
    case "$cmd" in
        mount)
            local name=${1:?Usage: srv mount <project> [remote-path]}
            local remote=${2:-/home/yulong/projects/$name}
            local mnt=$HOME/mnt/$name
            if mount | grep -q " on $mnt "; then
                echo "already mounted: $mnt"
                return 0
            fi
            mkdir -p "$mnt" "$HOME/.cache"
            rclone mount "hn:$remote" "$mnt" \
                --vfs-cache-mode full \
                --vfs-cache-max-age 24h \
                --dir-cache-time 60s \
                --log-file="$HOME/.cache/rclone-mount-$name.log" \
                --daemon \
                && echo "mounted: hn:$remote -> $mnt"
            ;;
        umount|unmount)
            local name=${1:?Usage: srv umount <project>}
            umount "$HOME/mnt/$name" && echo "unmounted: $HOME/mnt/$name"
            ;;
        pull)
            # Bulk pull from server -> local clone (no mount needed)
            local name=${1:?Usage: srv pull <project> [subpath]}
            local subpath=${2:-code/out/}
            rsync -av --progress \
                "hn:/home/yulong/projects/$name/$subpath" \
                "$HOME/projects/$name/$subpath"
            ;;
        git)
            # Run git on server-side clone: srv git <project> pull --rebase
            local name=${1:?Usage: srv git <project> <git-args...>}
            shift
            ssh hn "cd ~/projects/$name && git $*"
            ;;
        list|ls)
            mount | grep rclone || echo "no rclone mounts"
            ;;
        log)
            local name=${1:?Usage: srv log <project>}
            tail -f "$HOME/.cache/rclone-mount-$name.log"
            ;;
        help|*)
            cat <<'EOF'
srv — Hetzner server (hn) helpers

  srv mount   <project> [remote-path]  Mount via rclone (default remote: /home/yulong/projects/<project>)
  srv umount  <project>                Unmount
  srv pull    <project> [subpath]      Bulk rsync server -> local clone (default subpath: code/out/)
  srv git     <project> <git-args...>  Run git on server-side clone (e.g. srv git foo pull --rebase)
  srv list                             Show active rclone mounts
  srv log     <project>                Tail rclone mount log

Notes:
  - Mount survives shell exit (--daemon) but NOT laptop sleep — if it goes stale: srv umount X && srv mount X
  - New server-side files take up to 60s to appear in mount (--dir-cache-time)
  - For lots of small reads (rg, grep -r), prefer pulling into local clone first
EOF
            ;;
    esac
}
