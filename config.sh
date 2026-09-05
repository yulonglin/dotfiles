#!/usr/bin/env zsh
# ═══════════════════════════════════════════════════════════════════════════════
# Dotfiles Configuration
# ═══════════════════════════════════════════════════════════════════════════════
# Single source of truth for all installation and deployment settings.
# Edit this file to customize your setup, then run:
#   ./install.sh                    # Install dependencies
#   ./deploy.sh                     # Deploy configurations
#
# Or override at runtime:
#   ./install.sh --profile=server   # Use server profile
#   ./install.sh --no-ai-tools      # Disable specific component
# ═══════════════════════════════════════════════════════════════════════════════

# ─── Profile ──────────────────────────────────────────────────────────────────
# Pick by what the machine is FOR:
# - standard: default for a bare ./install.sh / ./deploy.sh — shell, editor,
#             git, Claude/Codex, supply-chain defenses. Nothing scheduled.
# - devbox:   a machine you live on (macOS/Linux) — the full set
# - agent:    ephemeral box you DO code on: standard + per-project secrets
# - bare:     ephemeral box you will NOT code on: shell + uv only
# - server:   shared machine — no GUI, no cleanup, no scheduled jobs
# - cloud:    lean remote dev box (RunPod); used by scripts/cloud/setup.sh
# - minimal:  nothing enabled; name what you want explicitly
# - personal: synonym for devbox, kept for existing invocations
#
# The default is `standard`, NOT the full set: a bare invocation on a fresh box
# should not schedule background jobs or touch a laptop's GUI settings. Use
# --devbox (or PROFILE=devbox) for the full set, or persist a picker selection.
PROFILE="${PROFILE:-standard}"

# ─── Component Registry (single source of truth) ────────────────────────────
# Format: "name|description|platform|default"
# - name: CLI flag name (dashes OK, auto-converted to UPPER_SNAKE for variables)
# - description: TUI menu display text
# - platform: all, macos, linux (controls TUI visibility; actual code may have its own guards)
# - default: true/false (initial value, overridden by profiles → config.local.sh → CLI flags)
#
# To add a new component: add one line here, then add the implementation block
# in install.sh/deploy.sh. TUI menu, --flag, --no-flag, --only all work automatically.

INSTALL_REGISTRY=(
    "core|Core packages, CLI tools, gh, uv|all|true|Base"
    "zsh|ZSH + oh-my-zsh + powerlevel10k theme|all|true|Base"
    "tmux|Terminal multiplexer|all|true|Base"
    "ai-tools|Claude Code, Codex CLI, OpenCode, Antigravity CLI|all|true|AI"
    "extras|hyperfine, gitui, code2prompt, ty, terminal-notifier|all|true|Dev Tools"
    "cleanup|Automatic cleanup (macOS only)|all|true|Dev Tools"
    "experimental|zotero MCP|all|true|Dev Tools"
    "macos-settings|macOS system defaults (Dock, Finder, keyboard)|macos|true|macOS"
    "apps|GUI + App Store apps via Brewfile (picker TUI)|macos|true|macOS"
    "docker|Docker engine + compose|linux|true|Linux"
    "pueue|Pueue job scheduler + pueued daemon|linux|true|Linux"
    "create-user|Create non-root dev user|linux|true|Linux"
)

