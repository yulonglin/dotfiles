# dotfiles
ZSH, Tmux, Vim, ssh and coding agents setup on both local/remote machines.

Originally built upon: https://github.com/jplhughes/dotfiles

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
| **macOS** | zsh, tmux, AI tools, cleanup + core tools via brew (bat, eza, zoxide, delta) |
| **Linux** | zsh, tmux, AI tools, create-user + **mise** + modern CLI tools (bat, eza, fd, ripgrep, delta, zoxide) |

**Modern CLI tools (installed by default on Linux via mise):**
- `bat` - syntax-highlighted `cat`
- `eza` - modern `ls` replacement
- `fd` - user-friendly `find`
- `ripgrep` (`rg`) - fast recursive search
- `delta` - improved git diff
- `zoxide` - smarter `cd` (use `z` command)

**Extras (--extras flag):** dust, jless, hyperfine, lazygit, code2prompt

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
- Git config, VSCode/Cursor settings, vim, Claude Code, Codex CLI, Ghostty, matplotlib styles
- Experimental features (ty type checker)
- Cleanup automation (macOS only)

**Flags are additive** - e.g., `./deploy.sh --aliases=custom` deploys defaults + custom aliases. Use `--minimal` to disable defaults.

### Claude Code Deployment (AI Assistant)

The `--claude` flag deploys custom Claude Code configuration:

```bash
./deploy.sh --claude
```

**What gets deployed:**
- `CLAUDE.md` - Global AI instructions for all projects
- `settings.json` - Claude Code settings
- `agents/` - Specialized agent definitions
- `hooks/` - Auto-logging, notifications
- `skills/` - Custom slash commands (/commit, /run-experiment, etc.)
- `commands/` & `templates/` - Custom commands and templates

**Smart Merge (automatic):**
If `~/.claude` already exists from Claude Code installation, the deployment:
1. 🔄 Backs up existing directory to `~/.claude.backup.<timestamp>`
2. 🔗 Creates symlink from `dotfiles/claude/` → `~/.claude`
3. ✅ Restores your runtime files (credentials, history, cache, projects, etc.)

**Your data is preserved** - credentials, conversation history, and all runtime files are automatically restored after the merge.

**Any order works:**
```bash
# Option 1: Install Claude first, then deploy config
./install.sh --ai-tools  # Creates ~/.claude with runtime files
./deploy.sh --claude      # Smart merge happens here

# Option 2: Deploy config first, then install Claude
./deploy.sh --claude      # Creates symlink
./install.sh --ai-tools  # Claude writes runtime files into symlinked dir
```

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

## Docker image for runpod

To build the docker image for runpod, you can run the following command:

```bash
export DOCKER_DEFAULT_PLATFORM=linux/amd64
docker build -f runpod/johnh_dev.Dockerfile -t jplhughes1/runpod-dev .

# Build with buildx
docker buildx create --name mybuilder --use
docker buildx build --platform linux/amd64 -f runpod/johnh_dev.Dockerfile -t jplhughes1/runpod-dev . --push

```

To test it

```bash
docker run -it -v $PWD/runpod/entrypoint.sh:/dotfiles/runpod/entrypoint.sh -e USE_ZSH=true jplhughes1/runpod-dev /bin/zsh
```

To push it to docker hub

```bash
docker push jplhughes1/runpod-dev
```
