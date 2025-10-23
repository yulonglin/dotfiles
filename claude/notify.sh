#!/bin/bash
# Enhanced notification script for Claude Code
# Provides multiple notification methods: Dock bounce, Notification Center, and sound

# Function to log notification attempts
log_notification() {
    echo "$(date): $1" >> ~/.claude/logs/notifications.log
}

# Create logs directory if it doesn't exist
mkdir -p ~/.claude/logs

# Use terminal-notifier for cleaner notifications (if available)
if command -v terminal-notifier &> /dev/null; then
    # Use a unique group ID to replace previous notifications
    # This prevents notifications from stacking up in Notification Center
    terminal-notifier \
        -message "Claude Code task completed!" \
        -title "Claude Code" \
        -subtitle "Ready for your next request" \
        -sound "Ping" \
        -group "claude-code-notification" \
        2>/dev/null
    
    if [ $? -eq 0 ]; then
        log_notification "Terminal-notifier notification sent (replaces previous)"
    else
        log_notification "Terminal-notifier notification failed"
    fi
else
    # Fallback to direct osascript if terminal-notifier is not installed
    osascript -e 'display notification "Claude Code task completed!" with title "Claude Code" subtitle "Ready for your next request" sound name "Ping"' 2>/dev/null
    if [ $? -eq 0 ]; then
        log_notification "Notification Center alert sent (fallback)"
    else
        log_notification "Notification Center alert failed"
    fi
fi

# Make Cursor bounce in Dock without bringing to front
osascript -e '
tell application "Cursor"
    if running then
        set frontmost to false
        set visible to true
    end if
end tell
tell application "System Events"
    tell application process "Cursor"
        if exists then
            set frontmost to false
        end if
    end tell
end tell
' 2>/dev/null
if [ $? -eq 0 ]; then
    log_notification "Cursor dock bounce triggered (without bringing to front)"
else
    log_notification "Cursor dock bounce failed (app may not be running)"
fi

# Alternative: Terminal bell as fallback
echo -e "\a"
log_notification "Terminal bell sent as fallback"

# Optional: Play system sound as additional audio cue
afplay /System/Library/Sounds/Ping.aiff 2>/dev/null &
if [ $? -eq 0 ]; then
    log_notification "System sound played"
else
    log_notification "System sound failed"
fi