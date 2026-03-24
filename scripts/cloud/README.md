# Cloud Setup

Setup scripts for cloud VMs/containers.

## RunPod (Step-by-Step)

**Goal:** Non-root user for safe Claude Code yolo mode.

```bash
# 1. Fresh pod - run as root (one-time)
curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/setup.sh | bash

# 2. Switch to user
su - yulong

# 3. After pod restart (recreates user entry lost from /etc/passwd)
curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/restart.sh | bash
su - yulong
```

**If you messed up** (ran things as root, now have permission errors):
```bash
# As root
curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/fix_permissions.sh | bash
su - yulong
```

Then SSH directly as user: `ssh yulong@<ip>`

## Hetzner / Standard VPS

**Option A: User-only** (same as RunPod)
```bash
curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/setup.sh | bash
su - yulong
```

**Option B: Both root and user** (if you want dotfiles for both)
```bash
# As root - setup root's environment
git clone https://github.com/yulonglin/dotfiles.git ~/code/dotfiles
cd ~/code/dotfiles && ./install.sh && ./deploy.sh

# Create user
useradd -m -s /bin/zsh yulong
echo "yulong ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/yulong

# As user - setup user's environment
su - yulong
git clone https://github.com/yulonglin/dotfiles.git ~/code/dotfiles
cd ~/code/dotfiles && ./install.sh && ./deploy.sh
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
USERNAME=dev USER_HOME=/data/dev curl ... | bash
```

| Variable | Default | Description |
|----------|---------|-------------|
| `USERNAME` | `yulong` | Non-root username to create |
| `USER_HOME` | Auto-detected | User home directory (`/workspace/$USERNAME` on RunPod, `/home/$USERNAME` otherwise) |
| `GITHUB_USER` | `yulonglin` | GitHub username (for SSH key import) |
| `DOTFILES_REPO` | `https://github.com/yulonglin/dotfiles.git` | Dotfiles repo URL |

## What Gets Installed

**System packages:** sudo, zsh, htop, vim, nvtop (if available)

**User tools:**
- uv (Python package manager)
- oh-my-zsh with powerlevel10k
- tmux with custom config
- Claude Code CLI

**Configuration:**
- ZSH with custom aliases and functions
- Git config with user settings
- Claude Code settings and skills
