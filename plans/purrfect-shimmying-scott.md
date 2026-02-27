# Plan: NordVPN + Tailscale Split Tunneling

**Context**: When NordVPN connects using NordLynx (WireGuard), it claims the entire
100.64.0.0/10 CGNAT block as its own. Tailscale also uses this range for its peer mesh.
Result: Tailscale peers become unreachable while NordVPN is active.

**Goal**: Make Tailscale peers reliably reachable while NordVPN is running on macOS,
with no speed penalty (keep NordLynx), minimal manual steps, and automatic recovery.

---

## Evaluation Criteria

| Criterion | Weight | Why |
|-----------|--------|-----|
| NordLynx speed preserved | Must | User explicitly chose NordLynx over IKEv2 |
| Full Tailscale fix (all peers, MagicDNS, new peers) | Must | Partial fixes create confusing failure modes |
| Automatic after one-time setup | Must | User wants "setup once, then it just works" |
| Survives NordVPN reconnects / server switches | Must | NordVPN reconnects several times per day |
| Survives reboots | Must | Daemon/config must persist across boots |
| NordVPN app preserved (no CLI/Tunnelblick switch) | Should | Significant UX regression if removed |
| Response time < 10s after NordVPN connects | Should | Avoid long dead zones on reconnect |
| Zero ongoing maintenance | Should | Should survive NordVPN app updates |
| Clean dotfiles integration (deploy.sh --vpn) | Should | Consistency with existing patterns |

---

## Approach Comparison

Two worktrees were explored:

### A. Codex worktree: OpenVPN profile generation
- Generates a modified `.ovpn` file with `route-nopull` + explicit Tailscale exemptions
- Requires switching from NordVPN app → manual `openvpn` CLI or Tunnelblick
- NordVPN service credentials required (separate from regular password)
- Split routes baked into profile → works on first connect, no daemon needed

| Criterion | Score | Notes |
|-----------|-------|-------|
| NordLynx preserved | ❌ FAIL | OpenVPN protocol is ~10-20% slower than NordLynx |
| Full Tailscale fix | ✅ | Route exemptions are complete |
| Automatic after setup | ⚠️ | One-time setup, but user must remember to use openvpn/Tunnelblick |
| Survives reconnects | ✅ | Baked into profile |
| Survives reboots | ✅ | Profile persists |
| NordVPN app preserved | ❌ FAIL | Must switch to manual openvpn or Tunnelblick |
| Response time | ✅ | Immediate on connect |
| Maintenance | ⚠️ | Profile needs regeneration if NordVPN OVPN format changes |

→ **REJECTED**: Fails two Must criteria (NordLynx speed, NordVPN app).

### B. Feat worktree: Route injection + polling daemon
- Keeps NordVPN app + NordLynx
- launchd daemon polls every 5s, detects when NordVPN overwrites Tailscale routes
- Re-injects: delete NordVPN's /10 route, add Tailscale /10 route, add MagicDNS /32 route
- Deploy integration planned but not yet implemented in deploy.sh

| Criterion | Score | Notes |
|-----------|-------|-------|
| NordLynx preserved | ✅ | Works with NordVPN app |
| Full Tailscale fix | ✅ | /10 + MagicDNS /32 both fixed |
| Automatic after setup | ✅ | launchd daemon runs at boot |
| Survives reconnects | ✅ | Daemon detects and re-injects |
| Survives reboots | ✅ | launchd KeepAlive |
| NordVPN app preserved | ✅ | No changes to NordVPN usage |
| Response time | ⚠️ | Up to 5s lag on reconnect |
| Maintenance | ✅ | Route injection is stable across NordVPN updates |

→ **SELECTED**: Passes all Must criteria. One weakness: 5s polling lag.

---

## Recommended Approach: Route Injection + route monitor (event-driven)

**Upgrade the feat worktree**: Replace 5s polling with `route monitor` for event-driven detection.

### Why `route monitor`?
`route monitor` is a macOS built-in (part of `route(8)`) that emits a line to stdout every time
the routing table changes. When NordVPN connects and overwrites Tailscale routes, `route monitor`
fires immediately — enabling sub-second response time without polling overhead.

```bash
route monitor | while IFS= read -r line; do
    # Route table changed — check if Tailscale routes are correct
    if routes_need_fixing; then
        inject_tailscale_routes
    fi
done
```

This replaces the polling loop while keeping the same route injection logic.

**Tradeoff**: `route monitor` output format is unstructured text. The daemon must parse it
carefully and avoid reacting to its own route injections (could cause loop). Mitigation: debounce
check after injection (500ms sleep + re-check before re-injecting).

---

## Implementation Plan

### Files to create/modify

