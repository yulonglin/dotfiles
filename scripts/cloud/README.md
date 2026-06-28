# Cloud Setup

Setup scripts for RunPod containers.

## Two-Script Flow

```
create-user.sh   ← infra: non-root user + SSH + /workspace symlinks (idempotent)
setup.sh         ← tools: zsh/vim/tmux (hard) + dotfiles/claude/gh/uv/tailscale (soft)
```

**First boot (run as root):**
```bash
# 1. Create user (infra only — fast, idempotent)
curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/create-user.sh | bash

# 2. Install tools (branch required)
curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/setup.sh | bash -s -- main

# 3. Switch to user
su - yulong
```

**After pod restart (recreates user + symlinks lost from ephemeral /home):**
```bash
curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/restart.sh | bash
su - yulong
```

**If you have permission issues** (ran things as root):
```bash
curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/fix_permissions.sh | bash
su - yulong
```

## What Each Script Does

### create-user.sh

Idempotent — safe to re-run (also runs on `restart.sh`).

- `apt install sudo zsh openssh-server`
- Creates non-root user with zsh as login shell, NOPASSWD sudo
- Symlinks `/workspace/{code,.claude,.local,.config}` into `~/` (RunPod persistence)
- Configures sshd (PubkeyAuthentication, StrictModes on volume-mounted FSes)
- Installs SSH authorized_keys from GitHub + root's keys
- Generates outbound `~/.ssh/id_ed25519` for git/gh

### setup.sh

Tiered installs — **zsh/vim/tmux** fail loud; everything else warns and continues.

| Tier | Tools |
|------|-------|
| **Hard** (abort on fail) | zsh, vim, tmux |
| **Soft** (warn + continue) | mosh, rsync, locale, uv, dotfiles, gh, claude, tailscale, BWS token, gh auth |

**Dropped vs old monolithic setup.sh:** Node.js 24, bun, Codex CLI. Add manually if needed.

## RunPod Architecture

```
/home/yulong/          ← local FS (ephemeral — recreated by create-user.sh on restart)
├── .ssh/              ← local FS
├── code/              → /workspace/code    (persists)
├── .claude/           → /workspace/.claude (persists)
├── .local/            → /workspace/.local  (persists)
└── .config/           → /workspace/.config (persists)
```

## Configuration

Override via env vars:

| Variable | Default | Description |
|----------|---------|-------------|
| `USERNAME` | `yulong` | Non-root username |
| `GITHUB_USER` | `yulonglin` | GitHub username (for SSH key import) |
| `DOTFILES_REPO` | `https://github.com/yulonglin/dotfiles.git` | Dotfiles repo |
| `DOTFILES_BRANCH` | (required in setup.sh) | Branch to clone |
| `BWS_TOKEN` | (unset) | BWS access token (non-interactive) |
| `TAILSCALE_AUTH_KEY` | (unset) | Tailscale auth key (non-interactive) |
| `INTERACTIVE` | `0` | Set `1` / pass `-i` to prompt for secrets |
| `GITHUB_AUTH` | `0` | Set `1` / pass `--github-auth` to auth gh inline |

### Non-interactive by default

`setup.sh` never blocks on a prompt — safe for `curl | bash` with no TTY.
Supply secrets via env (`BWS_TOKEN=…`, `TAILSCALE_AUTH_KEY=…`) or set them up after login.
Pass `-i` / `--interactive` to prompt on a box with a real terminal.
