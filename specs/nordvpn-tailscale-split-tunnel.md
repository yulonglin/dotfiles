# NordVPN + Tailscale Split Tunnel Specification

**Status**: Implemented
**Platform**: macOS only
**Created**: 2026-03-06

## Problem Statement

NordVPN's NordLynx protocol (WireGuard) assigns addresses in 100.64.0.0/10 (CGNAT)
and installs a /10 route capturing the entire block. Tailscale also uses this range
for its peer mesh. When both are active, NordVPN's route swallows Tailscale traffic,
making all Tailscale peers unreachable.

## Solution Overview

An event-driven route injection daemon that:

1. Detects when NordVPN and Tailscale interfaces coexist
2. Replaces NordVPN's /10 route with one pointing to Tailscale's interface
3. Adds an explicit /32 host route for MagicDNS (100.100.100.100)
4. Monitors the routing table for changes and re-injects as needed

Internet traffic continues to flow through NordVPN. Only CGNAT-range traffic
(Tailscale peers) is redirected.

## Architecture

### Event-Driven Detection

The daemon uses `route monitor` (PF_ROUTE kernel socket) to receive RTM_ADD/RTM_DELETE
messages whenever any process modifies the routing table. This provides sub-second
response to NordVPN reconnects or server switches.

A debounce pattern collapses burst events (NordVPN emits 4-8 RTM messages per reconnect):

```
route monitor | while read; do
    while read -t 0.3; do :; done   # drain until 300ms quiet
    check_and_fix_routes
done
```

A 60-second background heartbeat provides defense-in-depth against missed events.

### Interface Detection

| VPN | Method | Rationale |
|-----|--------|-----------|
| Tailscale | `tailscale ip -4` (preferred), ifconfig /32 fallback | CLI is authoritative; /32 netmask is unique to Tailscale |
| NordVPN | IP prefix 100.64-127.x with broad netmask match | Survives netmask changes (/8, /10, /11, /12) |

### Route Injection

The daemon MUST:

1. Delete NordVPN's existing /10 route
2. Add a /10 route pointing to Tailscale's utun interface
3. Add a /32 host route for MagicDNS (100.100.100.100)

On `route add` failure, the daemon MUST restore NordVPN's original route (rollback)
to avoid breaking both VPNs simultaneously.

### Error Handling

- **TOCTOU**: Interface existence is verified immediately before `route add`
- **Rollback**: Failed `route add` restores NordVPN's /10 route
- **Non-fatal in daemon mode**: `check_and_fix_routes` failures do not kill the daemon
- **`set -euo pipefail`**: Applies to script startup; daemon loop catches errors explicitly

## Deployment

### Install

```bash
./deploy.sh --vpn
```

Installs:
- `/usr/local/bin/tailscale-route-fix` (script, root:wheel 755)
- `/Library/LaunchDaemons/com.dotfiles.tailscale-route-fix.plist` (root:wheel 644)
- `/etc/newsyslog.d/tailscale-route-fix.conf` (log rotation)

The daemon runs as root (required for route manipulation) via launchd with
`KeepAlive: true` and `RunAtLoad: true`.

### Uninstall

`--no-vpn` skips VPN deployment; it does not uninstall an existing daemon. To fully remove:

```bash
sudo tailscale-route-fix uninstall
```

### Re-deploy

`deploy.sh --vpn` is idempotent: it runs `launchctl bootout` before `bootstrap`.

## CLI Interface

```
tailscale-route-fix <subcommand>

  status    Show current interfaces, routes, and conflict status
  once      Check and fix routes once, then exit
  watch     Run as daemon (route monitor loop) — used by launchd
  uninstall Remove daemon, script, and log rotation config
```

### Aliases

```bash
vpn-status   # → tailscale-route-fix status
vpn-fix      # → sudo tailscale-route-fix once
```

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| NordVPN not running | No NordVPN interface detected → no-op |
| Tailscale not running | No Tailscale interface detected → no-op |
| NordVPN uses IKEv2 | IKEv2 gets 10.x.x.x (not CGNAT) → no conflict → no-op |
| NordVPN server switch | `route monitor` fires → burst drained → routes re-injected |
| Both VPNs off | Daemon idles on `route monitor` |
| Boot before networking | Daemon starts, finds no interfaces, waits for events |
| `route add` fails | Rollback restores NordVPN route, logs error, continues monitoring |
| Self-triggered events | Daemon's own route changes trigger `route monitor`; `is_routing_correct` returns true → no-op |
| New Tailscale peer | Peer's /32 covered by existing /10 route → works automatically |

## Out of Scope

- Linux support (NordVPN Linux uses different CLI)
- IPv6 routing conflicts
- NordVPN kill switch interactions
- Tailscale exit node conflicts
- Multiple simultaneous VPN providers

## Acceptance Criteria

- AC-1: With NordVPN active, `tailscale ping <peer>` succeeds within 5s of NordVPN connecting
- AC-2: `curl ipinfo.io/ip` returns NordVPN exit IP (internet still routed through NordVPN)
- AC-3: `ping 100.100.100.100` succeeds (MagicDNS reachable)
- AC-4: Daemon running after `deploy.sh --vpn`: `sudo launchctl print system/com.dotfiles.tailscale-route-fix`
- AC-5: After reboot with both VPNs auto-starting, peers reachable within 15s
- AC-6: After `sudo tailscale-route-fix uninstall`, daemon fully removed, no route injection
- AC-7: NordVPN server switch → Tailscale peers recover within 5s
- AC-8: `deploy.sh --vpn` run twice succeeds without errors (idempotent)
