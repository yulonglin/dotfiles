#!/bin/bash
# Cloud VM/container first-boot setup
# Auto-detects provider (RunPod, Hetzner, generic Linux)
#
# Usage:
#   ./setup.sh                           # Auto-detect provider
#   USER_HOME=/custom/path ./setup.sh    # Override home directory
#   USERNAME=dev ./setup.sh              # Custom username
#
# One-liner:
#   curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/setup.sh | bash

set -e

# ─── Logging ────────────────────────────────────────────────────────────────
log()  { echo "  $*"; }
ok()   { echo "  ✓ $*"; }
warn() { echo "  ⚠ $*" >&2; }
fail() { echo "  ✗ $*" >&2; exit 1; }
step() { echo ""; echo "── $* ──"; }

# ─── Configuration (override via env vars) ───────────────────────────────────
USERNAME="${USERNAME:-yulong}"
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/yulonglin/dotfiles.git}"

# Auto-detect provider and set home directory
if [[ -n "$USER_HOME" ]]; then
    PROVIDER="custom"
elif [[ -d /workspace ]] || [[ -n "$RUNPOD_POD_ID" ]]; then
    USER_HOME="/workspace/$USERNAME"    # RunPod: persistent volume
    PROVIDER="runpod"
else
    USER_HOME="/home/$USERNAME"         # Standard unix
    PROVIDER="generic"
fi

echo "=== Cloud Setup ==="
log "Provider: $PROVIDER"
log "Username: $USERNAME"
log "Home:     $USER_HOME"

# ─── System deps ──────────────────────────────────────────────────────────────
step "System dependencies"
apt-get update && apt-get install -y sudo zsh htop vim cron curl ca-certificates unzip
command -v nvtop &>/dev/null || apt-get install -y nvtop 2>/dev/null || true
service cron start 2>/dev/null || true
ok "System deps installed"

# ─── Node 20 (for Gemini CLI) ─────────────────────────────────────────────────
step "Node.js"
if ! command -v node &>/dev/null || [[ "$(node -v | cut -d. -f1 | tr -d 'v')" -lt 20 ]]; then
    log "Installing Node 20..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
    ok "Node $(node -v) installed"
else
    ok "Node $(node -v) already installed"
fi

# ─── Create non-root user ─────────────────────────────────────────────────────
step "User account"
if ! id "$USERNAME" &>/dev/null; then
    log "Creating user $USERNAME with home $USER_HOME..."
    useradd -m -d "$USER_HOME" -s /usr/bin/zsh "$USERNAME"
    echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME"
    ok "User $USERNAME created (uid=$(id -u "$USERNAME"), gid=$(id -g "$USERNAME"))"
else
    ok "User $USERNAME already exists (uid=$(id -u "$USERNAME"))"
fi

# ─── Fix ownership & permissions of user's home (handles root-created files) ──
step "Home directory ownership"
if [[ -d "$USER_HOME" ]]; then
    OWNER_BEFORE=$(stat -c '%U:%G' "$USER_HOME" 2>/dev/null || stat -f '%Su:%Sg' "$USER_HOME")
    log "Current owner of $USER_HOME: $OWNER_BEFORE"

    # Home dir ownership MUST succeed — sshd refuses key auth if home is owned by root
    chown "$USERNAME:$USERNAME" "$USER_HOME" || fail "Cannot chown $USER_HOME — SSH login will not work"
    chmod 755 "$USER_HOME"

    OWNER_AFTER=$(stat -c '%U:%G' "$USER_HOME" 2>/dev/null || stat -f '%Su:%Sg' "$USER_HOME")
    ok "Home dir owner: $OWNER_AFTER (mode $(stat -c '%a' "$USER_HOME" 2>/dev/null || stat -f '%Lp' "$USER_HOME"))"

    # Subdirs are best-effort (container mounts may not support chown)
    chown -R "$USERNAME:$USERNAME" "$USER_HOME" 2>/dev/null || warn "Could not chown all files in $USER_HOME (container mount?)"
else
    fail "$USER_HOME does not exist"
fi

# ─── sshd config (ensure key auth works for non-root users) ──────────────────
step "sshd configuration"
SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_CHANGED=false

# Generate host keys if missing (common in containers)
if ! ls /etc/ssh/ssh_host_*_key &>/dev/null; then
    log "Generating SSH host keys..."
    ssh-keygen -A
    SSHD_CHANGED=true
    ok "Host keys generated"
else
    ok "Host keys present"
fi

# Ensure PubkeyAuthentication is enabled
if grep -q '^PubkeyAuthentication no' "$SSHD_CONFIG" 2>/dev/null; then
    sed -i 's/^PubkeyAuthentication no/PubkeyAuthentication yes/' "$SSHD_CONFIG"
    SSHD_CHANGED=true
    log "Enabled PubkeyAuthentication (was disabled)"
