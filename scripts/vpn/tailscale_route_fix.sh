#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# Tailscale + NordVPN Split Tunnel Route Fix
# ═══════════════════════════════════════════════════════════════════════════════
# Both NordVPN (NordLynx/WireGuard) and Tailscale use 100.64.0.0/10 (CGNAT).
# NordVPN's /10 netmask swallows Tailscale traffic. This script injects routes
# to prioritize Tailscale for CGNAT traffic while keeping NordVPN for everything
# else.
#
# Usage:
#   tailscale-route-fix status    # Show current VPN state and routes
#   tailscale-route-fix once      # Apply fix once (requires sudo)
#   tailscale-route-fix watch     # Event-driven daemon via route monitor
#   tailscale-route-fix uninstall # Remove launchd daemon and system script
#
# Alternative: Switch NordVPN to IKEv2/IPsec (Settings > VPN Protocol) to avoid
# the CGNAT collision entirely (~10-20% speed trade-off vs NordLynx).
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

CGNAT_NET="100.64.0.0/10"
MAGICDNS="100.100.100.100"
LOG_PREFIX="[tailscale-route-fix]"
PLIST_LABEL="com.dotfiles.tailscale-route-fix"
PLIST_PATH="/Library/LaunchDaemons/${PLIST_LABEL}.plist"
SYSTEM_SCRIPT="/usr/local/bin/tailscale-route-fix"

# ─── Interface Detection ─────────────────────────────────────────────────────
# utun interfaces are dynamically numbered — detect by IP and netmask.
#   Tailscale:  inet 100.x.x.x netmask 0xffffffff  (point-to-point /32)
#   NordLynx:   inet 100.64-127.x.x netmask 0xffc00000+ (/10 or similar)

detect_tailscale_if() {
  local ts_ip
  # Prefer tailscale CLI (more reliable than netmask matching)
  ts_ip=$(tailscale ip -4 2>/dev/null) || {
    # Fallback: match by /32 netmask in CGNAT range
    ifconfig 2>/dev/null | awk '
      /^[a-z]/ { iface = $1; sub(/:$/, "", iface) }
      /inet 100\./ && /netmask 0xffffffff/ { print iface; exit }
    '
    return
  }
  [[ -z "$ts_ip" ]] && return 1
  ifconfig 2>/dev/null | awk -v ip="$ts_ip" '
    /^[a-z]/ { iface = $1; sub(/:$/, "", iface) }
    $0 ~ "inet " ip { print iface; exit }
  '
}

detect_nordvpn_if() {
  # Match CGNAT IP prefix (100.64-127.x) with broad netmask, not exact /10
  ifconfig 2>/dev/null | awk '
    /^[a-z]/ { iface = $1; sub(/:$/, "", iface) }
    /inet 100\.(6[4-9]|[7-9][0-9]|1[0-2][0-7])\./ && /netmask 0xff[c-f]/ {
      print iface; exit
    }
  '
}

# ─── Route Helpers ───────────────────────────────────────────────────────────

current_cgnat_route_if() {
  route -n get 100.64.0.0 2>/dev/null | awk '/interface:/ { print $2 }'
}

current_magicdns_route_if() {
  route -n get "$MAGICDNS" 2>/dev/null | awk '/interface:/ { print $2 }'
}

is_routing_correct() {
  local ts_if="$1"
  [[ "$(current_cgnat_route_if)" == "$ts_if" ]] && \
  [[ "$(current_magicdns_route_if)" == "$ts_if" ]]
}

# ─── Core Logic ──────────────────────────────────────────────────────────────

check_and_fix_routes() {
  local ts_if nord_if
  ts_if=$(detect_tailscale_if)
  nord_if=$(detect_nordvpn_if)

  if [[ -z "$ts_if" ]]; then
    return 0  # No Tailscale — nothing to fix
  fi

  if [[ -z "$nord_if" ]]; then
    return 0  # No NordVPN — no conflict
  fi

  if is_routing_correct "$ts_if"; then
    return 0  # Already correct
  fi

  echo "$LOG_PREFIX $(date '+%Y-%m-%d %H:%M:%S') Detected Tailscale=$ts_if, NordVPN=$nord_if — fixing routes"

  # TOCTOU check: verify interface still exists before mutating routes
  if ! ifconfig "$ts_if" &>/dev/null; then
    echo "$LOG_PREFIX ERROR: $ts_if disappeared — aborting"
    return 1
  fi

  # Delete NordVPN's /10 route, add Tailscale's (with rollback on failure)
  route delete -net "$CGNAT_NET" 2>/dev/null || true
  if ! route add -net "$CGNAT_NET" -interface "$ts_if" 2>/dev/null; then
    echo "$LOG_PREFIX ERROR: Failed to add $CGNAT_NET route — restoring NordVPN route"
    route add -net "$CGNAT_NET" -interface "$nord_if" 2>/dev/null || true
    return 1
  fi

  # Explicit MagicDNS host route
  route delete -host "$MAGICDNS" 2>/dev/null || true
  route add -host "$MAGICDNS" -interface "$ts_if" 2>/dev/null || true

  # Post-apply verification
  if is_routing_correct "$ts_if"; then
    echo "$LOG_PREFIX Routes verified (CGNAT + MagicDNS → $ts_if)"
  else
    echo "$LOG_PREFIX WARNING: Routes applied but verification failed"
  fi
}

