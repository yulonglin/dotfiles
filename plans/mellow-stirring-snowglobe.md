# Plan: Centralized Component Registry

## Context

Components are defined in 3 places that drift: `config.sh` (defaults), `show_component_menu()` (TUI), and `parse_args()` (`_known_components` whitelist). Adding pueue to config.sh didn't add it to the TUI, so "select all" missed it. Goal: define each component once, derive everything else.

## Design

**Single registry in `config.sh`** — two ordered arrays (`INSTALL_REGISTRY`, `DEPLOY_REGISTRY`) replace the manual `INSTALL_*`/`DEPLOY_*` variable declarations. Format:

```zsh
# "name|description|platform|default"
INSTALL_REGISTRY=(
    "core|Core packages, CLI tools, gh, SOPS/age, uv|all|true"
    "pueue|Pueue job scheduler + pueued daemon|linux|true"
    ...
)
```

**New helper function `_init_component_vars()`** in `config.sh` — iterates registries, sets `INSTALL_*=<default>` / `DEPLOY_*=<default>` variables. Called once at end of registry section. This means:
- No more manual `INSTALL_CORE=true` lines — derived from registry
- `config.local.sh` overrides still work (loaded after init)
- CLI `--flags` still work (parsed after config.local.sh)

**`show_component_menu()` refactored** — reads from `INSTALL_REGISTRY`/`DEPLOY_REGISTRY` instead of hardcoded `comp_defs`. Filters by platform at runtime.

**`_known_components` derived** — built from registry arrays in `parse_args()`, eliminating the hardcoded whitelist.

## Files to Change

### 1. `config.sh`

**Replace** lines 23-65 (manual `INSTALL_*`/`DEPLOY_*` variables) with:

```zsh
# ─── Component Registry (single source of truth) ────────────────────────────
# Format: "name|description|platform|default"
# - name: CLI flag name (dashes OK, converted to underscores for variables)
# - description: TUI menu display text
# - platform: all, macos, linux
# - default: true/false (initial default, overridden by profiles/CLI)

INSTALL_REGISTRY=(
    "core|Core packages, CLI tools, gh, SOPS/age, uv|all|true"
    "zsh|ZSH + oh-my-zsh + powerlevel10k theme|all|true"
    "tmux|Terminal multiplexer|all|true"
    "ai-tools|Claude Code, Gemini CLI, Codex CLI|all|true"
    "extras|hyperfine, gitui, code2prompt, terminal-notifier|all|false"
    "cleanup|Automatic cleanup (macOS only)|all|true"
    "experimental|ty type checker, zerobrew|all|true"
    "macos-settings|macOS system defaults (Dock, Finder, keyboard)|macos|true"
    "finicky|Finicky browser routing|macos|true"
    "docker|Docker engine + compose|linux|true"
    "pueue|Pueue job scheduler + pueued daemon|linux|true"
    "create-user|Create non-root dev user|linux|true"
)

DEPLOY_REGISTRY=(
    "shell|ZSH config, aliases, key bindings|all|true"
    "tmux|tmux.conf + TPM plugins|all|true"
    "git-config|gitconfig, global gitignore, ripgrep config|all|true"
    "vim|vimrc|all|true"
    "editor|VSCode/Cursor settings + extensions (merges)|all|true"
    "claude|Claude Code config symlink (~/.claude)|all|true"
    "codex|Codex CLI config symlink (~/.codex)|all|true"
    "ghostty|Ghostty terminal config (symlinked)|all|true"
    "htop|htop config with dynamic CPU meters|all|true"
    "pdb|pdb++ debugger config (high-contrast)|all|true"
    "matplotlib|Style files: anthropic, deepmind, petri|all|true"
    "git-hooks|Global pre-commit secret detection|all|true"
    "secrets|Sync SSH/git identity via GitHub gist|all|true"
    "secrets-env|Decrypt SOPS-encrypted API keys (age)|all|true"
    "cleanup|Auto-cleanup Downloads/Screenshots (macOS)|all|true"
    "claude-cleanup|Remove idle Claude sessions after 24h|all|true"
    "ai-update|Daily auto-update: Claude, Gemini, Codex|all|true"
    "brew-update|Weekly package upgrade + cleanup|all|true"
    "claude-tools|Build claude-tools Rust binary|all|true"
    "finicky|Browser routing config (symlinked)|macos|true"
    "file-apps|Default editor for coding file types|macos|true"
    "keyboard|Keyboard repeat rate enforcement at login|macos|true"
    "bedtime|Bedtime timezone enforcement|macos|false"
    "text-replacements|Sync macOS + Alfred text replacements|macos|false"
    "mouseless|Keyboard-driven mouse control|macos|false"
    "vpn|NordVPN + Tailscale split tunnel daemon|macos|false"
    "pueue|Pueue + systemd resource slices|linux|true"
    "serena|Serena MCP server config (symlinked)|all|false"
)
```

Then add `_init_component_vars()`:

