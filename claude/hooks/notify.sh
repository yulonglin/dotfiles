#!/bin/sh
# Notification script for Claude Code
# Sends desktop notification when Claude finishes a task

# Function to log notification attempts
log_notification() {
    echo "$(date): $1" >> ~/.claude/logs/notifications.log
}

# Create logs directory if it doesn't exist
mkdir -p ~/.claude/logs

# Priority order and bundle IDs for -activate flag
# Cursor uses ToDesktop for packaging, hence the unusual bundle ID
APP_PRIORITY="Warp ghostty Cursor Code iTerm2"

get_app_bundle_id() {
    for app in $APP_PRIORITY; do
        if pgrep -x "$app" > /dev/null; then
            case "$app" in
                Warp)    echo "dev.warp.Warp-Stable" ;;
                ghostty) echo "com.mitchellh.ghostty" ;;
                Cursor)  echo "com.todesktop.230313mzl4w4u92" ;;
                Code)    echo "com.microsoft.VSCode" ;;
                iTerm2)  echo "com.googlecode.iterm2" ;;
            esac
            return
        fi
    done
    echo "com.apple.Terminal"
}

# Use terminal-notifier for cleaner notifications (if available)
if command -v terminal-notifier &> /dev/null; then
    BUNDLE_ID=$(get_app_bundle_id)
    # -activate: clicking notification brings specified app to front
    # -group: replaces previous notifications (prevents stacking)
    terminal-notifier \
        -message "Claude Code task completed!" \
        -title "Claude Code" \
        -subtitle "Ready for your next request" \
        -sound "Ping" \
        -group "claude-code-notification" \
        -activate "$BUNDLE_ID" \
        2>/dev/null

    if [ $? -eq 0 ]; then
        log_notification "Notification sent (activate: $BUNDLE_ID)"
    else
        log_notification "terminal-notifier failed"
    fi
else
    # Fallback to osascript (clicking will open Script Editor - known limitation)
    osascript -e 'display notification "Claude Code task completed!" with title "Claude Code" subtitle "Ready for your next request" sound name "Ping"' 2>/dev/null
    if [ $? -eq 0 ]; then
        log_notification "osascript notification sent (fallback)"
    else
        log_notification "osascript notification failed"
    fi
fi

# Terminal bell as additional fallback
printf '\a'
