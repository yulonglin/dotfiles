# CLAUDE.md

Project-specific guidance for Claude Code when working with the dotfiles repository.

## Project Overview

Comprehensive dotfiles repository for ZSH, Tmux, Vim, SSH, and development tools. Works across macOS, Linux, and RunPod containers. Uses oh-my-zsh with powerlevel10k theme.

## AI Agent Quick Reference

If you're an AI agent (Claude Code, Codex, etc.) working in this repo, read this first.

**What this repo is:** dotfiles deployed via `install.sh` + `deploy.sh`. `claude/` is symlinked to `~/.claude/` and `codex/` to `~/.codex/` — edits here affect your *running* environment immediately.

**Top rules:**
- **Direct pushes to main are allowed** — personal repo, no PR overhead. Use `cwmerge` from worktrees (note: `cwmerge` only recognises branches with the `worktree-` prefix; for branches like `claude/<name>` merge manually with `git -C <main-tree> merge --ff-only <branch>`).
- **Flags are ADDITIVE** to defaults unless `--minimal` is used. See [Flag Behavior](#flag-behavior-critical).
- **Sandbox blocks `git pull/merge/stash`** here, and `codex exec` crashes on macOS inside it — both need `dangerouslyDisableSandbox: true`. Details in the always-loaded `~/.claude/rules/safety-and-git.md` and `agents-and-delegation.md`.
- **`claude/settings.json` is the global source of truth** (symlinked to `~/.claude/settings.json`). Before staging it, verify it has `statusLine`, `hooks`, `permissions` keys — see [`.claude/rules/dotfiles-settings.md`](.claude/rules/dotfiles-settings.md).
- **Secrets are NOT globally exported** (supply chain defense). Use `setup-envrc` per-project via direnv. Edit secrets via `secrets-edit`.
- **Plot with Anthropic style by default** — `from anthro_colors import use_anthropic_defaults`. See [Plotting with Anthropic Style](#plotting-with-anthropic-style).

**Common tasks:**

| Want to... | Command / file |
|---|---|
| Add a new alias | `config/aliases/<topic>.sh` (themed split; or `aliases_<name>.sh` for env-specific) |
| Add a deploy component | Create `deploy_X()` in `deploy.sh` — see [Adding New Features](#adding-new-features) |
| Add a custom binary | Drop it in `custom_bins/` (already on PATH); `chmod +x` |
| Install/manage Mac apps | Add a line to `config/apps.conf` → run `app-picker` (gum TUI) → `brew bundle --file=config/Brewfile`. Official casks + `mas` only, **no third-party taps**. Then `scripts/setup/auth-setup` |
| Add an encrypted secret | `secrets-edit` (interactive dotenv editor) |
| Run an experiment with resource caps | `jexp uv run python -m ...` (Linux: needs pueue + systemd user session) |
| Commit / commit + push + PR | `/commit` skill or `/commit-push-sync` |
| Switch active plugin context | `claude-tools context <profile>` (composable: `code python rust`; `claude-tools context --list` for the current set) |
| Merge worktree → parent branch | `cwmerge` (or `git merge <branch>` from parent if branch isn't `worktree-` prefixed) |
| Pre-deploy verification | See [Claude Code Verification Planning](#claude-code-verification-planning) |

**Where to look:**
- Operational gotchas / surprises → [Important Gotchas](#important-gotchas)
- File layout reference → [Configuration Structure](#configuration-structure)
- Per-deploy behavior → [Important Behaviors](#important-behaviors)
- Global behavioral rules → `~/.claude/rules/*.md`
- This repo's project rules → `.claude/rules/*.md`

## Key Conventions

### Flag Behavior (Critical)

**Flags are ADDITIVE to defaults unless `--minimal` is used**

- `install.sh` defaults: all components enabled (use `--no-<component>` to disable)
- `deploy.sh` defaults: all components enabled (use `--no-<component>` to disable)
- Adding flags extends defaults; `--no-<component>` disables specific ones
- `--minimal` flag disables all defaults (only installs what you specify)
- Modifiers (`--append`, `--ascii`, `--force`) don't affect defaults

See README.md for detailed usage.

### Spec and Plan Locations

- **Specs** go in `specs/`, not `docs/superpowers/specs/` (overrides brainstorming skill default)
- **Plans** go in `plans/` (via `plansDirectory` setting)

### Git Workflow

- **Direct pushes to main are allowed** - no PR required for this personal repo
- **Single branch: `main`.** The old `main`/`yulong` split was collapsed into `main` on 2026-06-22 (PR #10) — `yulong` is kept dormant as a safety net but receives no new work. Do day-to-day work directly on `main`; branch worktrees off `main`. (Route only large/structural merges through a tracked PR; routine commits go direct.)
- **This repo is public, but we no longer keep `main` "clean for others"** — it's just the personal working branch. Genuinely private content (`plans/`, `specs/`, `.remember/`, secrets) still lives in the separate private repo (see [Personal Content](#personal-content)), never on a branch here.

### Personal Content

This repo is public (people star it). A branch in a public repo is **also public**,
so personal working artifacts must not live on any branch here — they go in a
separate **private** repo (`dotfiles-personal`).

| Repo | Visibility | Contents |
|------|-----------|----------|
| `dotfiles` (this one) | Public | Shareable dotfiles only. What people clone/star. |
| `dotfiles-personal` | **Private** | `plans/`, `specs/`, `.remember/`, `tmp/`, personal `docs/`, `config/machines.conf` |

The personal paths are listed in `.gitignore` here so they can't accidentally be
committed to public `main`. They are tracked in the private repo instead.

**Why not a `yulong`/personal branch?** Branches in a public repo are public — a
superset branch would have exposed everything it was meant to hide. A separate
private repo is the only real privacy boundary.

### Worktree Workflow

`yolo` works as before (skip permissions, no worktree). Use `cw`/`cwy` for isolated worktree sessions.

| Command | What it does |
|---------|-------------|
| `yolo` | Skip permissions (no worktree, no tmux) |
| `cw [name]` | Worktree + tmux (with permission prompts) |
| `cwy [name]` | Worktree + tmux + skip permissions |
| `cwl` | List all worktrees |
| `cwmerge [name]` | Merge worktree branch into parent (auto-detects from inside worktree) |
| `/merge-worktree` | Claude skill: merge + AI conflict resolution |
| `cwport <name> [dirs...]` | Copy artifacts (out/, logs/, etc.) from worktree to main tree |
| `cwrm [--no-merge] <name>` | Merge branch → remove worktree → delete branch |
| `cwclean [--dry-run]` | Remove clean worktrees (no changes, no artifacts) |

**`cwrm` merges by default** — the worktree branch is merged into your current branch before removal. Use `--no-merge` to skip. `--force` skips artifact warnings.

**Gitignored files** (.env, out/, logs/) do NOT exist in new worktrees. Each worktree starts clean with only tracked files.

**Artifact lifecycle**: `cw auth-fix` → work → `cwport auth-fix` → `cwrm auth-fix`

### Claude Code Verification Planning

Verification is a design problem — plan *how* you'll verify before you start. Full trigger table and checklist: [`.claude/skills/verification-planning/SKILL.md`](.claude/skills/verification-planning/SKILL.md). **Red flag**: if you think "let me figure out how to verify this," that's EnterPlanMode.

### Deployment Components

Full list of every `deploy.sh` component with its rationale: [`docs/deploy-components.md`](docs/deploy-components.md). Per-component gotchas are tabulated under [Important Behaviors](#important-behaviors) below.

## Architecture

### Configuration Structure

Browse the layout with `eza --tree -L2 config claude custom_bins tools lib` — filenames are self-describing. Only the non-obvious relationships are recorded here:

- **`config/ignore/` is a deliberate two-way split.** `gitignore_base` is deployed to git AND to search tools (ripgrep/fd); `gitignore_research` is deployed to **git only**, so `data/`/`archive/` stay invisible to git but searchable. `patterns` drives the `claude-tools ignore apply` TUI.
- **`config/macos_default_apps.conf` is the single source of truth** for both file-type associations and `$EDITOR`/`$VISUAL`.
- **Plotting is split by deployment method**: `lib/plotting/*.py` is **copied** to `~/.local/lib/plotting/` (so it needs a re-deploy to update), while `config/matplotlib/*.mplstyle` is **symlinked** (live). `anthro_colors.py` is the colour ground truth.
- **`claude/ai_docs -> docs`** is a permanent backwards-compat symlink; **`claude/ai-safety-plugins`** symlinks out to `~/code/marketplaces/ai-safety-plugins`.
- **`config/machines.conf.example` is the only tracked copy** — the real `machines.conf` is gitignored and lives in the private `dotfiles-personal` repo.
- **`.secrets` is legacy** and no longer the runtime path; the BWS token lives outside this repo at `$BWS_TOKEN_FILE` (default `~/.config/bws/token`).
- **`tools/` holds compiled code**, not config: `claude-tools/` (Rust: statusline, context, ignore, setup) and `set-default-app/` (Swift: macOS file associations).

### Directory Environment Variables

`CODE_DIR`, `WRITING_DIR`, `SCRATCH_DIR`, `PROJECTS_DIR`, `DOT_DIR`, `DOTFILES_SECRETS_DIR` override the standard locations — defaults and the `code`/`writing`/`scratch`/`projects`/`dotfiles` aliases are defined in `config/zshrc.sh`. Override in `~/.zshenv`, which loads before zshrc.

**Cloud environments:** The standard directory structure works transparently on RunPod/cloud via symlinks created by `scripts/cloud/setup.sh`. `setup.sh` runs the lean **`cloud` profile** (`install.sh --profile=cloud` / `deploy.sh --profile=cloud`) — `server` minus pueue, zotero MCP, Rust extras, and Docker; keeps modern CLI tools, uv, gh, claude, codex. It provisions the **`main` branch by default**; pin another with `--branch <name>` (env `DOTFILES_BRANCH`), e.g. `curl … | bash -s -- --branch yulong`. `setup.sh` is **always fetched from `main`** (one canonical bootstrap URL); `--branch` only chooses which branch is cloned on the box. `provision.py --branch yulong` likewise fetches `setup.sh` from main and passes `--branch yulong` through to the clone. The active branch is printed in the setup banner. gh is installed current (Linux: official `cli.github.com` apt repo with sudo, else release binary), not jammy's 2.4.0, so `gh auth login --git-protocol ssh` works.

### Important Behaviors

Subtleties worth knowing per deploy component. Full mechanics live in the matching `deploy_*()` function in [`deploy.sh`](./deploy.sh).

| Component | Mechanism | Key gotcha |
|-----------|-----------|------------|
| **Gist Sync** (`deploy_secrets`) | Bidirectional sync of `~/.ssh/config`, `authorized_keys`, `config/user.conf` with gist `3cc239...371`. `authorized_keys` uses **disable-wins union merge** (local is always canonical base; whole-line-commented keys are tombstones that suppress that key everywhere even if gist still lists it active); `~/.ssh/config` and `user.conf` use last-modified-wins. Daily 8 AM (launchd/cron). | Requires `gh auth login`. Manual: `sync-gist`. Runs before git config (user.conf provides identity). Merge logic in `scripts/shared/merge_authorized_keys.py`; active convention: `<type> <blob> [## note]`; disable convention: `# <type> <blob>` under `# --- Disabled / pending deletion ---`. |
| **Encrypted Secrets** (BWS) | API keys in Bitwarden Secrets Manager. **NOT globally exported** — use `setup-envrc` per repo (direnv), or `with-secrets KEY... -- <cmd>` for one-shot. Managed: `OPENAI/OPENROUTER/ANTHROPIC_API_KEY`, `HF_TOKEN`, `MODAL_TOKEN_ID/SECRET`. | BWS token at `~/.config/bws/token`. Run `secrets-init bws` on new machines. Use `secrets-edit` to add/update secrets. |
| **Obsidian Sync** (`--no-obsidian-sync`) | Writes `auth_token` and per-vault `encryptionKey`/`encryptionSalt` into `~/.config/obsidian-headless/` from BWS (`OBSIDIAN_AUTH_TOKEN`, `OBSIDIAN_ENCRYPTION_KEY`, `OBSIDIAN_ENCRYPTION_SALT` — never templated/committed). Any vault whose `sync.log` has no `"Fully synced"` entry yet is force-set to `ob sync-config --mode pull-only`; a vault with sync history is never touched, so a manual promotion sticks across redeploys. | Promote a vault to bidirectional **only** by hand: `ob sync-config --path <vault-path> --mode bidirectional` — never automated by this block or by `obsidian-sync-check`. Run `obsidian-sync-check [--path <vault-path>]` (advisory only, never changes mode) to see if a pull-only vault looks safe to promote. Root incident this guards against: a 2026-06/07 bidirectional sync against an incomplete local copy misread "never downloaded" as "deleted" and propagated deletions upstream (135 files lost, recovered via pull-only reconciliation). |
| **Git Config** (`deploy_git_config`) | Reads `config/user.conf`; prompts on conflicts. Deploys split ignores: `~/.gitignore_global` (git, broad), `~/.ignore_global` (ripgrep, narrow), `~/.config/fd/ignore` (fd). Result: git ignores `data/`/`archive/`, but search tools can still see them. | `fd` has no `--no-ignore-global` flag — use `fd -I` to traverse research dirs. |
| **Editor Settings** (`deploy_editor_settings`) | Merges into VSCode/Cursor/Antigravity settings (no overwrite, existing wins). Auto-installs 38 curated extensions from `vscode_extensions.txt`. | Antigravity CLI at `/Applications/Antigravity.app/Contents/Resources/app/bin/antigravity`. |
| **Zed** | Symlinks `config/zed/{settings,keymap}.json` → `~/.config/zed/`. Searches gitignored files by default. | SSH hosts read from `~/.ssh/config` (gist-synced). Cmd+K overrides Zed's chord prefix → inline AI edit. |
| **Finicky, Ghostty** | Symlinked to fixed paths (Ghostty path is platform-specific). Existing files backed up with timestamp. | Ghostty needs reload (Cmd+Shift+Comma) after config change. |
| **Plotting + matplotlib** (`--matplotlib`) | **Copies** Python modules to `~/.local/lib/plotting/` (isolation); **symlinks** `.mplstyle` files to `~/.config/matplotlib/stylelib/` (live updates). PYTHONPATH set in zshrc. | Python module updates require re-running `deploy.sh --matplotlib`. Default style: `anthropic`. |
| **File Associations** (`--file-apps`) | Reads `config/macos_default_apps.conf`, compiles `tools/set-default-app/main.swift` (cached), calls deprecated `LSSetDefaultRoleHandlerForContentType` (still works on Sequoia). Same conf drives `$EDITOR`/`$VISUAL`. | macOS only. Linux would need `xdg-mime` (not implemented). |
| **Claude Code** (smart merge) | Symlinks `claude/` → `~/.claude/`. If `~/.claude/` predates dotfiles, backed up to `~/.claude.backup.<ts>`, then runtime files restored: `.credentials.json`, `history.jsonl`, `cache/`, `projects/`, `plans/`, `todos/`, `mcp_servers.json`. | Works whether `install.sh` or `deploy.sh` runs first. |

## Plotting with Anthropic Style

**ALWAYS use Anthropic style as default** — `from anthro_colors import use_anthropic_defaults; use_anthropic_defaults()`. Colour constants, the `petri`/`deepmind` alternatives, and the full API are in the `anthropic-style` skill (`~/.claude/skills/anthropic-style/`); the copy-vs-symlink deploy split is under [Important Behaviors](#important-behaviors) above.

## Development Patterns

### Adding New Features

**New Aliases**:
- General: Add to the matching themed split in `config/aliases/<topic>.sh` (sourced by `zshrc.sh`'s `aliases/*.sh` loop)
- Environment-specific: Create `config/aliases_<name>.sh`
- Deploy with: `./deploy.sh --aliases=<name>`

**New Dependencies**:
- Add to `install.sh` with OS detection (`is_macos`/`is_linux`)
- Add feature flag if optional (e.g., `--extras`, `--experimental`)
- Update defaults at top of `install.sh` if should be included by default

**New Deployment Component**:
1. Create `deploy_X()` function in `deploy.sh`
2. Add flag parsing in `while` loop
3. Call function in appropriate section (symlink/copy/append logic)
4. Update help text and defaults

**New Custom Binary**:
- Add script to `custom_bins/` (automatically added to PATH)
- Make executable: `chmod +x custom_bins/<name>`

### Code Style

2-space indentation in shell scripts. Use the `backup_file()` helper for anything destructive. General language conventions live in `~/.claude/rules/coding-conventions.md`.

## Important Gotchas

- **macOS vs Linux paths**: VSCode settings location differs by OS
- **Symlinks vs copies vs sourced**: Some configs are symlinked (Finicky, Ghostty, Claude, Codex, Serena, gitui, `~/.ignore_global`, `~/.config/fd/ignore`), some copied (git, Mouseless). **ZSH is sourced-by-reference**: `~/.zshrc` is a plain file containing only `source $DOT_DIR/config/zshrc.sh`, so edits to `config/zshrc.sh` in the main checkout are live in any new shell with no `deploy.sh` step. `~/.gitignore_global` is composed (concatenated from `config/ignore/gitignore_base` + `config/ignore/gitignore_research`)
- **Mouseless config**: Copied (not symlinked) because Mouseless uses atomic `rename()` on UI save which destroys symlinks. Use `sync-mouseless` to pull UI changes back to dotfiles
- **Conditional loading**: ZSH config only sources tools if they exist (pyenv, micromamba, etc.)
- **Tmux environment pollution**: Use `tmux-clean` script to start with minimal env
- **TPM plugins**: Guarded with `if-shell` so tmux works fine without TPM installed. Deploy auto-installs plugins to disk, but already-running tmux sessions need `prefix + I` or a tmux restart to load them. `prefix + Ctrl-s` saves session, `prefix + Ctrl-r` restores. Continuum auto-restores last saved session on first server start after reboot; `touch ~/tmux_no_auto_restore` to suppress. Save files: `~/.tmux/resurrect/` (portable, auto-cleaned after 30 days)
- **Claude Code directory**: `claude/` is symlinked to `~/.claude/` (not copied)
- **Codex CLI directory**: `codex/` is symlinked to `~/.codex/` (not copied)
- **Serena MCP config**: `config/serena/serena_config.yml` symlinked to `~/.serena/serena_config.yml` (dashboard auto-open disabled)
- **Ghostty config**: Symlinked to platform-specific path, requires reload after changes (Cmd+Shift+Comma)
- **Zed config**: Symlinked (like Ghostty/Claude). `ssh_connections` are machine-specific (added via Zed UI, hosts from ~/.ssh/config)
- **Antigravity config**: VSCode fork by Google (`com.google.antigravity`). Same settings as Cursor, deployed via `--editor` flag. CLI at `/Applications/Antigravity.app/Contents/Resources/app/bin/antigravity`
- **Secrets (BWS)**: BWS token at `~/.config/bws/token`. Run `secrets-init bws` on new machines (paste token from Bitwarden). Use `secrets-edit` to add/update/delete secrets.
- **Secrets are per-project**: API keys require `setup-envrc` in each project. Running `npm postinstall` or `pip install` in a project without `.envrc` cannot access secrets (this is intentional — supply chain defense). Legacy `.secrets` / `.env` files may still exist locally but are no longer the intended runtime path.
- **min-release-age quarantine**: All package managers have a 7-day delay on new releases. Packages published <7 days ago will fail to install. This is intentional. See `claude/rules/supply-chain-security.md` for override syntax
- **Pueue + systemd slices**: `j*` aliases require pueue + systemd user session. `systemd --user` doesn't work inside Claude Code sandbox (bubblewrap blocks D-Bus) — test from normal shell. Cgroup delegation may need one-time `sudo systemctl set-property user-$(id -u).slice Delegate=yes`. Config in `config/resources.conf` (edit when scaling machine).
- **CLI tool package strategy**: macOS uses Homebrew (ecosystem, GUI apps, libraries). Linux uses apt for baseline + mise `github:` backend for modern versions of fast-moving CLI tools (fzf, bat, eza, fd, ripgrep, delta, dust, zoxide, jless, just, sd, duf, gum, vivid). apt packages are often years behind upstream; mise downloads release binaries from GitHub with version tracking (`mise upgrade --all`). Homebrew on Linux was rejected (too heavy, installs own gcc/glibc). See `PACKAGES_CORE` (apt/brew), `PACKAGES_MACOS` (brew), `PACKAGES_LINUX_MISE` (mise) in `config.sh`. **Node.js is the exception** — it's a global runtime (NodeSource `setup_lts.x` on Linux, brew on macOS), installed via `install_node` in `scripts/shared/helpers.sh`, NOT mise. Reason: tools shebang against `node` (e.g. obsidian-headless's `ob` → `#!/usr/bin/env node`) and systemd/cron can't see mise's shell-activated shims. Tracks the **current LTS line** (never an odd "Current" release); the skip-guard floor is the live latest-LTS major fetched from nodejs.org (never EOL — older node is converged up), so re-running `install.sh` after an LTS rollover force-upgrades the major and native modules must be rebuilt. `install_node` deliberately does NOT gate the `apt-get install` on the NodeSource script's exit code (it can exit non-zero after writing the repo, which once left a box on stock Ubuntu node 18). Its skip-guard checks the **system node** (`/usr/bin/node`, brew paths) via `system_node_path()`, never `node` from PATH — a mise-installed node shadows a stale apt node in interactive shells and would mask the guard forever; `install_node` also evicts any mise-managed node (`evict_mise_node`) once the system node is healthy. bun stays the package manager/runtime for JS/TS; it is NOT a Node version manager and can't run direct-V8 native modules like better-sqlite3. **One home per JS-ecosystem CLI on Linux: bun global (`~/.bun/bin`)** — `update-ai-tools` updates via `bun add -g` and removes `~/.npm-global/bin` duplicates that shadow the bun copy (`~/.npm-global` remains only as the sudo-free `NPM_CONFIG_PREFIX` home for socket-cli); root-owned strays in `/usr/local/bin` are flagged for manual removal
- **Rust + bash dual implementations**: Some tools have a Rust version (for speed) and a bash fallback. Keep both in sync. Rust source lives in `tools/claude-tools/src/`, bash in `claude/`. Recompile with `cd tools/claude-tools && cargo build --release` then `cp target/release/claude-tools ../../custom_bins/`. Current dual-impl tools: statusline (`statusline.rs` + `claude/statusline.sh`), usage (`usage.rs` + inline in `statusline.sh`)
- **`mas 7.0.0` requires sudo for every install** (`mas install`, `mas get`, `mas purchase`). `mas` self-escalates (calls `sudo` internally). `install.sh --apps` pre-warms sudo with `sudo -v` (interactive TTY only) and keeps it alive with a background heartbeat for the duration of `brew bundle`, so a single password entry covers all mas apps. `mas account` was removed in 7.0.0 — no CLI way to confirm the signed-in store account (App Store UI only). iCloud account and Media & Purchases (store) account can differ; `mas` only cares about the store account.

## Cross-Reference

- User documentation: README.md
- Cleanup system: scripts/cleanup/README.md
- Git config template: config/gitconfig
- Claude agents: claude/agents/*.md

## Learnings
<!-- Claude: add project-specific discoveries below. Prune entries >2 weeks old. Keep under 20 entries. -->
- tmux-resurrect: auto-save is on (15 min), auto-restore is OFF. Use `prefix+R` popup or `tmux-restore` CLI to selectively restore windows from any save. Resurrect file format: `pane` lines ($2=session, $3=win_index, $8=path) + `window` lines ($2=session, $3=win_index, $7=win_name) (2026-04-05)
- fzf pre-selection in `setup-envrc` requires fzf 0.54+ (`--bind "load:pos(N)+select"`). apt's fzf (0.44) is too old; mise installs 0.71 on Linux. macOS brew is fine. fzf is in both `PACKAGES_CORE` (apt baseline) and `PACKAGES_LINUX_MISE` (modern override) — mise's PATH takes precedence (2026-04-14)
- rust-skills plugin removed (2026-05-26). UserPromptSubmit matcher was hyper-broad ("error", "async", "API", "implement", "explain", "how to" — injected ~100 lines on most prompts). Neuter-via-SessionStart-hook didn't hold (still fired same session) and mutates a tracked file in the marketplace clone, blocking future `git pull`. Re-add if Rust work picks up
- mas `install` vs `get`: `brew bundle` drives App Store installs via `mas install` (re-download only — fails "Redownload Unavailable" on a new machine even for owned apps). `mas get` (= `mas purchase`) is acquire+install and actually works. Fixed by `custom_bins/mas-get`, called before `brew bundle` in install.sh. Ref: github.com/Homebrew/brew/issues/21559 (2026-06-20)
- Hourly checks: `usage-ping` warms the subscription 5-hour window (must run with `ANTHROPIC_API_KEY` unset so it uses OAuth, not the metered API — tested and confirmed working 2026-06-21); `tmux-resume` auto-resumes rate-limited tmux Claude/Codex panes. Parser bug caught: `IFS='|' read` splits on `|` inside ERE patterns, garbling the send sequence — fixed to use ` | ` (space-pipe-space) as field delimiter. Also: deploy `--only=usage-ping,tmux-resume` may race on Linux crontab since both run in parallel; install each setup script sequentially for guaranteed cron entries. (2026-06-21)
- node/JS-CLI drift audit on the Linux box: `npm` resolved 4 ways (socket alias → mise node 24 → `/usr/bin/npm` 9.2 distro deb → usr-merge dup) and `codex` had 4 installs (`~/.npm-global` 0.144.5 shadowing the bun copy 0.144.1 the daily updater maintained, plus native standalone and a stale root-owned `/usr/local/bin` one). Root causes: `install_node`'s guard read `node -v` from PATH so mise's node 24 masked the stock Ubuntu node 18 (NodeSource repo configured, candidate 24.18.0 never installed), and `update-ai-tools` updated the bun copy without checking PATH shadowing. Fixed: guard now uses `system_node_path()`, `evict_mise_node` converges mise, `dedupe_bun_shadows` removes npm-global duplicates. bun's `bun add -g X@latest` also lags ~7 days behind npm by design (bunfig `minimumReleaseAge` quarantine) — a version gap between bun and npm copies is not a bug (2026-07-19)
