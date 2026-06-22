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
# One-liner (always fetch this script from main; the dotfiles branch is a REQUIRED positional):
#   stable:  curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/setup.sh | bash -s -- main
#   dev:     curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/setup.sh | bash -s -- yulong

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

# True only if /dev/tty can actually be opened (a usable controlling terminal).
# `[[ -e /dev/tty ]]` is NOT enough — the device node exists in containers without
# a real terminal, so a `read </dev/tty` there blocks forever and ignores keystrokes.
tty_usable() { { : >/dev/tty; } 2>/dev/null; }

# ─── Configuration (override via env vars) ───────────────────────────────────
USERNAME="${USERNAME:-yulong}"
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/yulonglin/dotfiles.git}"
GITHUB_USER="${GITHUB_USER:-yulonglin}"
# Canonical bootstrap URL (this script always lives on main) — reused in the
# "branch is required" error below so the fix is copy-pasteable.
SETUP_URL="https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/setup.sh"
# Dotfiles branch to clone/check out — REQUIRED, no default. A silent default
# (main) meant forgetting the branch quietly provisioned the wrong dotfiles.
# Pass it as a positional (bash -s -- yulong), --branch <name>, or DOTFILES_BRANCH=.
DOTFILES_BRANCH="${DOTFILES_BRANCH:-}"
# GitHub CLI auth is OFF by default — its device flow polls for ~15 min and would
# block the rest of bootstrap. Enable inline with --github-auth or GITHUB_AUTH=1.
# (GH_TOKEN/GITHUB_TOKEN in the env auth gh transparently and skip this regardless.)
GITHUB_AUTH="${GITHUB_AUTH:-0}"
# Prompts (BWS token, Tailscale key) are OFF by default so curl|bash never blocks.
# Supply secrets inline via env (BWS_TOKEN=…, TAILSCALE_AUTH_KEY=…), or pass --interactive.
INTERACTIVE="${INTERACTIVE:-0}"
BWS_TOKEN="${BWS_TOKEN:-}"   # if set, used directly — no prompt, works non-interactively

# ─── Args (override env vars) ────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --branch) DOTFILES_BRANCH="$2"; shift 2 ;;
        --branch=*) DOTFILES_BRANCH="${1#*=}"; shift ;;
        --github-auth) GITHUB_AUTH=1; shift ;;
        -i|--interactive) INTERACTIVE=1; shift ;;
        -h|--help)
            echo "Usage: setup.sh <branch> [--github-auth] [--interactive]"
            echo "  <branch>          dotfiles branch to clone — REQUIRED (e.g. main, yulong)."
            echo "                    Also accepts --branch <name> or DOTFILES_BRANCH=<name>."
            echo "  --github-auth     run 'gh auth login' inline (default: off; deferred to after setup)"
            echo "  -i, --interactive prompt for BWS token + Tailscale key (default: off — supply via"
            echo "                    BWS_TOKEN=… / TAILSCALE_AUTH_KEY=… env, or set up after setup)"
            exit 0
            ;;
        -*) echo "Unknown option: $1 (try --help)" >&2; exit 1 ;;
        *) DOTFILES_BRANCH="$1"; shift ;;   # positional: the dotfiles branch
    esac
done

# Branch is required — fail loud with a copy-paste fix rather than silently
# provisioning the wrong dotfiles (the whole point of dropping the default).
if [[ -z "$DOTFILES_BRANCH" ]]; then
    {
        echo ""
        echo "  ✗ No dotfiles branch specified — it is required."
        echo ""
        echo "  Pass it as a positional arg (recommended):"
        echo "    curl -fsSL $SETUP_URL | bash -s -- yulong"
        echo ""
        echo "  …or via flag / env:"
        echo "    curl -fsSL $SETUP_URL | bash -s -- --branch yulong"
        echo "    curl -fsSL $SETUP_URL | DOTFILES_BRANCH=yulong bash"
        echo ""
        echo "  Common branches: 'main' (public/stable), 'yulong' (working branch)."
    } >&2
    exit 1
