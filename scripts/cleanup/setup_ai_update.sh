#!/bin/bash
# Setup daily auto-update for AI CLI tools (Claude Code, Antigravity CLI, Codex CLI, OpenCode)
# Works on macOS (launchd) and Linux (cron)

set -euo pipefail

# Get directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
UPDATE_BIN="$DOT_DIR/custom_bins/update-ai-tools"

# Source scheduler abstraction
source "$DOT_DIR/scripts/scheduler/scheduler.sh"

# Shared helpers, for install_bun. config.sh is deliberately NOT sourced: it is
# zsh-only (`${(U)name//-/_}`) and dies with "bad substitution" under this bash
# script. helpers.sh's only entry guard is PLATFORM being set, so set it here
# with config.sh's own Darwin/else rule. Consequence: is_macos/is_linux stay
# undefined in this script, so install_bun must never start using them.
export DOT_DIR
case "$(uname -s)" in
    Darwin*) PLATFORM="macos" ;;
    *)       PLATFORM="linux" ;;
esac
export PLATFORM
source "$DOT_DIR/scripts/shared/helpers.sh"

JOB_ID="update-ai-tools"

# Logging (uses scheduler's internal prefix to avoid conflicts)
log_step() { echo -e "${BLUE}==>${NC} $1"; }

# macOS updates Codex/OpenCode through brew, so bun is only a hard requirement
# on Linux. The install itself is install_bun in scripts/shared/helpers.sh —
# this wrapper keeps the Darwin gate and the "skipping setup" contract.
ensure_bun_for_linux() {
    if [[ "$(uname -s)" == "Darwin" ]]; then
        return 0
    fi

    if command -v bun &>/dev/null; then
        return 0
    fi

    _sched_log_info "bun not found; installing bun for Codex/OpenCode updates..."

    if ! install_bun; then
        _sched_log_warn "bun install failed. Skipping AI tools auto-update setup."
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
