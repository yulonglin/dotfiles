#!/bin/bash
# Setup daily shared MCP sync from config/mcp-servers.json into Claude and Codex.
# The sync is managed-only: it adds/updates configured servers and does not prune
# unmanaged MCP entries.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=scripts/scheduler/scheduler.sh
source "$DOT_DIR/scripts/scheduler/scheduler.sh"

JOB_ID="mcp-sync"
WRAPPER="$DOT_DIR/custom_bins/sync-mcp-servers"

log_step() { echo -e "${BLUE}==>${NC} $1"; }

uninstall() {
    unschedule "$JOB_ID" 2>/dev/null || true
}

install() {
    log_step "Setting up shared MCP sync..."

    if [[ ! -f "$DOT_DIR/config/mcp-servers.json" ]]; then
        _sched_log_warn "Shared MCP source not found at $DOT_DIR/config/mcp-servers.json. Skipping."
        return 1
    fi

    if [[ ! -f "$DOT_DIR/scripts/helpers/sync_mcp_servers.py" ]]; then
        _sched_log_warn "MCP sync helper not found. Skipping."
        return 1
    fi

    mkdir -p "$DOT_DIR/custom_bins"
    cat > "$WRAPPER" <<WRAPPER
#!/bin/bash
# Auto-generated wrapper for scheduled shared MCP sync
set -euo pipefail

export PATH="\$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:\$PATH"

exec python3 "$DOT_DIR/scripts/helpers/sync_mcp_servers.py" \\
    --source "$DOT_DIR/config/mcp-servers.json" \\
    --claude-settings "$DOT_DIR/claude/settings.json" \\
    --codex-config "$DOT_DIR/codex/config.toml" \\
    --apply
WRAPPER
    chmod +x "$WRAPPER"

    schedule_daily "$JOB_ID" "$WRAPPER" 6 30
}

uninstall >/dev/null 2>&1 || true

if [[ "${1:-}" == "--uninstall" ]]; then
    _sched_log_info "Shared MCP sync automation uninstalled."
    exit 0
fi

install
