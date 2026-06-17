# Plan: Improve CLI Flag UX for deploy.sh / install.sh

## Problem

Four distinct use cases need clean invocations:

| Use case | Current invocation | Problem |
|---|---|---|
| Full personal run | `./deploy.sh` | ✅ Works — default profile is `personal` |
| Default run for others | `./deploy.sh --profile=server` | ❌ `server` is wrong name; `default` is more discoverable |
| Default + specific add-on | `./deploy.sh --profile=server --serena` | ✅ Works but requires knowing `server` exists |
| ONLY specific add-ons | `./deploy.sh --minimal --vim --claude` | ❌ `--minimal` sounds like "small base", not "empty base"; and it's broken — shell/tmux/git still deploy unconditionally |

## Architecture Insight: Two-Stage Fix Required

**Three components deploy unconditionally** (no `DEPLOY_*` guard):
- Shell config (deploy.sh ~lines 109–195)
- tmux config (deploy.sh ~lines 99–100)
- Git config (deploy.sh ~lines 208–211)

This means `./deploy.sh --minimal --vim` today deploys vim + shell + tmux + git. Any `--only` flag would inherit this bug. **Must fix the unconditional sections first.**

Confirmed by Codex agent reading deploy.sh: all three sections have zero `if` guards.

---

## Critic Process

Two rounds of parallel critique:

**Round 1** (Codex + Gemini + Plan Critic — initial plan review):
- Two-pass/deferred parsing for `--only` (not inline `apply_profile`)
- Case ordering: new flags before `--*)` catch-all
- Component name validation with allowlist
- Space-separated `--only vim claude` as primary syntax (user feedback)
- `--no-defaults` as alias for `--minimal` (cargo `--no-default-features` precedent)

**Round 2** (Codex + Gemini + Plan Agent — comparing with alternative plan):
- Unconditional deploys are a hard prerequisite for `--only` correctness
- Stage B first (infrastructure guards), Stage A second (UX flags)
- `_known_components` must include `shell` and `git_config` from Stage 1
- Server profile correctly inherits `true` for shell/tmux/git — appropriate for `--default`
- Aliases block guard placement: aliases stay inside the shell guard, with a pre-guard warning

---

## Stage 1: Guard Unconditional Sections (prerequisite)

Makes shell, tmux, and git config skip-able. Zero UX change — just adds guards.

### 1a. `config.sh` — add defaults (~after line 50)

```bash
DEPLOY_SHELL=true               # ZSH/bash shell configuration
DEPLOY_TMUX=true                # tmux configuration
DEPLOY_GIT_CONFIG=true          # Git configuration (gitconfig, global gitignore)
```

### 1b. `config.sh` — add to `minimal` profile (~line 181)

```bash
DEPLOY_SHELL=false
DEPLOY_TMUX=false
DEPLOY_GIT_CONFIG=false
```

Update the `minimal` comment: `# Nothing enabled — specify everything explicitly`

Note: `server` profile needs no changes — inheriting `true` for shell/tmux/git is correct behavior.

### 1c. `deploy.sh` — default `RC_FILE` (~before line 99)

```bash
RC_FILE="$HOME/.zshrc"  # default; overwritten by shell block based on detected shell
```

Prevents undefined variable at line 657 when `DEPLOY_SHELL=false`.

### 1d. `deploy.sh` — wrap tmux section (~lines 99–100)

```bash
if [[ "$DEPLOY_TMUX" == "true" ]]; then
    log_info "Deploying tmux configuration..."
    eval "echo \"source $DOT_DIR/config/tmux.conf\" $OP \"\$HOME/.tmux.conf\""
fi
```

### 1e. `deploy.sh` — wrap shell section (~lines 109–195)

```bash
if [[ "$DEPLOY_SHELL" != "true" ]] && [[ ${#DEPLOY_ALIASES[@]} -gt 0 ]]; then
    log_warning "DEPLOY_ALIASES set but DEPLOY_SHELL=false — aliases will not be appended"
fi

if [[ "$DEPLOY_SHELL" == "true" ]]; then
    # ... lines 109–195 unchanged (shell detection, zshrc/bashrc, Atuin, aliases, ASCII)
fi
```

The aliases block stays inside the shell guard (it depends on `$RC_FILE`). The pre-guard warning fires when aliases are specified but shell deploy is off.

### 1f. `deploy.sh` — wrap git config section (~lines 208–211)

