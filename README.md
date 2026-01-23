# dotfiles

My personal development environment: ZSH, Tmux, Vim, SSH, and AI coding assistants across macOS, Linux, and cloud containers.

**Key highlights of this setup:**
- 🤖 **[Claude Code](https://docs.anthropic.com/en/docs/claude-code)** - Custom agents, hooks, skills, and slash commands for AI-assisted development
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

**More Rust extras** (`--extras` flag): [`hyperfine`](https://github.com/sharkdp/hyperfine) (benchmarking)

Also available: [`lazygit`](https://github.com/jesseduffield/lazygit) (TUI for git, written in Go)

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

### Claude Code (AI Assistant)

This setup includes extensive [Claude Code](https://docs.anthropic.com/en/docs/claude-code) customization for AI-assisted development:

```bash
./deploy.sh --claude  # Symlinks claude/ → ~/.claude
```

**What's included:**
- **`CLAUDE.md`** - Global instructions: research methodology, coding standards, zero-tolerance rules
- **`agents/`** - Specialized subagents (code-reviewer, research-engineer, debugger, etc.)
- **`skills/`** - Custom slash commands (`/commit`, `/run-experiment`, `/spec-interview`)
- **`hooks/`** - Auto-logging to `~/.claude/logs/`, desktop notifications
- **`templates/`** - Reproducibility reports, research specs

**Smart merge preserves your data** - if `~/.claude` already exists, credentials, history, and cache are automatically restored after symlinking.

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

### htop (Process Monitor)

Dynamic [htop](https://htop.dev/) configuration that adapts CPU meters to your core count:

```bash
./deploy.sh --htop  # Part of defaults
```

The config in `config/htop/htoprc` uses a dynamic layout that works across machines with different CPU counts—no manual adjustment needed.

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

### Step 3: Configure Powerlevel10k theme
This set of dotfiles uses the powerlevel10k theme for zsh, this makes your terminal look better and adds lots of useful features, e.g. env indicators, git status etc...

Note that as the provided powerlevel10k config uses special icons it is *highly recommended* you install a custom font that supports these icons. A guide to do that is [here](https://github.com/romkatv/powerlevel10k#meslo-nerd-font-patched-for-powerlevel10k). Alternatively you can set up powerlevel10k to not use these icons (but it won't look as good!)

This repo comes with a preconfigured powerlevel10k theme in [`./config/p10k.zsh`](./config/p10k.zsh) but you can reconfigure this by running `p10k configure` which will launch an interactive window. 


When you get to the last two options below
```
Powerlevel10k config file already exists.
Overwrite ~/git/dotfiles/config/p10k.zsh?
# Press y for YES

Apply changes to ~/.zshrc?
# Press n for NO 
```

## Getting to know these dotfiles

* Any software or command line tools you need, add them to the [install.sh](./install.sh) script. Try adding a new command line tool to the install script.
* Any new plugins or environment setup, add them to the [config/zshrc.sh](./config/zshrc.sh) script.
* Any aliases you need, add them to the [config/aliases.sh](./config/aliases.sh) script. Try adding your own alias to the bottom of the file. For example, try setting `cd1` to your most used git repo so you can just type `cd1` to get to it.
* Any setup you do in a new RunPod, add it to [runpod/runpod_setup.sh](./runpod/runpod_setup.sh).

## RunPod / Docker

For cloud GPU development, there's a Docker setup in `runpod/`:

```bash
# Build for linux/amd64
export DOCKER_DEFAULT_PLATFORM=linux/amd64
docker build -f runpod/Dockerfile -t your-username/runpod-dev .

# Test locally
docker run -it -e USE_ZSH=true your-username/runpod-dev /bin/zsh
```

See `runpod/` directory for Dockerfile and entrypoint configuration.
