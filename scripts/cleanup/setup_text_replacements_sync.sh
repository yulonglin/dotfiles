#!/bin/bash
# Setup automatic text replacements sync (macOS only)
# Syncs text replacements between YAML config, macOS, and Alfred daily at 9 AM

set -euo pipefail

# Get directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source scheduler abstraction
source "$DOT_DIR/scripts/scheduler/scheduler.sh"

JOB_ID="sync-text-replacements"
YAML_FILE="$DOT_DIR/config/text_replacements.yaml"

log_step() { echo -e "${BLUE}==>${NC} $1"; }

uninstall() {
    unschedule "$JOB_ID" 2>/dev/null || true
}

install() {
    log_step "Setting up automated text replacements sync..."

    # Only on macOS
    if [[ "$(uname -s)" != "Darwin" ]]; then
        _sched_log_warn "Text replacements sync is macOS-only. Skipping."
        return 0
    fi

    # Check YAML exists (skip if missing — initial export hasn't run yet)
    if [[ ! -f "$YAML_FILE" ]]; then
        _sched_log_warn "YAML config not found at $YAML_FILE. Run 'export-snippets' first."
        return 0
    fi

    # Check uv is available
    if ! command -v uv &>/dev/null; then
        _sched_log_warn "uv not found. Skipping text replacements sync setup."
        return 1
    fi

    # Create a wrapper script for the scheduler (needs full paths and uv)
    local wrapper="$DOT_DIR/custom_bins/sync-text-replacements"
    cat > "$wrapper" <<WRAPPER
#!/bin/bash
# Auto-generated wrapper for scheduled text replacements sync
set -euo pipefail

YAML_FILE="$YAML_FILE"
if [[ ! -f "\$YAML_FILE" ]]; then
    echo "YAML config not found, skipping sync"
    exit 0
fi

# Use uv to run with ruamel.yaml dependency
exec uv run --with ruamel.yaml "$DOT_DIR/scripts/sync_text_replacements.py" sync --prune --no-restart-alfred
WRAPPER
    chmod +x "$wrapper"

    # Schedule daily at 9:00 AM (after secrets sync at 8 AM)
    schedule_daily "$JOB_ID" "$wrapper" 9 0
}

# Always uninstall first to ensure clean state
uninstall >/dev/null 2>&1 || true

# If only uninstalling, exit
if [[ "${1:-}" == "--uninstall" ]]; then
    _sched_log_info "Text replacements sync automation uninstalled."
    exit 0
fi

# Otherwise install
install
