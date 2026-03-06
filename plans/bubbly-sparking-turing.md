# Dotfile Resources Adaptation Plan

## Context

Research across 5 dotfile resource categories (mathiasbynens/dotfiles, dotfiles.github.io bootstrap/utilities/frameworks, starship) to identify high-value additions. Cherry-picking specific improvements, not wholesale framework migrations.

Critiqued by Codex (correctness/safety), Gemini (gaps/compatibility), and plan-critic (architecture). All findings incorporated.

## Research Summary

### What's NOT Worth Adopting

| Resource | Verdict | Reasoning |
|----------|---------|-----------|
| **Starship prompt** | Skip | p10k is ZSH-optimized with instant prompt; Starship's cross-shell advantage not needed |
| **ZSH framework switch** (zinit/zgenom) | Skip | Migration cost > ~50-100ms startup savings. Revisit if startup >300ms |
| **Dotfile managers** (chezmoi/stow/dotbot) | Skip | Our install.sh/deploy.sh already handles profiles, smart merge, conflict resolution |
| **mathiasbynens basic aliases** (ls, grep) | Skip | Superseded by eza, bat, rg |

---

## 1. Expand macOS Defaults (`config/macos_settings.sh`)

**Tested on: macOS Sonoma 14.x / Sequoia 15.x. All user-level `defaults write`, no sudo.**

### Trackpad
- `defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true` — tap to click
- `defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1` — tap to click (login screen)
- `defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerVertSwipeGesture -int 2` — App Expose gesture
- `defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerVertSwipeGesture -int 2` — same (Bluetooth)
- `defaults write com.apple.dock showAppExposeGestureEnabled -bool true` — enable in Dock prefs

### Keyboard (supplements existing)
- `NSAutomaticCapitalizationEnabled -bool false` — disable auto-capitalize
- `NSAutomaticSpellingCorrectionEnabled -bool false` — disable auto-correct
- `NSAutomaticDashSubstitutionEnabled -bool false` — disable smart dashes
- `NSAutomaticQuoteSubstitutionEnabled -bool false` — disable smart quotes
- `NSAutomaticPeriodSubstitutionEnabled -bool false` — disable auto-period
- `AppleKeyboardUIMode -int 3` — full keyboard access (Tab in dialogs)

### Dock
- `com.apple.dock show-recents -bool false` — hide recent apps
- `com.apple.dock workspaces-auto-swoosh -bool NO` — disable workspace auto-switch
- `com.apple.dock autohide-time-modifier -float 0.2` — faster auto-hide animation
- `com.apple.dock minimize-to-application -bool true` — minimize to app icon
- `NSGlobalDomain AppleActionOnDoubleClick -string "Fill"` — double-click title bar → fill (**NOTE:** value is "Fill" not "Maximize" on macOS 14+)

### Finder (supplements existing)
- `com.apple.finder NewWindowTarget -string "PfLo"` + `NewWindowTargetPath -string "file://${HOME}/Downloads/"` — new window → Downloads
- `com.apple.finder ShowExternalHardDrivesOnDesktop -bool false` — hide desktop icons (all 4 types)
- `com.apple.finder ShowHardDrivesOnDesktop -bool false`
- `com.apple.finder ShowMountedServersOnDesktop -bool false`
- `com.apple.finder ShowRemovableMediaOnDesktop -bool false`
- `com.apple.finder _FXSortFoldersFirst -bool true` — folders on top
- `com.apple.finder FXDefaultSearchScope -string "SCcf"` — search current folder
- `com.apple.finder FXEnableExtensionChangeWarning -bool false` — no extension change warning
- `NSGlobalDomain AppleShowAllExtensions -bool true` — show all extensions
- `com.apple.desktopservices DSDontWriteNetworkStores -bool true` — no .DS_Store on network
- `com.apple.desktopservices DSDontWriteUSBStores -bool true` — no .DS_Store on USB
- `com.apple.finder FXPreferredViewStyle -string "Nlsv"` — list view default
- `com.apple.finder FXRemoveOldTrashItems -bool true` — auto-empty Trash after 30 days (verify with `defaults read` on each macOS upgrade)
- ~~`_FXShowPosixPathInTitle`~~ — **REMOVED**: broken on macOS Sequoia 15