DEPLOY_REGISTRY=(
    "shell|ZSH config, aliases, key bindings|all|true|Shell & Editors"
    "tmux|tmux.conf + TPM plugins|all|true|Shell & Editors"
    "vim|vimrc|all|true|Shell & Editors"
    "editor|VSCode/Cursor settings + extensions (merges)|all|true|Shell & Editors"
    "zed|Zed editor config (symlinked)|all|true|Shell & Editors"
    "ghostty|Ghostty terminal config (symlinked)|all|true|Shell & Editors"
    "htop|htop config with dynamic CPU meters|all|true|Shell & Editors"
    "gitui|gitui theme (theme-reactive, symlinked)|all|true|Shell & Editors"
    "claude|Claude Code config symlink (~/.claude)|all|true|AI & Apps"
    "codex|Codex CLI config symlink (~/.codex)|all|true|AI & Apps"
    "serena|Serena MCP server config (symlinked)|all|false|AI & Apps"
    "git-config|gitconfig, global gitignore, ripgrep config|all|true|Git"
    "git-hooks|Global pre-commit secret detection|all|true|Git"
    "secrets|Sync SSH/git identity via GitHub gist|all|true|Secrets"
    "secrets-env|Decrypt BWS secrets (Bitwarden Secrets Manager)|all|true|Secrets"
    "bws|Bitwarden Secrets Manager CLI|all|true|Secrets"
    "obsidian-sync|Obsidian-headless vault secrets + pull-only-first enforcement|all|true|Secrets"
    "pkg-configs|Package manager security configs (min-release-age)|all|true|Security"
    "dep-audit|Weekly dependency audit (supply chain defense)|all|true|Security"
    "stale-claims|Weekly staleness audit of auto-loaded AI instructions|all|true|Security"
    "cleanup|Auto-cleanup Downloads/Screenshots (macOS)|all|true|Automation"
    "claude-cleanup|Remove idle Claude sessions after 24h|all|true|Automation"
    "ai-update|Daily auto-update: Claude, Codex, OpenCode|all|true|Automation"
    "mcp-sync|Daily shared MCP sync for Claude and Codex|all|true|Automation"
    "dotfiles-sync|Daily commit + rebase + push of this repo so every machine converges|all|true|Automation"
    "usage-ping|Hourly Haiku ping to keep the 5-hour subscription window warm|all|true|Automation"
    "tmux-resume|Hourly auto-resume of rate-limited tmux Claude/Codex sessions|all|true|Automation"
    "hide-idle-apps|Hide, then close, then quit apps left covered up (per app-lifecycle.yaml)|macos|false|Automation"
    "brew-update|Weekly package upgrade + cleanup|all|true|Automation"
    "finicky|Browser routing config (symlinked)|macos|true|macOS"
    "file-apps|Default editor for coding file types|macos|true|macOS"
    "keyboard|Keyboard repeat rate enforcement at login|macos|true|macOS"
    "kill-sky-cua|Kill OpenAI Sky Computer Use helpers (AX-polling lag watchdog)|macos|true|macOS"
    "bedtime|Bedtime timezone enforcement|macos|true|macOS"
    "text-replacements|Sync macOS + Alfred text replacements|macos|true|macOS"
    "mouseless|Keyboard-driven mouse control|macos|true|macOS"
    "alfred|Repair Dropbox-synced Alfred prefs (de-quarantine, +x, hotkey)|macos|true|macOS"
    "bearcli|Symlink Bear CLI to /usr/local/bin (works in cron/scripts)|macos|true|macOS"
    "vpn|NordVPN + Tailscale split tunnel daemon|macos|true|macOS"
    "pueue|Pueue + systemd resource slices|linux|true|Linux"
    "storage|Per-machine data-volume config (config/storage.conf)|linux|true|Linux"
    "matplotlib|Style files: anthropic, deepmind, petri|all|true|Dev Tools"
    "playwright|Playwright + Chromium for the browser tests (~650MB, opt-in)|all|false|Dev Tools"
    "pdb|pdb++ debugger config (high-contrast)|all|true|Dev Tools"
    "claude-tools|Build claude-tools Rust binary|all|true|Build"
)

