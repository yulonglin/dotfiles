# Cloud Setup

One-command setup for cloud VMs/containers. Creates non-root user, installs dotfiles, Claude Code.

## Quick Start (Copy-Paste)

### RunPod

```bash
# Fresh pod (as root)
curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/setup.sh | bash

# After pod restart
curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/restart.sh | bash
```

Then: `ssh yulong@<ip>` (not root)

### Hetzner / Standard VPS

```bash
# Hetzner is a persistent VM, so /home works normally
curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/setup.sh | PERSISTENT=/home bash
```

Then: `ssh yulong@<ip>`

## How It Works

| Provider | Persistence | Home Dir | Code Dir |
|----------|-------------|----------|----------|
| RunPod | Only `/workspace` | `/workspace/yulong` | `~/code` |
| Hetzner | Full VM | `/home/yulong` | `~/code` |

RunPod containers lose `/etc/passwd` on restart, so the restart script recreates the user entry.

## Configuration

Override via env vars:

```bash
USERNAME=dev PERSISTENT=/data curl ... | bash
```

| Variable | Default | Description |
|----------|---------|-------------|
| `USERNAME` | `yulong` | Non-root username to create |
| `PERSISTENT` | `/workspace` | Persistent storage path |
| `HOME_DIR` | `$PERSISTENT/$USERNAME` | User home directory |
| `DOTFILES_REPO` | `https://github.com/yulonglin/dotfiles.git` | Dotfiles repo URL |

## What Gets Installed

**System packages:** sudo, zsh, htop, ncdu, vim, nvtop (if available)

**User tools:**
- uv (Python package manager)
- oh-my-zsh with powerlevel10k
- tmux with custom config
- Claude Code CLI

**Configuration:**
- ZSH with custom aliases and functions
- Git config with user settings
- Claude Code settings and skills
