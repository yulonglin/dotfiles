#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# Tailscale + NordVPN Split Tunnel Fix (routes + pf firewall)
# ═══════════════════════════════════════════════════════════════════════════════
# NordVPN and Tailscale conflict in two independent ways; this daemon fixes both:
#
#   1. Routes (CGNAT collision): when NordVPN assigns a CGNAT address
#      (100.64.0.0/10, some servers/protocols), its /10 route swallows
#      Tailscale traffic. Fix: inject more-specific routes for Tailscale.
#
#   2. pf leak firewall: whenever connected, NordVPN's root helper replaces the
#      main pf ruleset with default-deny leak protection (`block drop all`,
#      pass only its own utun and its helper's root:nordvpn_helper sockets on
#      the physical interface). This drops ALL Tailscale traffic — control
#      plane / DERP / WireGuard on the physical interface AND tailnet data on
#      Tailscale's utun. It is independent of the app's "Apps Kill Switch"
#      toggle and has no UI. Fix: load pass-quick rules into the
#      `main/tailscale` sub-anchor — Nord's ruleset evaluates `anchor "main/*"`
#      before its block, and per pf.conf(5) quick rules inside a nested anchor
#      abort evaluation of the enclosing ruleset, so our passes win without
#      modifying Nord's rules. Nord may flush the anchor on reconnect; the
#      route-monitor events + 60s heartbeat re-load it.
#
# Leak-protection tradeoff: the pass rules open outbound TCP 443 and
# Tailscale's UDP ports on the physical interface. Normal app traffic still
# routes via NordVPN's tunnel; only processes that deliberately bind the
# physical interface can use these holes.
#
# Usage:
#   tailscale-route-fix status    # Show current VPN state, routes, pf state
#   tailscale-route-fix once      # Apply fixes once (requires sudo)
#   tailscale-route-fix watch     # Event-driven daemon via route monitor
#   tailscale-route-fix uninstall # Remove launchd daemon and system script
#
# Alternative: Switch NordVPN to IKEv2/IPsec (Settings > VPN Protocol) to avoid
# the CGNAT collision entirely (~10-20% speed trade-off vs NordLynx) — does NOT
# help with the pf firewall.
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

