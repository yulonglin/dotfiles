#!/bin/bash
# Uninstall automatic cleanup job
# Works on both macOS (launchd) and Linux (cron)

set -e

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}==>${NC} $1"
}

# Function to uninstall from macOS
uninstall_macos() {
    local plist_file="$HOME/Library/LaunchAgents/com.user.cleanup-old-files.plist"

    if [[ ! -f "$plist_file" ]]; then
        log_warn "Cleanup job not found (launchd plist doesn't exist)"
        return 1
    fi

    log_step "Unloading launchd job..."
    launchctl unload "$plist_file" 2>/dev/null || true

    log_step "Removing plist file..."
    rm "$plist_file"

    # Optionally remove logs
    if [[ -f "$HOME/Library/Logs/cleanup-old-files.log" ]]; then
        log_info "Cleanup logs still exist at: $HOME/Library/Logs/cleanup-old-files.log"
        if [[ "${NON_INTERACTIVE:-false}" != "true" ]]; then
            read -p "Remove logs? [y/N] " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rm -f "$HOME/Library/Logs/cleanup-old-files.log"
                rm -f "$HOME/Library/Logs/cleanup-old-files.error.log"
                log_info "Logs removed"
            fi
        fi
    fi

    log_info "✅ Cleanup job uninstalled successfully!"
    return 0
}

# Function to uninstall from Linux
uninstall_linux() {
    if ! crontab -l 2>/dev/null | grep -q "cleanup_old_files.sh"; then
        log_warn "Cleanup job not found in crontab"
        return 1
    fi

    log_step "Removing cron job..."
    crontab -l 2>/dev/null | grep -v "cleanup_old_files.sh" | crontab -

    # Optionally remove logs
    if [[ -f "$HOME/.cleanup-old-files.log" ]]; then
        log_info "Cleanup logs still exist at: $HOME/.cleanup-old-files.log"
        if [[ "${NON_INTERACTIVE:-false}" != "true" ]]; then
            read -p "Remove logs? [y/N] " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rm -f "$HOME/.cleanup-old-files.log"
                log_info "Logs removed"
            fi
        fi
    fi

    log_info "✅ Cleanup job uninstalled successfully!"
    return 0
}

# Main uninstallation
main() {
    echo ""
    log_step "Uninstalling automatic cleanup job"
    echo ""

    # Detect OS and uninstall
    local result=1
    if [[ "$(uname -s)" == "Darwin" ]]; then
        uninstall_macos && result=0
    elif [[ "$(uname -s)" == "Linux" ]]; then
        uninstall_linux && result=0
    else
        log_error "Unsupported operating system: $(uname -s)"
        exit 1
    fi

    if [[ $result -ne 0 ]]; then
        echo ""
        log_error "No cleanup job was found to uninstall"
        exit 1
    fi

    echo ""
    log_info "The cleanup script itself is still available at:"
    echo "  $(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cleanup_old_files.sh"
    echo ""
    log_info "You can still run it manually anytime."
}

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --non-interactive|-y)
            NON_INTERACTIVE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --non-interactive, -y   Skip confirmation prompts"
            echo "  --help                  Show this help message"
            echo ""
            echo "This will remove the automatic cleanup job from:"
            echo "  • macOS: launchd (~/Library/LaunchAgents)"
            echo "  • Linux: crontab"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

main