elif ! grep -q '^PubkeyAuthentication' "$SSHD_CONFIG" 2>/dev/null; then
    echo 'PubkeyAuthentication yes' >> "$SSHD_CONFIG"
    SSHD_CHANGED=true
    log "Added PubkeyAuthentication yes"
else
    ok "PubkeyAuthentication already enabled"
fi

# Disable StrictModes if home is on a mount that doesn't support chown (RunPod, NFS, etc.)
# sshd refuses key auth if authorized_keys ownership doesn't match the user,
# but container mounts often don't allow chown at all
if ! chown --reference="$USER_HOME" "$USER_HOME" 2>/dev/null; then
    if ! grep -q '^StrictModes no' "$SSHD_CONFIG" 2>/dev/null; then
        sed -i 's/^StrictModes yes/StrictModes no/' "$SSHD_CONFIG"
        grep -q '^StrictModes' "$SSHD_CONFIG" || echo 'StrictModes no' >> "$SSHD_CONFIG"
        SSHD_CHANGED=true
        log "Disabled StrictModes (home dir mount doesn't support chown)"
    else
        ok "StrictModes already disabled"
    fi
else
    ok "Home dir supports chown — StrictModes left enabled"
fi

# ─── SSH keys (for direct SSH access as non-root) ────────────────────────────
step "SSH keys"
GITHUB_USER="${GITHUB_USER:-yulonglin}"
sudo -u "$USERNAME" mkdir -p "$USER_HOME/.ssh"
log "Created $USER_HOME/.ssh/"

# Combine root's keys + GitHub keys (covers all machines)
> "$USER_HOME/.ssh/authorized_keys"  # start fresh
if [ -f /root/.ssh/authorized_keys ]; then
    log "Source: /root/.ssh/authorized_keys"
    cat /root/.ssh/authorized_keys >> "$USER_HOME/.ssh/authorized_keys"
fi
log "Source: https://github.com/$GITHUB_USER.keys"
curl -fsSL "https://github.com/$GITHUB_USER.keys" >> "$USER_HOME/.ssh/authorized_keys" || warn "Could not fetch GitHub keys"

# Deduplicate (same key from multiple sources)
sort -u -o "$USER_HOME/.ssh/authorized_keys" "$USER_HOME/.ssh/authorized_keys"
chown "$USERNAME:$USERNAME" "$USER_HOME/.ssh/authorized_keys"

# Copy root's SSH config if it exists (e.g., provider-specific settings)
if [ -f /root/.ssh/config ]; then
    cat /root/.ssh/config | sudo -u "$USERNAME" tee "$USER_HOME/.ssh/config" > /dev/null 2>&1 || true
    log "Copied root SSH config"
fi

chmod 700 "$USER_HOME/.ssh"
chmod 600 "$USER_HOME/.ssh/authorized_keys"

# Verify SSH setup
KEY_COUNT=$(wc -l < "$USER_HOME/.ssh/authorized_keys" 2>/dev/null || echo 0)
SSH_DIR_OWNER=$(stat -c '%U:%G' "$USER_HOME/.ssh" 2>/dev/null || stat -f '%Su:%Sg' "$USER_HOME/.ssh")
SSH_DIR_MODE=$(stat -c '%a' "$USER_HOME/.ssh" 2>/dev/null || stat -f '%Lp' "$USER_HOME/.ssh")
AK_OWNER=$(stat -c '%U:%G' "$USER_HOME/.ssh/authorized_keys" 2>/dev/null || stat -f '%Su:%Sg' "$USER_HOME/.ssh/authorized_keys")
AK_MODE=$(stat -c '%a' "$USER_HOME/.ssh/authorized_keys" 2>/dev/null || stat -f '%Lp' "$USER_HOME/.ssh/authorized_keys")
ok "$KEY_COUNT key(s) installed"
log ".ssh/              owner=$SSH_DIR_OWNER mode=$SSH_DIR_MODE"
log "authorized_keys    owner=$AK_OWNER mode=$AK_MODE"

# Sanity checks
[[ "$SSH_DIR_MODE" != "700" ]] && warn ".ssh/ mode is $SSH_DIR_MODE, expected 700"
[[ "$AK_MODE" != "600" ]] && warn "authorized_keys mode is $AK_MODE, expected 600"
[[ "$AK_OWNER" != "$USERNAME:$USERNAME" ]] && warn "authorized_keys owned by $AK_OWNER, expected $USERNAME:$USERNAME"
HOME_OWNER=$(stat -c '%U:%G' "$USER_HOME" 2>/dev/null || stat -f '%Su:%Sg' "$USER_HOME")
[[ "$HOME_OWNER" != "$USERNAME:$USERNAME" ]] && warn "Home dir owned by $HOME_OWNER, expected $USERNAME:$USERNAME — SSH will fail!"

