#!/bin/bash
# Cloud VM/container first-boot setup
# Auto-detects provider (RunPod, Hetzner, generic Linux)
#
# Both providers: creates non-root user with home at /home/$USERNAME
# RunPod: persistent data symlinked from ~/code → /workspace/code, etc.
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

# Run a command as $USERNAME
run_as() {
    sudo -u "$USERNAME" -i bash -c "$*"
}

# ─── Configuration (override via env vars) ───────────────────────────────────
USERNAME="${USERNAME:-yulong}"
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/yulonglin/dotfiles.git}"
GITHUB_USER="${GITHUB_USER:-yulonglin}"

# Auto-detect provider and set home directory
if [[ -n "$USER_HOME" ]]; then
    PROVIDER="custom"
elif [[ -d /workspace ]] || [[ -n "$RUNPOD_POD_ID" ]]; then
    PROVIDER="runpod"
else
    PROVIDER="generic"
fi

# Always use /home/$USERNAME — local FS where chown/chmod work
# RunPod persistent data lives on /workspace, symlinked into home
USER_HOME="${USER_HOME:-/home/$USERNAME}"

echo "=== Cloud Setup ==="
log "Provider: $PROVIDER"
log "User:     $USERNAME"
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

step "Home directory ownership"
if [[ -d "$USER_HOME" ]]; then
    OWNER=$(stat -c '%U:%G' "$USER_HOME" 2>/dev/null || stat -f '%Su:%Sg' "$USER_HOME")
    log "Current: $USER_HOME owner=$OWNER"
    chown "$USERNAME:$USERNAME" "$USER_HOME" || fail "Cannot chown $USER_HOME — SSH login will not work"
    chmod 755 "$USER_HOME"
    chown -R "$USERNAME:$USERNAME" "$USER_HOME" 2>/dev/null || warn "Could not chown all files (sub-mounts?)"
    ok "Home dir ownership fixed"
else
    fail "$USER_HOME does not exist"
fi

# ─── RunPod: symlink persistent dirs from /workspace ─────────────────────────
# /home is ephemeral (lost on container restart), /workspace persists.
# Symlink working directories so data survives restarts.
if [[ "$PROVIDER" == "runpod" ]]; then
    step "Persistent storage symlinks"
    PERSIST="/workspace"
    for dir in code .claude .local .config; do
        target="$PERSIST/$dir"
        link="$USER_HOME/$dir"
        mkdir -p "$target"
        if [[ -d "$link" && ! -L "$link" ]]; then
            # Move existing contents to persistent storage, then symlink
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
    ok "Persistent symlinks configured"
fi

# ─── sshd config ─────────────────────────────────────────────────────────────
step "sshd configuration"
SSHD_CONFIG="/etc/ssh/sshd_config"

# Generate host keys if missing (common in containers)
if ! ls /etc/ssh/ssh_host_*_key &>/dev/null; then
    log "Generating SSH host keys..."
    ssh-keygen -A

    ok "Host keys generated"
else
    ok "Host keys present"
fi

# Ensure PubkeyAuthentication is enabled (first-match-wins in sshd_config)
if grep -q '^PubkeyAuthentication no' "$SSHD_CONFIG" 2>/dev/null; then
    sed -i 's/^PubkeyAuthentication no/PubkeyAuthentication yes/' "$SSHD_CONFIG"

    log "Enabled PubkeyAuthentication (was disabled)"
elif ! grep -q '^PubkeyAuthentication' "$SSHD_CONFIG" 2>/dev/null; then
    echo 'PubkeyAuthentication yes' >> "$SSHD_CONFIG"

    log "Added PubkeyAuthentication yes"
else
    ok "PubkeyAuthentication already enabled"
fi

# Container/volume mounts often don't support chmod — sshd refuses authorized_keys
# with wrong permissions unless StrictModes is disabled
if ! grep -q '^StrictModes no' "$SSHD_CONFIG" 2>/dev/null; then
    # Test if chmod actually works on the target filesystem
    _test_file="$USER_HOME/.ssh_chmod_test"
    touch "$_test_file" 2>/dev/null
    chmod 600 "$_test_file" 2>/dev/null
    _actual_mode=$(stat -c '%a' "$_test_file" 2>/dev/null || stat -f '%Lp' "$_test_file" 2>/dev/null)
    rm -f "$_test_file"
    if [[ "$_actual_mode" != "600" ]]; then
        sed -i 's/^StrictModes yes/StrictModes no/' "$SSHD_CONFIG"
        grep -q '^StrictModes' "$SSHD_CONFIG" || echo 'StrictModes no' >> "$SSHD_CONFIG"
    
        log "Added StrictModes no (filesystem ignores chmod)"
    fi
fi

# ─── SSH keys ────────────────────────────────────────────────────────────────
step "SSH keys"
SSH_DIR="$USER_HOME/.ssh"
mkdir -p "$SSH_DIR"
log "SSH dir: $SSH_DIR"

# Combine existing keys + GitHub keys (covers all machines)
EXISTING_KEYS=""
[[ -f "$SSH_DIR/authorized_keys" ]] && EXISTING_KEYS=$(cat "$SSH_DIR/authorized_keys")
[[ -f /root/.ssh/authorized_keys ]] && {
    log "Source: /root/.ssh/authorized_keys"
    EXISTING_KEYS=$(printf '%s\n%s' "$EXISTING_KEYS" "$(cat /root/.ssh/authorized_keys)")
}

