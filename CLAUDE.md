# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a comprehensive dotfiles repository for ZSH, Tmux, Vim, and SSH setup that works across local and remote machines (including RunPod environments). The configuration uses oh-my-zsh with powerlevel10k theme and includes extensive customization for development workflows.

## Core Commands

### Installation and Deployment
```bash
# Install dependencies (remove flags if not needed)
./install.sh --tmux --zsh --extras

# Deploy configuration (basic setup)
./deploy.sh

# Deploy with additional aliases (e.g., for remote machines)
./deploy.sh --aliases=speechmatics

# Deploy with vim configuration
./deploy.sh --vim

# Deploy with custom ASCII art
./deploy.sh --ascii=cat.txt

# Append to existing configs instead of overwriting
./deploy.sh --append
```

### Docker/RunPod Commands
```bash
# Build RunPod Docker image
export DOCKER_DEFAULT_PLATFORM=linux/amd64
docker build -f runpod/johnh_dev.Dockerfile -t jplhughes1/runpod-dev .

# Test Docker image
docker run -it -v $PWD/runpod/entrypoint.sh:/dotfiles/runpod/entrypoint.sh -e USE_ZSH=true jplhughes1/runpod-dev /bin/zsh

# Push to Docker Hub
docker push jplhughes1/runpod-dev
```

## Architecture and Structure

### Core Configuration Files
- `config/zshrc.sh` - Main ZSH configuration, sources all other config files
- `config/aliases.sh` - General purpose aliases (git, tmux, file operations, slurm)
- `config/aliases_speechmatics.sh` - Environment-specific aliases
- `config/tmux.conf` - Tmux configuration
- `config/p10k.zsh` - Powerlevel10k theme configuration
- `config/key_bindings.sh` - Custom key bindings
- `config/extras.sh` - Additional shell configurations

### Custom Binaries
Located in `custom_bins/` and automatically added to PATH:
- `rl` - readlink -f with clipboard copy functionality
- `tsesh` - Tmux session management utility
- `twin` - Tmux window management utility  
- `yk` - Clipboard utility

### ASCII Art System
- ASCII art files stored in `config/ascii_arts/`
- Default art displayed on shell startup from `config/start.txt`
- Can be customized during deployment with `--ascii` flag

### Environment Support
The dotfiles support multiple environments:
- **Local Mac/Linux** - Full feature set with Homebrew/apt packages
- **Remote Linux servers** - Streamlined setup for development VMs
- **RunPod containers** - Docker-based development environments with GPU support

### Package Management Integration
- **uv** - Python package manager, automatically sourced
- **Cargo/Rust** - Rust toolchain, conditionally loaded
- **pyenv** - Python version management, conditionally loaded  
- **micromamba** - Conda alternative, conditionally loaded
- **fnm** - Node version manager, conditionally loaded

### Key Features
- **Modular alias system** - Base aliases + environment-specific extensions
- **Conditional loading** - Tools only loaded if installed
- **Cross-platform compatibility** - Works on Mac (Homebrew) and Linux (apt)
- **GPU development support** - Slurm aliases and RunPod integration
- **Shell enhancements** - History substring search, autosuggestions, syntax highlighting

## Customization Patterns

### Adding New Aliases
Add general aliases to `config/aliases.sh` or create environment-specific files like `config/aliases_<environment>.sh`

### Adding New Dependencies
Add installation commands to `install.sh` with appropriate OS detection and optional flags

### Adding ASCII Art
Place new art files in `config/ascii_arts/` and reference with `--ascii=filename.txt` during deployment

### RunPod Customization
Modify `runpod/runpod_setup.sh` for container-specific setup requirements