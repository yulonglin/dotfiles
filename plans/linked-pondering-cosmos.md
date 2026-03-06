# Plan: Protect Google Meet windows in clear-mac-apps

## Context

User runs `clear-mac-apps` (via macOS Shortcuts) to clean up running apps. Currently Chrome gets quit entirely. Two changes needed:
1. If Chrome has a Google Meet window → close non-Meet windows, keep Chrome alive
2. If Chrome has no Google Meet window → quit Chrome normally (default behavior)

Chrome stays in the default "quit" category. A new `[protected-windows]` config section dynamically overrides quit → close-windows when a matching window is detected.

## Changes

### 1. Config: `config/clear_mac_apps.conf`

Add new `[protected-windows]` section (Chrome is NOT added to `[close-windows]`):

```
[protected-windows]
# Substrings matched against window titles (case-insensitive)
# If ANY window of a quit-eligible app matches, that app switches to
# close-windows behavior: non-matching windows are closed, app stays alive
Google Meet
```

### 2. Script: `custom_bins/clear-mac-apps`

**Config parsing** — new `get_apps_in_section "protected-windows"` call, store patterns in an array.

**New helper: `app_has_protected_window()`** — given an app name and the protected patterns array, use System Events to get all window names of that process and check if any contain a protected pattern (case-insensitive).

**Modify classification in `main()`** — after the existing no-touch/slow-close/close-windows checks, before adding to `apps_to_quit`:
1. Call `app_has_protected_window "$app"` with the protected patterns
2. If true → move app to `apps_close_windows` instead of `apps_to_quit`

**Modify `close_app_windows()`** — accept protected patterns and before each Cmd+W:
1. Get front window's `name` via System Events
2. Check if it contains any protected pattern (case-insensitive)
3. If protected: send Cmd+\` to cycle to next window, increment a "skipped" counter
4. If not protected: send Cmd+W as usual
5. Stop if we've cycled through all remaining windows without finding a closeable one (skipped counter >= remaining window count)

**Dry-run output** — show which apps were dynamically moved from quit → close-windows due to protected windows.

### Key design decisions

- **Dynamic, not static**: Chrome isn't hardcoded in `[close-windows]` — it only gets close-windows behavior when a protected window exists
- **Generic**: any quit-eligible app with a protected window gets the same treatment
- **Cmd+\` cycling**: when front window is protected, cycle to next window (maintains Electron app compatibility)
- **Case-insensitive substring match**: "Google Meet" matches "Google Meet - Team Standup" etc.

## Files to modify

1. `config/clear_mac_apps.conf` — add `[protected-windows]` section
2. `custom_bins/clear-mac-apps` — dynamic classification + window-title-aware closing

## Verification

1. `clear-mac-apps --dry-run` with Chrome open + Google Meet tab → Chrome shows under "CLOSE WINDOWS" (dynamically moved)
2. `clear-mac-apps --dry-run` with Chrome open, no Meet → Chrome shows under "QUIT"
3. Live run: Chrome with Meet tab + regular tab → Meet window stays, other closes, Chrome stays alive
4. Live run: Chrome with no Meet → Chrome quits normally