log "Source: https://github.com/$GITHUB_USER.keys"
GITHUB_KEYS=$(curl -fsSL "https://github.com/$GITHUB_USER.keys" 2>/dev/null) || warn "Could not fetch GitHub keys"
ALL_KEYS=$(printf '%s\n%s' "$EXISTING_KEYS" "$GITHUB_KEYS" | grep -v '^$' | sort -u)

printf '%s\n' "$ALL_KEYS" > "$SSH_DIR/authorized_keys"
chmod 700 "$SSH_DIR"
chmod 600 "$SSH_DIR/authorized_keys"

chown -R "$USERNAME:$USERNAME" "$SSH_DIR"

KEY_COUNT=$(echo "$ALL_KEYS" | wc -l | tr -d ' ')
ok "$KEY_COUNT key(s) installed"
log "Owner: $(stat -c '%U:%G' "$SSH_DIR/authorized_keys" 2>/dev/null || stat -f '%Su:%Sg' "$SSH_DIR/authorized_keys")"
log "Mode:  .ssh=$(stat -c '%a' "$SSH_DIR" 2>/dev/null || stat -f '%Lp' "$SSH_DIR") authorized_keys=$(stat -c '%a' "$SSH_DIR/authorized_keys" 2>/dev/null || stat -f '%Lp' "$SSH_DIR/authorized_keys")"

# Always restart sshd — keys or config may have changed
step "Restart sshd"
service ssh restart 2>/dev/null || systemctl restart sshd 2>/dev/null || warn "Could not restart sshd"
ok "sshd restarted"

# ─── Bun ─────────────────────────────────────────────────────────────────────
step "Bun"
if ! run_as 'command -v bun' &>/dev/null; then
    log "Installing bun..."
    run_as 'curl -fsSL https://bun.sh/install | bash'
    ok "Bun installed"
else
    ok "Bun already installed"
fi

# ─── uv ──────────────────────────────────────────────────────────────────────
step "uv"
if ! run_as 'command -v uv' &>/dev/null; then
    log "Installing uv..."
    run_as 'curl -LsSf https://astral.sh/uv/install.sh | sh'
    ok "uv installed"
else
    ok "uv already installed"
fi

# ─── Dotfiles ────────────────────────────────────────────────────────────────
step "Dotfiles"
DOTFILES="$USER_HOME/code/dotfiles"
if [ ! -d "$DOTFILES/.git" ]; then
    log "Cloning $DOTFILES_REPO → $DOTFILES"
    run_as "mkdir -p $USER_HOME/code"
    # Remove empty dir if it exists (e.g., from volume mount)
    [ -d "$DOTFILES" ] && [ -z "$(ls -A "$DOTFILES" 2>/dev/null)" ] && rmdir "$DOTFILES"
    run_as "git clone $DOTFILES_REPO $DOTFILES"
    ok "Dotfiles cloned"
else
    log "Dotfiles already exist, pulling latest..."
    run_as "cd $DOTFILES && git pull --ff-only" || true
    ok "Dotfiles up to date"
fi

# ─── install.sh ──────────────────────────────────────────────────────────────
step "install.sh"
run_as "cd $DOTFILES && ./install.sh"
ok "install.sh complete"

# ─── GitHub CLI auth ─────────────────────────────────────────────────────────
step "GitHub CLI auth"
if ! run_as 'gh auth status' &>/dev/null; then
    log "Authenticating GitHub CLI..."
    # --git-protocol requires gh >= 2.13; fall back without it
    if run_as 'gh auth login --web --git-protocol ssh </dev/tty' 2>/dev/null; then
        ok "GitHub CLI authenticated"
    elif run_as 'gh auth login --web </dev/tty' 2>/dev/null; then
        ok "GitHub CLI authenticated (without git-protocol flag)"
    else
        warn "gh auth failed — run 'gh auth login' manually after setup"
    fi
else
    ok "GitHub CLI already authenticated"
fi

# ─── SOPS age key ────────────────────────────────────────────────────────────
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
        run_as "mkdir -p $AGE_KEY_DIR"
        printf '%s\n' "$AGE_KEY" | run_as "tee $AGE_KEY_DIR/keys.txt > /dev/null"
        chmod 600 "$AGE_KEY_DIR/keys.txt" 2>/dev/null || true
        ok "Age key saved to $AGE_KEY_DIR/keys.txt"
    else
        log "Skipping — run secrets-init after login to set up SOPS"
    fi
else
    ok "Age key already exists"
fi

# ─── deploy.sh ───────────────────────────────────────────────────────────────
step "deploy.sh"
run_as "cd $DOTFILES && ./deploy.sh"
ok "deploy.sh complete"

# ─── Claude Code ─────────────────────────────────────────────────────────────
step "Claude Code"
if ! run_as 'command -v claude' &>/dev/null; then
    log "Installing Claude Code..."
    run_as 'curl -fsSL https://claude.ai/install.sh | sh'
    ok "Claude Code installed"
else
    ok "Claude Code already installed"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "=== Setup Complete ==="
log "User:     $USERNAME"
log "Home:     $USER_HOME"
log "Dotfiles: $USER_HOME/code/dotfiles"
if [[ "$PROVIDER" == "runpod" ]]; then
    log "SSH:      ssh $USERNAME@<ip> -p <port>"
    log "Switch:   su - $USERNAME"
    log "Restart:  curl -fsSL .../restart.sh | bash && su - $USERNAME"
else
    log "SSH:      ssh $USERNAME@<ip>"
fi
