# Plan: NordVPN + Tailscale Split Tunneling

## Setup: Git Worktree

Create a fresh feature branch in a worktree:
```bash
git worktree add ../dotfiles-vpn -b feat/vpn-split-tunnel
```
All file creation/edits happen in `../dotfiles-vpn/`. Merge back to `main` when verified.

## Context

**Tailnet**: `taile13c17.ts.net`

Both NordVPN (NordLynx/WireGuard) and Tailscale assign IPs from the same `100.64.0.0/10` CGNAT range. When both are active, NordVPN's `/10` netmask claims the entire CGNAT block, swallowing Tailscale traffic for peers that don't have explicit `/32` host routes. Tailscale partially works because it installs per-peer `/32` routes (which beat `/10` via longest-prefix match), but MagicDNS (`100.100.100.100`) conflicts and new/unseen peers route through NordVPN.

**Goal**: Route all `100.64.0.0/10` traffic through Tailscale, everything else through NordVPN.

## Decision: Protocol Switch vs Route Injection

Two viable approaches:

| Approach | Pros | Cons |
|----------|------|------|
| **Switch NordVPN to IKEv2/OpenVPN** | Zero maintenance, no scripts needed, eliminates collision entirely | ~10-20% speed reduction vs NordLynx |
| **Route injection script + daemon** | Keeps NordLynx speed, automated via launchd | Requires sudo, polling daemon, fragile if NordVPN fights routes |

**Recommendation**: Implement the route injection approach as a dotfiles component (it's the interesting/useful one), but document the protocol switch as the simple alternative. User can choose.

## Implementation

### 1. Create `scripts/vpn/tailscale_route_fix.sh`

A script with three modes:
- `status` — Show current VPN interfaces, CGNAT routes, and whether routing is correct
- `once` — Detect interfaces by netmask signature, inject `100.64.0.0/10 → tailscale_if` route + MagicDNS `/32`
- `watch` — Poll every 5s, re-apply if NordVPN reasserts routes

Interface detection logic (reliable across reboots — interface names like `utun7`/`utun8` are dynamic):
- Tailscale: `inet 100.x.x.x` + `netmask 0xffffffff` (point-to-point `/32`)
- NordVPN NordLynx: `inet 100.x.x.x` + `netmask 0xffc00000` (`/10`)

### 2. Create `scripts/vpn/com.dotfiles.tailscale-route-fix.plist`

launchd daemon (runs as root under `/Library/LaunchDaemons/`) that starts the script in `watch` mode at boot. Logs to `/var/log/tailscale-route-fix.log`.

### 3. Add aliases to `config/aliases.sh`

```bash
alias vpn-fix='sudo ~/code/dotfiles/scripts/vpn/tailscale_route_fix.sh once'
alias vpn-status='~/code/dotfiles/scripts/vpn/tailscale_route_fix.sh status'
alias vpn-watch='sudo ~/code/dotfiles/scripts/vpn/tailscale_route_fix.sh watch'
```

### 4. Add deployment to `deploy.sh`

New `--vpn` flag (not in defaults — opt-in):
- Copy script to `/usr/local/bin/tailscale-route-fix`
- Install launchd plist to `/Library/LaunchDaemons/`
- `launchctl bootstrap system` to start the daemon

### 5. Add uninstall support

`scripts/vpn/tailscale_route_fix.sh uninstall` or `deploy.sh --vpn --uninstall`:
- `launchctl bootout system/com.dotfiles.tailscale-route-fix`
- Remove plist and script from system paths

## Files to Create/Modify

| File | Action |
|------|--------|
| `scripts/vpn/tailscale_route_fix.sh` | **Create** — main script |
| `scripts/vpn/com.dotfiles.tailscale-route-fix.plist` | **Create** — launchd daemon |
| `config/aliases.sh` | **Edit** — add `vpn-fix`, `vpn-status`, `vpn-watch` |
| `deploy.sh` | **Edit** — add `--vpn` flag + `deploy_vpn()` function |

## Traffic Flow After Fix

| Destination | Interface |
|-------------|-----------|
| `100.64.0.0/10` (all Tailscale) | Tailscale (`utun7` etc.) |
| `100.100.100.100` (MagicDNS) | Tailscale (explicit `/32`) |
| `0.0.0.0/0` (everything else) | NordVPN (`utun8` etc.) |
| LAN (`10.x.x.x/24`) | Physical (`en0`) |

## Verification

Test against tailnet `taile13c17.ts.net`:

```bash
# 1. Connect both VPNs, check current state
vpn-status

# 2. Apply fix
vpn-fix

# 3. Verify Tailscale peers reachable via tailnet
tailscale status                          # List peers on taile13c17.ts.net
tailscale ping <peer-name>               # Direct peer connectivity
ping -c 3 100.100.100.100                # MagicDNS resolver
nslookup <peer-name>.taile13c17.ts.net   # MagicDNS name resolution

# 4. Verify NordVPN still handles general traffic
curl -s https://ipinfo.io/ip             # Should show NordVPN exit IP, NOT your real IP

# 5. Verify DNS doesn't leak
# MagicDNS (100.100.100.100) should resolve tailnet names
# External DNS should route through NordVPN
nslookup example.com                     # Should use NordVPN's DNS

# 6. Reconnection resilience (if watch mode running)
# Disconnect NordVPN, reconnect, verify daemon re-applies
tail -f /var/log/tailscale-route-fix.log
vpn-status                                # Should still show correct routing
```

## Alternative (Zero-Maintenance)

If the route injection proves fragile, switch NordVPN to IKEv2: **Settings > VPN Protocol > IKEv2/IPsec**. This gives NordVPN a `10.x.x.x` address, eliminating the CGNAT collision entirely. ~10-20% speed trade-off.
