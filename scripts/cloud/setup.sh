#!/bin/bash
# RunPod tool setup — run as root, installs tools for $USERNAME
# Assumes create-user.sh has already run (user + SSH + persistent dirs).
#
# Tiers:
#   HARD (zsh vim tmux) — fail loud, abort
#   SOFT (everything else) — warn and continue
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/setup.sh | bash -s -- main
#   TAILSCALE_AUTH_KEY=tskey-... BWS_TOKEN=... curl ... | bash -s -- main -i

set -e

log()  { echo "  $*"; }
ok()   { echo "  ✓ $*"; }
warn() { echo "  ⚠ $*" >&2; }
fail() { echo "  ✗ $*" >&2; exit 1; }
step() { echo ""; echo "── $* ──"; }

# Run a named block; warn on failure, never exits the script
try() {
    local label="$1"; shift
    if "$@"; then
        ok "$label"
    else
        warn "$label failed — continuing without it"
    fi
}

run_as() { sudo -u "$USERNAME" -i bash -c "$*"; }
tty_usable() { { : >/dev/tty; } 2>/dev/null; }

# ── Config ────────────────────────────────────────────────────────────────────
USERNAME="${USERNAME:-yulong}"
USER_HOME="/home/$USERNAME"
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/yulonglin/dotfiles.git}"
DOTFILES_BRANCH="${DOTFILES_BRANCH:-}"
GITHUB_AUTH="${GITHUB_AUTH:-0}"
INTERACTIVE="${INTERACTIVE:-0}"
BWS_TOKEN="${BWS_TOKEN:-}"
SETUP_URL="https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/setup.sh"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --branch) DOTFILES_BRANCH="$2"; shift 2 ;;
        --branch=*) DOTFILES_BRANCH="${1#*=}"; shift ;;
        --github-auth) GITHUB_AUTH=1; shift ;;
        -i|--interactive) INTERACTIVE=1; shift ;;
        -h|--help)
            echo "Usage: setup.sh <branch> [--github-auth] [-i]"
            echo "  <branch>        dotfiles branch — REQUIRED (e.g. main)"
            echo "  --github-auth   run gh auth login inline (default: deferred)"
            echo "  -i              prompt for BWS token + Tailscale key"
            exit 0 ;;
        -*) echo "Unknown option: $1 (try --help)" >&2; exit 1 ;;
        *) DOTFILES_BRANCH="$1"; shift ;;
    esac
done

[[ -n "$DOTFILES_BRANCH" ]] || {
    echo ""
    echo "  ✗ Dotfiles branch required."
    echo "    curl -fsSL $SETUP_URL | bash -s -- main"
    echo ""
    exit 1
}

[[ "$(id -u)" -eq 0 ]] || fail "Must run as root"
id "$USERNAME" &>/dev/null || fail "User $USERNAME not found — run create-user.sh first"

echo "=== RunPod Setup ==="
log "User:   $USERNAME"
log "Branch: $DOTFILES_BRANCH"
[[ "$DOTFILES_BRANCH" != "main" ]] && warn "Using non-main branch: $DOTFILES_BRANCH"

# ── HARD: core packages (must succeed) ────────────────────────────────────────
step "Core packages (zsh vim tmux)"
apt-get update -qq
apt-get install -y zsh vim tmux || fail "Cannot install core packages (zsh vim tmux)"
ok "zsh vim tmux installed"

# ── SOFT: optional system packages ────────────────────────────────────────────
step "Optional system packages"
_optional_pkgs() {
    apt-get install -y mosh rsync curl ca-certificates unzip locales
    # mosh-server requires a native UTF-8 locale
    locale-gen en_GB.UTF-8 en_US.UTF-8 2>/dev/null
    update-locale LANG=en_GB.UTF-8 LC_ALL=en_GB.UTF-8 2>/dev/null
    export LANG=en_GB.UTF-8 LC_ALL=en_GB.UTF-8
}
try "mosh rsync locale" _optional_pkgs

# ── SOFT: uv ─────────────────────────────────────────────────────────────────
step "uv"
_install_uv() {
    run_as 'command -v uv' &>/dev/null && return 0
    run_as 'curl -LsSf https://astral.sh/uv/install.sh | sh'
}
try "uv" _install_uv

# ── SOFT: dotfiles ────────────────────────────────────────────────────────────
step "Dotfiles"
DOTFILES="$USER_HOME/code/dotfiles"
_dotfiles() {
    git ls-remote --exit-code --heads "$DOTFILES_REPO" "$DOTFILES_BRANCH" >/dev/null 2>&1 \
        || { warn "Branch '$DOTFILES_BRANCH' not found on $DOTFILES_REPO"; return 1; }
    if [[ ! -d "$DOTFILES/.git" ]]; then
        run_as "mkdir -p $USER_HOME/code"
        [[ -d "$DOTFILES" && -z "$(ls -A "$DOTFILES" 2>/dev/null)" ]] && rmdir "$DOTFILES"
        run_as "git clone --branch $DOTFILES_BRANCH $DOTFILES_REPO $DOTFILES"
    else
        run_as "cd $DOTFILES && git fetch origin $DOTFILES_BRANCH \
            && { git diff --quiet && git diff --cached --quiet \
                 || git stash push -u -m 'setup auto-stash'; } \
            && git checkout $DOTFILES_BRANCH && git pull --ff-only"
    fi
    run_as "cd $DOTFILES && ./install.sh --profile=cloud"
    run_as "cd $DOTFILES && ./deploy.sh --profile=cloud"
}
try "dotfiles" _dotfiles