### General UI/UX
- `NSNavPanelExpandedStateForSaveMode -bool true` (×2) — expand save panel
- `PMPrintingExpandedStateForPrint -bool true` (×2) — expand print panel
- `NSDocumentSaveNewDocumentsToCloud -bool false` — save to disk, not iCloud
- `NSWindowResizeTime -float 0.001` — instant window resize (may be non-functional on macOS 14+; harmless)

### Lock Screen
- ~~`askForPassword`~~ — **REMOVED**: deprecated since macOS 13. Add echo: `"Manual: System Settings > Lock Screen > Require password: Immediately"`

### App Store
- `com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true` — auto-check
- `com.apple.SoftwareUpdate AutomaticDownload -int 1` — auto-download
- `com.apple.commerce AutoUpdate -bool true` — auto-update apps

### Activity Monitor
- `com.apple.ActivityMonitor ShowCategory -int 0` — show all processes
- `com.apple.ActivityMonitor SortColumn -string "CPUUsage"` + `SortDirection -int 0` — sort by CPU desc

### Misc
- `com.apple.CrashReporter DialogType -string "none"` — disable crash reporter dialog
- `com.apple.Safari ShowOverlayStatusBar -bool true` — Safari status bar

### Implementation Notes
- Add `killall Dock` after Dock section (auto-restarts in <1s)
- Keep existing `killall Finder` and `killall SystemUIServer`
- ALL commands use `2>/dev/null || true` pattern consistently (fix existing inconsistency too)
- Wrap categories in functions (`configure_dock()`, `configure_finder()`, etc.) for maintainability
- Script remains idempotent

### Sudo Operations → Separate Script (`scripts/macos_sudo_extras.sh`)

**Do NOT put interactive prompts inside macos_settings.sh** (breaks in pipes/CI/subshells). Create a standalone script referenced with echo at the end of macos_settings.sh.

Contents of `scripts/macos_sudo_extras.sh`:
```bash
# Firewall
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on

# GarageBand removal (if installed)
if [[ -d "/Applications/GarageBand.app" ]]; then
    sudo trash "/Applications/GarageBand.app" 2>/dev/null || \
        sudo rm -rf "/Applications/GarageBand.app"
fi
```

At end of `macos_settings.sh`:
```bash
echo "Optional: Run scripts/macos_sudo_extras.sh for firewall + GarageBand removal"
echo "Manual: Enable FileVault in System Settings > Privacy & Security > FileVault"
echo "Manual: System Settings > Lock Screen > Require password: Immediately"
```

### Files to modify
- `config/macos_settings.sh` — expand with new sections
- `scripts/macos_sudo_extras.sh` — new file for sudo operations

---

## 2. Add Shell Functions (`config/modern_tools.sh`)

Functions to add (8 total). macOS-only ones gated with `[[ "$(uname)" == "Darwin" ]]`.

| Function | Implementation | Notes |
|----------|---------------|-------|
| `mkd` | `mkdir -p "$@" && cd "$_"` | General-purpose |
| `cdf` | AppleScript to get Finder window path | **macOS-only**, handle no-window case |
| `targz` | Smart tar+compress (zopfli/pigz/gzip) | Cross-platform |
| `dataurl` | `file -b --mime-type` + `openssl base64` | Cross-platform |
| `digga` | `dig +nocmd "$1" any +multiline +noall +answer` | Cross-platform |
| `getcertnames` | openssl s_client + x509 cert parsing | Cross-platform |
| `o` | Cross-platform `open` (macOS: open, Linux: xdg-open) | Check for oh-my-zsh conflict first |
| `server` | `python3 -m http.server "${1:-8000}"` | **Python 3 explicit** |

