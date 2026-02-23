# Plan: Fix macOS Key Repeat Settings Resetting

## Context

On macOS Tahoe (26.x), keyboard repeat rate and delay-until-repeat settings spontaneously reset — sometimes after reboot, sometimes without any clear trigger. The GUI slider shows "fastest" / "shortest" but the actual repeat rate becomes much faster than intended (keys repeat with extreme sensitivity from normal typing), and the delay-until-repeat resets to the long end. This was not an issue on Sequoia or earlier.

Tahoe has [broader keyboard/input issues](https://discussions.apple.com/thread/256181139) — UI lag, input delays, and [keyboard glitches on M1](https://discussions.apple.com/thread/256184343). The settings reset may be related to Tahoe's new InputKit framework.

The right `defaults write` commands already exist in `config/macos_settings.sh:19-24` (applied one-time during `install.sh`). The fix is to **persistently enforce** these values at every login via a launchd `RunAtLoad` agent.

## Implementation

### 1. Create the enforcement binary

**File:** `custom_bins/enforce-keyboard-repeat` (new, executable)

Follows the established pattern — every setup script schedules a `custom_bins/` binary.

```bash
#!/bin/bash
# Enforce keyboard repeat settings (macOS Tahoe workaround)
# Tahoe spontaneously resets these values after reboot/sleep
[[ "$(uname -s)" != "Darwin" ]] && exit 0

defaults write -g InitialKeyRepeat -int 10
defaults write -g KeyRepeat -int 1
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
```

Also runnable standalone: `enforce-keyboard-repeat` from any terminal.

### 2. Create the setup script with inline plist

**File:** `scripts/cleanup/setup_keyboard_repeat.sh` (new, executable)

Self-contained — writes the `RunAtLoad` plist inline. Does NOT use `scripts/scheduler/scheduler.sh` (that abstraction is for time-based scheduling; `RunAtLoad` is structurally simpler and this is the only use case).

Follows the setup script pattern: uninstall-first, supports `--uninstall`.

```bash
#!/bin/bash
# Setup keyboard repeat enforcement at login (macOS only)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

LABEL="com.user.keyboard-repeat"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
BIN="$DOT_DIR/custom_bins/enforce-keyboard-repeat"

[[ "$(uname -s)" != "Darwin" ]] && exit 0

# Uninstall first (idempotent)
launchctl unload "$PLIST" 2>/dev/null || true
[[ -f "$PLIST" ]] && rm -f "$PLIST"

if [[ "${1:-}" == "--uninstall" ]]; then
    echo "Keyboard repeat enforcement uninstalled."
    exit 0
fi

# Verify binary exists
if [[ ! -f "$BIN" ]]; then
    echo "Warning: $BIN not found. Skipping."
    exit 1
fi

# Install plist
mkdir -p "$(dirname "$PLIST")"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/$LABEL.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/$LABEL.log</string>
</dict>
</plist>
EOF

launchctl load "$PLIST"
echo "Keyboard repeat enforcement installed (runs at login)."
```

### 3. Add deploy flag and wire into deploy.sh

**File:** `config.sh` — add `DEPLOY_KEYBOARD=true` to defaults, disable in `server` and `minimal` profiles.

**File:** `deploy.sh` — add new section after file cleanup (macOS only), following the exact pattern of other scheduled jobs:

```bash
# ─── Keyboard Repeat Enforcement (macOS only) ─────────────────────────────────

if [[ "$DEPLOY_KEYBOARD" == "true" ]] && is_macos; then
    log_info "Setting up keyboard repeat enforcement..."
    if [[ -f "$DOT_DIR/scripts/cleanup/setup_keyboard_repeat.sh" ]]; then
        "$DOT_DIR/scripts/cleanup/setup_keyboard_repeat.sh" || log_warning "Keyboard repeat setup failed"
    else
        log_warning "Keyboard repeat setup script not found"
    fi
fi
```

Also add `--keyboard` to deploy.sh help text.

## Files Summary

| File | Action | Notes |
|------|--------|-------|
| `custom_bins/enforce-keyboard-repeat` | **Create** | 3 `defaults write` commands, macOS guard |
| `scripts/cleanup/setup_keyboard_repeat.sh` | **Create** | Inline plist, `--uninstall` support |
| `config.sh` | **Modify** | Add `DEPLOY_KEYBOARD=true`, disable in server/minimal |
| `deploy.sh` | **Modify** | Add keyboard repeat section + help text |

**NOT modified** (vs. original plan):
- `scripts/scheduler/scheduler.sh` — over-engineering for single macOS-only use case
- `config/macos_settings.sh` — already applies settings one-time; scheduling is deploy.sh's concern

## Architecture

```
install.sh → config/macos_settings.sh  →  applies settings NOW (one-time)
deploy.sh  → setup_keyboard_repeat.sh  →  installs launchd agent (persistent, every login)
                                       →  custom_bins/enforce-keyboard-repeat (also manual)
```

Both paths are idempotent and complement each other.

## Verification

1. `chmod +x custom_bins/enforce-keyboard-repeat scripts/cleanup/setup_keyboard_repeat.sh`
2. Run `scripts/cleanup/setup_keyboard_repeat.sh` — verify plist created at `~/Library/LaunchAgents/com.user.keyboard-repeat.plist`
3. `launchctl list | grep keyboard-repeat` — should show the agent loaded
4. `defaults read -g KeyRepeat` → `1`, `defaults read -g InitialKeyRepeat` → `10`
5. Run `scripts/cleanup/setup_keyboard_repeat.sh --uninstall` — verify plist removed
6. Reboot and verify settings persist (the real test)