# Initialize INSTALL_*/DEPLOY_* variables from registry
_init_component_vars() {
    local entry name var_name default rest
    # Format: name|desc|platform|default[|group]
    # Extract the 4th pipe-delimited field for default (strip optional 5th group field)
    for entry in "${INSTALL_REGISTRY[@]}"; do
        name="${entry%%|*}"
        rest="${entry#*|}"    # desc|platform|default[|group]
        rest="${rest#*|}"     # platform|default[|group]
        rest="${rest#*|}"     # default[|group]
        default="${rest%%|*}" # default (stops before optional group)
        var_name="${(U)name//-/_}"
        typeset -g "INSTALL_${var_name}=${default}"
    done
    for entry in "${DEPLOY_REGISTRY[@]}"; do
        name="${entry%%|*}"
        rest="${entry#*|}"
        rest="${rest#*|}"
        rest="${rest#*|}"
        default="${rest%%|*}"
        var_name="${(U)name//-/_}"
        typeset -g "DEPLOY_${var_name}=${default}"
    done
}
_init_component_vars

# ─── Non-Registry Variables ──────────────────────────────────────────────────
DEPLOY_ALIASES=()               # Additional alias scripts: ("inspect") — array, not boolean

# ─── Deploy Modifiers ─────────────────────────────────────────────────────────
DEPLOY_APPEND=false             # Append to existing configs instead of overwrite
DEPLOY_ASCII_FILE="start.txt"   # ASCII art file for shell startup

# ─── Identity & Secrets ───────────────────────────────────────────────────────
# Edit these values for your setup. Everything else should work out of the box.
DOTFILES_USERNAME="${DOTFILES_USERNAME:-yulong}"
DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/yulonglin/dotfiles.git}"
GIT_USER_NAME="yulonglin"
GIT_USER_EMAIL="30549145+yulonglin@users.noreply.github.com"
GIST_SYNC_ID="${GIST_SYNC_ID:-3cc239f160a2fe8c9e6a14829d85a371}"  # Gist used for config sync (SSH, git identity)

# ─── AI Tools Configuration ───────────────────────────────────────────────────
# MCP servers to configure for Claude Code
MCP_SERVERS=(
    "context7:https://mcp.context7.com/mcp"
)

# Local MCP servers built from source (require Go)
# Format: "name:repo:binary_name:env_var_for_token"
MCP_SERVERS_LOCAL=()

# Claude Code plugins and marketplaces are NOT listed here — the single source
# of truth is claude/settings.json (extraKnownMarketplaces + enabledPlugins).
# claude-plugin-reset derives its lists from that file at runtime.

# ─── Core Packages ────────────────────────────────────────────────────────────
# Installed on all platforms
PACKAGES_CORE=(
    "jq"
    "fzf"
    "htop"
    "rsync"
    "shellcheck"  # Shell script linter
    "tldr"        # Simplified man pages
    "mosh"        # resilient SSH over flaky/roaming connections
)

# macOS-specific packages (via Homebrew)
PACKAGES_MACOS=(
    "coreutils"  # GNU utilities on macOS (gdate, gawk, gsed)
    "fzf"
    "bat"
    "eza"
    "zoxide"
    "delta"
    "gitleaks"
    "dust"
    "fd"
    "ripgrep"
    "jless"
    "just"
    "watch"
    "sd"          # sed replacement (preferred over sed)
    "duf"         # df replacement (disk free space)
    "gum"         # interactive shell UI (app-picker TUI)
    "vivid"       # LS_COLORS theme generator (catppuccin-mocha)
    "fpart"       # parallel rsync (fpsync) for fast many-file copies
)

# Linux packages (via Homebrew / Linuxbrew)
# FORMULA names, which differ from the binary for two entries: ripgrep→rg,
# git-delta→delta. Getting these wrong is a silent "no available formula".
PACKAGES_LINUX_BREW=(
    "fzf"
    "bat"
    "eza"
    "fd"
    "ripgrep"     # binary: rg
    "git-delta"   # binary: delta
    "dust"
    "zoxide"
    "jless"
    "just"
    "sd"
    "duf"
    "gum"
    "vivid"
)

# Extra packages (--extras flag)
PACKAGES_EXTRAS_MACOS=(
    "hyperfine"
    "gitui"
    "terminal-notifier"
)

PACKAGES_EXTRAS_LINUX=(
    "hyperfine"
    "gitui"
    "code2prompt"
)