```bash
if [[ "$DEPLOY_GIT_CONFIG" == "true" ]]; then
    log_section "DEPLOYING GIT CONFIGURATION"
    deploy_git_config
else
    log_warning "Skipping git config — ~/.gitignore_global and ~/.ignore_global will not be deployed"
fi
```

### 1g. `deploy.sh` — update help text

Remove stale line: `"Git configuration is always deployed."`

Add to OPTIONS:
```
    --shell           Deploy ZSH/bash shell configuration
    --tmux            Deploy tmux configuration
    --git-config      Deploy gitconfig and global ignore files
```

### Stage 1 Verification

```bash
source scripts/shared/config.sh && source scripts/shared/helpers.sh

# Defaults: all three true
echo "shell=$DEPLOY_SHELL tmux=$DEPLOY_TMUX git=$DEPLOY_GIT_CONFIG"
# Expected: shell=true tmux=true git=true

# Minimal: all three false
apply_profile "minimal"
echo "shell=$DEPLOY_SHELL tmux=$DEPLOY_TMUX git=$DEPLOY_GIT_CONFIG"
# Expected: shell=false tmux=false git=false

# Server: inherits true (correct for shared machines)
source scripts/shared/config.sh  # reset
apply_profile "server"
echo "shell=$DEPLOY_SHELL tmux=$DEPLOY_TMUX git=$DEPLOY_GIT_CONFIG"
# Expected: shell=true tmux=true git=true
```

---

## Stage 2: Add `--default`, `--only`, `--no-defaults` flags

### 2a. `--default` shorthand

`./deploy.sh --default` = `./deploy.sh --profile=server`

In `helpers.sh` → `parse_args()`, insert after `--personal)` and before `--no-*)`:

```zsh
--default)
    apply_profile "server"
    ;;
```

### 2b. `--no-defaults` alias

In `helpers.sh` → `parse_args()`, insert alongside `--minimal`:

```zsh
--no-defaults)
    apply_profile "minimal"
    ;;
```

### 2c. `--only` flag (deferred two-pass implementation)

**Semantics:**
- `./deploy.sh --only vim claude codex` — space-separated, primary form
- `./deploy.sh --only vim,claude` — comma convenience (scripts)
- `./deploy.sh --only vim --only claude` — repeatable, all forms mix freely
- Cannot be mixed with `--profile`, `--minimal`, `--server`, `--personal`, `--default`, or individual `--component`/`--no-component` flags — error if mixed

**Step 1: Declare accumulator** (before the `while` loop):

```zsh
typeset -a _only_components
_only_components=()
local _only_mode=false
```

**Step 2: Add case branches** (before `--no-*)`):

```zsh
--only=*)
    _only_mode=true
    IFS=',' read -rA _parsed_comps <<< "${1#--only=}"
    _only_components+=("${_parsed_comps[@]}")
    ;;
--only)
    _only_mode=true
    shift
    while [[ $# -gt 0 && "${1:0:1}" != "-" ]]; do
        IFS=',' read -rA _parsed_comps <<< "$1"
        _only_components+=("${_parsed_comps[@]}")
        shift
    done
    continue  # skip outer shift — args already consumed
    ;;
```

**Step 3: Mixing guard** (add at the top of profile/component branches):

```zsh
if [[ "$_only_mode" == true ]]; then
    echo "Error: --only cannot be mixed with profile or component flags" >&2
    exit 1
fi
```

**Step 4: Deferred apply** (after the `while` loop, before `parse_args` returns):

```zsh
if [[ "$_only_mode" == true ]]; then
    local _known_components=(vim editor claude codex ghostty htop pdb matplotlib
        git_hooks secrets cleanup claude_cleanup ai_update brew_update keyboard
        bedtime serena zsh tmux ai_tools docker extras experimental create_user
        shell git_config)  # ← from Stage 1

    for _comp in "${_only_components[@]}"; do
        _comp="${_comp// /}"
        [[ -z "$_comp" ]] && continue
        local _comp_lower="${_comp:l}"
        _comp_lower="${_comp_lower//-/_}"
        if (( ! "${_known_components[(Ie)$_comp_lower]}" )); then
            echo "Error: Unknown component '${_comp}'. Valid: ${(j:, :)_known_components}" >&2
            exit 1
        fi
    done

    apply_profile "minimal"
    for _comp in "${_only_components[@]}"; do
        _comp="${_comp// /}"
        [[ -z "$_comp" ]] && continue
        local _comp_upper="${(U)_comp//-/_}"
        typeset -g "INSTALL_${_comp_upper}=true"
        typeset -g "DEPLOY_${_comp_upper}=true"
    done
fi
```

