# Deploy Core Component Flags

## Context

Currently, `deploy.sh` deploys three components **unconditionally** (no `DEPLOY_*` flag guard):
- ZSH/bash shell config (lines ~109–195, including Atuin, aliases, ASCII art)
- tmux config (lines ~99–100)
- git config (lines ~208–211, calls `deploy_git_config()`)

This prevents selective deployments like "only Mouseless" (`./deploy.sh --minimal --mouseless` currently also deploys shell + tmux + git).

Adding `DEPLOY_SHELL`, `DEPLOY_TMUX`, `DEPLOY_GIT_CONFIG` flags (all defaulting `true`) preserves existing behavior for all current use cases while enabling "bare skeleton" and "component-only" deployments.

This work was split from the Mouseless integration plan (`serialized-mixing-coral.md`) to keep that change focused.

**Critiques incorporated from:** Codex + Gemini agents (see `serialized-mixing-coral.md` conversation for full critique transcripts)

---

## Changes

### 1. `config.sh` — add defaults

Add to "Deploy Components" section (near existing `DEPLOY_VIM=true`, lines 32–50):
```bash
DEPLOY_SHELL=true               # ZSH/bash shell configuration
DEPLOY_TMUX=true                # tmux configuration
DEPLOY_GIT_CONFIG=true          # Git configuration (gitconfig, global gitignore)
```

Add to `minimal` profile (~line 181) — must be explicitly zeroed since they default `true`:
```bash
DEPLOY_SHELL=false
DEPLOY_TMUX=false
DEPLOY_GIT_CONFIG=false
```

Fix the misleading `minimal` comment:
```bash
# Nothing optional enabled; shell/tmux/git-config also suppressed — specify everything explicitly
```

**Note:** `server` profile does not need changes — these three default `true` and the server profile already omits them (they're appropriate for servers).

### 2. `deploy.sh` — initialize `RC_FILE` default (line ~96)

**Critical bug fix:** Line 657 references `$RC_FILE` unconditionally in the "Deployment complete!" message. When `DEPLOY_SHELL=false`, `RC_FILE` is never set → undefined variable.

Add **before** the tmux section (~line 96):
```bash
RC_FILE="$HOME/.zshrc"  # default; overwritten by shell block based on detected shell
```

### 3. `deploy.sh` — wrap tmux section (lines 99–100)

```bash
# ─── tmux ─────────────────────────────────────────────────────────────────────

if [[ "$DEPLOY_TMUX" == "true" ]]; then
    log_info "Deploying tmux configuration..."
    eval "echo \"source $DOT_DIR/config/tmux.conf\" $OP \"\$HOME/.tmux.conf\""
fi
```

### 4. `deploy.sh` — wrap shell section (lines 109–195)

Wrap the **entire** shell block in:
```bash
if [[ "$DEPLOY_SHELL" == "true" ]]; then
    # ... lines 109–195 unchanged ...
    # (includes: shell detection, zshrc/bashrc deploy, Atuin, aliases, ASCII art)
fi
```

**Important:** The alias-appending sub-block (lines 184–189) uses `RC_FILE`, which is set inside this same block. Both stay together inside the guard. The default init in step 2 handles the line-657 reference when the block is skipped.

**Alias-skipping warning:** Optionally add after the closing `fi`, if `DEPLOY_ALIASES` is non-empty and `DEPLOY_SHELL` is false:
```bash
if [[ "$DEPLOY_SHELL" != "true" ]] && [[ ${#DEPLOY_ALIASES[@]} -gt 0 ]]; then
    log_warning "DEPLOY_ALIASES set but DEPLOY_SHELL=false — aliases will not be appended"
fi
```

### 5. `deploy.sh` — wrap git config section (lines 208–211)

```bash
# ─── Git Configuration ────────────────────────────────────────────────────────

if [[ "$DEPLOY_GIT_CONFIG" == "true" ]]; then
    log_section "DEPLOYING GIT CONFIGURATION"
    deploy_git_config
else
    log_warning "Skipping git config — ~/.gitignore_global and ~/.ignore_global will not be deployed; ripgrep/fd may pick up unintended files"
fi
```

**Naming rationale:** `DEPLOY_GIT_CONFIG` (not `DEPLOY_GIT`) avoids ambiguity with `DEPLOY_GIT_HOOKS`. Flag is `--git-config`.

### 6. `deploy.sh` — update help text (`show_help()`)

Remove the stale line: `"Git configuration is always deployed."` (it's no longer true after this change).

Add to OPTIONS section (near existing `--vim`, `--editor` flags):
```
    --shell           Deploy ZSH/bash shell configuration
    --tmux            Deploy tmux configuration
    --git-config      Deploy gitconfig and global ignore files
```

Add explicit `--no-*` examples (these already work via generic handler, but worth documenting):
```
    --no-shell        Skip .zshrc / .bashrc deployment
    --no-tmux         Skip .tmux.conf deployment
    --no-git-config   Skip gitconfig and global ignore files
```

Update the profile description line to clarify `minimal`:
```
    minimal: all components suppressed — pair with explicit flags (e.g., --shell --git-config)
```

### 7. `CLAUDE.md` — update deploy.sh defaults list

The "Deployment Components" section lists the deploy.sh defaults. Add `--shell`, `--tmux`, `--git-config` to the defaults list.

Update the `--minimal` description to note that shell/tmux/git are now also suppressed.

---

## Critical Files

| File | Change |
|------|--------|
| `config.sh` | Add `DEPLOY_SHELL/TMUX/GIT_CONFIG=true`; add all three as `false` in minimal profile; fix minimal comment |
| `deploy.sh` | `RC_FILE` default init; wrap 3 sections; update help text; remove stale comment |
| `CLAUDE.md` | Update deployment components and defaults list |

---

## Usage After This Change

| Command | What deploys |
|---------|-------------|
| `./deploy.sh` | All defaults (unchanged behavior — shell/tmux/git all still deploy) |
| `./deploy.sh --minimal` | Nothing — bare skeleton |
| `./deploy.sh --minimal --mouseless` | Only Mouseless (no shell/tmux/git) |
| `./deploy.sh --minimal --shell --tmux --git-config` | Core only (same as current `--minimal`) |
| `./deploy.sh --no-shell` | All defaults except shell config |

---

## Verification

1. `./deploy.sh` — confirm behavior unchanged (all components deploy as before)
2. `./deploy.sh --minimal` — confirm nothing deploys (no ~/.zshrc, ~/.tmux.conf, gitconfig changes)
3. `./deploy.sh --minimal --shell` — confirm only shell config deploys
4. `./deploy.sh --no-tmux` — confirm all defaults except tmux deploy
5. `./deploy.sh --minimal --shell --tmux --git-config` — confirm same result as old `./deploy.sh --minimal`
