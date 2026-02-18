# Repository Guidelines

`CLAUDE.md` is the source of truth and updated from time to time.

## Project Structure & Module Organization
Core workflows run through `install.sh` (dependency bootstrap) and `deploy.sh` (symlink + alias wiring); keep both safe to rerun after OS updates. Runtime configuration lives in `config/` (`zshrc.sh`, `aliases*.sh`, `p10k.zsh`, `tmux.conf`, `user.conf.example`), while lightweight executables belong in `custom_bins/`. Installer helpers stay inside `scripts/helpers/`, cleanup automations inside `scripts/cleanup/`, and container or remote assets inside `runpod/` (notably `johnh_dev.Dockerfile` and `entrypoint.sh`).

## Build, Test, and Development Commands
- `./install.sh --minimal --tmux --zsh` installs the requested components only; drop `--minimal` to accept the platform defaults.
- `./deploy.sh --aliases=speechmatics --vim` applies the ZSH/Tmux/Vim configs and optional alias packs; rerun after editing `config/*.sh`.
- `runpod/runpod_setup.sh` mirrors the dotfiles inside new RunPod machines; execute it immediately after cloning in remote shells.
- `docker build -f runpod/johnh_dev.Dockerfile -t <tag> .` builds the reference dev image (set `DOCKER_DEFAULT_PLATFORM=linux/amd64` on Apple Silicon), and `docker run -it -v $PWD/runpod/entrypoint.sh:/dotfiles/runpod/entrypoint.sh <tag> /bin/zsh` smoke-tests it.

## Coding Style & Naming Conventions
Scripts use `#!/bin/bash` plus `set -euo pipefail`, long-form options, and explicit booleans (see `install.sh`). Name files in lowercase with hyphens (`custom_bins/tmux-clean`) and keep reusable helpers close to their callers with terse comments only when flow is non-obvious. Zsh fragments must stay idempotent, so guard host-specific logic with `if [[ "$OSTYPE" == ... ]]`.

## Testing Guidelines
Run `shellcheck path/to/script.sh` and `zsh -n config/zshrc.sh` before shipping. Validate terminal assets locally with `tmux -f config/tmux.conf new-session` and `p10k configure`, then rerun `./deploy.sh` to ensure reentrancy. For RunPod changes, rebuild the Docker image and start a disposable container using the mounted `entrypoint.sh` to confirm the bootstrap sequence.

## Commit & Pull Request Guidelines
Follow the current history: short (≤72 char) imperative summaries, optional descriptive body, and issue references such as “Refs #42.” Every commit or PR should list the commands you ran (e.g., `./deploy.sh --vim`) and mention the host used (macOS, Ubuntu, RunPod). PRs need a brief risk assessment (shell version, remote home directory layout) plus screenshots only when touching visual assets like iTerm color schemes.

## Security & Configuration Tips
Copy `config/user.conf.example` to `config/user.conf` for local Git identity and keep the real file untracked; never hardcode tokens in scripts. Prefer package managers first and fall back to local installers the way `scripts/helpers/install_zsh_local.sh` does so that CI and remote hosts stay in sync. Before enabling any cleanup cron jobs, confirm the target directories and respect `config/ignore_global` and `config/ignore_research` so caches, fonts, and secrets remain outside Git.