fi

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
log "Branch:   $DOTFILES_BRANCH"
[[ "$DOTFILES_BRANCH" != "main" ]] && warn "Using development branch: $DOTFILES_BRANCH (not main)"

# ─── System deps ──────────────────────────────────────────────────────────────
step "System dependencies"
apt-get update && apt-get install -y sudo zsh htop vim cron curl ca-certificates unzip locales mosh
command -v nvtop &>/dev/null || apt-get install -y nvtop 2>/dev/null || true
# Generate AND activate a UTF-8 locale. mosh-server refuses to start without a
# native UTF-8 locale; locale-gen alone isn't enough — update-locale must write
# /etc/default/locale so login shells (and the mosh-server they spawn) inherit it.
# en_US.UTF-8 is generated as a universally-present fallback for non-en_GB clients.
locale-gen en_GB.UTF-8 en_US.UTF-8 2>/dev/null || true
update-locale LANG=en_GB.UTF-8 LC_ALL=en_GB.UTF-8 2>/dev/null || true
export LANG=en_GB.UTF-8 LC_ALL=en_GB.UTF-8
service cron start 2>/dev/null || true
ok "System deps installed (locale: en_GB.UTF-8)"

# ─── Node 24 LTS (for OpenCode / Node-based AI CLIs) ──────────────────────────
# Node 24 (Krypton) is the Active LTS; Node 20 went EOL on 2026-03-24.
step "Node.js"
if ! command -v node &>/dev/null || [[ "$(node -v | cut -d. -f1 | tr -d 'v')" -lt 24 ]]; then
    log "Installing Node 24..."
    curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
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
    # User exists but home dir might be wrong (e.g., previously set to /workspace/yulong)
    CURRENT_HOME=$(getent passwd "$USERNAME" | cut -d: -f6)
    if [[ "$CURRENT_HOME" != "$USER_HOME" ]]; then
        log "Updating home: $CURRENT_HOME → $USER_HOME"
        usermod -d "$USER_HOME" "$USERNAME"
    fi
    ok "User $USERNAME exists (uid=$(id -u "$USERNAME"))"
fi

# Ensure home directory exists
mkdir -p "$USER_HOME"

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

# Outbound identity key: authorized_keys above lets you log IN; this is the key
# the box uses to talk OUT to GitHub (git push, gh over SSH). Generate it
# non-interactively if absent so gh never drops into its own interactive keygen
# prompt (the original bootstrap-hang cause) and git-over-SSH works immediately.
# ed25519, no passphrase — the sensible default for an unattended ephemeral box.
if [[ ! -f "$SSH_DIR/id_ed25519" ]]; then
    log "Generating outbound SSH key (ed25519, no passphrase)..."
    run_as "ssh-keygen -t ed25519 -N '' -C '$USERNAME@$(hostname)' -f '$SSH_DIR/id_ed25519' -q"
    ok "SSH key generated: $SSH_DIR/id_ed25519.pub"
else
    log "Outbound SSH key already present: $SSH_DIR/id_ed25519"
fi

# Always restart sshd — keys or config may have changed
step "Restart sshd"
service ssh restart 2>/dev/null || systemctl restart sshd 2>/dev/null || warn "Could not restart sshd"
ok "sshd restarted"

# ─── Bun + uv (parallel) ────────────────────────────────────────────────────
step "Bun + uv"

bun_pid="" bun_log=""
uv_pid="" uv_log=""

if ! run_as 'command -v bun' &>/dev/null; then
    bun_log=$(mktemp)
    run_as 'curl -fsSL https://bun.sh/install | bash' &>"$bun_log" &
    bun_pid=$!
else
    ok "Bun already installed"
fi

if ! run_as 'command -v uv' &>/dev/null; then
    uv_log=$(mktemp)
    run_as 'curl -LsSf https://astral.sh/uv/install.sh | sh' &>"$uv_log" &
    uv_pid=$!
else
    ok "uv already installed"
fi

