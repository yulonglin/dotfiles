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

### A. Codex worktree: OpenVPN profile generation (`codex/nordvpn-tailscale-split`)
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

### B. Feat worktree: Route injection + polling daemon (`feat/vpn-split-tunnel`)
- Keeps NordVPN app + NordLynx
- launchd daemon polls every 5s, detects when NordVPN overwrites Tailscale routes
- Re-injects: delete NordVPN's /10 route, add Tailscale /10 route, add MagicDNS /32 route

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

→ **SELECTED as foundation**: Passes all Must criteria. Upgrade: replace polling with event-driven.

### Rejected Alternatives (from critique agents)

| Alternative | Why rejected |
|-------------|-------------|
| OpenVPN profile (Codex approach) | Loses NordLynx speed + requires app switch |
| IKEv2 protocol switch | ~10-20% slower than NordLynx, user explicitly declined |
| NordVPN built-in split tunneling | macOS NordVPN app does not support split tunneling (only on Windows/Android) |
| Tailscale `--accept-routes` | Cannot reclaim /10 once NordVPN has claimed it at the routing table level |
| WireGuard direct (bypass NordVPN app) | NordVPN doesn't expose WG configs; requires reverse-engineering their API |

---

## Recommended Approach: Route Injection + `route monitor` (event-driven)

**Upgrade the feat worktree**: Replace 5s polling with `route monitor` for event-driven detection.

