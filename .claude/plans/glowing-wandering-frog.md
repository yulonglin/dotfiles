# Plan: Bedtime Timezone Enforcement

## Context

Cold Turkey Blocker locks the laptop at 12:30 AM. The primary bypass is changing the timezone via `sudo systemsetup -settimezone`, making the system clock appear earlier. Other vectors: `sudo date`, disabling NTP, changing `/etc/localtime` directly.

A system-level LaunchDaemon running every 2 minutes detects and reverts all of these. Uses `WatchPaths` on `/etc/localtime` for near-instant timezone change detection.

## Key Decisions

1. **LaunchDaemon** (not LaunchAgent) — requires sudo to unload. User can't trivially `launchctl bootout` it.
2. **No sudoers** — daemon runs as root natively.
3. **Delta detection** — caches timezone each run. If changed, restart `locationd` to force re-determination. No hardcoded timezone, no travel friction.
4. **Skip cache update on delta** — prevents false positive on next cycle when locationd corrects the TZ.
5. **`killall timed`** for NTP sync (not `sntp -sS`) — more reliable on modern macOS (Sequoia/Tahoe).
6. **`WatchPaths` + `StartInterval`** — near-instant response to `/etc/localtime` changes, plus periodic fallback for NTP/date bypasses.
7. **`logger`** for logging — writes to unified macOS log, avoids path issues with root's `~`.
8. **Opt-in only** — `DEPLOY_BEDTIME=false` default.

## Files to Create

### 1. `custom_bins/enforce-timezone` (new, chmod +x)

Runs as root via LaunchDaemon. Logic:

```
CACHE_FILE="/var/db/enforce-timezone.last"
CURRENT_TZ = readlink /etc/localtime | sed 's|.*/zoneinfo/||'
CHANGED=0

Check 1: Auto-timezone flag
  → defaults read /Library/Preferences/com.apple.timezone.auto Active
  → If != 1: re-enable with `defaults write ... Active -bool true`
  → Set CHANGED=1, restart locationd (plist change not picked up until restart)
  → Log via: logger -t enforce-timezone "Bypass detected: auto-timezone was disabled"

Check 2: NTP enabled
  → systemsetup -getusingnetworktime 2>/dev/null
  → If "Off": re-enable with `systemsetup -setusingnetworktime on 2>/dev/null`
  → Set CHANGED=1, restart timed
  → Log via logger

Check 3: Timezone delta
  → Read CACHED_TZ from CACHE_FILE (create with CURRENT_TZ if missing → exit)
  → If CURRENT_TZ != CACHED_TZ:
      Set CHANGED=1
      Log "Timezone changed from $CACHED_TZ to $CURRENT_TZ"
      killall locationd  (launchd relaunches it, forces re-determination)
      DON'T update cache (leave as last known-good value)

If CHANGED == 0:
  Update cache with CURRENT_TZ (only on clean runs)

If CHANGED > 0:
  killall timed  (force NTP re-sync, launchd relaunches it)

Exit 0 always.
```

Rate limiting: Track restart count in `/var/db/enforce-timezone.restarts`. If >5 restarts in 10 min, log error and skip restart. Reset counter on clean runs.

Also supports `--set-timezone` to update cache (for travel):
```bash
sudo enforce-timezone --set-timezone  # saves current TZ as new baseline
```

### 2. `scripts/cleanup/setup_bedtime_enforce.sh` (new, chmod +x)

Setup script (requires sudo). Follows keyboard-repeat pattern (manual plist).

**Install:**
- Create plist at `/Library/LaunchDaemons/com.user.enforce-timezone.plist`:
  ```xml
  <key>StartInterval</key>
  <integer>120</integer>
  <key>WatchPaths</key>
  <array>
    <string>/etc/localtime</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  ```
- Set ownership: `sudo chown root:wheel`, `sudo chmod 644`
- `sudo launchctl load` the plist
- No StandardOutPath/StandardErrorPath (script uses `logger`)

**Uninstall** (`--uninstall`):
- `sudo launchctl unload` + `sudo rm` plist
- `sudo rm -f /var/db/enforce-timezone.last /var/db/enforce-timezone.restarts`

## Files to Modify

### 3. `config.sh`

