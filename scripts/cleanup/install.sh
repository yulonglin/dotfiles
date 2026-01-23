#!/bin/bash
# Install automatic cleanup job for old files in Downloads and Screenshots
# Works on both macOS (launchd) and Linux (cron)

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEANUP_SCRIPT="$SCRIPT_DIR/cleanup_old_files.sh"

# Default configuration
RETENTION_DAYS=${RETENTION_DAYS:-180}  # 6 months
SCHEDULE_INTERVAL=${SCHEDULE_INTERVAL:-monthly}  # daily, weekly, monthly

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

# Check if cleanup script exists
if [[ ! -f "$CLEANUP_SCRIPT" ]]; then
    log_error "Cleanup script not found: $CLEANUP_SCRIPT"
    exit 1
fi

# Make sure cleanup script is executable
chmod +x "$CLEANUP_SCRIPT"

# Function to install on macOS using launchd
install_macos() {
    local plist_file="$HOME/Library/LaunchAgents/com.user.cleanup-old-files.plist"
    local interval_seconds

    case "$SCHEDULE_INTERVAL" in
        daily)
            interval_seconds=86400
            ;;
        weekly)
            interval_seconds=604800
            ;;
        monthly)
            interval_seconds=2592000
            ;;
        *)
            log_error "Unknown schedule interval: $SCHEDULE_INTERVAL"
            exit 1
            ;;
    esac

    log_step "Creating launchd plist: $plist_file"

    mkdir -p "$HOME/Library/LaunchAgents"

    cat > "$plist_file" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.cleanup-old-files</string>
    <key>ProgramArguments</key>
    <array>
        <string>$CLEANUP_SCRIPT</string>
    </array>
    <key>StartInterval</key>
    <integer>$interval_seconds</integer>
    <key>RunAtLoad</key>
    <false/>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/cleanup-old-files.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/cleanup-old-files.error.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>RETENTION_DAYS</key>
        <string>$RETENTION_DAYS</string>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
</dict>
</plist>
EOF

    log_step "Loading launchd job..."
    launchctl unload "$plist_file" 2>/dev/null || true
    launchctl load "$plist_file"

    log_info "✅ Cleanup job installed successfully!"
    echo ""
    log_info "Configuration:"
    echo "  • Schedule: $SCHEDULE_INTERVAL"
    echo "  • Retention: $RETENTION_DAYS days"
    echo "  • Logs: $HOME/Library/Logs/cleanup-old-files.log"
    echo ""
    log_info "To uninstall, run: $SCRIPT_DIR/uninstall.sh"
}

# Function to install on Linux using cron
install_linux() {
    local cron_schedule

    case "$SCHEDULE_INTERVAL" in
        daily)
            cron_schedule="0 2 * * *"  # 2 AM daily
            ;;
        weekly)
            cron_schedule="0 2 * * 0"  # 2 AM every Sunday
            ;;
        monthly)
            cron_schedule="0 2 1 * *"  # 2 AM on 1st of month
            ;;
        *)
            log_error "Unknown schedule interval: $SCHEDULE_INTERVAL"
            exit 1
            ;;
    esac

    log_step "Adding cron job..."

    # Check if job already exists
    if crontab -l 2>/dev/null | grep -q "cleanup_old_files.sh"; then
        log_warn "Cleanup job already exists in crontab. Removing old entry..."
        crontab -l 2>/dev/null | grep -v "cleanup_old_files.sh" | crontab -
    fi

    # Add new cron job
    (crontab -l 2>/dev/null; echo "$cron_schedule RETENTION_DAYS=$RETENTION_DAYS $CLEANUP_SCRIPT >> $HOME/.cleanup-old-files.log 2>&1") | crontab -

    log_info "✅ Cleanup job installed successfully!"
    echo ""
    log_info "Configuration:"
    echo "  • Schedule: $SCHEDULE_INTERVAL ($cron_schedule)"
    echo "  • Retention: $RETENTION_DAYS days"
    echo "  • Logs: $HOME/.cleanup-old-files.log"
    echo ""
    log_info "To uninstall, run: $SCRIPT_DIR/uninstall.sh"
}

# Main installation
main() {
    echo ""
    log_step "Installing automatic cleanup job"
    echo ""

    # Show configuration
    log_info "This will set up automatic cleanup for:"
    echo "  • ~/Downloads"
    echo "  • ~/Screenshots"
    echo ""
    log_info "Files will be moved to trash if:"
    echo "  • Not accessed or modified in $RETENTION_DAYS days"
    echo "  • Cleanup runs: $SCHEDULE_INTERVAL"
    echo ""

    # Ask for confirmation unless non-interactive
    if [[ "${NON_INTERACTIVE:-false}" != "true" ]]; then
        read -p "Continue with installation? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_warn "Installation cancelled"
            exit 0
        fi
    fi

    echo ""

    # Detect OS and install
    if [[ "$(uname -s)" == "Darwin" ]]; then
        install_macos
    elif [[ "$(uname -s)" == "Linux" ]]; then
        install_linux
    else
        log_error "Unsupported operating system: $(uname -s)"
        exit 1
    fi

    # Install Claude Code session cleanup
    if [[ -f "$SCRIPT_DIR/setup_claude_cleanup.sh" ]]; then
        "$SCRIPT_DIR/setup_claude_cleanup.sh"
    fi

    echo ""
    log_info "Testing cleanup script (dry run)..."
    "$CLEANUP_SCRIPT" --dry-run || log_warn "Dry run test failed. Check permissions."
}

# Parse command line arguments
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --days)
            RETENTION_DAYS="$2"
            shift 2
            ;;
        --schedule)
            SCHEDULE_INTERVAL="$2"
            shift 2
            ;;
        --non-interactive|-y)
            NON_INTERACTIVE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --days DAYS             Set retention period in days (default: 180)"
            echo "  --schedule INTERVAL     Set schedule: daily, weekly, monthly (default: monthly)"
            echo "  --non-interactive, -y   Skip confirmation prompt"
            echo "  --help                  Show this help message"
            echo ""
            echo "Environment variables:"
            echo "  RETENTION_DAYS         Override default retention period"
            echo "  SCHEDULE_INTERVAL      Override default schedule"
            echo ""
            echo "Examples:"
            echo "  $0                              # Install with defaults (180 days, monthly)"
            echo "  $0 --days 90 --schedule weekly  # Custom retention and schedule"
            echo "  $0 -y                           # Skip confirmation prompt"
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