for name in bun uv; do
    eval "pid=\${${name}_pid:-}"
    eval "logfile=\${${name}_log:-}"
    [[ -z "$pid" ]] && continue
    if wait "$pid" 2>/dev/null; then
        ok "$name installed"
    else
        warn "$name installation failed"
    fi
    echo "  ── $name ──"
    cat "$logfile" 2>/dev/null
    rm -f "$logfile"
done

# ─── Dotfiles ────────────────────────────────────────────────────────────────
step "Dotfiles"
DOTFILES="$USER_HOME/code/dotfiles"
# Fail fast on a typo'd / missing branch (public repo → no auth needed for ls-remote).
git ls-remote --exit-code --heads "$DOTFILES_REPO" "$DOTFILES_BRANCH" >/dev/null 2>&1 \
    || fail "Branch '$DOTFILES_BRANCH' not found on $DOTFILES_REPO"
if [ ! -d "$DOTFILES/.git" ]; then
    log "Cloning $DOTFILES_REPO ($DOTFILES_BRANCH) → $DOTFILES"
    run_as "mkdir -p $USER_HOME/code"
    # Remove empty dir if it exists (e.g., from volume mount)
    [ -d "$DOTFILES" ] && [ -z "$(ls -A "$DOTFILES" 2>/dev/null)" ] && rmdir "$DOTFILES"
    run_as "git clone --branch $DOTFILES_BRANCH $DOTFILES_REPO $DOTFILES"
    ok "Dotfiles cloned ($DOTFILES_BRANCH)"
else
    log "Dotfiles already exist, checking out $DOTFILES_BRANCH and pulling latest..."
    # install.sh regenerates committed binaries (e.g. custom_bins/claude-tools-linux-x86_64)
    # with different bytes, so the worktree is reliably dirty here. Stash before switching
    # (reversible — the fresh binary is rebuilt by install.sh) so checkout can't abort.
    # Report honestly instead of masking failure with `|| true` (was printing a false "✓").
    if run_as "cd $DOTFILES && git fetch origin $DOTFILES_BRANCH \
        && { git diff --quiet && git diff --cached --quiet || git stash push -u -m 'setup.sh auto-stash'; } \
        && git checkout $DOTFILES_BRANCH && git pull --ff-only"; then
        ok "Dotfiles up to date ($DOTFILES_BRANCH)"
    else
        warn "Dotfiles update failed — pod may run stale dotfiles. Check: cd $DOTFILES && git status"
    fi
fi

# ─── install.sh ──────────────────────────────────────────────────────────────
# Lean cloud profile: server minus heavy compiles (extras/pueue) and zotero MCP.
step "install.sh"
run_as "cd $DOTFILES && ./install.sh --profile=cloud"
ok "install.sh complete"

# ─── GitHub CLI auth ─────────────────────────────────────────────────────────
# Off the critical path by default: gh's --web device flow polls for ~15 min and
# would block deploy.sh + the rest of bootstrap. Deferred to a post-setup step
# (gist/secrets sync degrade gracefully without it). Opt in with --github-auth.
GH_NEEDS_AUTH=0
step "GitHub CLI auth"
if run_as 'gh auth status' &>/dev/null; then
    ok "GitHub CLI already authenticated"
elif [[ "$GITHUB_AUTH" != "1" ]]; then
    GH_NEEDS_AUTH=1
    log "Skipping (not on critical path) — run 'gh auth login' after setup for gist/secrets sync"
    log "Re-run with --github-auth to authenticate inline"
elif ! tty_usable; then
    GH_NEEDS_AUTH=1
    warn "Non-interactive — can't run gh device flow. Run 'gh auth login' manually after setup"
else
    log "Authenticating GitHub CLI..."
    # --git-protocol requires gh >= 2.13; fall back without it
    if run_as 'gh auth login --web --git-protocol ssh </dev/tty' 2>/dev/null; then
        ok "GitHub CLI authenticated"
    elif run_as 'gh auth login --web </dev/tty' 2>/dev/null; then
        ok "GitHub CLI authenticated (without git-protocol flag)"
    else
        GH_NEEDS_AUTH=1
        warn "gh auth failed — run 'gh auth login' manually after setup"
    fi
