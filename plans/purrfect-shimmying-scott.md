# Plan: Fix Review Findings (VPN + SOPS)

## Context

Three review agents (Codex, Gemini, code-reviewer) found bugs in the VPN split tunnel
implementation and a conflict with the concurrent SOPS encrypted secrets feature.
Two issues are showstoppers for the daemon on stock macOS.

---

## Fixes

### C1: `read -t 0.3` fails on macOS bash 3.2 (CRITICAL)

**File:** `scripts/vpn/tailscale_route_fix.sh:181`

launchd uses `/bin/bash` (3.2) which doesn't support fractional timeouts.
`set -euo pipefail` causes daemon crash on every route event.

**Fix:** `read -t 0.3` → `read -t 1` (integer timeout, still collapses bursts).

### C2: NordVPN IP regex misses octets 108-109, 118-119 (CRITICAL)

**File:** `scripts/vpn/tailscale_route_fix.sh:55`

`1[0-2][0-7]` → `(10[0-9]|11[0-9]|12[0-7])` to cover full 100-127 range.

Full fixed line:
```
/inet 100\.(6[4-9]|[7-9][0-9]|10[0-9]|11[0-9]|12[0-7])\./
```

### C3: `DEPLOY_VPN=false` missing from config.sh (CRITICAL)

**File:** `config.sh:55`

SOPS change replaced VPN line. Add back after `DEPLOY_MOUSELESS`:
```bash
DEPLOY_VPN=false                # NordVPN+Tailscale split tunnel daemon (macOS only, opt-in)
```

### C4: `vpn` missing from `_known_components` (CRITICAL)

**File:** `scripts/shared/helpers.sh:974`

Add `vpn` to the array so `--only vpn` works.

### I1: Launchd plist lacks PATH (IMPORTANT)

**File:** `scripts/vpn/com.dotfiles.tailscale-route-fix.plist`

Add before `</dict>`:
```xml
<key>EnvironmentVariables</key>
<dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
</dict>
```

### I2: Netmask regex false positives (IMPORTANT)

**File:** `scripts/vpn/tailscale_route_fix.sh:55`

`/netmask 0xff[c-f]/` → `/netmask 0xff[c-f]00000/` to reject /24, /16 etc.
Covers /10 (`0xffc00000`), /11 (`0xffe00000`), /12 (`0xfff00000`).
Does NOT match /13 (`0xfff80000`) — acceptable since NordVPN uses /10 exclusively.

### I3: Spec `--no-vpn` uninstall claim (IMPORTANT)

**File:** `specs/nordvpn-tailscale-split-tunnel.md`

Change uninstall section: `--no-vpn` just skips deployment, manual uninstall via
`sudo tailscale-route-fix uninstall`.

### I4: `secrets-init` overwrites `.sops.yaml` unconditionally (IMPORTANT)

**File:** `config/aliases.sh:52`

Wrap the `cat > "$sops_yaml"` in `if [[ ! -f "$sops_yaml" ]]; then`.

### I5: Add ThrottleInterval to plist (IMPORTANT)

**File:** `scripts/vpn/com.dotfiles.tailscale-route-fix.plist`

Add `<key>ThrottleInterval</key><integer>30</integer>` to prevent crash-loop spam.

## Files to Modify

| File | Fixes |
|------|-------|
| `scripts/vpn/tailscale_route_fix.sh` | C1, C2, I2 |
| `scripts/vpn/com.dotfiles.tailscale-route-fix.plist` | I1, I5 |
| `config.sh` | C3 |
| `scripts/shared/helpers.sh` | C4 |
| `specs/nordvpn-tailscale-split-tunnel.md` | I3 |
| `config/aliases.sh` | I4 |

## Not Fixing (deferred/false alarms)

- **M1**: No ThrottleInterval in plist → **now fixed as I5**
- **M2**: age install uses `/tmp` instead of `$TMPDIR` in install.sh — non-blocking, install.sh runs outside sandbox
- **M3**: `$TMPDIR` used without `mkdir -p` in secrets-init — `$TMPDIR` is set by macOS, always exists
- **M4**: direnv install pipes `curl | bash` with `2>/dev/null` — standard install method, has `|| log_warning` fallback
- **I5 (envrc eval)**: false alarm — template uses direnv `dotenv` builtin, not `eval`
- **I6 (.secrets truncation)**: already uses temp+mv pattern in both deploy.sh and secrets-decrypt
- **I8 (age key gist security)**: gist is secret (unlisted), same mechanism as existing SSH key sync