# ── SOFT: GitHub CLI ──────────────────────────────────────────────────────────
step "GitHub CLI"
_install_gh() {
    run_as 'command -v gh' &>/dev/null && return 0
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
https://cli.github.com/packages stable main" \
        | tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    apt-get update -qq && apt-get install -y gh
}
try "gh" _install_gh

# ── SOFT: Claude Code ─────────────────────────────────────────────────────────
step "Claude Code"
_install_claude() {
    run_as 'command -v claude' &>/dev/null && return 0
    run_as 'curl -fsSL https://claude.ai/install.sh | sh'
}
try "claude" _install_claude

# ── SOFT: Tailscale ───────────────────────────────────────────────────────────
step "Tailscale"
_install_tailscale() {
    command -v tailscale &>/dev/null && return 0
    curl -fsSL https://tailscale.com/install.sh | sh
}
try "tailscale install" _install_tailscale

TS_NEEDS_SETUP=0
TS_AUTH_KEY="${TAILSCALE_AUTH_KEY:-}"
if [[ -z "$TS_AUTH_KEY" && "$INTERACTIVE" == "1" ]] && tty_usable; then
    echo "Tailscale auth key (leave empty to skip):"
    echo "(Tip: use an ephemeral reusable key for cloud servers)"
    read -rs TS_AUTH_KEY </dev/tty; echo ""
fi
if [[ -n "$TS_AUTH_KEY" ]]; then
    _ts_up() {
        pgrep tailscaled &>/dev/null || {
            mkdir -p /var/lib/tailscale /var/run/tailscale
            tailscaled --tun=userspace-networking \
                --state=/var/lib/tailscale/tailscaled.state &>/dev/null &
            sleep 2
        }
        local hn="runpod-$(hostname -s)"
        tailscale up --authkey "$TS_AUTH_KEY" --hostname "$hn" --ssh --ephemeral 2>/dev/null || \
            tailscale up --authkey "$TS_AUTH_KEY" --hostname "$hn" --ssh 2>/dev/null
    }
    if try "tailscale up" _ts_up; then
        log "IP: $(tailscale ip -4 2>/dev/null || echo 'check tailscale ip')"
    fi
    unset TS_AUTH_KEY
else
    TS_NEEDS_SETUP=1
    log "Skipping — run: tailscale up --ssh --authkey <key>"
fi

# ── SOFT: BWS token ───────────────────────────────────────────────────────────
step "BWS token"
BWS_TOKEN_FILE="$USER_HOME/.config/bws/token"
BWS_NEEDS_SETUP=0
if [[ -f "$BWS_TOKEN_FILE" ]]; then
    ok "BWS token already present"
else
    if [[ -z "$BWS_TOKEN" && "$INTERACTIVE" == "1" ]] && tty_usable; then
        echo "BWS access token (leave empty to skip):"
        read -rs BWS_TOKEN </dev/tty; echo ""
    fi
    if [[ -n "$BWS_TOKEN" ]]; then
        _save_bws() {
            local dir
            dir="$(dirname "$BWS_TOKEN_FILE")"
            run_as "mkdir -p $dir && chmod 700 $dir"
            printf '%s\n' "$BWS_TOKEN" | run_as "tee $BWS_TOKEN_FILE >/dev/null"
            run_as "chmod 600 $BWS_TOKEN_FILE"
        }
        try "bws token" _save_bws
        unset BWS_TOKEN
    else
        BWS_NEEDS_SETUP=1
        log "Skipping — run: secrets-init-bws"
    fi
fi

# ── SOFT: GitHub CLI auth ─────────────────────────────────────────────────────
GH_NEEDS_AUTH=0
step "GitHub CLI auth"
if run_as 'gh auth status' &>/dev/null 2>&1; then
    ok "Already authenticated"
elif [[ "$GITHUB_AUTH" != "1" ]]; then
    GH_NEEDS_AUTH=1
    log "Deferred — run: gh auth login  (then: sync-gist)"
elif ! tty_usable; then
    GH_NEEDS_AUTH=1
    warn "Non-interactive — run: gh auth login manually"
else
    _gh_auth() {
        run_as 'gh auth login --web --git-protocol ssh </dev/tty' 2>/dev/null || \
            run_as 'gh auth login --web </dev/tty' 2>/dev/null
    }
    if ! try "gh auth" _gh_auth; then
        GH_NEEDS_AUTH=1
    fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "=== Setup Complete ==="
log "User:   $USERNAME @ $USER_HOME"
log "Mosh:   mosh $USERNAME@<host>  (UDP 60000-61000, or use Tailscale)"
log "Switch: su - $USERNAME"
log "SSH:    ssh $USERNAME@<ip> -p <port>"
[[ "$GH_NEEDS_AUTH"   == "1" ]] && log "Next: gh auth login  →  sync-gist"
[[ "$BWS_NEEDS_SETUP" == "1" ]] && log "Next: secrets-init-bws   (or re-run with BWS_TOKEN=…)"
[[ "$TS_NEEDS_SETUP"  == "1" ]] && log "Next: tailscale up --ssh --authkey <key>"
