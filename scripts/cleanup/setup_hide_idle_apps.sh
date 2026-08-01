#!/bin/bash
# Setup periodic hide-idle-apps polling: apps left covered up are hidden, then
# have their windows closed, then are quit, each after its own delay.
# macOS only. Poll interval comes from config/hide-idle.conf; every per-app
# policy (which rungs apply, and after how long) from config/app-lifecycle.yaml.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
HIDE_BIN="$DOT_DIR/custom_bins/hide-idle-apps"
TUNABLES_CONF="$DOT_DIR/config/hide-idle.conf"
HELPER_SRC="$DOT_DIR/tools/window-exposure/main.swift"
HELPER_BIN="$DOT_DIR/tools/window-exposure/window-exposure"

source "$DOT_DIR/scripts/scheduler/scheduler.sh"

JOB_ID="hide-idle-apps"
# The token whose presence permits hide-idle-apps to close windows and quit apps.
# Absent it, the job still hides - that rung is implemented locally and is what
# the default-on era actually consented to.
#
# Reaching this script does NOT by itself mean the user asked for the ladder.
# deploy.sh queues it from the resolved DEPLOY_HIDE_IDLE_APPS, and that boolean
# can equally come from a config.local.sh line - sourced before parse_args -
# written back when this component was hide-only. Minting on arrival would hand
# close/quit consent to precisely the machine the token exists to protect. So the
# statement we need ("the user asked for this, on this machine, with the ladder as
# it exists today") comes from HIDE_IDLE_APPS_EXPLICIT_CONSENT, which deploy.sh
# exports only when the component appears in EXPLICIT_OPT_INS.
#
# Not under ~/.cache: that directory holds this job's state file and is
# disposable by design, so a cache sweep would silently revoke consent.
# Keep in sync with ESCALATION_TOKEN in custom_bins/hide-idle-apps.
ESCALATION_TOKEN="${HOME}/.local/state/hide-idle-apps/escalation-enabled"
# Captured HERE, before the unconditional `uninstall` below deletes it. Consent
# already given is not re-asked on every redeploy: an ordinary `./deploy.sh` on a
# machine that opted in once must not silently revoke it. Only an explicit
# --no-hide-idle-apps takes it away, via uninstall's own exit path.
_token_preexisting=false
[[ -f "$ESCALATION_TOKEN" ]] && _token_preexisting=true
# The FILE is authoritative for the installed job, and an inherited
# HIDE_IDLE_POLL_SECONDS is deliberately not honoured here.
#
# It cannot be: launchd's ProgramArguments is a bare argv with no shell and no
# environment of ours, so an override would set the plist's StartInterval and
# never reach the job. hide-idle-apps would re-read this file, get 60, derive
# MAX_GAP=180, and then read every 300s wake as a skipped interval - resetting
# every app's timers on each poll, so the automation would never act at all.
# One value both the plist and the runtime can see is the only safe kind.
_poll_override="${HIDE_IDLE_POLL_SECONDS:-}"
HIDE_IDLE_POLL_SECONDS=60
# shellcheck source=/dev/null
[[ -f "$TUNABLES_CONF" ]] && source "$TUNABLES_CONF"
if [[ -n "$_poll_override" && "$_poll_override" != "$HIDE_IDLE_POLL_SECONDS" ]]; then
    _sched_log_warn "Ignoring HIDE_IDLE_POLL_SECONDS=$_poll_override from the environment:"
    _sched_log_warn "it cannot reach a launchd job. Set HIDE_IDLE_POLL_SECONDS in $TUNABLES_CONF instead."
fi

uninstall() {
    unschedule "$JOB_ID" 2>/dev/null || true
    # Withdrawing the schedule withdraws the consent with it. Leaving the token
    # behind would mean a later reinstall - or a stray copy of the old plist -
    # started quitting apps again without anyone re-asking.
    rm -f "$ESCALATION_TOKEN" 2>/dev/null || true
}

# Build the exposure helper here so the first poll doesn't have to. The script
# can compile it lazily too, but launchd jobs run without a developer PATH.
build_helper() {
    [[ -f "$HELPER_SRC" ]] || return 1
    [[ -x "$HELPER_BIN" && "$HELPER_BIN" -nt "$HELPER_SRC" ]] && return 0
    command -v swiftc >/dev/null 2>&1 || return 1
    swiftc -O -o "$HELPER_BIN" "$HELPER_SRC" >/dev/null 2>&1
}

install() {
    if [[ "$(uname -s)" != "Darwin" ]]; then
        _sched_log_info "hide-idle-apps is macOS-only. Skipping."
        return 0
    fi
    if [[ ! -f "$HIDE_BIN" ]]; then
        _sched_log_warn "Binary not found at $HIDE_BIN. Skipping."
        return 1
    fi
    if ! build_helper; then
        _sched_log_warn "Could not build window-exposure helper (needs swiftc)."
        _sched_log_warn "hide-idle-apps hides nothing without it. Skipping."
        return 1
    fi
    schedule_interval "$JOB_ID" "$HIDE_BIN" "$HIDE_IDLE_POLL_SECONDS"

    # Only after the job is actually installed, and only for a machine that has
    # genuinely consented: either it said so on THIS invocation, or it had already
    # said so and we are just redeploying. A resolved-true component boolean on
    # its own is not consent - see the ESCALATION_TOKEN comment above.
    if [[ "${HIDE_IDLE_APPS_EXPLICIT_CONSENT:-}" != true && "$_token_preexisting" != true ]]; then
        _sched_log_info "hide-idle-apps installed in hide-only mode."
        _sched_log_info "Run ./deploy.sh --hide-idle-apps to also allow closing windows and quitting apps."
        return 0
    fi
    mkdir -p "$(dirname "$ESCALATION_TOKEN")"
    printf '%s\n' \
        "Written by scripts/cleanup/setup_hide_idle_apps.sh on an explicit --hide-idle-apps." \
        "Its presence is what permits hide-idle-apps to close windows and quit apps." \
        "Delete it to keep the hourly hiding but stop the destructive rungs." \
        > "$ESCALATION_TOKEN"
}

# Always uninstall first for clean state
uninstall >/dev/null 2>&1 || true

if [[ "${1:-}" == "--uninstall" ]]; then
    _sched_log_info "hide-idle-apps uninstalled."
    exit 0
fi

install