# Restart sshd to pick up all changes
step "Restart sshd"
if [[ "$SSHD_CHANGED" == true ]]; then
    log "sshd config changed, restarting..."
else
    log "Restarting sshd to pick up new keys..."
fi
service ssh restart 2>/dev/null || systemctl restart sshd 2>/dev/null || /usr/sbin/sshd 2>/dev/null || warn "Could not restart sshd"
ok "sshd restarted"

# ─── Bun (preferred for global CLI tools on Linux) ───────────────────────────
step "Bun"
if ! command -v bun &>/dev/null; then
    log "Installing bun..."
    sudo -u "$USERNAME" -i bash -c 'curl -fsSL https://bun.sh/install | bash'
    ok "Bun installed"
else
    ok "Bun already installed"
fi

# ─── Install uv (as user) ─────────────────────────────────────────────────────
step "uv"
log "Installing uv..."
sudo -u "$USERNAME" -i bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
ok "uv installed"

# ─── Clone dotfiles to ~/code/dotfiles ────────────────────────────────────────
step "Dotfiles"
DOTFILES="$USER_HOME/code/dotfiles"
if [ ! -d "$DOTFILES/.git" ]; then
    log "Cloning $DOTFILES_REPO → $DOTFILES"
    sudo -u "$USERNAME" mkdir -p "$USER_HOME/code"
    # Remove empty dir if it exists (e.g., from volume mount)
    [ -d "$DOTFILES" ] && [ -z "$(ls -A "$DOTFILES" 2>/dev/null)" ] && rmdir "$DOTFILES"
    sudo -u "$USERNAME" git clone "$DOTFILES_REPO" "$DOTFILES"
    ok "Dotfiles cloned"
else
    log "Dotfiles already exist at $DOTFILES, pulling latest..."
    sudo -u "$USERNAME" -i bash -c "cd $DOTFILES && git pull --ff-only" || true
    ok "Dotfiles up to date"
fi

# ─── Run install as user ─────────────────────────────────────────────────────
step "install.sh"
sudo -u "$USERNAME" -i bash -c "cd $DOTFILES && ./install.sh"
ok "install.sh complete"

# ─── Authenticate gh (needed for gist sync in deploy) ────────────────────────
step "GitHub CLI auth"
if ! sudo -u "$USERNAME" -i bash -c 'gh auth status' &>/dev/null; then
    log "Authenticating GitHub CLI..."
    sudo -u "$USERNAME" -i bash -c 'gh auth login --web --git-protocol ssh </dev/tty'
    ok "GitHub CLI authenticated"
else
    ok "GitHub CLI already authenticated"
fi

# ─── Age key for SOPS secrets (paste from Bitwarden) ─────────────────────────
step "SOPS age key"
AGE_KEY_DIR="$USER_HOME/.config/sops/age"
if [ ! -f "$AGE_KEY_DIR/keys.txt" ]; then
    echo "Paste your age private key (from Bitwarden), then press Enter:"
    echo "(starts with AGE-SECRET-KEY-, leave empty to skip)"
    if [[ -e /dev/tty ]]; then
        read -rs AGE_KEY </dev/tty
    else
        warn "Non-interactive — skipping age key prompt. Paste after login with: secrets-init"
        AGE_KEY=""
    fi
    if [[ -n "$AGE_KEY" ]]; then
        sudo -u "$USERNAME" mkdir -p "$AGE_KEY_DIR"
        printf '%s\n' "$AGE_KEY" | sudo -u "$USERNAME" tee "$AGE_KEY_DIR/keys.txt" > /dev/null
        chmod 600 "$AGE_KEY_DIR/keys.txt" 2>/dev/null || true
        ok "Age key saved to $AGE_KEY_DIR/keys.txt"
    else
        log "Skipping — run secrets-init after login to set up SOPS"
    fi
else
    ok "Age key already exists at $AGE_KEY_DIR/keys.txt"
fi

# ─── Deploy configs (with secrets now available) ─────────────────────────────
step "deploy.sh"
sudo -u "$USERNAME" -i bash -c "cd $DOTFILES && ./deploy.sh"
ok "deploy.sh complete"

# ─── Install Claude Code as user ──────────────────────────────────────────────
step "Claude Code"
log "Installing Claude Code..."
sudo -u "$USERNAME" -i bash -c 'curl -fsSL https://claude.ai/install.sh | sh'
ok "Claude Code installed"

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "=== Setup Complete ==="
log "SSH with:  ssh $USERNAME@<ip>"
log "Home:      $USER_HOME"
log "Code:      ~/code = $USER_HOME/code"
log "Provider:  $PROVIDER"