### Why `route monitor`?
`route monitor` uses a PF_ROUTE kernel socket — every process that modifies the routing table
(including NordLynx's WireGuard utun interface) broadcasts RTM_ADD/RTM_DELETE messages.
This is reliable for all route changes from all sources. Sub-second response, no polling.

### Debounce Pattern (from Codex critique — CRITICAL FIX)

The naive `sleep 0.5` after `read` is architecturally inverted — it serializes events instead
of collapsing bursts. Use a drain pattern:

```bash
# Initial fix on startup (handles NordVPN already connected at boot)
check_and_fix_routes

# Event-driven: react to routing table changes
route monitor | while IFS= read -r _; do
    # Drain the burst: keep reading until pipe is quiet for 300ms
    while read -t 0.3 -r _; do :; done
    check_and_fix_routes
done
```

`read -t 0.3` times out after 300ms of no new events, collapsing a burst of 4-8 RTM messages
into a single `check_and_fix_routes` call.

### Fallback Timer (from plan-critic — defense-in-depth)

Add a 60s background heartbeat to catch any events `route monitor` might miss:

```bash
# Background heartbeat (defense-in-depth)
while true; do sleep 60; check_and_fix_routes; done &
HEARTBEAT_PID=$!
trap "kill $HEARTBEAT_PID 2>/dev/null" EXIT

# Primary: event-driven
route monitor | while IFS= read -r _; do
    while read -t 0.3 -r _; do :; done
    check_and_fix_routes
done
```

---

## Implementation Plan

### Step 1: Merge feat worktree files to main

Cherry-pick from `feat/vpn-split-tunnel`:
- `scripts/vpn/tailscale_route_fix.sh`
- `scripts/vpn/com.dotfiles.tailscale-route-fix.plist`

### Step 2: Fix critical bugs in `tailscale_route_fix.sh`

**Bug 1 — `route add` failure leaves routing broken (CRITICAL)**

Current: `route delete` succeeds → `route add` fails → `set -e` exits script → /10 route is
gone → BOTH Tailscale AND NordVPN CGNAT traffic have no route.

Fix: Wrap route mutations with rollback:
```bash
route delete -net "$CGNAT_NET" 2>/dev/null || true
if ! route add -net "$CGNAT_NET" -interface "$ts_if" 2>/dev/null; then
    echo "$LOG_PREFIX ERROR: Failed to add $CGNAT_NET route — restoring NordVPN route"
    route add -net "$CGNAT_NET" -interface "$nord_if" 2>/dev/null || true
    return 1
fi
```

**Bug 2 — TOCTOU race: interface disappears between detect and use**

Fix: Verify interface still exists immediately before `route add`:
```bash
if ! ifconfig "$ts_if" &>/dev/null; then
    echo "$LOG_PREFIX ERROR: $ts_if disappeared — aborting"
    return 1
fi
```

**Bug 3 — `set -euo pipefail` kills daemon on transient failures**

Fix: In watch mode, wrap `check_and_fix_routes` in a non-fatal call:
```bash
check_and_fix_routes || echo "$LOG_PREFIX WARNING: check failed, will retry on next event"
```

### Step 3: Upgrade interface detection

**Current (fragile)**: Match exact netmask `0xffc00000` for NordVPN.
Breaks if NordVPN changes subnet size (/8, /11, /12).

**Improved**: Match IP prefix 100.64–100.127 (the CGNAT range) regardless of netmask:
```bash
detect_nordvpn_if() {
    ifconfig 2>/dev/null | awk '
        /^[a-z]/ { iface = $1; sub(/:$/, "", iface) }
        /inet 100\.(6[4-9]|[7-9][0-9]|1[0-2][0-7])\./ && /netmask 0xff[c-f]/ {
            print iface; exit
        }
    '
}
```

**For Tailscale**: Use `tailscale ip -4` when available (more reliable than netmask matching):
```bash
detect_tailscale_if() {
    local ts_ip
    ts_ip=$(tailscale ip -4 2>/dev/null) || return 1
    [[ -z "$ts_ip" ]] && return 1
    ifconfig 2>/dev/null | awk -v ip="$ts_ip" '
        /^[a-z]/ { iface = $1; sub(/:$/, "", iface) }
        $0 ~ "inet " ip { print iface; exit }
    '
}
```

### Step 4: Upgrade daemon loop (polling → `route monitor`)

Replace the `while true; sleep 5` loop with the debounced `route monitor` pattern
(see "Debounce Pattern" section above).

### Step 5: Add post-apply verification

After `route add`, verify routes took effect:
```bash
if is_routing_correct "$ts_if"; then
    echo "$LOG_PREFIX Routes verified"
else
    echo "$LOG_PREFIX WARNING: Routes applied but not verified — monitoring"
fi
```

### Step 6: deploy.sh integration (`--vpn` flag)

New `deploy_vpn()` function:

```bash
deploy_vpn() {
    if ! is_macos; then
        echo "VPN split tunneling is macOS-only"
        return
    fi

    local PLIST_LABEL="com.dotfiles.tailscale-route-fix"
    local PLIST_PATH="/Library/LaunchDaemons/${PLIST_LABEL}.plist"
    local SCRIPT_PATH="/usr/local/bin/tailscale-route-fix"

    sudo -v  # Acquire sudo upfront

    # Idempotent: bootout existing before bootstrap (CRITICAL — bootstrap fails if already loaded)
    sudo launchctl bootout "system/${PLIST_LABEL}" 2>/dev/null || true

    # Install script
    sudo mkdir -p /usr/local/bin
    sudo cp scripts/vpn/tailscale_route_fix.sh "$SCRIPT_PATH"
    sudo chmod 755 "$SCRIPT_PATH"
    sudo chown root:wheel "$SCRIPT_PATH"

    # Install plist
    sudo cp scripts/vpn/${PLIST_LABEL}.plist "$PLIST_PATH"
    sudo chmod 644 "$PLIST_PATH"
    sudo chown root:wheel "$PLIST_PATH"

    # Load daemon
    sudo launchctl bootstrap system "$PLIST_PATH"
    sudo launchctl enable "system/${PLIST_LABEL}"
    sudo launchctl kickstart -k "system/${PLIST_LABEL}"

    # Verify
    if sudo launchctl print "system/${PLIST_LABEL}" &>/dev/null; then
        echo "VPN split tunnel daemon installed and running"
    else
        echo "WARNING: daemon installed but may not be running"
    fi
}
```

**Uninstall (`deploy.sh --no-vpn`)**:
```bash
undeploy_vpn() {
    local PLIST_LABEL="com.dotfiles.tailscale-route-fix"
    sudo launchctl bootout "system/${PLIST_LABEL}" 2>/dev/null || true
    sudo launchctl disable "system/${PLIST_LABEL}" 2>/dev/null || true
    sudo rm -f "/Library/LaunchDaemons/${PLIST_LABEL}.plist"
    sudo rm -f "/usr/local/bin/tailscale-route-fix"
    echo "VPN split tunnel daemon removed"
}
```

### Step 7: Aliases

Add to `config/aliases.sh`:
```bash
alias vpn-status='tailscale-route-fix status'
alias vpn-fix='sudo tailscale-route-fix once'
```

### Step 8: Log rotation

Add newsyslog config as part of `deploy_vpn()`:
```bash
echo "/var/log/tailscale-route-fix.log 640 5 1000 * J" | \
    sudo tee /etc/newsyslog.d/tailscale-route-fix.conf > /dev/null
```
(5 rotated files, 1MB max each, compressed)

### Step 9: Write formal spec

Write `specs/nordvpn-tailscale-split-tunnel.md` from this plan (RFC 2119 language).

---

## Files to Create/Modify (Summary)

| File | Action | Purpose |
|------|--------|---------|
| `scripts/vpn/tailscale_route_fix.sh` | Cherry-pick + modify | Fix bugs, upgrade to route monitor |
| `scripts/vpn/com.dotfiles.tailscale-route-fix.plist` | Cherry-pick (minor edits) | launchd daemon config |
| `deploy.sh` | Edit: add `deploy_vpn()` + `undeploy_vpn()` | `--vpn` / `--no-vpn` flags |
| `config/aliases.sh` | Edit: add vpn-* aliases | Manual override |
| `specs/nordvpn-tailscale-split-tunnel.md` | Create | Formal spec |

---

## Edge Cases & Error Handling

| Scenario | Handling |
|----------|----------|
| NordVPN not running, Tailscale up | No conflict detected → no-op |
| Tailscale not running, NordVPN up | No Tailscale interface → no-op |
| NordVPN switches servers mid-session | `route monitor` fires → drain burst → re-inject |
| Both off | Daemon idles on `route monitor`, no action |
| NordVPN uses IKEv2 instead of NordLynx | IKEv2 gets 10.x.x.x → no CGNAT conflict → no-op |
| `route monitor` dies | launchd `KeepAlive: true` restarts entire daemon |
| Daemon's own route injection triggers `route monitor` | Drain pattern collapses self-triggered events; `check_and_fix_routes` sees "already correct" → no-op |
| `route add` fails (interface gone) | Rollback: restore NordVPN's /10 route, log error, continue monitoring |
| Boot before networking ready | launchd restarts daemon; `check_and_fix_routes` returns early (no interfaces found) |
| NordVPN changes netmask (/10 → /8) | IP-prefix detection (100.64-127.x) still matches; only netmask-exclusive check would break |
| New Tailscale peer joins | Peer's /32 added by Tailscale; covered by existing /10 route |
| Re-deploy (`deploy.sh --vpn` run twice) | `bootout || true` before `bootstrap` — idempotent |

---

## Acceptance Criteria

- [ ] AC-1: With NordVPN active, `tailscale ping <peer>` succeeds within 5s of NordVPN connecting
- [ ] AC-2: `curl ipinfo.io/ip` returns NordVPN exit IP (NordVPN still routing internet traffic)
- [ ] AC-3: `ping 100.100.100.100` succeeds (MagicDNS reachable)
- [ ] AC-4: Daemon running after `deploy.sh --vpn`: `sudo launchctl print system/com.dotfiles.tailscale-route-fix`
- [ ] AC-5: After reboot with NordVPN + Tailscale auto-start, peers reachable within 15s
- [ ] AC-6: After `deploy.sh --no-vpn`, daemon fully removed, no route injection
- [ ] AC-7: NordVPN server switch mid-session → Tailscale peers recover within 5s
- [ ] AC-8: Running `deploy.sh --vpn` twice succeeds without errors (idempotent)

## Test Matrix

| Test | Steps | Expected |
|------|-------|----------|
| Cold start with conflict | Start NordVPN → start daemon | Routes fixed within 2s |
| NordVPN reconnect | Disconnect + reconnect NordVPN | Routes fixed within 2s |
| Tailscale restart | Restart Tailscale while NordVPN active | Routes re-established |
| Server switch | Change NordVPN server | Routes fixed within 2s |
| Deploy + redeploy | `deploy.sh --vpn` twice | No errors, daemon running |
| Uninstall | `deploy.sh --no-vpn` | Daemon stopped, files removed |
| Reboot | Reboot with both enabled | Peers reachable within 15s |

---

## Out of Scope

- Linux support (NordVPN Linux uses different CLI; future work)
- NordVPN protocol selection (user manages manually)
- Multiple simultaneous VPN providers
- Tailscale exit node conflicts (separate issue)
- IPv6 routing conflicts (investigate if needed later)
- NordVPN kill switch interactions (may need testing)

---

## CLI Interface (frozen)

```
tailscale-route-fix <subcommand>

Subcommands:
  watch     - Run as daemon (route monitor loop) — used by launchd
  once      - Check and fix routes once, then exit
  status    - Show current state (interfaces, routes, conflict status)
  uninstall - Remove daemon and config files
```

---

## Critique Integration Log

Issues found by Codex and plan-critic agents, all addressed above:

| # | Severity | Issue | Resolution |
|---|----------|-------|------------|
| 1 | CRITICAL | `route add` failure leaves /10 route deleted (broken routing) | Rollback: restore NordVPN route on failure (Step 2) |
| 2 | CRITICAL | Missing initial `check_and_fix_routes` before `route monitor` loop | Added startup check before entering loop (Step 4) |
| 3 | CRITICAL | `launchctl bootstrap` not idempotent on re-deploy | `bootout || true` before `bootstrap` (Step 6) |
| 4 | HIGH | Debounce inverted (sleep after read, not drain) | `read -t 0.3` drain pattern (Debounce Pattern section) |
| 5 | HIGH | TOCTOU: interface disappears between detect and `route add` | Verify interface exists before `route add` (Step 2) |
| 6 | HIGH | `set -euo pipefail` kills daemon on transient failures | Non-fatal wrapper in watch mode (Step 2) |
| 7 | HIGH | Netmask 0xffc00000 detection is fragile | IP-prefix based detection (Step 3) |
| 8 | HIGH | `route monitor` multi-line events cause per-line processing | Drain pattern collapses burst (Step 4) |
| 9 | IMPORTANT | `/usr/local/bin` may not exist on Apple Silicon | `sudo mkdir -p` in deploy (Step 6) |
| 10 | IMPORTANT | `--no-vpn` uninstall underspecified | Full `undeploy_vpn()` with correct ordering (Step 6) |
| 11 | IMPORTANT | No post-apply route verification | Added `is_routing_correct` check after injection (Step 5) |
| 12 | SUGGESTION | No log rotation | newsyslog config in deploy (Step 8) |
| 13 | SUGGESTION | `sudo rm` inside root-level script is redundant | Remove `sudo` from `cmd_uninstall` |
| 14 | SUGGESTION | CLI contract and test matrix underspecified | Frozen CLI interface + test matrix added |
