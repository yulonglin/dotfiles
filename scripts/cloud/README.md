# Cloud Setup

Setup scripts for cloud VMs/containers.

## RunPod (Step-by-Step)

**Goal:** Non-root user for safe Claude Code yolo mode.

```bash
# 1. Fresh pod - run as root (one-time). The dotfiles branch is REQUIRED (main = stable, yulong = working).
curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/setup.sh | bash -s -- yulong

# 2. Switch to user
su - yulong

# 3. After pod restart (recreates user + symlinks lost from ephemeral /home)
curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/restart.sh | bash
su - yulong
```

**If you messed up** (ran things as root, now have permission errors):
```bash
# As root
curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/fix_permissions.sh | bash
su - yulong
```

Then SSH directly as user: `ssh yulong@<ip> -p <port>`

## Hetzner / Standard VPS

**Option A: User-only** (same as RunPod; branch is required)
```bash
curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/setup.sh | bash -s -- yulong
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

| Provider | Home Dir | Persistent Data | What Survives Restart |
|----------|----------|-----------------|----------------------|
| RunPod | `/home/yulong` (ephemeral) | `/workspace` (FUSE volume) | `~/code`, `~/.claude`, `~/.local`, `~/.config` via symlinks |
| Hetzner | `/home/yulong` (full VM) | Everything | Everything |

**RunPod architecture:** `/workspace` is a FUSE-mounted network volume that doesn't support `chown`/`chmod`. So the user home lives on the local FS (`/home/yulong`) where permissions work, and working directories are symlinked to `/workspace` for persistence:

```
/home/yulong/          ← local FS (chown works, SSH happy)
├── .ssh/              ← local FS (recreated by restart.sh)
├── code/              → /workspace/code (symlink)
├── .claude/           → /workspace/.claude (symlink)
├── .local/            → /workspace/.local (symlink)
└── .config/           → /workspace/.config (symlink)
```

On container restart, `/etc/passwd` and `/home` are lost. `restart.sh` recreates the user entry and re-establishes the symlinks.

## Branch Selection

`setup.sh` clones and provisions a specific dotfiles branch. The branch is a **required argument** — there
is no default, so you can never silently provision the wrong branch. Omitting it exits with a loud error
that shows the exact command to run. The active branch is printed prominently in the setup banner.

Pass it as a positional (recommended), via `--branch`, or via the `DOTFILES_BRANCH` env var:

```bash
# Positional (recommended; note `bash -s --` to pass args through curl|bash)
curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/setup.sh | bash -s -- yulong

# Flag form (equivalent)
curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/setup.sh | bash -s -- --branch yulong

# Env-var form (no `-s --` needed)
curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/setup.sh | DOTFILES_BRANCH=yulong bash
```

`setup.sh` itself is **always fetched from `main`** — one canonical bootstrap URL. The `--branch` flag
only chooses which branch gets cloned on the box. (Two separate concepts: where the bootstrap script
comes from vs. which branch it checks out.) When provisioning via `provision.py`, pass `--branch yulong`
— it fetches `setup.sh` from main and passes `--branch yulong` through to clone that branch on the pod.

## Configuration

Override via env vars:

```bash
USERNAME=dev curl ... | bash
```

| Variable | Default | Description |
|----------|---------|-------------|
| `USERNAME` | `yulong` | Non-root username to create |
| `USER_HOME` | `/home/$USERNAME` | User home directory |
| `GITHUB_USER` | `yulonglin` | GitHub username (for SSH key import) |
| `DOTFILES_REPO` | `https://github.com/yulonglin/dotfiles.git` | Dotfiles repo URL |
| `DOTFILES_BRANCH` | `main` | Dotfiles branch to clone (overridden by `--branch`) |
| `BWS_TOKEN` | (unset) | BWS access token — supplied non-interactively (no prompt) |
| `TAILSCALE_AUTH_KEY` | (unset) | Tailscale auth key — supplied non-interactively (no prompt) |
| `INTERACTIVE` | `0` | Set `1` (or pass `--interactive`) to prompt for BWS/Tailscale |

### Non-interactive by default

`setup.sh` runs **unattended** — a bare `curl … | bash` never blocks on a prompt, so it works
on RunPod pods that lack a usable controlling terminal (where a `read` would hang and ignore
the keyboard). Supply secrets inline via the `BWS_TOKEN` / `TAILSCALE_AUTH_KEY` env vars, or set
them up after setup (`secrets-init-bws`, `tailscale up --authkey …`) — the summary prints the
exact next-steps for anything skipped. Pass `--interactive` / `-i` to re-enable the BWS +
Tailscale prompts for a guided setup on a box with a real terminal.

## What Gets Installed

`setup.sh` runs `install.sh --profile=cloud` and `deploy.sh --profile=cloud` — a **lean profile** for
remote dev boxes. It's `server` minus the heavy compiles/MCP:

- **Drops** (vs `personal`/`server`): zotero MCP (`--experimental`, slow), pueue + systemd resource
  slices (Rust `cargo install` compile), Rust toolchain + code2prompt (`--extras`), Docker, and all
  macOS/desktop/cleanup/cron/gist components.
- **Keeps**: zsh + oh-my-zsh + p10k, tmux, git, Claude Code, Codex, modern CLI tools (the mise
  binaries — zsh aliases like `ls=eza`, `cat=bat` depend on them), uv, and a current `gh`.

**System packages:** sudo, zsh, htop, vim, nvtop (if available), cron, mosh (roaming/resilient SSH)

**User tools:**
- uv (Python package manager)
- bun (JS runtime + package manager)
- oh-my-zsh with powerlevel10k
- tmux with custom config
- Claude Code CLI + Codex CLI
- gh (GitHub CLI — current version; Linux installs from the official `cli.github.com` apt repo with
  sudo, else a release binary to `~/.local/bin`, so `gh auth login --git-protocol ssh` works).
  Auth is **deferred by default** (the `--web` device flow polls ~15 min and would block bootstrap):
  setup prints a `gh auth login` + `sync-gist` next-step, or pass `--github-auth` to authenticate
  inline. `GH_TOKEN`/`GITHUB_TOKEN` in the env authenticate gh transparently with no prompt.

**Configuration:**
- ZSH with custom aliases and functions
- Git config with user settings
- Claude Code settings and skills
- BWS encrypted secrets (Bitwarden Secrets Manager access token)
