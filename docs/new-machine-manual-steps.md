# New Machine — Manual Steps

The irreducible clicks. Everything automatable lives in `config/macos_settings.sh`
(run automatically on macOS install) and the `deploy.sh` components. The items below
have **no automation path** — they're security-gated, stored in opaque plists
(SFL2 / symbolichotkeys), or live inside third-party apps. Work top to bottom on a
fresh Mac.

> Run the automated layer first: `./install.sh` then `./deploy.sh`. Then do these.

## Security (do first)

- **FileVault** — System Settings → Privacy & Security → FileVault → Turn On.
  Can't be scripted: macOS shows the recovery key and requires interactive confirmation.
- **Firewall + stealth mode** — automated but opt-in (needs sudo):
  `scripts/macos_sudo_extras.sh`.
- **Lock screen → require password immediately** — System Settings → Lock Screen →
  "Require password after screen saver begins…" → Immediately.
  Apple removed the `askForPasswordDelay` default on Sonoma+, so this can no longer
  be set via `defaults`. Must be done in the UI.

## Apple Shortcuts

- **Allow Running Scripts** — Shortcuts → Settings → Advanced → enable
  "Allow Running Scripts" (and the other Advanced toggles as needed).
  These are per-device security gates stored in Shortcuts' iCloud/CloudKit store,
  intentionally **not** exposed to `defaults`. Does not sync across machines — flip
  it once per Mac. Required for Run Shell Script / Run AppleScript / Run Script over SSH.

## Finder

- **Sidebar** — add Home + your code dir; uncheck all Shared. Stored in the SFL2
  plist (`~/Library/Application Support/com.apple.sharedfilelist/…`), too opaque to script reliably.
- **Tags** — disable all (Finder → Settings → Tags). Same SFL2 territory.

## Keyboard / Menu bar

- **Keyboard backlight** — turn off after 5 min inactivity (System Settings → Keyboard).
  No stable `defaults` key.
- **Disable Spotlight shortcut** (⌘Space) — System Settings → Keyboard → Keyboard
  Shortcuts → Spotlight, uncheck. Frees ⌘Space if you want it elsewhere.
  (symbolichotkeys plist — scriptable in theory but fragile; do it by hand.)
- **Menu bar control center icons** — battery percentage is now automated
  (`com.apple.controlcenter BatteryShowPercentage`); add/remove any other Control
  Center icons to taste in System Settings → Control Center.

## Global hotkeys (third-party apps — set inside each app)

| App | Binding | Notes |
|-----|---------|-------|
| Alfred | Caps Lock → summon | **Automated** via `alfred-fix` golden snapshot (`config/alfred/local-golden/`). Verify after first launch. |
| Mouseless | grid = Right ⌘, free mode = Right ⌥ | Config in `config/mouseless/config.yaml` (copied by deploy). |
| VoiceInk | Right Shift → start recording | Manual — set in VoiceInk's own settings. |

> Caps Lock as a hotkey needs Caps Lock to emit a keycode (System Settings →
> Keyboard → Modifier Keys, or a remapper). Confirm Alfred actually captures it.

## Misc apps

- **uBlock Origin Lite** — enable the cookie-notices filter list (Filter lists → Annoyances).
- **GarageBand** — removal is automated but opt-in via `scripts/macos_sudo_extras.sh`.
- **Safari** — status bar is automated (`ShowOverlayStatusBar`); nothing else needed.

---

_Anything on this list that becomes scriptable on a future macOS → move it into
`config/macos_settings.sh` and delete it here._