fi

# ─── Register SSH key with GitHub ────────────────────────────────────────────
# Upload the outbound key generated above so git push / gh over SSH work
# immediately. gh reads GH_TOKEN/GITHUB_TOKEN from the env transparently, so this
# also auto-uploads in the non-interactive path when a token is supplied.
# Idempotent: skips if the key is already registered (restart-safe).
step "Register SSH key with GitHub"
SSH_KEY_NEEDS_UPLOAD=0
PUBKEY_FILE="$SSH_DIR/id_ed25519.pub"
if [[ ! -f "$PUBKEY_FILE" ]]; then
    log "No SSH public key — skipping"
elif run_as 'gh auth status' &>/dev/null; then
    pubkey_body=$(awk '{print $2}' "$PUBKEY_FILE")
    if run_as 'gh ssh-key list' 2>/dev/null | grep -qF "$pubkey_body"; then
        ok "SSH key already registered with GitHub"
    elif run_as "gh ssh-key add '$PUBKEY_FILE' --title '$(hostname)-$USERNAME'" &>/dev/null; then
        ok "SSH key uploaded to GitHub"
    else
        SSH_KEY_NEEDS_UPLOAD=1
        warn "Could not upload SSH key to GitHub"
    fi
else
    SSH_KEY_NEEDS_UPLOAD=1
    log "Skipping upload (gh not authenticated) — add the key after 'gh auth login'"
fi

# ─── BWS access token ──────────────────────────────────────────────────────
step "BWS access token (Bitwarden Secrets Manager)"
BWS_TOKEN_DIR="$USER_HOME/.config/bws"
BWS_TOKEN_FILE="$BWS_TOKEN_DIR/token"
BWS_NEEDS_SETUP=0
if [ ! -f "$BWS_TOKEN_FILE" ]; then
    # Priority: env-supplied token (non-interactive) > --interactive prompt > skip.
    if [[ -n "$BWS_TOKEN" ]]; then
        log "Using BWS_TOKEN from environment"
    elif [[ "$INTERACTIVE" == "1" ]] && tty_usable; then
        echo "Paste your BWS access token (from Bitwarden Secrets Manager), leave empty to skip:"
        read -rs BWS_TOKEN </dev/tty
    else
        log "Skipping BWS token (non-interactive) — supply via BWS_TOKEN=… or run secrets-init-bws after login"
        BWS_TOKEN=""
    fi
    if [[ -n "$BWS_TOKEN" ]]; then
        # Smoke test before saving — catch typos early
        # Pass token via env to avoid leaking in process argv (visible via ps)
        # sudo -i resets env, so use env(1) to inject it for the child process
        if sudo -u "$USERNAME" env "BWS_ACCESS_TOKEN=$BWS_TOKEN" bws secret list &>/dev/null 2>&1; then
            run_as "mkdir -p $BWS_TOKEN_DIR && chmod 700 $BWS_TOKEN_DIR"
            printf '%s\n' "$BWS_TOKEN" | run_as "tee $BWS_TOKEN_FILE > /dev/null"
            run_as "chmod 600 $BWS_TOKEN_FILE"
            ok "BWS token saved and verified"
        else
            BWS_NEEDS_SETUP=1
            warn "BWS token failed connectivity test — not saved. Run secrets-init-bws after login to retry"
        fi
        unset BWS_TOKEN
    else
        BWS_NEEDS_SETUP=1
        log "Skipping — run secrets-init-bws after login"
    fi
else
    ok "BWS token already exists"
fi

# ─── deploy.sh ───────────────────────────────────────────────────────────────
step "deploy.sh"
run_as "cd $DOTFILES && ./deploy.sh --profile=cloud"
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