### Files to modify
- `config/modern_tools.sh` — add new functions section

---

## 3. Add System Aliases (`config/aliases.sh`)

**Removed from original plan** (already exist as functions in modern_tools.sh):
- ~~`ip`~~ — shadows Linux `/usr/sbin/ip` command. Existing `myip()` function works.
- ~~`localip`~~ — already exists as `localip()` in modern_tools.sh
- ~~`lscleanup`~~ — too niche for daily use
- ~~`update`~~ — already have `ai-update` and `pkg-update`

**Keeping:**

| Alias | Command | Platform |
|-------|---------|----------|
| `flush` | macOS: `dscacheutil -flushcache && killall -HUP mDNSResponder`; Linux: `sudo resolvectl flush-caches` | Both (gated) |
| `week` | `date +%V` | Both |
| `afk` | `pmset displaysleepnow` | macOS only (stable across versions) |

**Platform gating:** Use `[[ "$(uname)" == "Darwin" ]]` (not `is_macos` — that's in helpers.sh, not available at shell sourcing time).

### Files to modify
- `config/aliases.sh` — add system aliases section

---

## 4. Add Config Files + `.hushlogin`

### New config files
- **`config/editorconfig`** → `~/.editorconfig` (symlink via `safe_symlink`)
- **`config/curlrc`** → `~/.curlrc` (symlink). Keep minimal: just `--location` and `--show-error`. Document `curl --disable` to bypass.
- **`config/inputrc`** → `~/.inputrc` (symlink). Case-insensitive completion, show all on single tab, colored stats.
- **`config/gitattributes_global`** → `~/.gitattributes` (symlink). Binary file handling (*.png, *.jpg, *.zip, *.pdf as binary; `* text=auto` for line endings). Reference from gitconfig `core.attributesFile`.

### `.hushlogin`
- `touch "$HOME/.hushlogin"` — suppresses "Last login" message

### Deploy integration
Bundle under existing `--editor` flag (`DEPLOY_EDITOR`) since these are editor-adjacent configs. Add to `deploy_editor_settings()` using `safe_symlink` pattern.

### Files to modify
- `config/editorconfig` — new file
- `config/curlrc` — new file
- `config/inputrc` — new file
- `config/gitattributes_global` — new file
- `deploy.sh` — add to `deploy_editor_settings()`, add `.hushlogin` touch

---

## 5. Update Documentation

### Files to modify
- `CLAUDE.md` — update config/ directory listing, mention new files
- `README.md` — document new aliases/functions, macOS defaults expansion

---

## Implementation Order

1. macOS defaults expansion in `config/macos_settings.sh` + new `scripts/macos_sudo_extras.sh`
2. Shell functions in `config/modern_tools.sh` (8 functions)
3. System aliases in `config/aliases.sh` (3 aliases: flush, week, afk)
4. Config files: editorconfig, curlrc, inputrc, gitattributes_global + deploy.sh integration + .hushlogin
5. Documentation: CLAUDE.md, README.md
6. Commit

## Verification

- `shellcheck config/macos_settings.sh scripts/macos_sudo_extras.sh`
- Run `config/macos_settings.sh` on macOS — verify no errors
- Spot-check: `defaults read com.apple.dock show-recents`, `defaults read NSGlobalDomain NSAutomaticCapitalizationEnabled`
- Source `config/modern_tools.sh` in fresh shell — test `mkd /tmp/test123`, `digga google.com`, `server`
- Verify aliases: `flush`, `week`, `afk`
- `./deploy.sh --minimal --editor` — verify symlinks created: `ls -la ~/.editorconfig ~/.curlrc ~/.inputrc ~/.gitattributes ~/.hushlogin`
- Verify `.gitattributes` referenced: `git config --global core.attributesFile`