# ═══════════════════════════════════════════════════════════════════════════════
# Profile Presets
# ═══════════════════════════════════════════════════════════════════════════════

# Platform facts that outrank any profile. Called at the END of apply_profile,
# not once at source time: a CLI flag re-applies a profile long after sourcing,
# and a profile that resets to registry defaults would otherwise resurrect
# components this platform cannot run.
# parse_args fills these; declare them here so a platform override consulted
# before parse_args runs does not trip `set -u`.
typeset -ga EXPLICIT_OPT_OUTS EXPLICIT_OPT_INS

# Platform facts outrank the PROFILE, but they do NOT outrank the user, and
# they do not apply to a profile that means "nothing". Both exemptions are
# load-bearing, because this now runs at the END of apply_profile (a CLI flag
# re-runs it long after source time):
#
#   - `minimal` means nothing enabled, and `--only X` is built on it. Setting a
#     component true here made `install.sh --only vim` resolve
#     INSTALL_CREATE_USER=true, which as root runs useradd, grants
#     NOPASSWD:ALL in /etc/sudoers.d and copies /root/.ssh.
#   - an explicit `--no-X` or `--X` on the command line is the user saying it
#     outright, and used to win because overrides ran once at source time,
#     before parse_args.
_platform_override() {
    local var="$1" value="$2" component="${1#INSTALL_}"
    component="${component#DEPLOY_}"
    [[ "${PROFILE:-}" == "minimal" ]] && return 0
    (( ${EXPLICIT_OPT_OUTS[(Ie)$component]} )) && return 0
    (( ${EXPLICIT_OPT_INS[(Ie)$component]} )) && return 0
    typeset -g "$var=$value"
}

_apply_platform_overrides() {
    if is_linux; then
        _platform_override INSTALL_CLEANUP false   # File cleanup uses launchd (macOS only)
        _platform_override DEPLOY_CLEANUP false    # File cleanup uses launchd (macOS only)
        # DEPLOY_CLAUDE_CLEANUP stays true - works with cron on Linux
        _platform_override INSTALL_CREATE_USER true  # Useful for containers
        # INSTALL_DOCKER=true is already default
    elif is_macos; then
        _platform_override INSTALL_DOCKER false    # Use Docker Desktop on macOS
    fi
}

# config.local.sh sits AFTER apply_profile in the documented precedence, so a
# profile flag that re-runs apply_profile has to re-apply it too — otherwise
# resetting the registry silently discards the machine's own opt-outs, and
# `--server` resurrects DEPLOY_OBSIDIAN_SYNC on a box that turned it off.
_apply_local_config() {
    [[ "${DOTFILES_SKIP_LOCAL_CONFIG:-0}" == "1" ]] && return 0
    # `minimal` means nothing enabled, and `--only X` is built on it. A
    # positive override in config.local.sh (DEPLOY_MCP_SYNC=true) would
    # otherwise survive `--minimal` and install the very background jobs the
    # invocation asked to suppress — measured before this guard.
    [[ "${PROFILE:-}" == "minimal" ]] && return 0
    [[ -n "${DOT_DIR:-}" && -f "$DOT_DIR/config.local.sh" ]] || return 0
    source "$DOT_DIR/config.local.sh"
}

