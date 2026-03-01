#!/bin/bash
# Setup daily auto-update for AI CLI tools (Claude Code, Gemini CLI, Codex CLI)
# Works on macOS (launchd) and Linux (cron)

set -euo pipefail

# Get directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
UPDATE_BIN="$DOT_DIR/custom_bins/update-ai-tools"

# Source scheduler abstraction
source "$DOT_DIR/scripts/scheduler/scheduler.sh"

JOB_ID="update-ai-tools"

# Logging (uses scheduler's internal prefix to avoid conflicts)
log_step() { echo -e "${BLUE}==>${NC} $1"; }

ensure_bun_for_linux() {
    if [[ "$(uname -s)" == "Darwin" ]]; then
        return 0
    fi

    if command -v bun &>/dev/null; then
        return 0
    fi

    _sched_log_info "bun not found; installing bun for Gemini/Codex updates..."

    if ! command -v curl &>/dev/null; then
        _sched_log_warn "curl is required to install bun. Skipping AI tools auto-update setup."
        return 1
    fi

    if ! curl -fsSL https://bun.sh/install | bash; then
        _sched_log_warn "bun installation failed. Skipping AI tools auto-update setup."
        return 1
    fi

    export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
    export PATH="$BUN_INSTALL/bin:$PATH"

    if ! command -v bun &>/dev/null; then
        _sched_log_warn "bun still not found after install. Skipping AI tools auto-update setup."
        return 1
    fi

    _sched_log_info "bun installed at $(command -v bun)"
}

uninstall() {
    unschedule "$JOB_ID" 2>/dev/null || true
}

install() {
    log_step "Setting up AI tools auto-update..."

    if [[ ! -f "$UPDATE_BIN" ]]; then
        _sched_log_warn "Binary not found at $UPDATE_BIN. Skipping."
        return 1
    fi

    ensure_bun_for_linux || return 1

    schedule_daily "$JOB_ID" "$UPDATE_BIN" 6 0
}

# Always uninstall first to ensure clean state
uninstall >/dev/null 2>&1 || true

# If only uninstalling, exit
if [[ "${1:-}" == "--uninstall" ]]; then
    _sched_log_info "AI tools auto-update uninstalled."
    exit 0
fi

# Otherwise install
install
