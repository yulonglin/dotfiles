# Plan: Protect Google Meet windows in clear-mac-apps

## Context

User runs `clear-mac-apps` (via macOS Shortcuts) to clean up running apps. Currently Chrome gets quit entirely. Desired behavior:
- Chrome has a Google Meet window → close non-Meet windows, keep Chrome alive with Meet
- Chrome has no Google Meet window → quit Chrome normally

## Design (2 rounds of agent critique applied)

**Core approach**: Two-pass zsh-filtering with Chrome's AppleScript API.

1. **Pass 1** — Fetch all Chrome window IDs + tab titles via one `osascript` call
2. **Filter in zsh** — Match tab titles against protected patterns (case-insensitive)
3. **Pass 2** — Close non-protected windows by ID via dynamically-built `osascript`

Why this design:
- Chrome's AppleScript API enumerates ALL tabs (not just active tab — System Events only shows active tab title)
- Pattern matching in zsh avoids quoting nightmares in AppleScript
- Closing by window ID avoids index-shifting bugs
- Two osascript calls total (not N per app)

## Changes

### 1. Config: `config/clear_mac_apps.conf`

Add `[protected-windows]` section:

```conf
[protected-windows]
# Substrings matched against window/tab titles (case-insensitive)
# Chrome: checks ALL tab titles (reliable). Other apps: active window title only.
# If ANY window has a match, that app gets selective-close instead of quit
Google Meet
```

### 2. Script: `custom_bins/clear-mac-apps`

#### A. Rename `get_apps_in_section` → `get_entries_in_section`

Generic awk parser returns lines from a section — rename reflects that it returns patterns too, not just app names. Update all 3 call sites.

#### B. New helper: `get_chrome_window_tabs()`

Returns `window_id|tab_title` per line via heredoc osascript:

```zsh
get_chrome_window_tabs() {
    osascript <<'APPLESCRIPT'
tell application "Google Chrome"
    set output to ""
    repeat with w in every window
        repeat with t in every tab of w
            set output to output & (id of w) & "|" & (title of t) & linefeed
        end repeat
    end repeat
    return output
end tell
APPLESCRIPT
}
```

Notes: `id` is type `text` in Chrome's API. `every window` returns `{}` safely when no windows. Heredoc pipes to stdin (no `/tmp` file — sandbox-safe).

#### C. New helper: `close_app_selectively(app, patterns...)`

Two-pass zsh-filtering approach:

```zsh
close_app_selectively() {
    local app="$1"; shift
    local -a protected_patterns=("$@")

    if [[ "$app" != "Google Chrome" ]]; then
        # Non-Chrome fallback: close all windows (best-effort)
        close_app_windows "$app" 3
        return
    fi

    # Pass 1: fetch window/tab data, filter in zsh
    local -A protected_windows all_windows
    while IFS='|' read -r wid title; do
        [[ -z "$wid" ]] && continue
        all_windows[$wid]=1
        for pattern in "${protected_patterns[@]}"; do
            if [[ "${(L)title}" == *"${(L)pattern}"* ]]; then
                protected_windows[$wid]=1
                break
            fi
        done
    done < <(get_chrome_window_tabs)

    # Collect IDs to close
    local -a ids_to_close=()
    for wid in ${(k)all_windows}; do
        (( ${+protected_windows[$wid]} )) || ids_to_close+=("$wid")
    done

    # All windows protected → nothing to do
    (( ${#ids_to_close} == 0 )) && return 0

    # No protected windows → quit entirely
    if (( ${#protected_windows} == 0 )); then
        quit_app "$app"
        return
    fi

    # Pass 2: close non-protected windows by ID
    local script='tell application "Google Chrome"'$'\n'
    for wid in "${ids_to_close[@]}"; do
        script+="    close (every window whose id is \"${wid}\")"$'\n'
    done
    script+='end tell'
    osascript -e "$script"

    # Zombie check: if 0 windows remain after close, quit the app
    local remaining
    remaining=$(osascript <<'APPLESCRIPT'
tell application "Google Chrome" to return count of windows
APPLESCRIPT
    )
    if [[ "$remaining" == "0" ]]; then
        quit_app "$app"
    fi
}
```

#### D. Modify classification in `main()`

Load protected patterns array once. After no-touch/slow-close/close-windows checks, before adding to `apps_to_quit`:

1. If protected patterns exist, call `get_chrome_window_tabs` (for Chrome) or System Events (for others) to get titles
2. Check titles against patterns in zsh (case-insensitive `${(L)...}` matching)
3. If match found → add to `apps_selective_close` instead of `apps_to_quit`

One osascript call per app, pattern matching in zsh.

#### E. Execution order in `main()`

1. Quit apps in parallel (unchanged)
2. Close-windows apps sequentially (unchanged)
3. Slow-close apps sequentially (unchanged)
4. **New**: Selective-close apps sequentially

#### F. Dry-run output

Show config patterns only — do NOT run osascript during dry-run (avoids triggering Automation permission dialogs):

```
Would SELECTIVE-CLOSE (matching: "Google Meet"):
  - Google Chrome
```

### Known limitations (accepted for v1)

- **TOCTOU**: If Meet tab opens during the sub-second classify→quit gap, Chrome could still be quit. Extremely unlikely in practice.
- **Non-Chrome apps**: Fallback uses System Events window names (active tab only). Config comment documents this.

## Files to modify

1. `config/clear_mac_apps.conf` — add `[protected-windows]` section
2. `custom_bins/clear-mac-apps` — rename parser, add helpers, modify classification + execution

## Verification

1. `clear-mac-apps --dry-run` with Chrome + Meet tab → Chrome under "SELECTIVE-CLOSE"
2. `clear-mac-apps --dry-run` with Chrome, no Meet → Chrome under "QUIT"
3. Live: Chrome with 2 windows (one has Meet tab, one doesn't) → Meet window closes, Meet window stays
4. Live: Chrome with 1 window, Meet tab + other tabs → window stays (has protected tab)
5. Live: Chrome with no Meet → Chrome quits normally
6. Live: Meet tab closed between classify and execute → Chrome quits (zombie check)
7. Verify other apps unaffected