| File | Action | Purpose |
|------|--------|---------|
| `scripts/vpn/tailscale_route_fix.sh` | Modify (from feat worktree) | Upgrade polling → route monitor |
| `scripts/vpn/com.dotfiles.tailscale-route-fix.plist` | Use as-is from feat worktree | launchd daemon config |
| `deploy.sh` | Add --vpn deployment function | Install script + plist, load daemon |
| `config.sh` | Add DEPLOY_VPN=false | Opt-in flag |
| `config/aliases.sh` | Add vpn-* aliases | Manual override |
| `specs/nordvpn-tailscale-split-tunnel.md` | Create (from this plan) | Formal spec |

### Route injection logic (from feat worktree, verified correct)

Interface detection (netmask-based, survives renames):
- Tailscale: `inet 100.x.x.x netmask 0xffffffff` (point-to-point /32)
- NordVPN: `inet 100.x.x.x netmask 0xffc00000` (/10)

Routes to inject when NordVPN is up and Tailscale is up:
1. Delete NordVPN's `100.64.0.0/10` route
2. Add `100.64.0.0/10 → tailscale_interface`
3. Add `100.100.100.100/32 → tailscale_interface` (MagicDNS, beats /10)

### Daemon upgrade: polling → route monitor

Current (feat worktree):
```bash
while true; do
    check_and_fix_routes
    sleep 5
done
```

Proposed:
```bash
# Initial fix on startup
check_and_fix_routes

# Event-driven: react to routing table changes
route monitor | while IFS= read -r _; do
    sleep 0.5  # debounce: wait for NordVPN to finish setting up routes
    check_and_fix_routes
done
```

### deploy.sh integration

New `deploy_vpn()` function:
1. Copy `scripts/vpn/tailscale_route_fix.sh` → `/usr/local/bin/tailscale-route-fix`
2. Copy `scripts/vpn/com.dotfiles.tailscale-route-fix.plist` → `/Library/LaunchDaemons/`
3. Set permissions (755 script, 644 plist, owned by root:wheel)
4. `sudo launchctl bootstrap system /Library/LaunchDaemons/com.dotfiles.tailscale-route-fix.plist`
5. Verify daemon is running: `launchctl list com.dotfiles.tailscale-route-fix`

Uninstall: `deploy.sh --no-vpn` stops daemon + removes files.

### Aliases (from feat worktree, keep as-is)
```bash
alias vpn-status='$DOT_DIR/scripts/vpn/tailscale_route_fix.sh status'
alias vpn-fix='sudo $DOT_DIR/scripts/vpn/tailscale_route_fix.sh once'
```

---

## Edge Cases & Error Handling

| Scenario | Handling |
|----------|----------|
| NordVPN not running, Tailscale up | Status: no conflict. No route changes. |
| Tailscale not running, NordVPN up | Status: no conflict (no Tailscale interface to protect). |
| NordVPN switches servers mid-session | `route monitor` fires → re-inject routes |
| Both off | Daemon idles, no action |
| NordVPN uses IKEv2 instead of NordLynx | IKEv2 gets 10.x.x.x range → no conflict, fix is no-op |
| `route monitor` process dies | launchd `KeepAlive: true` restarts the daemon |
| Daemon re-injects, triggering another route monitor event | Debounce (500ms sleep + re-check) prevents loop |
| New Tailscale peer (not yet in routing table) | Peer's /32 added by Tailscale automatically; /10 route covers remaining range |

---

## Acceptance Criteria

- [ ] AC-1: With NordVPN active, `tailscale ping <peer>` succeeds within 15s of NordVPN connecting
- [ ] AC-2: `curl ipinfo.io/ip` returns NordVPN exit IP (not real IP) — NordVPN still routing internet
- [ ] AC-3: `ping 100.100.100.100` succeeds (MagicDNS reachable)
- [ ] AC-4: After `sudo launchctl kickstart system/com.dotfiles.tailscale-route-fix`, daemon is running
- [ ] AC-5: After reboot with NordVPN and Tailscale both enabled, Tailscale peers reachable within 15s
- [ ] AC-6: After `deploy.sh --no-vpn`, daemon removed and no route injection occurs

---

## Out of Scope

- Linux support (NordVPN Linux uses different CLI; out of scope for now)
- NordVPN protocol selection (user manages this manually)
- Multiple simultaneous VPN providers
- Tailscale exit node conflicts (separate issue)

---

## Open Questions for Critique Agents

1. Is `route monitor` reliable on macOS — does it fire for all route changes including those
   made by system daemons? Or are there events it misses?
2. Does debouncing with `sleep 0.5` inside the `route monitor` loop cause missed events
   (if NordVPN fires multiple route events in quick succession)?
3. Is there a more elegant macOS-native mechanism? (e.g., `networksetup`, `scutil --nwi`,
   or using launchd `WatchPaths` on a NordVPN state file?)
4. Should we validate that NordLynx interface detection by netmask is stable across
   NordVPN app versions? (Could NordVPN change from /10 to /8 or similar?)
5. Any security concerns with a daemon that modifies routing tables with root privileges?
6. The codex approach (OpenVPN profile) — is there a hybrid where we could use OpenVPN
   with NordLynx-like performance? (e.g., WireGuard directly with NordVPN WG config)