```zsh
# Initialize INSTALL_*/DEPLOY_* variables from registry
_init_component_vars() {
    local entry name var_name default
    for entry in "${INSTALL_REGISTRY[@]}"; do
        name="${entry%%|*}"
        default="${entry##*|}"
        var_name="${(U)name//-/_}"
        typeset -g "INSTALL_${var_name}=${default}"
    done
    for entry in "${DEPLOY_REGISTRY[@]}"; do
        name="${entry%%|*}"
        default="${entry##*|}"
        var_name="${(U)name//-/_}"
        typeset -g "DEPLOY_${var_name}=${default}"
    done
}
_init_component_vars
```

**Keep non-registry items unchanged:**
- `DEPLOY_ALIASES=()` (array, not boolean)
- `DEPLOY_APPEND=false` (modifier)
- `DEPLOY_ASCII_FILE="start.txt"` (modifier)

### 2. `scripts/shared/helpers.sh` — `show_component_menu()`

Replace hardcoded `comp_defs` construction with registry iteration:

```zsh
show_component_menu() {
    local mode="$1"
    if [[ "${NON_INTERACTIVE:-false}" == "true" ]] || ! [[ -t 0 ]] || ! cmd_exists gum; then
        return 0
    fi

    typeset -a comp_defs
    local registry_name="_registry"
    local prefix

    if [[ "$mode" == "install" ]]; then
        registry_name="INSTALL_REGISTRY"
        prefix="INSTALL"
    elif [[ "$mode" == "deploy" ]]; then
        registry_name="DEPLOY_REGISTRY"
        prefix="DEPLOY"
    fi

    local entry name desc platform var_name
    for entry in "${(P)${registry_name}[@]}"; do
        name="${entry%%|*}"
        local rest="${entry#*|}"
        desc="${rest%%|*}"
        rest="${rest#*|}"
        platform="${rest%%|*}"

        # Platform filter
        if [[ "$platform" == "macos" ]] && ! is_macos; then continue; fi
        if [[ "$platform" == "linux" ]] && ! is_linux; then continue; fi

        var_name="${(U)name//-/_}"
        local current_val="${(P)${prefix}_${var_name}}"
        comp_defs+=("${name}|${desc}|${current_val}")
    done

    # ... rest of function unchanged (items/selected_csv logic)
}
```

### 3. `scripts/shared/helpers.sh` — `parse_args()` `_known_components`

Replace hardcoded array with dynamic derivation:

```zsh
# Build _known_components from registries
local _known_components=()
local _entry _name _var
for _entry in "${INSTALL_REGISTRY[@]}" "${DEPLOY_REGISTRY[@]}"; do
    _name="${_entry%%|*}"
    _var="${${(U)_name}//-/_}"
    if (( ! ${_known_components[(Ie)$_var]} )); then
        _known_components+=("$_var")
    fi
done
```

### 4. `config.sh` — `apply_profile()`

**`minimal` profile** — replace the hardcoded list (lines 209-249) with a registry loop:
```zsh
minimal)
    local _entry _name _var
    for _entry in "${INSTALL_REGISTRY[@]}"; do
        _name="${_entry%%|*}"; _var="${(U)_name//-/_}"
        typeset -g "INSTALL_${_var}=false"
    done
    for _entry in "${DEPLOY_REGISTRY[@]}"; do
        _name="${_entry%%|*}"; _var="${(U)_name//-/_}"
        typeset -g "DEPLOY_${_var}=false"
    done
    INSTALL_PUEUE=false  # explicit for --only validation
    ;;
```

**`server` and `personal` profiles** — keep as explicit overrides (curated lists are clearer for named profiles).

## Adding a New Component (after refactor)

1. Add one line to `INSTALL_REGISTRY` and/or `DEPLOY_REGISTRY` in `config.sh`
2. Add the `if [[ "$INSTALL_NEWCOMP" == "true" ]]` block in `install.sh`/`deploy.sh`
3. Done — TUI, `--flag`, `--no-flag`, `--only` all work automatically

## Edge Cases

- **DEPLOY_ALIASES**: Array, stays manual (line 56), not in registry
- **DEPLOY_APPEND/ASCII_FILE**: Modifiers, stay manual
- **Shared names** (tmux, cleanup, pueue, finicky): Appear in both registries with independent descriptions — correct behavior
- **Platform "all" with runtime guard**: Components like `cleanup` are `platform=all` in registry but have `is_macos` guards in the actual deploy/install code — this is fine, registry controls TUI visibility, actual code controls execution

## Non-interactive htop (already done)

The htop prompt in `deploy.sh` already defaults to skip when `NON_INTERACTIVE=true` or `! [[ -t 0 ]]` (from earlier edit in this session).

## Verification

1. `./install.sh --non-interactive` — runs without prompts, all components applied
2. `./deploy.sh --non-interactive` — runs without prompts, htop skipped
3. `./install.sh` (interactive) — TUI shows pueue on Linux
4. `./deploy.sh --only pueue` — works without hardcoded whitelist
5. `./install.sh --no-pueue` — disables pueue
6. Add a dummy component to registry → verify it appears in TUI and responds to `--only`
