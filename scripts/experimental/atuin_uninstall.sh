#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════════
# Atuin uninstall + backup
# ═══════════════════════════════════════════════════════════════════════════════
# Backs up atuin's local state (history, encryption key, session) before
# removing the binary + config symlink. The encryption key is CRITICAL — losing
# it means you cannot decrypt cloud-synced history from a new install.
#
# Usage:
#   ./atuin_uninstall.sh             # Back up + uninstall (prompts)
#   ./atuin_uninstall.sh --backup    # Back up only, do not uninstall
#   ./atuin_uninstall.sh --force     # Skip prompts
#   ./atuin_uninstall.sh --keep-data # Uninstall binary but leave ~/.local/share/atuin
# ═══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

MODE="uninstall"
FORCE=false
KEEP_DATA=false

for arg in "$@"; do
    case "$arg" in
        --backup)    MODE="backup" ;;
        --force)     FORCE=true ;;
        --keep-data) KEEP_DATA=true ;;
        -h|--help)
            sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "Unknown flag: $arg" >&2; exit 2 ;;
    esac
done

BOLD=$'\033[1m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; GREEN=$'\033[32m'; RESET=$'\033[0m'
log_info()    { printf '%s[*]%s %s\n' "$BOLD" "$RESET" "$*"; }
log_warn()    { printf '%s[!]%s %s\n' "$YELLOW" "$RESET" "$*"; }
log_err()     { printf '%s[x]%s %s\n' "$RED" "$RESET" "$*" >&2; }
log_ok()      { printf '%s[✓]%s %s\n' "$GREEN" "$RESET" "$*"; }

confirm() {
    $FORCE && return 0
    local prompt="$1"
    read -r -p "$prompt [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

ATUIN_DATA="$HOME/.local/share/atuin"
ATUIN_CONFIG="$HOME/.config/atuin/config.toml"
BACKUP_ROOT="$HOME/.atuin-backups"
TS=$(date -u +%Y-%m-%dT%H-%M-%SZ)
BACKUP_DIR="$BACKUP_ROOT/$TS"

# ─── Step 1: Backup ──────────────────────────────────────────────────────────

if [[ -d "$ATUIN_DATA" ]]; then
    log_info "Backing up atuin data → $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"

    # Copy-then-verify (rsync-like), not move — data stays in place until uninstall step
    cp -a "$ATUIN_DATA/." "$BACKUP_DIR/" 2>/dev/null || {
        log_err "Backup failed — aborting"
        exit 1
    }

    # The key file is the single most important artifact
    if [[ -f "$BACKUP_DIR/key" ]]; then
        chmod 600 "$BACKUP_DIR/key"
        log_ok "Backed up encryption key → $BACKUP_DIR/key"
        log_warn "  Keep this key safe — without it, synced history is unrecoverable"
    else
        log_warn "No encryption key found — sync was likely never configured"
    fi

    # Summary
    local_db_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | awk '{print $1}')
    log_ok "Backup complete ($local_db_size) at $BACKUP_DIR"
else
    log_warn "No atuin data directory found at $ATUIN_DATA — nothing to back up"
fi

if [[ "$MODE" == "backup" ]]; then
    log_ok "Backup-only mode — exiting without uninstall"
    exit 0
fi

# ─── Step 2: Uninstall ───────────────────────────────────────────────────────

if ! confirm "Proceed with uninstalling atuin?"; then
    log_info "Aborted — backup kept at $BACKUP_DIR"
    exit 0
fi

# Remove config symlink (safe — the source is in the dotfiles repo)
if [[ -L "$ATUIN_CONFIG" ]]; then
    rm "$ATUIN_CONFIG"
    log_ok "Removed config symlink: $ATUIN_CONFIG"
elif [[ -f "$ATUIN_CONFIG" ]]; then
    log_warn "Config at $ATUIN_CONFIG is not a symlink — leaving in place"
fi

# Remove data directory unless --keep-data
if ! $KEEP_DATA && [[ -d "$ATUIN_DATA" ]]; then
    if command -v trash >/dev/null 2>&1; then
        trash "$ATUIN_DATA" && log_ok "Moved $ATUIN_DATA to Trash"
    else
        # No trash command → rename to a .bak (reversible) rather than rm -rf
        mv "$ATUIN_DATA" "${ATUIN_DATA}.removed.$TS"
        log_ok "Renamed $ATUIN_DATA → ${ATUIN_DATA}.removed.$TS"
        log_info "  Delete manually when confident: rm -rf ${ATUIN_DATA}.removed.$TS"
    fi
fi

# Remove binary
if command -v atuin >/dev/null 2>&1; then
    ATUIN_BIN=$(command -v atuin)
    case "$ATUIN_BIN" in
        */homebrew/*|/usr/local/*)
            if command -v brew >/dev/null 2>&1; then
                if brew uninstall atuin 2>/dev/null; then
                    log_ok "Uninstalled atuin via brew"
                else
                    log_warn "brew uninstall atuin failed"
                fi
            fi
            ;;
        "$HOME"/.cargo/bin/*)
            if cargo uninstall atuin 2>/dev/null; then
                log_ok "Uninstalled atuin via cargo"
            else
                log_warn "cargo uninstall atuin failed"
            fi
            ;;
        "$HOME"/.local/bin/*|"$HOME"/.atuin/bin/*)
            rm "$ATUIN_BIN"
            log_ok "Removed binary: $ATUIN_BIN"
            # Official installer drops things under ~/.atuin
            if [[ -d "$HOME/.atuin" ]]; then
                mv "$HOME/.atuin" "$HOME/.atuin.removed.$TS"
                log_ok "Renamed ~/.atuin → ~/.atuin.removed.$TS"
            fi
            ;;
        *)
            log_warn "atuin binary at $ATUIN_BIN — unknown install method, remove manually"
            ;;
    esac
fi

# ─── Done ────────────────────────────────────────────────────────────────────

cat <<EOF

${GREEN}✓ Atuin uninstalled.${RESET}

  Backup:  $BACKUP_DIR
  Restore: scripts/experimental/atuin_uninstall.sh cannot restore — re-install and:
             mkdir -p ~/.local/share/atuin
             cp -a $BACKUP_DIR/. ~/.local/share/atuin/
             atuin login   # uses the restored key

  Shell init in zshrc.sh is binary-gated — nothing to edit.
EOF