### Case Ordering (critical)

```
1.  --profile=*)
2.  --force|--force-reinstall
3.  --append
4.  --ascii=*
5.  --aliases=*
6.  --minimal / --server / --personal
7.  --default           ← NEW
8.  --no-defaults       ← NEW
9.  --only=* / --only   ← NEW
10. --no-*)             ← existing catch-all
11. --*)                ← existing catch-all
```

### 2d. Help text updates (`deploy.sh` + `install.sh`)

```
PROFILES:
    --default         Safe base for shared/new machines (alias for --profile=server)
    --minimal         Suppress ALL components — specify what you want explicitly
    --no-defaults     Same as --minimal (clearer name)
    --server          Server-appropriate subset
    --personal        Full personal setup (default)

SELECTIVE DEPLOYMENT:
    --only COMP...    Deploy ONLY these components, nothing else
                      Examples:
                        --only vim claude         # space-separated
                        --only vim,claude         # comma-separated
                        --only vim --only claude  # repeatable
                      Cannot be mixed with profiles or --component flags.
```

---

## Files to Change

| File | Stage | Change |
|---|---|---|
| `config.sh` | 1 | Add `DEPLOY_SHELL/TMUX/GIT_CONFIG=true` defaults; add as `false` in minimal profile |
| `deploy.sh` | 1 | `RC_FILE` default init; wrap 3 sections with guards; update help |
| `deploy.sh` | 2 | Help text: `--default`, `--only`, `--no-defaults` |
| `install.sh` | 2 | Help text: same |
| `scripts/shared/helpers.sh` | 2 | `parse_args()`: accumulator, `--default`, `--no-defaults`, `--only` cases, mixing guard, deferred apply |
| `CLAUDE.md` | 2 | Update "Flag Behavior" and "Deployment Components" |

---

## Full Verification

```bash
source scripts/shared/config.sh && source scripts/shared/helpers.sh

# 1: Backwards compat — personal still default
echo "vim=$DEPLOY_VIM editor=$DEPLOY_EDITOR shell=$DEPLOY_SHELL"
# Expected: vim=true editor=true shell=true

# 2: --default = server profile
parse_args --default
echo "vim=$DEPLOY_VIM claude=$DEPLOY_CLAUDE editor=$DEPLOY_EDITOR shell=$DEPLOY_SHELL"
# Expected: vim=true claude=true editor=false shell=true

# 3: --default + add-on
parse_args --default --serena
echo "serena=$DEPLOY_SERENA vim=$DEPLOY_VIM"
# Expected: serena=true vim=true

# 4: --only vim claude (space-separated)
parse_args --only vim claude
echo "vim=$DEPLOY_VIM claude=$DEPLOY_CLAUDE editor=$DEPLOY_EDITOR shell=$DEPLOY_SHELL tmux=$DEPLOY_TMUX"
# Expected: vim=true claude=true editor=false shell=false tmux=false

# 5: --only vim,claude (comma)
parse_args --only vim,claude
# Expected: same as test 4

# 6: --only vim --only claude (repeatable)
parse_args --only vim --only claude
# Expected: same as test 4

# 7: --only with typo = error
parse_args --only cluade 2>&1
# Expected: "Error: Unknown component 'cluade'..."

# 8: --only + profile flag = error
parse_args --only vim --default 2>&1
# Expected: "Error: --only cannot be mixed with profile or component flags"

# 9: --no-defaults = same as --minimal
parse_args --no-defaults
echo "vim=$DEPLOY_VIM shell=$DEPLOY_SHELL"
# Expected: vim=false shell=false

# 10: --minimal truly suppresses everything (Stage 1 fix)
parse_args --minimal
echo "shell=$DEPLOY_SHELL tmux=$DEPLOY_TMUX git=$DEPLOY_GIT_CONFIG vim=$DEPLOY_VIM"
# Expected: all false
```

---

## Summary

| Use case | Invocation | Status |
|---|---|---|
| Full personal run | `./deploy.sh` | ✅ Unchanged |
| Default for others | `./deploy.sh --default` | ✅ New shorthand |
| Default + add-on | `./deploy.sh --default --serena` | ✅ Profile + flag (existing mechanics) |
| Only specific add-ons | `./deploy.sh --only vim claude` | ✅ New, with validation + truly nothing else |
| Empty base (explicit) | `./deploy.sh --no-defaults --vim` | ✅ Clearer alias for `--minimal` |
| Minimal truly empty | `./deploy.sh --minimal` | ✅ Fixed — shell/tmux/git now suppressed too |
