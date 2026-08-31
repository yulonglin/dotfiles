# dotfiles

**Highly opinionated** development environment for AI safety research. ZSH, Tmux, Vim, SSH, and AI coding assistants across macOS, Ubuntu, and cloud containers.

This setup reflects workflows optimized for ML research: reproducibility, experiment tracking, async API patterns, and rigorous methodology. The AI assistant configurations enforce research discipline—interview before planning, plan before implementing, skepticism of surprisingly good results.

**Key highlights:**

- 🤖 **AI Coding Assistants** - Extensively configured Claude Code and some Codex support
- 👻 **Sensible defaults for [Ghostty](https://ghostty.org/)**
- 🦀 **Rust-powered CLI tools** - Modern, blazing-fast replacements for standard Unix utilities
- 🧹 **Automatic cleanup** - Scheduled cleanup of Downloads/Screenshots (macOS, moves to trash)

> Originally forked from [jplhughes/dotfiles](https://github.com/jplhughes/dotfiles) - thanks John for the solid foundation!

> **AI agents working here:** start with [`CLAUDE.md`](./CLAUDE.md) — top rules, a common-tasks table, and pointers into [`docs/deploy-components.md`](./docs/deploy-components.md) (deploy behavior, cloud, extending) and [`docs/tooling-and-packages.md`](./docs/tooling-and-packages.md) (packages, symlink-vs-copy, gotchas). This README is human-oriented onboarding; CLAUDE.md is the operational doc.

## Quickstart

This project offers two quickstart paths: **Local** and **Cloud**.

---

### Local Quickstart

For setting up on your personal machine (macOS, Linux, desktop/laptop):

```bash
git clone https://github.com/yulonglin/dotfiles.git && cd dotfiles

# 1. Install dependencies (zsh, tmux, CLI tools, AI assistants)
./install.sh

# 2. Deploy configurations (symlinks, shell config, secrets, automation)
./deploy.sh

# 3. Restart your shell
source ~/.zshrc
```

- `install.sh` installs required software.
- `deploy.sh` deploys config files and settings.
- Both scripts are **idempotent** and safe to re-run.

All configuration options are stored in [`config.sh`](./config.sh). Flags are **additive** (e.g., `--mouseless` adds that feature to defaults). Use `--minimal` to disable most options.


---

### Cloud Quickstart

For cloud environments (RunPod, Hetzner, Lambda Labs, etc):

1. **SSH into your new remote machine as root.**
2. **Run the one-liner:**
   ```bash
   # RunPod (fresh pod)
   curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/setup.sh | bash

   # Hetzner / standard VPS (persistent /home)
   curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/setup.sh | USER_HOME=/home bash
   ```
   This creates a non-root user in persistent storage (`/workspace/yulong` on RunPod), copies SSH keys, installs dependencies, clones dotfiles, and runs `install.sh --profile=cloud` + `deploy.sh --profile=cloud` (a lean remote-dev set — no pueue/zotero/Rust toolchain). It will prompt for GitHub auth.

   Provisions the **`main`** branch by default. To pin another branch, pass `--branch` (use `bash -s --` to forward args through `curl | bash`) or set `DOTFILES_BRANCH`:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/setup.sh | bash -s -- --branch yulong
   ```
3. **Reconnect as your user:**
   ```bash
   ssh yulong@<ip>
   ```
4. **(Optional) After pod restart** (RunPod recreates `/etc/passwd`):
   ```bash
   curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/restart.sh | bash
   ```
5. **(Optional) Customize components:**
   Edit [`config.sh`](./config.sh) to disable resource-intensive options (AI assistants, cleanup automation, etc.) before running install/deploy.

**Tip:** The setup auto-detects cloud providers and adjusts accordingly (persistent storage paths, SSH config, no macOS-only features). See [`scripts/cloud/README.md`](./scripts/cloud/README.md) for details.

## Installation

### Step 1: Install dependencies

Install dependencies (e.g. oh-my-zsh and related plugins). The installer auto-detects your OS and applies sensible defaults.

```bash
# Install with defaults (recommended)
./install.sh

# Install only specific components
./install.sh --minimal --tmux --zsh  # --minimal disables all defaults
```

**Defaults by platform:**


| Platform  | Defaults                                                                            |
| --------- | ----------------------------------------------------------------------------------- |
| **macOS** | zsh, tmux, AI tools, cleanup + Rust CLI tools via Homebrew                          |
| **Linux** | zsh, tmux, AI tools, create-user + Rust CLI tools via [mise](https://mise.jdx.dev/) |


Installation on macOS requires Homebrew - install from [brew.sh](https://brew.sh/) first if needed.

The Rust CLI tools installed by default: [`bat`](https://github.com/sharkdp/bat) (cat), [`eza`](https://github.com/eza-community/eza) (ls), [`fd`](https://github.com/sharkdp/fd) (find), [`ripgrep`](https://github.com/BurntSushi/ripgrep) (grep), [`delta`](https://github.com/dandavison/delta) (diff), [`zoxide`](https://github.com/ajeetdsouza/zoxide) (cd), [`dust`](https://github.com/bootandy/dust) (du), [`jless`](https://github.com/PaulJuliusMartinez/jless) (JSON viewer). `--extras` adds [`hyperfine`](https://github.com/sharkdp/hyperfine), [`gitui`](https://github.com/extrawurst/gitui), and [`code2prompt`](https://github.com/mufeedvh/code2prompt).

### Step 2: Deploy configurations

Deploy configurations (sources aliases for .zshrc, applies oh-my-zsh settings, etc.). All settings live in [`config.sh`](./config.sh) — edit once, deploy everywhere.

```bash
# Deploy with defaults (recommended)
./deploy.sh

# Profiles
./deploy.sh --profile=server    # Safe base for shared machines
./deploy.sh --profile=minimal   # Nothing enabled — specify what you want

# Deploy only specific components
./deploy.sh --only vim claude   # Only vim and claude, nothing else

# Add to defaults
./deploy.sh --mouseless         # Defaults + mouseless
```

**Default components:**

- **Shell**: ZSH, tmux, vim, Powerlevel10k
- **Editors**: VSCode/Cursor/Antigravity (merged settings), Zed (symlinked config + keymap), `.editorconfig`, `.curlrc`, `.inputrc`
- **AI tools**: Claude Code, Codex CLI, Serena MCP, Ghostty terminal
- **Git**: gitconfig, global gitignore/gitattributes, global git hooks (secret detection)
- **Dev tools**: htop, pdb++, matplotlib styles, `claude-tools` Rust binary
- **Secrets**: GitHub gist sync, Bitwarden Secrets Manager (BWS)
- **Supply chain**: 7-day quarantine for npm/bun/pnpm/uv, weekly dep-audit
- **Automation**: file cleanup (macOS), Claude Code session cleanup, AI tools auto-update, package auto-update, text replacements sync (macOS)

**Flags are additive** — e.g., `./deploy.sh --mouseless` deploys defaults + mouseless. Use `--minimal` to disable all defaults, then specify only what you want.

## Adopting These Dotfiles

This repo is highly personal — it reflects one person's workflow, opinions, and tooling choices. The best way to use it is to **point a coding agent at this repo and ask it to extract the parts you find useful** into your own dotfiles.

**Generalizable (worth extracting):**

- Shell config (zsh/tmux/p10k)
- Modern CLI tools (bat, eza, fd, rg, etc.)
- Git config + global gitignore/gitattributes
- Editor settings (VSCode/Cursor merge logic)
- Cleanup automation (Downloads/Screenshots)
- Gist sync (bidirectional SSH config/identity sync)
- BWS encrypted secrets workflow

**Personal (skip or replace):**

- Claude Code plugins/agents/skills
- Website alias, SSH host colors
- Mouseless config
- Ghostty theme aliases
- Specific API keys and gist IDs
- Cloud setup scripts (RunPod user)
- Plugin marketplace selections

All personal values are centralized in [`config.sh`](./config.sh) — edit `DOTFILES_USERNAME`, `DOTFILES_REPO`, `GIST_SYNC_ID`, `GIT_USER_NAME`, and `GIT_USER_EMAIL` to make it yours.

## Secrets & Security

### Encrypted Secrets (Bitwarden Secrets Manager)

API keys are stored in [Bitwarden Secrets Manager](https://bitwarden.com/products/secrets-manager/) (BWS) — a hosted, team-shareable secrets vault. The CLI (`bws`) fetches secrets on demand; nothing is written to disk except a machine access token (at `~/.config/bws/token`).

**Commands:**

```bash
secrets-init bws         # First-time setup: save BWS access token
secrets-edit             # Add/update/delete secrets (fzf TUI or: secrets-edit KEY VALUE)
secrets-paths            # Show resolved backend + token path
```

**New machine setup:**

1. Run `./install.sh` (installs bws CLI)
2. Run `secrets-init bws` and paste your BWS access token from Bitwarden

**Per-project usage:** Run `setup-envrc` in any repo to create a `.envrc` that selectively exposes only the secrets that repo should see. It supports direct exports (`KEY`), renamed exports (`ENV_VAR=SECRET_NAME`), and a repo-specific Telegram plugin binding (`--telegram-secret SECRET_NAME`). If local `.env` files already exist, the TUI scans the repo root recursively and can offer to delete selected files.

`setup-envrc` tries `direnv allow` automatically. If that cannot update direnv's allowlist (for example in a sandboxed environment), it prints the manual `direnv allow .` command and still completes the rest of the setup.

### Supply Chain Defense

Multi-layer defense against npm/PyPI supply chain attacks (axios 2026, litellm 2026, shai-hulud 2025). Deployed automatically with `./deploy.sh`.

**What it does:**

| Layer | Defense | What it blocks |
|-------|---------|----------------|
| 7-day quarantine | `min-release-age` on all package managers | Freshly-published malicious versions (caught within days) |
| Script blocking | `ignore-scripts=true` in npm/pnpm | Postinstall scripts that exfiltrate secrets or install RATs |
| Credential isolation | API keys scoped per-project via direnv | Compromised package in project A can't read project B's keys |
| Lockfile scanning | Pre-commit hook checks changed lockfiles | Known-bad packages entering your lockfile |
| Weekly audit | Scans all repos for known-bad IOCs | Packages you already have that were later found compromised |
| Claude Code hook | Warns before any `npm install` / `pip install` | AI assistant installing packages without checking them first |

**Day-to-day workflow:**

```bash
# Installing packages works normally — quarantine is transparent
npm install express          # Works (express is >7 days old)
bun add zod                  # Works
uv add httpx                 # Works

# New packages published <7 days ago are blocked (intentional)
npm install some-brand-new-pkg
# Error: min-release-age — package was published 2 days ago

# Override for a specific install (after checking it's safe)
npm install --min-release-age=0 some-brand-new-pkg   # npm
bun add --minimumReleaseAge=0 some-brand-new-pkg      # bun
UV_EXCLUDE_NEWER= uv pip install some-brand-new-pkg   # uv
```

**Credential isolation:**

API keys stay in `$DOTFILES_SECRETS_DIR/secrets.env.enc` and are NOT globally exported. Each project gets only the keys it needs:

```bash
# Interactive picker (fzf)
cd ~/code/my-project
setup-envrc                  # Select keys with TAB, confirm with ENTER
# → Creates .envrc with eval-based exports, direnv auto-loads on cd

# Non-interactive
setup-envrc ANTHROPIC_API_KEY OPENAI_API_KEY

# Map a namespaced secret into the env var your app expects
setup-envrc ANTHROPIC_API_KEY TELEGRAM_BOT_TOKEN=NUDGE_TELEGRAM_BOT_TOKEN

# Claude Telegram plugin: keep the token canonical in dotfiles-secrets,
# and generate .claude/channels/telegram/.env only at launch time
setup-envrc --telegram-secret AMBASSADOR_TELEGRAM_BOT_TOKEN

# Check what's configured
setup-envrc --list           # Show keys in current .envrc
setup-envrc --clean          # Remove .envrc

# One-off command with selected keys (no .envrc needed)
with-secrets ANTHROPIC_API_KEY OPENAI_API_KEY -- python my_script.py
```

**Manual audit:**

```bash
dep-audit                    # Scan all repos for known-bad packages now
# Runs automatically every Sunday at 10 AM
```

**Config files deployed:**

| File | Deployed to | Purpose |
|------|-------------|---------|
| `config/npmrc` | `~/.npmrc` | `ignore-scripts=true` + `min-release-age=7` |
| `config/bunfig.toml` | `~/.bunfig.toml` | `minimumReleaseAge=604800` (seconds) |
| `config/pnpmrc` | `~/Library/Preferences/pnpm/rc` | `minimum-release-age=10080` (minutes) |
| `config/uv.toml` | `~/.config/uv/uv.toml` | `exclude-newer` (via `UV_EXCLUDE_NEWER` env var) |

**Selective deploy:**

```bash
./deploy.sh --only pkg-configs    # Just package manager configs
./deploy.sh --no-pkg-configs      # Everything except package configs
./deploy.sh --only dep-audit      # Just the weekly audit
```

### Global Git Hooks

Pre-commit hooks for secret detection across all repositories (`./deploy.sh --git-hooks`, part of defaults). Scans staged files for API keys, tokens, and credentials before each commit.

## Where The Detail Lives

Everything else this repo does is documented next to the code it configures:

- **Deploy components** (every component, mechanisms, gotchas, how to extend) → [`docs/deploy-components.md`](./docs/deploy-components.md)
- **Terminal, shell & dev tools** (Ghostty themes + SSH colors, Powerlevel10k machine ID, Claude Code statusline, `claude-tools ignore`, SSH keys, pdb++, htop, media recovery) → [`docs/terminal-and-dev-tools.md`](./docs/terminal-and-dev-tools.md)
- **Claude Code setup** (rules/skills/hooks layout, smart-merge restore) → [`CLAUDE.md`](./CLAUDE.md) + [`docs/deploy-components.md`](./docs/deploy-components.md)
- **Plugin marketplaces & management** → [`docs/plugin-management.md`](./docs/plugin-management.md)
- **Codex / Antigravity / OpenCode integration** → [`docs/cross-tool-extensibility.md`](./docs/cross-tool-extensibility.md)
- **Automation schedules** (cleanup, auto-updates, uninstall commands) → [`scripts/cleanup/README.md`](./scripts/cleanup/README.md)
- **Cloud provisioning detail** → [`scripts/cloud/README.md`](./scripts/cloud/README.md)
- **Packages & tooling strategy** (symlink-vs-copy, operational gotchas) → [`docs/tooling-and-packages.md`](./docs/tooling-and-packages.md)
