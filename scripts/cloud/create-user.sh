#!/bin/bash
# RunPod: create (or recreate) the non-root user + SSH infra + persistent dirs
# Idempotent — safe to re-run after pod restart.
#
# Usage (run as root):
#   curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/create-user.sh | bash
#   curl -fsSL ... | USERNAME=dev bash
set -e

log()  { echo "  $*"; }
ok()   { echo "  ✓ $*"; }
warn() { echo "  ⚠ $*" >&2; }
fail() { echo "  ✗ $*" >&2; exit 1; }
step() { echo ""; echo "── $* ──"; }

USERNAME="${USERNAME:-yulong}"
GITHUB_USER="${GITHUB_USER:-yulonglin}"
USER_HOME="/home/$USERNAME"

[[ "$(id -u)" -eq 0 ]] || fail "Must run as root"

echo "=== Create User ==="
log "User:   $USERNAME"
log "Home:   $USER_HOME"

# ── System prereqs ────────────────────────────────────────────────────────────
step "System prereqs"
apt-get update -qq
apt-get install -y sudo zsh openssh-server || fail "Cannot install prereqs (sudo zsh openssh-server)"
ok "prereqs ready"

# ── User account ──────────────────────────────────────────────────────────────
step "User account"
if ! id "$USERNAME" &>/dev/null; then
    useradd -m -d "$USER_HOME" -s /usr/bin/zsh "$USERNAME"
    log "Created $USERNAME"
else
    CURRENT_HOME=$(getent passwd "$USERNAME" | cut -d: -f6)
    if [[ "$CURRENT_HOME" != "$USER_HOME" ]]; then
        usermod -d "$USER_HOME" "$USERNAME"
        log "Updated home: $CURRENT_HOME → $USER_HOME"
    fi
fi
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME"
mkdir -p "$USER_HOME"
chown "$USERNAME:$USERNAME" "$USER_HOME"
chmod 755 "$USER_HOME"
chown -R "$USERNAME:$USERNAME" "$USER_HOME" 2>/dev/null || true
ok "User $USERNAME (uid=$(id -u "$USERNAME"))"

# ── RunPod persistent storage ─────────────────────────────────────────────────
# /home is ephemeral (lost on container restart), /workspace persists.
if [[ -d /workspace ]] || [[ -n "$RUNPOD_POD_ID" ]]; then
    step "Persistent symlinks (/workspace)"
    for dir in code .claude .local .config; do
        target="/workspace/$dir"
        link="$USER_HOME/$dir"
        mkdir -p "$target"
        if [[ -d "$link" && ! -L "$link" ]]; then
            cp -a "$link/." "$target/" 2>/dev/null || true
            rm -rf "$link"
        fi
        if [[ ! -e "$link" ]]; then
            ln -sf "$target" "$link"
            log "$link → $target"
        else
            ok "$link already linked"
        fi
    done
    chown -R "$USERNAME:$USERNAME" "$USER_HOME" 2>/dev/null || true
    ok "Persistent symlinks ready"
fi

# ── sshd ──────────────────────────────────────────────────────────────────────
step "sshd"
SSHD_CONFIG="/etc/ssh/sshd_config"
ls /etc/ssh/ssh_host_*_key &>/dev/null || ssh-keygen -A

grep -q '^PubkeyAuthentication no' "$SSHD_CONFIG" 2>/dev/null && \
    sed -i 's/^PubkeyAuthentication no/PubkeyAuthentication yes/' "$SSHD_CONFIG"
grep -q '^PubkeyAuthentication' "$SSHD_CONFIG" 2>/dev/null || \
    echo 'PubkeyAuthentication yes' >> "$SSHD_CONFIG"

# Disable StrictModes if the filesystem ignores chmod (common in containers)
if ! grep -q '^StrictModes no' "$SSHD_CONFIG" 2>/dev/null; then
    _f="$USER_HOME/.ssh_chmod_test"; touch "$_f" 2>/dev/null; chmod 600 "$_f" 2>/dev/null
    _m=$(stat -c '%a' "$_f" 2>/dev/null || stat -f '%Lp' "$_f" 2>/dev/null); rm -f "$_f"
    if [[ "$_m" != "600" ]]; then
        grep -q '^StrictModes' "$SSHD_CONFIG" 2>/dev/null && \
            sed -i 's/^StrictModes yes/StrictModes no/' "$SSHD_CONFIG" || \
            echo 'StrictModes no' >> "$SSHD_CONFIG"
        log "StrictModes disabled (filesystem ignores chmod)"
    fi
fi

service ssh restart 2>/dev/null || systemctl restart sshd 2>/dev/null || warn "Could not restart sshd"
ok "sshd configured"

# ── SSH authorized_keys ────────────────────────────────────────────────────────
step "SSH keys"
SSH_DIR="$USER_HOME/.ssh"
mkdir -p "$SSH_DIR"

EXISTING=""
[[ -f "$SSH_DIR/authorized_keys" ]] && EXISTING=$(cat "$SSH_DIR/authorized_keys")
[[ -f /root/.ssh/authorized_keys  ]] && EXISTING=$(printf '%s\n%s' "$EXISTING" "$(cat /root/.ssh/authorized_keys)")
GH_KEYS=$(curl -fsSL "https://github.com/$GITHUB_USER.keys" 2>/dev/null) || warn "Could not fetch GitHub keys"
ALL=$(printf '%s\n%s' "$EXISTING" "$GH_KEYS" | grep -v '^$' | sort -u)

printf '%s\n' "$ALL" > "$SSH_DIR/authorized_keys"
chmod 700 "$SSH_DIR"
chmod 600 "$SSH_DIR/authorized_keys"
chown -R "$USERNAME:$USERNAME" "$SSH_DIR"
ok "$(echo "$ALL" | wc -l | tr -d ' ') key(s) installed"

# Outbound identity key (for git push / gh over SSH)
if [[ ! -f "$SSH_DIR/id_ed25519" ]]; then
    sudo -u "$USERNAME" ssh-keygen -t ed25519 -N '' -C "$USERNAME@$(hostname)" -f "$SSH_DIR/id_ed25519" -q
    ok "Outbound SSH key generated: $SSH_DIR/id_ed25519.pub"
fi

# ── cron ──────────────────────────────────────────────────────────────────────
service cron start 2>/dev/null || true

echo ""
echo "=== Done ==="
log "Switch: su - $USERNAME"
log "SSH:    ssh $USERNAME@<ip>"
log "Next:   curl -fsSL .../setup.sh | bash -s -- main"
