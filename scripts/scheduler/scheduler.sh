#!/bin/bash
# Cross-platform job scheduler abstraction
# Handles launchd (macOS) and cron (Linux)

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

_sched_log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
_sched_log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
_sched_log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Validate job ID format (alphanumeric, underscore, hyphen only)
_validate_job_id() {
    local job_id="$1"
    if [[ ! "$job_id" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        _sched_log_error "Invalid job_id: '$job_id' (only alphanumeric, underscore, hyphen allowed)"
        return 1
    fi
}

# Ensure cron is available on Linux
# Returns 0 if available, 1 if not (with install instructions)
ensure_cron() {
    [[ "$(uname -s)" == "Darwin" ]] && return 0
    command -v crontab &>/dev/null && return 0

    _sched_log_error "cron is not installed. Please install it:"
    if command -v apt-get &>/dev/null; then
        echo "  sudo apt-get install -y cron && sudo service cron start"
    elif command -v dnf &>/dev/null; then
        echo "  sudo dnf install -y cronie && sudo systemctl enable --now crond"
    elif command -v pacman &>/dev/null; then
        echo "  sudo pacman -S --noconfirm cronie && sudo systemctl enable --now cronie"
    else
        echo "  Install the 'cron' package for your distribution"
    fi
    return 1
}

# Add a cron job (Linux only, idempotent)
# Usage: add_cron_job "job_id" "schedule" "command"
# Example: add_cron_job "my-cleanup" "0 17 * * *" "/path/to/script"
add_cron_job() {
    local job_id="$1"
    local schedule="$2"
    local command="$3"
    local log_file="${4:-$HOME/.$job_id.log}"

    [[ "$(uname -s)" != "Linux" ]] && return 0
    ensure_cron || return 1

    # Remove existing job with same ID
    remove_cron_job "$job_id" 2>/dev/null || true

    # Add new job
    ( (crontab -l 2>/dev/null || true); echo "$schedule $command >> $log_file 2>&1 # $job_id") | crontab -
}

# Remove a cron job by ID (Linux only)
# Matches: "# job_id" at end (new format) OR "/job_id " followed by >> (old format)
remove_cron_job() {
    local job_id="$1"
    [[ "$(uname -s)" != "Linux" ]] && return 0

    if crontab -l 2>/dev/null | grep -qE "(# ${job_id}$|/${job_id} .*>>)"; then
        crontab -l 2>/dev/null | grep -vE "(# ${job_id}$|/${job_id} .*>>)" | crontab -
        return 0
    fi
    return 1
}

# Create a launchd plist (macOS only)
# Usage: create_launchd_plist "label" "command" "hour" "minute" "log_file"
create_launchd_plist() {
    local label="$1"
    local command="$2"
    local hour="${3:-17}"
    local minute="${4:-0}"
    local log_file="${5:-$HOME/Library/Logs/$label.log}"
    local plist_file="$HOME/Library/LaunchAgents/$label.plist"

    [[ "$(uname -s)" != "Darwin" ]] && return 0

    mkdir -p "$(dirname "$plist_file")"
    cat > "$plist_file" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$label</string>
    <key>ProgramArguments</key>
    <array>
        <string>$command</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>$hour</integer>
        <key>Minute</key>
        <integer>$minute</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>$log_file</string>
    <key>StandardErrorPath</key>
    <string>$log_file</string>
</dict>
</plist>
EOF
    echo "$plist_file"
}

# Load a launchd plist (macOS only)
load_launchd() {
    local plist_file="$1"
    [[ "$(uname -s)" != "Darwin" ]] && return 0
    launchctl unload "$plist_file" 2>/dev/null || true
    launchctl load "$plist_file"
}

# Unload and remove a launchd plist (macOS only)
remove_launchd() {
    local label="$1"
    local plist_file="$HOME/Library/LaunchAgents/$label.plist"
    [[ "$(uname -s)" != "Darwin" ]] && return 0
    [[ ! -f "$plist_file" ]] && return 0
    launchctl unload "$plist_file" 2>/dev/null || true
    rm -f "$plist_file"
}

# Schedule a daily job (cross-platform)
# Usage: schedule_daily "job_id" "command" "hour" [minute] [log_file]
schedule_daily() {
    local job_id="$1"
    local command="$2"
    local hour="${3:-17}"
    local minute="${4:-0}"
    local log_file="${5:-}"

    _validate_job_id "$job_id" || return 1

    if [[ "$(uname -s)" == "Darwin" ]]; then
        local label="com.user.$job_id"
        log_file="${log_file:-$HOME/Library/Logs/$label.log}"
        local plist
        plist=$(create_launchd_plist "$label" "$command" "$hour" "$minute" "$log_file")
        load_launchd "$plist"
        _sched_log_info "✅ Installed launchd agent (runs daily at $hour:$(printf '%02d' "$minute"))"
    else
        log_file="${log_file:-$HOME/.$job_id.log}"
        add_cron_job "$job_id" "$minute $hour * * *" "$command" "$log_file"
        _sched_log_info "✅ Installed cron job (runs daily at $hour:$(printf '%02d' "$minute"))"
    fi
}

# Create a launchd plist for weekly jobs (macOS only)
# Usage: create_launchd_plist_weekly "label" "command" "weekday" "hour" "minute" "log_file"
create_launchd_plist_weekly() {
    local label="$1"
    local command="$2"
    local weekday="${3:-0}"  # 0=Sunday
    local hour="${4:-3}"
    local minute="${5:-0}"
    local log_file="${6:-$HOME/Library/Logs/$label.log}"
    local plist_file="$HOME/Library/LaunchAgents/$label.plist"

    [[ "$(uname -s)" != "Darwin" ]] && return 0

    mkdir -p "$(dirname "$plist_file")"
    cat > "$plist_file" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$label</string>
    <key>ProgramArguments</key>
    <array>
        <string>$command</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Weekday</key>
        <integer>$weekday</integer>
        <key>Hour</key>
        <integer>$hour</integer>
        <key>Minute</key>
        <integer>$minute</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>$log_file</string>
    <key>StandardErrorPath</key>
    <string>$log_file</string>
</dict>
</plist>
EOF
    echo "$plist_file"
}

# Schedule a weekly job (cross-platform)
# Usage: schedule_weekly "job_id" "command" "weekday" "hour" [minute] [log_file]
# weekday: 0=Sunday, 1=Monday, ..., 6=Saturday
schedule_weekly() {
    local job_id="$1"
    local command="$2"
    local weekday="${3:-0}"  # Default: Sunday
    local hour="${4:-3}"     # Default: 3am
    local minute="${5:-0}"
    local log_file="${6:-}"

    _validate_job_id "$job_id" || return 1

    local day_names=("Sunday" "Monday" "Tuesday" "Wednesday" "Thursday" "Friday" "Saturday")
    local day_name="${day_names[$weekday]}"

    if [[ "$(uname -s)" == "Darwin" ]]; then
        local label="com.user.$job_id"
        log_file="${log_file:-$HOME/Library/Logs/$label.log}"
        local plist
        plist=$(create_launchd_plist_weekly "$label" "$command" "$weekday" "$hour" "$minute" "$log_file")
        load_launchd "$plist"
        _sched_log_info "✅ Installed launchd agent (runs weekly on $day_name at $hour:$(printf '%02d' "$minute"))"
    else
        log_file="${log_file:-$HOME/.$job_id.log}"
        add_cron_job "$job_id" "$minute $hour * * $weekday" "$command" "$log_file"
        _sched_log_info "✅ Installed cron job (runs weekly on $day_name at $hour:$(printf '%02d' "$minute"))"
    fi
}

# Unschedule a job (cross-platform)
unschedule() {
    local job_id="$1"
    if [[ "$(uname -s)" == "Darwin" ]]; then
        remove_launchd "com.user.$job_id"
    else
        remove_cron_job "$job_id"
    fi
}