CGNAT_NET="100.64.0.0/10"
MAGICDNS="100.100.100.100"
LOG_PREFIX="[tailscale-route-fix]"
PLIST_LABEL="com.dotfiles.tailscale-route-fix"
PLIST_PATH="/Library/LaunchDaemons/${PLIST_LABEL}.plist"
SYSTEM_SCRIPT="/usr/local/bin/tailscale-route-fix"
PF_ANCHOR="main/tailscale"
PF_SIG_FILE="/var/run/tailscale-route-fix.pfsig"
WG_FALLBACK_PORT=41641

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
    /inet 100\.(6[4-9]|[7-9][0-9]|10[0-9]|11[0-9]|12[0-7])\./ && /netmask 0xff[c-f]00000/ {
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

# ─── pf Firewall Helpers (NordVPN leak protection) ──────────────────────────

nordvpn_pf_block_active() {
  # Nord's helper loads a "NordVPN" anchor and a default-deny main ruleset.
  # Both must be present to count as "Nord's leak firewall is active".
  pfctl -sA 2>/dev/null | grep -q 'NordVPN' && \
  pfctl -sr 2>/dev/null | grep -q '^block drop all'
}

detect_physical_if() {
  local iface
  # Prefer the interface Nord's own helper-whitelist rule names
  # (e.g. "pass on en0 all user = 0 group = 101 ...")
  iface=$(pfctl -sr 2>/dev/null | sed -n 's/^pass on \([a-z0-9]*\) all user = 0 .*/\1/p' | head -1)
  if [[ -z "$iface" ]]; then
    iface=$(echo "show State:/Network/Global/IPv4" | scutil 2>/dev/null | awk '/PrimaryInterface/ { print $3 }')
  fi
  echo "${iface:-en0}"
}

detect_tailscale_udp_ports() {
  # Tailscale's UDP sockets (WireGuard + STUN). The App Store variant may bind
  # a random port, so detect from live sockets rather than assuming 41641.
  lsof -nP -iUDP +c 0 2>/dev/null | awk '
    /[Tt]ailscale|IPNExtension/ {
      if (match($NF, /:[0-9]+$/)) print substr($NF, RSTART + 1)
    }
  ' | sort -un | head -8
}

pf_build_rules() {
  local ts_if="$1" phys_if="$2"
  shift 2
  # Tailnet data + MagicDNS on Tailscale's own tunnel; SYN rule for new TCP,
  # flags-any rule so mid-stream packets still pass after an anchor reload.
  printf '%s\n' \
    "pass quick on $ts_if all keep state" \
    "pass quick on $ts_if proto tcp all flags any keep state" \
    "pass out quick on $phys_if proto tcp from any to any port 443 flags any keep state"
  # Control plane + DERP need TCP 443 out on the physical interface; WireGuard/
  # STUN need Tailscale's UDP ports both ways, scoped to those exact ports.
  local p
  for p in "$@"; do
    printf '%s\n' \
      "pass out quick on $phys_if proto udp from any port $p to any keep state" \
      "pass in quick on $phys_if proto udp from any to any port $p keep state"
  done
}

check_and_fix_pf() {
  if ! nordvpn_pf_block_active; then
    # Nord's firewall gone (disconnected/uninstalled) — retire our anchor
    if [[ -f "$PF_SIG_FILE" ]]; then
      pfctl -a "$PF_ANCHOR" -F rules 2>/dev/null || true
      rm -f "$PF_SIG_FILE"
      echo "$LOG_PREFIX $(date '+%Y-%m-%d %H:%M:%S') NordVPN pf firewall gone — flushed $PF_ANCHOR anchor"
    fi
    return 0
  fi

  local ts_if
  ts_if=$(detect_tailscale_if || true)
  [[ -z "$ts_if" ]] && return 0  # No Tailscale — nothing to whitelist

  local phys_if ports sig
  phys_if=$(detect_physical_if)
  ports=$(detect_tailscale_udp_ports)
  [[ -z "$ports" ]] && ports="$WG_FALLBACK_PORT"
  sig="$ts_if $phys_if ${ports//$'\n'/ }"

  # Idempotency: skip reload when parameters unchanged and anchor still loaded
  # (pf states survive a rule reload, so reloading is cheap but noisy).
  if [[ "$(cat "$PF_SIG_FILE" 2>/dev/null)" == "$sig" ]] && \
     pfctl -a "$PF_ANCHOR" -sr 2>/dev/null | grep -q .; then
    return 0
  fi

  echo "$LOG_PREFIX $(date '+%Y-%m-%d %H:%M:%S') NordVPN pf firewall active — loading $PF_ANCHOR pass rules ($sig)"
  # shellcheck disable=SC2086  # word splitting of port list is intentional
  if pf_build_rules "$ts_if" "$phys_if" $ports | pfctl -q -a "$PF_ANCHOR" -f - 2>/dev/null; then
    echo "$sig" > "$PF_SIG_FILE"
    echo "$LOG_PREFIX pf pass rules loaded into $PF_ANCHOR"
  else
    echo "$LOG_PREFIX ERROR: failed to load pf rules into $PF_ANCHOR"
    return 1
  fi
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

  echo "=== NordVPN pf Leak Firewall ==="
  if [[ $EUID -ne 0 ]]; then
    echo "  (run with sudo to inspect pf state)"
  elif nordvpn_pf_block_active; then
    echo "  Nord default-deny ruleset: ACTIVE"
    local anchor_rules
    anchor_rules=$(pfctl -a "$PF_ANCHOR" -sr 2>/dev/null | grep -c . || true)
    if [[ "${anchor_rules:-0}" -gt 0 ]]; then
      echo "  Tailscale pass anchor ($PF_ANCHOR): loaded ($anchor_rules rules)"
    else
      echo "  Tailscale pass anchor ($PF_ANCHOR): NOT loaded — Tailscale is blocked"
      echo "  Run: sudo $0 once"
    fi
  else
    echo "  Nord default-deny ruleset: not present"
  fi
  echo ""

  echo "=== Verdict ==="
  if [[ -z "$ts_if" ]]; then
    echo "  Tailscale not running — nothing to fix"
  elif [[ -z "$nord_if" ]] && ! { [[ $EUID -eq 0 ]] && nordvpn_pf_block_active; }; then
    echo "  NordVPN not running — no conflict"
  elif is_routing_correct "$ts_if" || [[ -z "$nord_if" ]]; then
    echo "  Routes OK; check pf section above for firewall state"
  else
    echo "  CONFLICT: CGNAT traffic routes through $cgnat_if (should be $ts_if)"
    echo "  Run: sudo $0 once"
  fi
}

cmd_once() {
  check_and_fix_routes
  check_and_fix_pf
}

cmd_watch() {
  echo "$LOG_PREFIX Starting event-driven watch (route monitor + 60s heartbeat)"

  # Initial fix on startup (handles NordVPN already connected at boot)
  check_and_fix_routes || echo "$LOG_PREFIX WARNING: initial route check failed, continuing"
  check_and_fix_pf || echo "$LOG_PREFIX WARNING: initial pf check failed, continuing"

  # Background heartbeat (defense-in-depth; also catches Nord flushing our
  # anchor without a route change)
  while true; do sleep 60; check_and_fix_routes || true; check_and_fix_pf || true; done &
  HEARTBEAT_PID=$!
  # shellcheck disable=SC2064  # intentional early expansion to capture PID
  trap "kill $HEARTBEAT_PID 2>/dev/null" EXIT

  # Primary: event-driven via route monitor (PF_ROUTE kernel socket).
  # Nord connect/disconnect always changes routes, so pf transitions are
  # caught here too.
  route monitor | while IFS= read -r _; do
    # Drain burst: keep reading until quiet for 1s (integer for bash 3.2 compat)
    while read -t 1 -r _; do :; done
    check_and_fix_routes || echo "$LOG_PREFIX WARNING: route check failed, will retry on next event"
    check_and_fix_pf || echo "$LOG_PREFIX WARNING: pf check failed, will retry on next event"
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

  # Retire pf pass rules (harmless no-op if never loaded)
  pfctl -a "$PF_ANCHOR" -F rules 2>/dev/null || true
  rm -f "$PF_SIG_FILE"

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