# ─── Commands ────────────────────────────────────────────────────────────────

cmd_status() {
  local ts_if nord_if
  ts_if=$(detect_tailscale_if)
  nord_if=$(detect_nordvpn_if)

  echo "=== VPN Interface Detection ==="
  if [[ -n "$ts_if" ]]; then
    echo "  Tailscale:  $ts_if"
  else
    echo "  Tailscale:  not detected"
  fi
  if [[ -n "$nord_if" ]]; then
    echo "  NordVPN:    $nord_if"
  else
    echo "  NordVPN:    not detected"
  fi
  echo ""

  echo "=== CGNAT Route ($CGNAT_NET) ==="
  local cgnat_if
  cgnat_if=$(current_cgnat_route_if)
  if [[ -n "$cgnat_if" ]]; then
    echo "  Routed via: $cgnat_if"
  else
    echo "  No route found"
  fi
  echo ""

  echo "=== MagicDNS ($MAGICDNS) ==="
  local magic_if
  magic_if=$(current_magicdns_route_if)
  if [[ -n "$magic_if" ]]; then
    echo "  Routed via: $magic_if"
  else
    echo "  No route found"
  fi
  echo ""

  echo "=== Verdict ==="
  if [[ -z "$ts_if" ]]; then
    echo "  Tailscale not running — nothing to fix"
  elif [[ -z "$nord_if" ]]; then
    echo "  NordVPN not running — no conflict"
  elif is_routing_correct "$ts_if"; then
    echo "  OK: CGNAT traffic routes through Tailscale ($ts_if)"
  else
    echo "  CONFLICT: CGNAT traffic routes through $cgnat_if (should be $ts_if)"
    echo "  Run: sudo $0 once"
  fi
}

cmd_once() {
  check_and_fix_routes
}

cmd_watch() {
  echo "$LOG_PREFIX Starting event-driven watch (route monitor + 60s heartbeat)"

  # Initial fix on startup (handles NordVPN already connected at boot)
  check_and_fix_routes || echo "$LOG_PREFIX WARNING: initial check failed, continuing"

  # Background heartbeat (defense-in-depth)
  while true; do sleep 60; check_and_fix_routes || true; done &
  HEARTBEAT_PID=$!
  # shellcheck disable=SC2064  # intentional early expansion to capture PID
  trap "kill $HEARTBEAT_PID 2>/dev/null" EXIT

  # Primary: event-driven via route monitor (PF_ROUTE kernel socket)
  route monitor | while IFS= read -r _; do
    # Drain burst: keep reading until quiet for 300ms
    while read -t 0.3 -r _; do :; done
    check_and_fix_routes || echo "$LOG_PREFIX WARNING: check failed, will retry on next event"
  done
}

cmd_uninstall() {
  echo "$LOG_PREFIX Uninstalling..."

  if [[ -f "$PLIST_PATH" ]]; then
    launchctl bootout "system/$PLIST_LABEL" 2>/dev/null || true
    rm -f "$PLIST_PATH"
    echo "$LOG_PREFIX Removed $PLIST_PATH"
  else
    echo "$LOG_PREFIX No plist found at $PLIST_PATH"
  fi

  if [[ -f "$SYSTEM_SCRIPT" ]]; then
    rm -f "$SYSTEM_SCRIPT"
    echo "$LOG_PREFIX Removed $SYSTEM_SCRIPT"
  else
    echo "$LOG_PREFIX No script found at $SYSTEM_SCRIPT"
  fi

  rm -f /etc/newsyslog.d/tailscale-route-fix.conf
  echo "$LOG_PREFIX Uninstall complete"
}

# ─── Main ────────────────────────────────────────────────────────────────────

case "${1:-status}" in
  status)    cmd_status ;;
  once)      cmd_once ;;
  watch)     cmd_watch ;;
  uninstall) cmd_uninstall ;;
  *)
    echo "Usage: $0 {status|once|watch|uninstall}"
    exit 1
    ;;
esac