Add after `DEPLOY_KEYBOARD` (line 47):
```bash
DEPLOY_BEDTIME=false            # Bedtime timezone enforcement (macOS only, opt-in)
```

Also add `DEPLOY_BEDTIME=false` in `server` and `minimal` profiles.

### 4. `deploy.sh`

**Help text** (after `--keyboard`, line 56):
```
    --bedtime         Install bedtime timezone enforcement (macOS only, opt-in)
```

**Deployment section** (between Keyboard Repeat and Safari Web App, ~line 631):
```bash
# ─── Bedtime Timezone Enforcement (macOS only) ───────────────────────────────
if [[ "$DEPLOY_BEDTIME" == "true" ]] && is_macos; then
    log_section "INSTALLING BEDTIME TIMEZONE ENFORCEMENT"
    if [[ -f "$DOT_DIR/scripts/cleanup/setup_bedtime_enforce.sh" ]]; then
        "$DOT_DIR/scripts/cleanup/setup_bedtime_enforce.sh" || log_warning "Bedtime enforcement setup failed"
    fi
fi
```

No changes to `parse_args()` — generic `--*` handler auto-maps `--bedtime` → `DEPLOY_BEDTIME=true`.

## Bypass Analysis

| Vector | Countered by | Response time |
|--------|-------------|---------------|
| `systemsetup -settimezone` | WatchPaths on /etc/localtime | Seconds |
| `ln -sf` /etc/localtime | WatchPaths on /etc/localtime | Seconds |
| `sudo date` | Periodic timed restart | ~2 min |
| Disable auto-timezone | Check 1 + locationd restart | ~2 min |
| Disable NTP | Check 2 + timed restart | ~2 min |
| `launchctl unload` daemon | Requires sudo | High friction |
| Safe reboot | RunAtLoad | Daemon starts before login |
| Disable Location Services | Not countered | Low risk (multi-step, affects other apps) |

**Known limitation**: User with sudo can `sudo launchctl bootout system/com.user.enforce-timezone`. This is inherent — can't prevent root from disabling a root daemon. The friction is the point, not impossibility.

## Scenario Walkthroughs

**Bypass attempt** (user runs `sudo systemsetup -settimezone US/Pacific`):
1. `/etc/localtime` changes → WatchPaths triggers script within seconds
2. Cache: `Europe/London`, Current: `US/Pacific` → delta detected
3. Script kills locationd (re-determines TZ from location), kills timed (re-syncs NTP)
4. Cache NOT updated (stays `Europe/London`)
5. locationd sets TZ back to `Europe/London`
6. Next run: cache=`Europe/London`, current=`Europe/London` → clean → update cache → stable

**Travel** (user flies to New York, locationd detects):
1. locationd changes TZ to `America/New_York` → WatchPaths triggers
2. Cache: `Europe/London`, Current: `America/New_York` → delta
3. Script kills locationd → it re-determines `America/New_York` (correct for location)
4. Cache NOT updated
5. Next WatchPaths trigger or periodic run: cache=`Europe/London`, current=`America/New_York` → delta again
6. After locationd re-confirms: user runs `sudo enforce-timezone --set-timezone` to accept new baseline
7. Or: after 5 restarts (rate limit), script stops restarting and logs warning — user notices and runs `--set-timezone`

**DST transition**: Clock offset changes but timezone name stays same → no delta → no action. Correct.

## Verification

1. **Timezone bypass**: `sudo systemsetup -settimezone US/Pacific` → verify log entry within seconds (`log show --predicate 'process == "logger"' --last 1m | grep enforce-timezone`)
2. **NTP bypass**: `sudo systemsetup -setusingnetworktime off` → wait 2 min → verify re-enabled
3. **Auto-TZ bypass**: `sudo defaults write /Library/Preferences/com.apple.timezone.auto Active -bool false` → wait 2 min → verify re-enabled
4. **No-op**: Run when correct → no log output
5. **Setup/teardown**: install → `launchctl list | grep enforce-timezone` → uninstall → verify clean
6. **Deploy**: `./deploy.sh --minimal --bedtime` end-to-end
7. **Opt-in**: `./deploy.sh` defaults → bedtime NOT installed
8. **Travel**: `sudo enforce-timezone --set-timezone` → verify cache updated
