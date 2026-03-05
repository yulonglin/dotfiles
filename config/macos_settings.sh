#!/bin/bash
# macOS System Defaults Configuration
# This script sets various macOS defaults for better developer experience
# Can be run standalone or called during install.sh
#
# All commands are user-level (no sudo required).
# Tested on macOS Sonoma 14.x / Sequoia 15.x.

set -e

# Check if running on macOS
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "This script is only for macOS. Skipping..."
    exit 0
fi

echo "Configuring macOS system defaults..."

# ─── Keyboard ────────────────────────────────────────────────────────────────

configure_keyboard() {
    echo "  → Configuring keyboard..."

    # Fast key repeat (1 = fastest, 10 = short delay before repeat)
    defaults write -g InitialKeyRepeat -int 10 2>/dev/null || true
    defaults write -g KeyRepeat -int 1 2>/dev/null || true

    # Enable key repeat (disable press-and-hold accents)
    defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false 2>/dev/null || true
    defaults write com.microsoft.VSCode ApplePressAndHoldEnabled -bool false 2>/dev/null || true

    # Disable auto-capitalize
    defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false 2>/dev/null || true

    # Disable auto-correct
    defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false 2>/dev/null || true

    # Disable smart dashes
    defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false 2>/dev/null || true

    # Disable smart quotes
    defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false 2>/dev/null || true

    # Disable auto-period (double-space → period)
    defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false 2>/dev/null || true

    # Full keyboard access — Tab in all dialog controls
    defaults write NSGlobalDomain AppleKeyboardUIMode -int 3 2>/dev/null || true
}

# ─── Trackpad ─────────────────────────────────────────────────────────────────

configure_trackpad() {
    echo "  → Configuring trackpad..."

    # Tap to click (both built-in and Bluetooth trackpad)
    defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true 2>/dev/null || true
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true 2>/dev/null || true
    defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1 2>/dev/null || true

    # Three-finger vertical swipe → App Expose
    defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerVertSwipeGesture -int 2 2>/dev/null || true
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerVertSwipeGesture -int 2 2>/dev/null || true
    defaults write com.apple.dock showAppExposeGestureEnabled -bool true 2>/dev/null || true
}

# ─── Mouse ────────────────────────────────────────────────────────────────────

configure_mouse() {
    echo "  → Configuring mouse..."
    defaults write -g com.apple.mouse.scaling 5.0 2>/dev/null || true
}

# ─── Dock ─────────────────────────────────────────────────────────────────────

configure_dock() {
    echo "  → Configuring Dock..."

    # Hide recent apps section
    defaults write com.apple.dock show-recents -bool false 2>/dev/null || true

    # Don't automatically rearrange Spaces based on most recent use
    defaults write com.apple.dock mru-spaces -bool false 2>/dev/null || true

    # Disable workspace auto-switch when app opens on another Space
    defaults write com.apple.dock workspaces-auto-swoosh -bool NO 2>/dev/null || true

    # Faster auto-hide animation
    defaults write com.apple.dock autohide-time-modifier -float 0.2 2>/dev/null || true

    # Minimize windows to their application icon
    defaults write com.apple.dock minimize-to-application -bool true 2>/dev/null || true

    # Double-click title bar → fill screen
    defaults write NSGlobalDomain AppleActionOnDoubleClick -string "Fill" 2>/dev/null || true
}

# ─── Finder ───────────────────────────────────────────────────────────────────

configure_finder() {
    echo "  → Configuring Finder..."

    # Show hidden files
    defaults write com.apple.finder AppleShowAllFiles YES 2>/dev/null || true

    # Show path bar + status bar
    defaults write com.apple.finder ShowPathbar -bool true 2>/dev/null || true
    defaults write com.apple.finder ShowStatusBar -bool true 2>/dev/null || true

    # Show Library folder
    chflags nohidden ~/Library 2>/dev/null || true

    # New Finder window → Downloads
    defaults write com.apple.finder NewWindowTarget -string "PfLo" 2>/dev/null || true
    defaults write com.apple.finder NewWindowTargetPath -string "file://${HOME}/Downloads/" 2>/dev/null || true

    # Hide desktop icons (external drives, servers, removable media)
    defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool false 2>/dev/null || true
    defaults write com.apple.finder ShowHardDrivesOnDesktop -bool false 2>/dev/null || true
    defaults write com.apple.finder ShowMountedServersOnDesktop -bool false 2>/dev/null || true
    defaults write com.apple.finder ShowRemovableMediaOnDesktop -bool false 2>/dev/null || true

    # Folders on top when sorting by name
    defaults write com.apple.finder _FXSortFoldersFirst -bool true 2>/dev/null || true

    # Search the current folder by default
    defaults write com.apple.finder FXDefaultSearchScope -string "SCcf" 2>/dev/null || true

    # Disable extension change warning
    defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false 2>/dev/null || true

    # Show all filename extensions
    defaults write NSGlobalDomain AppleShowAllExtensions -bool true 2>/dev/null || true

    # No .DS_Store on network and USB volumes
    defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true 2>/dev/null || true
    defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true 2>/dev/null || true

    # Default to list view
    defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv" 2>/dev/null || true

    # Auto-empty Trash after 30 days (verify with `defaults read` on each macOS upgrade)
    defaults write com.apple.finder FXRemoveOldTrashItems -bool true 2>/dev/null || true
}