# ─── Codex CLI ───────────────────────────────────────────────────────────────
# The lean `cloud` profile keeps INSTALL_AI_TOOLS=false (that gate also pulls in
# the Rust toolchain + OpenCode + Antigravity), so install Codex directly here —
# lightweight `bun add -g`, no compile. Mirrors the Claude Code block above.
step "Codex CLI"
if ! run_as 'command -v codex' &>/dev/null; then
    log "Installing Codex CLI..."
    if run_as 'bun add -g @openai/codex' &>/dev/null; then
        ok "Codex CLI installed"
    else
        warn "Codex CLI install failed (bun required); skipping"
    fi
else
    ok "Codex CLI already installed"
fi

# ─── Tailscale ───────────────────────────────────────────────────────────────
step "Tailscale"
if ! command -v tailscale &>/dev/null; then
    log "Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
    ok "Tailscale installed"
else
    ok "Tailscale already installed"
fi

TS_NEEDS_SETUP=0
TS_AUTH_KEY="${TAILSCALE_AUTH_KEY:-}"
if [[ -z "$TS_AUTH_KEY" ]]; then
    # Priority: TAILSCALE_AUTH_KEY env (above, non-interactive) > --interactive prompt > skip.
    if [[ "$INTERACTIVE" == "1" ]] && tty_usable; then
        echo "Paste your Tailscale auth key (tailscale.com/admin/settings/keys), leave empty to skip:"
        echo "(Tip: use an ephemeral reusable key for cloud servers)"
        read -rs TS_AUTH_KEY </dev/tty
        echo ""
    else
        log "Skipping Tailscale (non-interactive) — supply via TAILSCALE_AUTH_KEY=… or run 'tailscale up' after login"
    fi
fi

if [[ -n "$TS_AUTH_KEY" ]]; then
    # Start tailscaled — containers often lack systemd
    if ! pgrep tailscaled &>/dev/null; then
        mkdir -p /var/lib/tailscale /var/run/tailscale
        # --tun=userspace-networking: avoids iptables/TUN (required in most containers)
        tailscaled --tun=userspace-networking --state=/var/lib/tailscale/tailscaled.state &>/dev/null &
        sleep 2
    fi

    TS_HOSTNAME="${PROVIDER}-$(hostname -s)"
    # --ephemeral: auto-removes from tailnet when pod shuts down (ideal for cloud VMs)
    tailscale up --authkey "$TS_AUTH_KEY" --hostname "$TS_HOSTNAME" --ephemeral 2>/dev/null || \
        tailscale up --authkey "$TS_AUTH_KEY" --hostname "$TS_HOSTNAME" 2>/dev/null || \
        warn "tailscale up failed — run manually after login"
    unset TS_AUTH_KEY
    ok "Tailscale connected ($(tailscale ip -4 2>/dev/null || echo 'check tailscale ip'))"
else
    TS_NEEDS_SETUP=1
    log "Skipping — run 'tailscale up --authkey <key>' after login to connect"
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
log "Mosh:     mosh $USERNAME@<host>  (mosh-server installed; UDP 60000-61000, or just use Tailscale)"
if [[ "$GH_NEEDS_AUTH" == "1" || "$SSH_KEY_NEEDS_UPLOAD" == "1" || "$BWS_NEEDS_SETUP" == "1" || "$TS_NEEDS_SETUP" == "1" ]]; then
    echo ""
    [[ "$GH_NEEDS_AUTH" == "1" ]]  && log "Next:     gh auth login   then   sync-gist   (enables gist + secrets sync)"
    [[ "$SSH_KEY_NEEDS_UPLOAD" == "1" ]] && log "Next:     gh ssh-key add $SSH_DIR/id_ed25519.pub --title $(hostname)-$USERNAME   (register box key on GitHub)"
    [[ "$BWS_NEEDS_SETUP" == "1" ]] && log "Next:     secrets-init-bws   (or re-run with BWS_TOKEN=… / --interactive)"
    [[ "$TS_NEEDS_SETUP" == "1" ]]  && log "Next:     tailscale up --authkey <key>   (or set TAILSCALE_AUTH_KEY=…)"
fi