apply_profile() {
    local profile="${1:-$PROFILE}"
    PROFILE="$profile"   # keep the banner label in sync with the flags actually applied

    # Profiles delegate: standard -> minimal, agent -> standard, devbox ->
    # personal, cloud -> server. The tail passes below must run ONCE, at the
    # outermost call — otherwise a bare run sources config.local.sh twice
    # (measured), which is harmless for plain assignments but double-appends
    # anything written as `+=(…)`.
    typeset -g _APPLY_PROFILE_DEPTH=$(( ${_APPLY_PROFILE_DEPTH:-0} + 1 ))
    # Unwind the counter on every exit path, including the unknown-profile
    # refusal below, or a later apply_profile would think it is nested.
    _apply_profile_unwind() {
        typeset -g _APPLY_PROFILE_DEPTH=$(( _APPLY_PROFILE_DEPTH - 1 ))
    }

    case "$profile" in
        personal)
            # Everything enabled. _init_component_vars is load-bearing, not
            # decorative: this case used to be EMPTY, assuming the registry
            # defaults were still live. Once `standard` became the source-time
            # default it ran apply_profile minimal first, zeroing every
            # component — so a later `--devbox`/`--personal` on the CLI composed
            # on top of zero and produced 14 components instead of 50. Every
            # profile must therefore establish its own base explicitly rather
            # than inherit whatever the last one left behind.
            _init_component_vars
            ;;
        standard)
            # What a BARE ./install.sh or ./deploy.sh gets: enough to open a
            # shell, edit, commit, and run Claude/Codex on a fresh machine.
            # Deliberately excluded — everything that schedules a background
            # job, needs auth/hardware/apps that do not exist yet, or is
            # specific to one person's laptop. The picker puts any of it one
            # keystroke away, and --devbox restores the full set.
            #
            # git-hooks and pkg-configs are in the base set on purpose: they are
            # the secret-leak and supply-chain defenses, and a default you have
            # to remember to enable is not a defense.
            apply_profile minimal
            PROFILE="standard"
            INSTALL_CORE=true          # modern CLI tools, gh, uv
            INSTALL_ZSH=true
            INSTALL_TMUX=true
            INSTALL_AI_TOOLS=true      # the point of a new machine
            DEPLOY_SHELL=true
            DEPLOY_TMUX=true
            DEPLOY_VIM=true
            DEPLOY_GIT_CONFIG=true
            DEPLOY_GIT_HOOKS=true
            DEPLOY_CLAUDE=true
            DEPLOY_CODEX=true
            DEPLOY_PKG_CONFIGS=true
            DEPLOY_CLAUDE_TOOLS=true
            ;;
        devbox)
            # A machine you live on (macOS or Linux): the full set.
            apply_profile personal
            PROFILE="devbox"
            ;;
        agent)
            # Ephemeral box you DO code on — Claude Code, and the things that
            # make coding there safe rather than merely possible:
            #   tmux        a dropped ssh/mosh must not kill a running agent
            #   git-hooks   secret scan before you commit from a throwaway box
            #   pkg-configs the 7-day quarantine still applies here
            #   bws/direnv  per-project keys, so nothing is globally exported
            # No scheduled jobs, no editors, no GUI, no gist sync.
            apply_profile standard
            PROFILE="agent"
            DEPLOY_SECRETS_ENV=true    # direnv needs keys available to expose
            DEPLOY_BWS=true
            ;;
        bare)
            # Ephemeral box you will NOT code on: a usable shell and uv, so a
            # script or notebook can run. No AI tools, no git identity, nothing
            # scheduled. Fastest install of the lot.
            apply_profile minimal
            PROFILE="bare"
            INSTALL_CORE=true          # uv + modern CLI
            INSTALL_ZSH=true
            DEPLOY_SHELL=true
            ;;
        server)
            # Subtracts from the full set, so it must start from the full set —
            # see the note in `personal)`.
            _init_component_vars
            INSTALL_AI_TOOLS=false
            INSTALL_CLEANUP=false
            INSTALL_DOCKER=false
            INSTALL_EXTRAS=false
            INSTALL_MACOS_SETTINGS=false
            INSTALL_APPS=false
            DEPLOY_EDITOR=false
            DEPLOY_SERENA=false
            DEPLOY_GHOSTTY=false
            DEPLOY_ZED=false
            DEPLOY_HTOP=false
            DEPLOY_GITUI=false
            DEPLOY_PDB=false
            DEPLOY_MATPLOTLIB=false
            DEPLOY_CLEANUP=false
            DEPLOY_CLAUDE_CLEANUP=false
            DEPLOY_AI_UPDATE=false
            DEPLOY_BREW_UPDATE=false
            DEPLOY_KEYBOARD=false
            DEPLOY_BEDTIME=false
            DEPLOY_SECRETS=false
            DEPLOY_SECRETS_ENV=false
            DEPLOY_FINICKY=false
            DEPLOY_BEARCLI=false
            DEPLOY_FILE_APPS=false
            DEPLOY_CLAUDE_TOOLS=false
            ;;
        cloud)
            # Lean remote dev box (RunPod): server minus the heavy compiles/MCP.
            # Keeps core (modern CLI tools, gh, uv), zsh, tmux, git, claude, codex.
            # mosh is installed by scripts/cloud/setup.sh's apt baseline regardless.
            apply_profile server
            PROFILE="cloud"              # restore label (the server recursion above reset it)
            INSTALL_EXPERIMENTAL=false   # zotero MCP — slow
            INSTALL_PUEUE=false          # cargo install pueue pueued — Rust compile
            DEPLOY_PUEUE=false           # systemd resource slices
            DEPLOY_DOTFILES_SYNC=false   # ephemeral box: nothing worth pushing, no SSH deploy key
            ;;
        minimal)
            # Nothing enabled — derived from registry (no manual list to drift)
            local _entry _name _var
            for _entry in "${INSTALL_REGISTRY[@]}"; do
                _name="${_entry%%|*}"; _var="${(U)_name//-/_}"
                typeset -g "INSTALL_${_var}=false"
            done
            for _entry in "${DEPLOY_REGISTRY[@]}"; do
                _name="${_entry%%|*}"; _var="${(U)_name//-/_}"
                typeset -g "DEPLOY_${_var}=false"
            done
            ;;
        *)
            # Fail CLOSED. This used to warn and fall back to `personal`, so a
            # typo like `--profile=servre` silently resolved to the full
            # 50-component devbox install on a machine meant to be a server,
            # with one warning as the only signal. Refuse instead: a
            # misspelled profile must install nothing.
            echo "Error: Unknown profile '$profile'." >&2
            echo "       Valid profiles: bare, standard, agent, devbox, personal, server, cloud, minimal" >&2
            _apply_profile_unwind
            return 2
            ;;
    esac

    # Precedence, restored in full: profile -> config.local.sh -> platform.
    # Both must be re-applied here rather than once at source time, because a
    # CLI flag re-runs this long after sourcing — but only once per invocation,
    # not once per delegation level.
    typeset -g _APPLY_PROFILE_DEPTH=$(( _APPLY_PROFILE_DEPTH - 1 ))
    if (( _APPLY_PROFILE_DEPTH == 0 )); then
        _apply_local_config
        _apply_platform_overrides
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# Platform Detection (set automatically)
# ═══════════════════════════════════════════════════════════════════════════════

