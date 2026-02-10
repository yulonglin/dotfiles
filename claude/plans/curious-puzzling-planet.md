# Plan: Selective Tab Closing + Persistent Quit

## Context

Two issues with `clear-mac-apps` (`custom_bins/clear-mac-apps`):

1. **`Focusmate (Safari)` in `[no-touch]`** was always a literal process-name match that never matched anything. We want: close all non-Focusmate Safari tabs, keep Focusmate tab alive, don't quit Safari. If no Focusmate tab → quit Safari.
2. **`[slow-close]` (Spark Desktop)** uses Cmd+W (`close_app_windows`) which is unreliable for apps with sync/save dialogs — and wrong, since the intent is to quit, not close windows. Replace with repeated quit + verification.

## Changes

### Files to modify

1. `custom_bins/clear-mac-apps` — new functions + modified main loop
2. `config/clear_mac_apps.conf` — new sections, revert `Safari` → `Focusmate (Safari)`

### 1. New config sections

Replace overloaded semantics with explicit sections:

```ini
[no-touch]
Ghostty
Things
zoom.us

[selective-close]
# Syntax: Pattern (AppName) — close non-matching tabs/windows, keep matching. No match = quit.
Focusmate (Safari)

[close-windows]
Claude
VoiceInk
BeardedSpice
Spotify

[persistent-quit]
# Apps that need multiple quit attempts (sync, save dialogs)
Spark Desktop
```

### 2. Config parser improvements

- **Strip inline comments**: `line="${line%%#*}"` before matching
- **Add validation**: if all sections parse to zero entries, error out (prevents "quit everything" on parse failure)
- Keep awk parser (it works — earlier test failures were shell escaping, not awk syntax)

### 3. `selective_close()` — new function

For entries like `Focusmate (Safari)`:

**Parsing**: regex `^(.+)[[:space:]]+\(([^)]+)\)\s*$` → pattern + app name. Store in `selective_set[app_lower]="pattern"`.

**`app_has_matching_content(app, pattern)`**:
- Guard with `if application "AppName" is running` to avoid launching the app
- Safari: check `name of tab` AND `URL of tab` (URL is more stable — page titles change with notification badges like "(1) Focusmate")
- Other apps: check `name of every window` via System Events

**`selective_close_safari(pattern)`**:
```applescript
if application "Safari" is not running then return
tell application "Safari"
    repeat with w in (reverse of every window)
        repeat with t in (reverse of tabs of w)
            if name of t does not contain "Pattern" and URL of t does not contain "pattern" then
                try
                    close t
                end try
            end if
        end repeat
        try
            if (count of tabs of w) = 0 then close w
        end try
    end repeat
end tell
```

Key details:
- Reverse iteration to avoid index shifting when closing
- Safari's native `close` command — no Cmd+W, no Accessibility permission needed, no focus switching
- `try` blocks around count/close (windows may auto-close when last tab closes)
- Match both `name` (title) and `URL` for robustness

**`selective_close_windows(app, pattern)`** — for non-Safari apps:
- Use System Events `name of every window of process`
- Close non-matching windows with `close window` or Cmd+W fallback

**Main loop branch**:
```
if selective_set has app →
    if app_has_matching_content → selective close, keep app alive
    else → quit app (no matching content to protect)
```

### 4. `quit_app_persistent()` — replaces slow-close Cmd+W approach

```zsh
quit_app_persistent() {
    local app="$1" timeout="${2:-15}"
    local elapsed=0
    osascript -e "tell application \"$app\" to quit" 2>/dev/null || true
    while (( elapsed < timeout )); do
        sleep 2
        elapsed=$((elapsed + 2))
        pgrep -xiq "$app" 2>/dev/null || return 0  # app quit, done
        # Still running — retry quit (maybe dialog appeared)
        osascript -e "tell application \"$app\" to quit" 2>/dev/null || true
    done
    echo "Warning: $app did not quit within ${timeout}s" >&2
}
```

- Quit once, then poll `pgrep` every 2s up to 15s timeout
- Re-send quit only if still running (handles dialogs/sync delays)
- Exits early on success
- Sequential (not parallel) — only 1 app in this section, parallelism adds complexity for no gain

### 5. Dry-run output updates

Add new categories to `--dry-run` output:
- "Would SELECTIVE-CLOSE (keep: Pattern)" for selective entries with matches
- "Would QUIT (persistent)" for persistent-quit apps
- "Would QUIT (no matching tabs)" for selective entries without matches

### 6. Main loop priority order

```
selective_set has app?
├─ yes + has matching content → selective close
├─ yes + no matching content → quit
no_touch → skip
persistent_quit → quit_app_persistent
close_windows → close_app_windows (existing Cmd+W approach)
else → quit_app
```

Selective checked first so `Focusmate (Safari)` is evaluated before Safari could fall through to quit.

## Verification

1. `clear-mac-apps --dry-run` with Safari open + Focusmate tab → "Would SELECTIVE-CLOSE (keep: Focusmate)" for Safari
2. `clear-mac-apps --dry-run` with Safari open + NO Focusmate tab → Safari in "Would QUIT"
3. `clear-mac-apps --dry-run` with Safari closed → no Safari in output
4. Live run with Focusmate + other tabs → other tabs close, Focusmate stays, Safari stays
5. `clear-mac-apps --dry-run` shows Spark Desktop in "Would QUIT (persistent)"
6. Config with all entries removed → script errors out (doesn't quit everything)
