#!/bin/bash
# Setup the daily dotfiles commit + rebase + push (custom_bins/dotfiles-sync).
# Works on macOS (launchd) and Linux (cron) through scripts/scheduler/scheduler.sh,
# the same mechanism as the gist sync. Runs at 08:05, five minutes after the
# gist sync has refreshed the git identity it commits with.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SYNC_BIN="$DOT_DIR/custom_bins/dotfiles-sync"

# shellcheck source=scripts/scheduler/scheduler.sh
source "$DOT_DIR/scripts/scheduler/scheduler.sh"

JOB_ID="dotfiles-sync"
PRUNE_JOB_ID="dotfiles-prune"
PRUNE_BIN="$DOT_DIR/custom_bins/dotfiles-prune"

log_step() { echo -e "${BLUE}==>${NC} $1"; }

uninstall() {
    unschedule "$JOB_ID" 2>/dev/null || true
    unschedule "$PRUNE_JOB_ID" 2>/dev/null || true
}

install() {
    log_step "Setting up daily dotfiles sync..."

    if [[ ! -x "$SYNC_BIN" ]]; then
        _sched_log_warn "Binary not found or not executable at $SYNC_BIN. Skipping."
        return 1
    fi

    schedule_daily "$JOB_ID" "$SYNC_BIN" 8 5

    # Weekly worktree housekeeping: Sunday 08:15, after that day's sync has
    # pushed, so "merged" is judged against a branch the remote already has.
    log_step "Setting up weekly worktree prune..."
    if [[ -x "$PRUNE_BIN" ]]; then
        schedule_weekly "$PRUNE_JOB_ID" "$PRUNE_BIN" 0 8 15
    else
        _sched_log_warn "Binary not found or not executable at $PRUNE_BIN. Prune not scheduled."
    fi
}

# Always uninstall first to ensure clean state
uninstall >/dev/null 2>&1 || true

if [[ "${1:-}" == "--uninstall" ]]; then
    _sched_log_info "Dotfiles sync automation uninstalled."
    exit 0
fi

install