detect_platform() {
    case "$(uname -s)" in
        Darwin*) PLATFORM="macos" ;;
        Linux*)  PLATFORM="linux" ;;
        *)       PLATFORM="unknown" ;;
    esac
    export PLATFORM
}

is_macos() { [[ "$PLATFORM" == "macos" ]]; }
is_linux() { [[ "$PLATFORM" == "linux" ]]; }

# ═══════════════════════════════════════════════════════════════════════════════
# Auto-initialization
# ═══════════════════════════════════════════════════════════════════════════════

# Detect platform on source
detect_platform

# Precedence: defaults -> apply_profile() -> config.local.sh -> CLI flags
# (parse_args). DOTFILES_SKIP_LOCAL_CONFIG=1 ignores config.local.sh — tests
# capturing reproducible fixtures must not inherit whatever a particular
# machine has overridden.
#
# Either/or, not both: apply_profile now ends with _apply_local_config and
# _apply_platform_overrides itself (a CLI flag re-runs it long after this
# point). Calling them again here sourced config.local.sh twice on every run,
# which is harmless for plain assignments but double-appends anything using
# `+=(…)`.
if [[ -n "$PROFILE" ]]; then
    apply_profile "$PROFILE"
else
    _apply_local_config
    _apply_platform_overrides
fi
