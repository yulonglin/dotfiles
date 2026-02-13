# dotfiles

**Highly opinionated** development environment for AI safety research. ZSH, Tmux, Vim, SSH, and AI coding assistants across macOS, Linux, and cloud containers.

This setup reflects workflows optimized for ML research: reproducibility, experiment tracking, async API patterns, and rigorous methodology. The AI assistant configurations enforce research discipline—interview before planning, plan before implementing, skepticism of surprisingly good results.

**Key highlights:**
- 🤖 **AI Coding Assistants** - Extensively configured Claude Code, plus Codex CLI and Gemini CLI support
- 👻 **[Ghostty](https://ghostty.org/)** - Fast, GPU-accelerated terminal with sensible defaults
- 📊 **[htop](https://htop.dev/)** - Dynamic CPU meter configuration that adapts to your core count
- 🦀 **Rust-powered CLI tools** - Modern, blazing-fast replacements for standard Unix utilities
- 🧹 **Automatic cleanup** - Scheduled cleanup of Downloads/Screenshots (macOS, moves to trash)

> Originally forked from [jplhughes/dotfiles](https://github.com/jplhughes/dotfiles) - thanks John for the solid foundation!

## Rust CLI Tools

These modern alternatives are installed by default and significantly faster than their traditional counterparts:

| Tool | Replaces | Why it's better |
|------|----------|-----------------|
| [`bat`](https://github.com/sharkdp/bat) | `cat` | Syntax highlighting, line numbers, git integration |
| [`eza`](https://github.com/eza-community/eza) | `ls` | Colors, icons, git status, tree view built-in |
| [`fd`](https://github.com/sharkdp/fd) | `find` | Intuitive syntax, respects `.gitignore`, 5x faster |
| [`ripgrep`](https://github.com/BurntSushi/ripgrep) (`rg`) | `grep` | Recursive by default, respects `.gitignore`, 10x+ faster |
| [`delta`](https://github.com/dandavison/delta) | `diff` | Side-by-side, syntax highlighting, line numbers |
| [`zoxide`](https://github.com/ajeetdsouza/zoxide) | `cd` | Learns your habits, jump with `z dirname` |
| [`dust`](https://github.com/bootandy/dust) | `du` | Intuitive visualization of disk usage |
| [`jless`](https://github.com/PaulJuliusMartinez/jless) | `less` (JSON) | Interactive JSON viewer with vim keybindings |

**Extras** (`--extras` flag):
- [`hyperfine`](https://github.com/sharkdp/hyperfine) — statistical benchmarking with warmup and multiple runs
- [`lazygit`](https://github.com/jesseduffield/lazygit) — TUI for git
- [`code2prompt`](https://github.com/mufeedvh/code2prompt) — generate LLM prompts from codebases

## Installation

### Step 1: Install dependencies

Install dependencies (e.g. oh-my-zsh and related plugins). The installer auto-detects your OS and applies sensible defaults.

```bash
# Install with defaults (recommended)
./install.sh

# Install only specific components (--minimal disables defaults)
./install.sh --minimal --tmux --zsh
```

**Defaults by platform:**

| Platform | Defaults |
|----------|----------|
| **macOS** | zsh, tmux, AI tools, cleanup + Rust CLI tools via Homebrew |
| **Linux** | zsh, tmux, AI tools, create-user + Rust CLI tools via [mise](https://mise.jdx.dev/) |

Installation on macOS requires Homebrew - install from [brew.sh](https://brew.sh/) first if needed.

### Step 2: Deploy configurations

Deploy configurations (sources aliases for .zshrc, applies oh-my-zsh settings, etc.)

```bash
# Deploy with defaults (recommended)
./deploy.sh

# Deploy with extra aliases (useful for remote machines)
./deploy.sh --aliases=speechmatics

# Deploy only specific components (--minimal disables defaults)
./deploy.sh --minimal --vim --claude
```

**Defaults:**
- Git config, VSCode/Cursor settings, vim, Claude Code, Codex CLI, Ghostty, htop, matplotlib styles
- Experimental features (ty type checker)
- Cleanup automation (macOS only)

**Flags are additive** - e.g., `./deploy.sh --aliases=custom` deploys defaults + custom aliases. Use `--minimal` to disable defaults.

### Claude Code (Primary AI Assistant)

This setup includes extensive [Claude Code](https://docs.anthropic.com/en/docs/claude-code) customization optimized for AI safety research:

```bash
./deploy.sh --claude  # Symlinks claude/ → ~/.claude
```

**What's included:**
- **`CLAUDE.md`** - Global instructions enforcing research discipline:
  - Zero-tolerance rules (no mock data, no fabrication, no destructive git)
  - Research methodology (interview → plan → implement, change one variable at a time)
  - Performance patterns (async API calls, caching, 100+ concurrent requests)
  - Context management (subagents for large files, efficient exploration)
- **`agents/`** - Specialized subagents for different tasks:
  - `code-reviewer`, `research-engineer`, `debugger`, `performance-optimizer`
  - `experiment-designer`, `research-skeptic`, `data-analyst`
  - `literature-scout`, `paper-writer`, `clarity-critic`
- **`skills/`** - Custom slash commands:
  - `/commit`, `/run-experiment`, `/spec-interview-research`
  - `/read-paper`, `/review-draft`, `/reproducibility-report`
- **`hooks/`** - Auto-logging to `~/.claude/logs/`, desktop notifications, file read warnings
- **`templates/`** - Reproducibility reports, research specs

**Smart merge preserves your data** - if `~/.claude` already exists, credentials, history, and cache are automatically restored after symlinking.

### Codex CLI (OpenAI)

[Codex CLI](https://github.com/openai/codex) configuration that reuses Claude Code's skills:

```bash
./deploy.sh --codex  # Symlinks codex/ → ~/.codex
```

**What's included:**
- **`AGENTS.md`** - Global instructions (references CLAUDE.md as source of truth)
- **`config.toml`** - Model settings and per-project trust levels
- **`skills/`** - Symlinked to Claude Code's skills for consistency

The configuration follows the same research discipline as Claude Code but adapted for Codex's execution model.

### Gemini CLI (Google)

[Gemini CLI](https://github.com/google-gemini/gemini-cli) can sync with Claude Code configurations:

```bash
./scripts/sync_claude_to_gemini.sh  # Syncs skills/agents/permissions
```

**What it does:**
- Symlinks Claude Code skills to `~/.gemini/skills/`
- Converts Claude agents to Gemini skill format
- Syncs permissions from `.claude/settings.json` to Gemini policies
- Creates `GEMINI.md` pointer to CLAUDE.md

**Note:** Gemini CLI uses a different skills format. The sync script adapts Claude's configuration but some features may not translate directly.

### Ghostty (Terminal Emulator)

[Ghostty](https://ghostty.org/) is a fast, GPU-accelerated terminal written in Zig. Config is symlinked to the platform-specific location:

```bash
./deploy.sh --ghostty  # Part of defaults
```

**Key settings in `config/ghostty.conf`:**
- `Cmd+C` triggers shell-based copy (integrates with tmux)
- `Shift+Enter` for multiline input
- Sensible font and color defaults

Config location: macOS `~/Library/Application Support/com.mitchellh.ghostty/config`, Linux `~/.config/ghostty/config`

#### Theme Aliases

Launch new Ghostty windows with different color themes - useful for visually distinguishing contexts:

| Alias | Theme | Character |
|-------|-------|-----------|
| `g1` | Catppuccin Mocha | Warm purple/pink |
| `g2` | TokyoNight | Cool blue |
| `g3` | Gruvbox Dark | Retro orange/brown |
| `g4` | Nord | Arctic icy blue |
| `g5` | Dracula | Purple accents |
| `g6` | Rose Pine | Muted rose tones |

```bash
g1                        # Launch Ghostty with Catppuccin Mocha
gtheme "Tomorrow Night"   # Launch with any theme
ghostty +list-themes      # See all available themes
```

Each alias opens a **single fresh window** (no tab restoration) with the specified theme.

#### SSH Color Switching

Terminal colors automatically change when SSH-ing to help identify which machine you're on. Colors revert when the session ends.

```bash
ssh myserver     # In Ghostty: colors change automatically
sshc myserver    # Explicit color-changing SSH (works in any terminal)
```

**Configure per-host colors** by editing `SSH_HOST_COLORS` in `config/aliases.sh`:

```bash
# Format: "background:foreground:cursor" in hex
SSH_HOST_COLORS[prod*]="#3d0000:#ffffff:#ff6666"      # Red-tinted for production
SSH_HOST_COLORS[dev*]="#002200:#ffffff:#66ff66"       # Green-tinted for dev
SSH_HOST_COLORS[gpu*]="#1a0033:#ffffff:#cc66ff"       # Purple for GPU servers
SSH_HOST_COLORS[default]="#0d1926:#c5d4dd:#88c0d0"    # Blue-gray fallback
```

Patterns support wildcards (`prod*` matches `prod1`, `prod-web`, etc.). The `default` key applies to any host without a specific match.

### htop (Process Monitor)

Dynamic [htop](https://htop.dev/) configuration that adapts CPU meters to your core count:

```bash
./deploy.sh --htop  # Part of defaults
```

The config in `config/htop/htoprc` uses a dynamic layout that works across machines with different CPU counts—no manual adjustment needed.

### pdb++ (Python Debugger)

High-contrast color scheme for [pdb++](https://github.com/pdbpp/pdbpp), the enhanced Python debugger:

```bash
./deploy.sh --pdb  # Part of defaults
```

**Global config works with per-project installations**. The config is deployed to `~/.pdbrc.py` (symlinked), but pdb++ is installed per-project via `uv add --dev pdbpp`. This works because pdb++ reads the global config at runtime.

**Auto-detects terminal background** using OSC 11 escape sequence:
- **Light terminals**: Dark colors on light background (solarized-light theme)
- **Dark terminals**: Bright colors on dark background (monokai theme)
- **Fallback**: Defaults to dark theme if detection fails (SSH, older terminals)

Detection succeeds in modern terminals (iTerm2, Ghostty, Kitty, Alacritty) and fails gracefully elsewhere.

**Test it works:**
```bash
cd /path/to/project
uv add --dev pdbpp
python -c "import pdb; pdb.set_trace()" <<< "c"
# Should show high-contrast colors
```

**Per-project override** (advanced): Create `.pdbrc.py` in project root. It takes precedence over the global config. See [pdb++ docs](https://github.com/pdbpp/pdbpp#configuration) for details.

### Automatic Cleanup (macOS)

Scheduled cleanup of old files from `~/Downloads` and `~/Screenshots`:

```bash
./deploy.sh --cleanup  # Part of macOS defaults
```

**How it works:**
- Moves files older than 180 days (configurable) to **Trash** (not permanent delete)
- Runs monthly via launchd
- Only deletes files not accessed AND not modified in retention period

```bash
# Preview what would be cleaned
./scripts/cleanup/cleanup_old_files.sh --dry-run

# Custom retention (90 days) and schedule (weekly)
./scripts/cleanup/install.sh --days 90 --schedule weekly
```

See [`scripts/cleanup/README.md`](./scripts/cleanup/README.md) for full documentation.

### Claude Code Session Cleanup (both platforms)

Automatically kills idle Claude Code processes daily at 17:00:

```bash
./deploy.sh --claude-cleanup  # Part of defaults (both macOS and Linux)
```

**How it works:**
- Only kills processes with **no output activity for 24h** (preserves active + tmux sessions)
- Runs daily via launchd (macOS) or cron (Linux)
- Manual control via `clear-claude-code` command (aliases: `ccl`, `cci`, `ccf`)

```bash
# Check status
clear-claude-code --list

# Uninstall
./scripts/cleanup/setup_claude_cleanup.sh --uninstall
```

### Secrets Sync Automation (both platforms)

Automatically sync secrets with GitHub gist daily at 08:00:

```bash
./deploy.sh --secrets  # Part of defaults
```

**How it works:**
- Bidirectional sync with GitHub gist (SSH config, authorized_keys, git identity)
- Auto-adds local public key to `authorized_keys` (enables SSH between your machines)
- Last-modified wins: compares local vs gist timestamps
- Requires `gh auth login` (run once for authentication)
- Runs daily via launchd (macOS) or cron (Linux)

```bash
# Manual sync
sync-secrets

# Uninstall automation
./scripts/cleanup/setup_secrets_sync.sh --uninstall
```

### Step 3: Configure Powerlevel10k theme

[Powerlevel10k](https://github.com/romkatv/powerlevel10k) provides a fast, feature-rich ZSH prompt. This config includes custom segments for SSH-aware machine identification.

**Requirements**: Install a [Nerd Font](https://github.com/romkatv/powerlevel10k#meslo-nerd-font-patched-for-powerlevel10k) for icons.

**Reconfigure**: Run `p10k configure` (when prompted, overwrite `p10k.zsh` but don't apply to `.zshrc`).

#### Prompt Features

| Segment | Description |
|---------|-------------|
| **Remote host** | Machine name + emoji (SSH sessions only) |
| **Directory** | Current path with git root highlighting |
| **Git status** | Branch, dirty indicator, stash count |
| **Right side** | Exit code, command duration, Python venv, cloud contexts |

#### SSH-Aware Machine Identification

When SSH'd to a remote machine, the prompt shows a **consistent machine name** derived from your SSH config:

```
🛜 mats ~/code/project (main)                   # Instead of: user@ip-172-31-42-17
```

**How it works:**
1. Looks up your public IP against `~/.ssh/config` `HostName` entries
2. Uses the matching `Host` alias as the display name
3. Falls back to abbreviated hostname if no match

**Example SSH config:**
```
Host mats
    HostName 203.0.113.42
    User yulong

Host hetzner-gpu
    HostName 198.51.100.10
    User root
```

SSH to `203.0.113.42` → prompt shows `🛜 mats` instead of the IP or hostname.

**Customization:**
- `SERVER_NAME` env var overrides everything
- `MACHINE_EMOJI` env var changes the icon (default: 🛜)

### Claude Code Statusline

Claude Code displays a custom statusline with session info. Configuration: `claude/statusline.sh`

```
🛜 mats ~/code/project (main*) +12,-3 · 📊 45% · $0.23
│        │              │      │        │        └─ Session cost
│        │              │      │        └─ Context usage (color-coded)
│        │              │      └─ Git insertions/deletions
│        │              └─ Branch (* = dirty)
│        └─ Directory
└─ Machine name (SSH only, same as p10k)
```

**Features:**
- **Machine name**: Uses same `machine-name` script as Powerlevel10k for consistency
- **Git info**: Branch with dirty indicator, line change stats
- **Context %**: Color-coded usage (green <70%, yellow 70-89%, red 90%+)
- **Cost**: Running session total in USD

Both the shell prompt and Claude Code statusline use your SSH config aliases, so machine identification is consistent across tools.

### SSH Key Management

Automatically adds your SSH key to ssh-agent on shell startup:

```bash
# Automatically enabled when you deploy ZSH config
./deploy.sh  # (default: includes ZSH)
```

**How it works:**
- Checks for `~/.ssh/id_ed25519` (customizable via `SSH_KEY_PATH` env var)
- **Prompts to generate** if key doesn't exist (never overwrites existing keys)
- Adds to macOS Keychain (`--apple-use-keychain`) or Linux ssh-agent
- Only runs in interactive shells
- Skips if key already loaded in agent

**First-time setup flow:**
1. Shell starts → detects no key → prompts "Generate a new ed25519 SSH key now? [y/N]"
2. If yes → generates key → shows command to copy public key
3. Automatically adds to agent on this and future shell sessions

**Custom key path:**
```bash
export SSH_KEY_PATH=~/.ssh/id_rsa  # Use RSA key instead
```

Configuration: [`config/ssh_setup.sh`](config/ssh_setup.sh)

## Getting to know these dotfiles

* Any software or command line tools you need, add them to the [install.sh](./install.sh) script. Try adding a new command line tool to the install script.
* Any new plugins or environment setup, add them to the [config/zshrc.sh](./config/zshrc.sh) script.
* Any aliases you need, add them to the [config/aliases.sh](./config/aliases.sh) script. Try adding your own alias to the bottom of the file. For example, try setting `cd1` to your most used git repo so you can just type `cd1` to get to it.
## Cloud Setup (RunPod, Hetzner, etc.)

One-command setup for cloud VMs and containers:

```bash
# RunPod (fresh pod, as root)
curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/setup.sh | bash

# After pod restart (recreates user entry)
curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/restart.sh | bash

# Hetzner / standard VPS (persistent /home)
curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/setup.sh | PERSISTENT=/home bash
```

Then SSH as `yulong@<ip>` (not root). See [`scripts/cloud/README.md`](./scripts/cloud/README.md) for details.

**What it does:**
- Creates non-root user in persistent storage (`/workspace/yulong` on RunPod)
- Installs uv, dotfiles, Claude Code
- Copies SSH keys for direct access
