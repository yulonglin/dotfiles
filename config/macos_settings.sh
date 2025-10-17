#!/bin/bash
# macOS System Defaults Configuration
# This script sets various macOS defaults for better developer experience
# Can be run standalone or called during install.sh

# Exit on error
set -e

# Check if running on macOS
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "This script is only for macOS. Skipping..."
    exit 0
fi

echo "Configuring macOS system defaults..."

# Keyboard settings
echo "  → Setting keyboard repeat rates..."
defaults write -g InitialKeyRepeat -int 10 2>/dev/null || true
defaults write -g KeyRepeat -int 1 2>/dev/null || true

# Enable repeating keys by pressing and holding down keys
echo "  → Enabling key repeat (disabling press-and-hold accents)..."
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false

# VSCode-specific press-and-hold disable
defaults write com.microsoft.VSCode ApplePressAndHoldEnabled -bool false 2>/dev/null || true

# Mouse settings
echo "  → Setting mouse tracking speed..."
defaults write -g com.apple.mouse.scaling 5.0 2>/dev/null || true

# Finder settings
echo "  → Configuring Finder..."

# Show hidden files
defaults write com.apple.finder AppleShowAllFiles YES

# Show path bar
defaults write com.apple.finder ShowPathbar -bool true

# Show status bar
defaults write com.apple.finder ShowStatusBar -bool true

# Show Library folder
chflags nohidden ~/Library 2>/dev/null || true

# Preview settings
echo "  → Configuring Preview..."
# Do not open previous previewed files (e.g. PDFs) when opening a new one
defaults write com.apple.Preview ApplePersistenceIgnoreState YES

# Screenshot settings
echo "  → Configuring screenshot location..."
SCREENSHOTS_DIR=~/Screenshots
mkdir -p "$SCREENSHOTS_DIR"
defaults write com.apple.screencapture location "$SCREENSHOTS_DIR"

# Restart affected services
echo "  → Restarting Finder and SystemUIServer..."
killall Finder 2>/dev/null || true
killall SystemUIServer 2>/dev/null || true

echo "✅ macOS system defaults configured successfully!"
echo ""
echo "Note: Some changes may require logging out and back in to take full effect."
echo ""
echo "Optional: Set up automatic cleanup for ~/Downloads and ~/Screenshots"
echo "  Run: $DOT_DIR/scripts/cleanup/install.sh"