# ─── General UI/UX ────────────────────────────────────────────────────────────

configure_ui() {
    echo "  → Configuring general UI/UX..."

    # Expand save panel by default
    defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true 2>/dev/null || true
    defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true 2>/dev/null || true

    # Expand print panel by default
    defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true 2>/dev/null || true
    defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true 2>/dev/null || true

    # Save to disk, not iCloud, by default
    defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false 2>/dev/null || true

    # Drag windows from anywhere with Ctrl+Cmd+click (macOS Sequoia+)
    defaults write NSGlobalDomain NSWindowShouldDragOnGesture -bool true 2>/dev/null || true
}

# ─── Preview ──────────────────────────────────────────────────────────────────

configure_preview() {
    echo "  → Configuring Preview..."
    defaults write com.apple.Preview ApplePersistenceIgnoreState YES 2>/dev/null || true
}

# ─── Screenshots ──────────────────────────────────────────────────────────────

configure_screenshots() {
    echo "  → Configuring screenshots..."
    SCREENSHOTS_DIR=~/Screenshots
    mkdir -p "$SCREENSHOTS_DIR"
    defaults write com.apple.screencapture location "$SCREENSHOTS_DIR" 2>/dev/null || true
}

# ─── App Store ────────────────────────────────────────────────────────────────

configure_appstore() {
    echo "  → Configuring App Store..."

    # Auto-check for updates
    defaults write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true 2>/dev/null || true

    # Auto-download updates
    defaults write com.apple.SoftwareUpdate AutomaticDownload -int 1 2>/dev/null || true

    # Auto-update App Store apps
    defaults write com.apple.commerce AutoUpdate -bool true 2>/dev/null || true
}

# ─── Activity Monitor ────────────────────────────────────────────────────────

configure_activity_monitor() {
    echo "  → Configuring Activity Monitor..."

    # Show all processes
    defaults write com.apple.ActivityMonitor ShowCategory -int 0 2>/dev/null || true

    # Sort by CPU usage descending
    defaults write com.apple.ActivityMonitor SortColumn -string "CPUUsage" 2>/dev/null || true
    defaults write com.apple.ActivityMonitor SortDirection -int 0 2>/dev/null || true
}

# ─── Misc ─────────────────────────────────────────────────────────────────────

configure_misc() {
    echo "  → Configuring misc settings..."

    # Disable crash reporter dialog
    defaults write com.apple.CrashReporter DialogType -string "none" 2>/dev/null || true

    # Safari: show status bar
    defaults write com.apple.Safari ShowOverlayStatusBar -bool true 2>/dev/null || true
}

# ─── Run All ──────────────────────────────────────────────────────────────────

configure_keyboard
configure_trackpad
configure_mouse
configure_dock
configure_finder
configure_ui
configure_preview
configure_screenshots
configure_appstore
configure_activity_monitor
configure_misc

# ─── Restart Affected Services ───────────────────────────────────────────────

echo "  → Restarting affected services..."
killall Dock 2>/dev/null || true
killall Finder 2>/dev/null || true
killall SystemUIServer 2>/dev/null || true

echo "✅ macOS system defaults configured successfully!"
echo ""
echo "Note: Some changes may require logging out and back in to take full effect."
echo ""
echo "Optional: Run scripts/macos_sudo_extras.sh for firewall + GarageBand removal"
echo "Manual: Enable FileVault in System Settings > Privacy & Security > FileVault"
echo "Manual: System Settings > Lock Screen > Require password: Immediately"
echo ""
echo "Optional: Set up automatic cleanup for ~/Downloads and ~/Screenshots"
echo "  Run: $DOT_DIR/scripts/cleanup/install.sh"