## Verification Criteria

### Static checks (run after implementation)

| # | Check | Command | Expected |
|---|-------|---------|----------|
| S1 | Shellcheck clean | `shellcheck scripts/vpn/tailscale_route_fix.sh` | Exit 0, no warnings |
| S2 | Bash syntax valid | `bash -n scripts/vpn/tailscale_route_fix.sh` | Exit 0 |
| S3 | Plist valid XML | `plutil -lint scripts/vpn/com.dotfiles.tailscale-route-fix.plist` | OK |
| S4 | DEPLOY_VPN in config.sh | `grep -c 'DEPLOY_VPN=false' config.sh` | 1 |
| S5 | vpn in _known_components | `grep '_known_components' scripts/shared/helpers.sh \| grep -c vpn` | 1 |
| S6 | No fractional read timeout | `grep -c 'read -t 0\.' scripts/vpn/tailscale_route_fix.sh` | 0 |
| S7 | Integer read timeout used | `grep -c 'read -t 1' scripts/vpn/tailscale_route_fix.sh` | 1 (in drain loop) |
| S8 | PATH in plist | `grep -c '/opt/homebrew/bin' scripts/vpn/com.dotfiles.tailscale-route-fix.plist` | 1 |
| S9 | ThrottleInterval in plist | `grep -c 'ThrottleInterval' scripts/vpn/com.dotfiles.tailscale-route-fix.plist` | 1 |

### Regex correctness tests

| # | Test | Command | Expected |
|---|------|---------|----------|
| R1 | Match 100.64.x | `echo 'inet 100.64.1.1 netmask 0xffc00000' \| awk '/100\.(6[4-9]\|[7-9][0-9]\|10[0-9]\|11[0-9]\|12[0-7])\./'` | Match |
| R2 | Match 100.108.x (was missed) | Same awk with `100.108.1.1` | Match |
| R3 | Match 100.119.x (was missed) | Same awk with `100.119.1.1` | Match |
| R4 | Match 100.127.x (boundary) | Same awk with `100.127.1.1` | Match |
| R5 | No match 100.128.x (out of range) | Same awk with `100.128.1.1` | No match |
| R6 | No match 100.63.x (below range) | Same awk with `100.63.1.1` | No match |
| R7 | Netmask anchored | `echo '0xffffff00' \| grep -c '0xff[c-f]00000'` | 0 (no false positive) |
| R8 | Netmask /10 matches | `echo '0xffc00000' \| grep -c '0xff[c-f]00000'` | 1 |
| R9 | Bash 3.2 compat | `/bin/bash -c 'read -t 1 -r _ < /dev/null' && echo OK` | OK |
| R10 | Netmask /24 rejected | `echo '0xffffff00' \| grep -c '0xff[c-f]00000'` | 0 |

### Behavioral checks (manual, post-deploy)

| # | Test | Steps | Expected |
|---|------|-------|----------|
| B1 | Daemon starts | `deploy.sh --vpn` then `sudo launchctl print system/com.dotfiles.tailscale-route-fix` | State = running |
| B2 | Status works | `vpn-status` | Shows interfaces + verdict |
| B3 | One-shot fix | Connect NordVPN, `vpn-fix` | Routes corrected |
| B4 | Event-driven fix | Connect NordVPN, wait 2s | Routes auto-corrected (check log) |
| B5 | Idempotent redeploy | `deploy.sh --vpn` twice | No errors |
| B6 | secrets-init safe | Run `secrets-init` when `.sops.yaml` exists | Skips overwrite |

### Spec accuracy checks

| # | Check | Expected |
|---|-------|----------|
| P1 | Uninstall section | Says `sudo tailscale-route-fix uninstall` (not `--no-vpn`) |
| P2 | `--no-vpn` described accurately | Says it skips deployment, not uninstalls |
