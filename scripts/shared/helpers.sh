#!/usr/bin/env zsh
# ═══════════════════════════════════════════════════════════════════════════════
# Shared Helper Functions
# ═══════════════════════════════════════════════════════════════════════════════
# Common utilities used by install.sh and deploy.sh
# Source this after config.sh
# ═══════════════════════════════════════════════════════════════════════════════

# Ensure config is loaded
if [[ -z "${PLATFORM:-}" ]]; then
    echo "Error: config.sh must be sourced before helpers.sh" >&2
    exit 1
fi

# ─── Logging ──────────────────────────────────────────────────────────────────

log_info()    { echo "  $*"; }
log_success() { echo "✓ $*"; }
log_warning() { echo "⚠️  $*"; }
log_error()   { echo "✗ $*" >&2; }
log_section() { echo ""; echo "───────── $* ─────────"; }

# ─── Interactive Component Menu ──────────────────────────────────────────────

# Resolve the prebuilt-binary asset name for this platform, or "" if unsupported.
_claude_tools_asset() {
    case "$(uname -s)-$(uname -m)" in
        Darwin-arm64)  echo "claude-tools-darwin-arm64" ;;
        Darwin-x86_64) echo "claude-tools-darwin-x86_64" ;;
        Linux-x86_64)  echo "claude-tools-linux-x86_64" ;;
        Linux-aarch64) echo "claude-tools-linux-aarch64" ;;
        *) echo "" ;;
    esac
}

# Compute the SHA-256 of a file (portable: Linux sha256sum / macOS shasum).
_sha256_of() {
    if cmd_exists sha256sum; then sha256sum "$1" | awk '{print $1}'
    elif cmd_exists shasum; then shasum -a 256 "$1" | awk '{print $1}'
    else return 1; fi
}

# Fetch a prebuilt claude-tools from the rolling "claude-tools-bin" GitHub
# Release and verify it against the SHA-256 committed in the repo (the trust
# anchor — NOT a checksum from the release itself). A tampered/corrupt binary,
# or one we cannot verify, is never moved into place or executed. Returns 1 on
# any failure so the caller can fall back to a source build.
_fetch_claude_tools() {
    cmd_exists curl || return 1

    local asset; asset="$(_claude_tools_asset)"
    [[ -z "$asset" ]] && return 1  # unsupported platform
    local bin="${DOT_DIR}/custom_bins/${asset}"

    # Trust anchor: checksum committed in the repo you cloned.
    local sums_file="${DOT_DIR}/tools/claude-tools/SHA256SUMS"
    local expected
    expected="$(awk -v a="$asset" '$2 == a {print $1}' "$sums_file" 2>/dev/null)"
    # Refuse to fetch if we have no committed checksum to verify against.
    [[ -z "$expected" ]] && return 1

    # Derive owner/repo slug from DOTFILES_REPO (config.sh), override via env.
    local slug="${DOTFILES_GH_SLUG:-}"
    if [[ -z "$slug" ]]; then
        slug="${DOTFILES_REPO#https://github.com/}"
        slug="${slug%.git}"
    fi
    [[ -z "$slug" ]] && return 1

    local url="https://github.com/${slug}/releases/download/claude-tools-bin/${asset}"
    log_info "Fetching prebuilt claude-tools (${asset})..."
    mkdir -p "${DOT_DIR}/custom_bins"
    local tmp="${bin}.tmp.$$"

    # HTTPS + TLS 1.2 only; never pipe-to-shell — download to temp, then verify.
    if ! curl --proto '=https' --tlsv1.2 -fsSL "$url" -o "$tmp" 2>/dev/null; then
        rm -f "$tmp"; return 1
    fi

    local actual; actual="$(_sha256_of "$tmp")"
    if [[ -z "$actual" || "$actual" != "$expected" ]]; then
        log_warning "claude-tools checksum mismatch — discarding download (expected ${expected:0:12}…, got ${actual:0:12}…)"
        rm -f "$tmp"; return 1
    fi

    chmod +x "$tmp"
    if ! "$tmp" --version >/dev/null 2>&1; then
        rm -f "$tmp"; return 1
    fi
    mv "$tmp" "$bin"
    return 0
}

# Last-resort fallback: build claude-tools from source (needs cargo). Quiet,
# synchronous; only attempted when the verified fetch path is unavailable.
_build_claude_tools_from_source() {
    cmd_exists cargo || return 1
    [[ -f "${DOT_DIR}/tools/claude-tools/Cargo.toml" ]] || return 1
    log_info "Building claude-tools from source (fallback)..."
    ( cd "${DOT_DIR}/tools/claude-tools" && cargo build --release --quiet ) || return 1
    local asset; asset="$(_claude_tools_asset)"
    [[ -z "$asset" ]] && return 1
    mkdir -p "${DOT_DIR}/custom_bins"
    cp "${DOT_DIR}/tools/claude-tools/target/release/claude-tools" "${DOT_DIR}/custom_bins/${asset}" \
        && chmod +x "${DOT_DIR}/custom_bins/${asset}"
}

# Bootstrap claude-tools so the component-selection TUI works on a fresh machine
# before deploy.sh's from-source build runs. Fallback chain:
#   1. working native binary already present  → use it
#   2. verified prebuilt fetch from Releases   → use it
#   3. source build (if cargo present)         → use it
#   4. otherwise                               → return 1 (menu uses defaults)
# Set CLAUDE_TOOLS_NO_FETCH=1 to skip the network fetch (air-gapped / paranoid).
bootstrap_claude_tools() {
    local wrapper="${DOT_DIR}/custom_bins/claude-tools"

    # 1) Wrapper exists and the platform binary it delegates to runs? Nothing to do.
    [[ -x "$wrapper" ]] && "$wrapper" --version >/dev/null 2>&1 && return 0

    # Skip in non-interactive runs — the menu won't show anyway. deploy.sh's
    # own (backgrounded) build still produces the runtime binary either way.
    [[ "${NON_INTERACTIVE:-false}" == "true" ]] && return 1

    # 2) Verified prebuilt fetch (downloads to custom_bins/claude-tools-{platform}).
    if [[ "${CLAUDE_TOOLS_NO_FETCH:-0}" != "1" ]]; then
        _fetch_claude_tools && return 0
    fi

    # 3) Source build fallback (builds to custom_bins/claude-tools-{platform}).
    _build_claude_tools_from_source && "$wrapper" --version >/dev/null 2>&1 && return 0

    # 4) Give up — caller falls back to defaults (no menu).
    return 1
}

# Usage: show_component_menu install|deploy
# Requires: claude-tools (graceful fallback to defaults if unavailable).
# CI publishes prebuilt binaries; bootstrap_claude_tools fetches the right one.
#
# Flat toggle list by design — j/k navigate, space toggles a whole component,
# enter confirms. Group labels (Base/AI/...) are headers only; there is no
# drill-in / sub-component selection. The sole exception is `apps`: leaving it
# checked later opens app-picker (gum) to choose individual GUI/App-Store apps.
show_component_menu() {
    local mode="$1"

    # Skip if non-interactive, no TTY, binary missing, or binary won't run on
    # this platform (wrong-arch leftover → --version fails cleanly, no noise).
    if [[ "${NON_INTERACTIVE:-false}" == "true" ]] || ! [[ -t 0 ]] \
        || ! cmd_exists claude-tools || ! claude-tools --version >/dev/null 2>&1; then
        return 0
    fi

    local registry_name prefix
    if [[ "$mode" == "install" ]]; then
        registry_name="INSTALL_REGISTRY"
        prefix="INSTALL"
    elif [[ "$mode" == "deploy" ]]; then
        registry_name="DEPLOY_REGISTRY"
        prefix="DEPLOY"
    fi

    # Build input for claude-tools select: group|name|description|checked
    # Format: name|desc|platform|default[|group]
    typeset -a all_names
    local stdin_input=""
    local entry name rest desc platform default group var_name current_val
    for entry in "${(@P)registry_name}"; do
        name="${entry%%|*}"
        rest="${entry#*|}"
        desc="${rest%%|*}"
        rest="${rest#*|}"
        platform="${rest%%|*}"
        rest="${rest#*|}"
        default="${rest%%|*}"
        rest="${rest#*|}"
        group="${rest:-Uncategorized}"
        # If no 5th field, rest equals default (no pipe was consumed), treat as Uncategorized
        [[ "$group" == "$default" ]] && group="Uncategorized"

        # Platform filter
        if [[ "$platform" == "macos" ]] && ! is_macos; then continue; fi
        if [[ "$platform" == "linux" ]] && ! is_linux; then continue; fi

        var_name="${prefix}_${(U)name//-/_}"
        current_val="${(P)var_name:-$default}"
        all_names+=("$name")
        stdin_input+="${group}|${name}|${desc}|${current_val}"$'\n'
    done

    # Run TUI; on cancel (exit 1) keep current values.
    #
    # Pass options via a temp file, NOT a stdin pipe: piping makes fd 0 a pipe,
    # which forces crossterm onto a fragile /dev/tty fallback for keyboard input
    # that fails on some terminals ("Failed to initialize input reader") and
    # silently drops the menu. Keeping stdin on the terminal is the reliable path.
    local items_file result
    items_file=$(mktemp "${TMPDIR:-/tmp}/claude-tools-select.XXXXXX")
    printf '%s' "$stdin_input" > "$items_file"
    result=$(claude-tools select --title "Select ${mode} components" --items "$items_file")
    local rc=$?
    rm -f "$items_file"
    [[ $rc -ne 0 ]] && return 0

    # Disable all filtered components, then re-enable selected ones
    for name in "${all_names[@]}"; do
        local var_name="${(U)name//-/_}"
        if [[ "$mode" == "install" ]]; then
            typeset -g "INSTALL_${var_name}=false"
        else
            typeset -g "DEPLOY_${var_name}=false"
        fi
    done

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local var_name="${(U)line//-/_}"
        if [[ "$mode" == "install" ]]; then
            typeset -g "INSTALL_${var_name}=true"
        else
            typeset -g "DEPLOY_${var_name}=true"
        fi
    done <<< "$result"
}

# ─── Command Checking ─────────────────────────────────────────────────────────

# Check if command exists
cmd_exists() {
    command -v "$1" &>/dev/null
}

# True when interactive prompts that fire AFTER the component menu should be
# skipped in favor of safe defaults: --non-interactive, --unattended/--yes, or
# no TTY on stdin. The component menu itself is gated separately (only on
# NON_INTERACTIVE) so --unattended keeps it as the one interactive step.
prompts_disabled() {
    [[ "${NON_INTERACTIVE:-false}" == "true" ]] && return 0
    [[ "${ASSUME_DEFAULTS:-false}" == "true" ]] && return 0
    [[ -t 0 ]] || return 0
    return 1
}

# Cache sudo credentials once, up front, so privileged steps later in the run
# don't block on a password prompt mid-install. A background keepalive refreshes
# the timestamp until the calling script exits. No-op if sudo is already cached,
# unavailable, or we're non-interactive (nothing to prompt).
front_load_sudo() {
    cmd_exists sudo || return 0
    [[ -t 0 ]] || return 0
    sudo -n true 2>/dev/null && return 0   # already cached — no prompt needed
    prompts_disabled && return 0            # don't prompt in unattended mode
    log_info "Some steps need administrator access — caching sudo credentials up front."
    sudo -v || return 0
    # Refresh until the parent script exits (canonical installer pattern).
    ( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &>/dev/null &
}

# Check if command is installed, print version if so
# Usage: is_installed <cmd> [version_flag]
# Returns 0 if installed, 1 if not
is_installed() {
    local cmd="$1"
    local version_flag="${2:---version}"

    if [[ "${FORCE_REINSTALL:-false}" == "true" ]]; then
        return 1
    fi

    if cmd_exists "$cmd"; then
        local version
        version=$("$cmd" $version_flag 2>/dev/null | head -1 || echo "")
        if [[ -n "$version" ]]; then
            log_info "$cmd already installed ($version)"
        else
            log_info "$cmd already installed"
        fi
        return 0
    fi
    return 1
}

# Check if brew cask is installed (macOS)
is_cask_installed() {
    local cask="$1"
    if [[ "${FORCE_REINSTALL:-false}" == "true" ]]; then
        return 1
    fi
    cmd_exists brew && brew list --cask "$cask" &>/dev/null
}

# ─── File Operations ──────────────────────────────────────────────────────────

# Backup a file with timestamp
# Usage: backup_file <path>
backup_file() {
    local filepath="$1"
    if [[ -e "$filepath" && ! -L "$filepath" ]]; then
        local backup="${filepath}.backup.$(date -u +%d-%m-%Y_%H-%M-%S)"
        mv "$filepath" "$backup"
        log_info "Backed up to $backup"
        echo "$backup"  # Return backup path
    fi
}

# Create symlink, backing up existing file if needed
# Usage: safe_symlink <source> <target>
safe_symlink() {
    local source="$1"
    local target="$2"

    if [[ ! -e "$source" ]]; then
        log_error "Source does not exist: $source"
        return 1
    fi

    # Remove existing symlink
    if [[ -L "$target" ]]; then
        rm "$target"
    # Backup existing file/directory
    elif [[ -e "$target" ]]; then
        backup_file "$target"
    fi

    # Create parent directory if needed
    mkdir -p "$(dirname "$target")"

    ln -sf "$source" "$target"
    log_success "Symlinked $source → $target"
}

# Get file modification time (cross-platform)
get_mtime() {
    local file="$1"
    if is_macos; then
        stat -f %m "$file" 2>/dev/null || echo "0"
    else
        stat -c %Y "$file" 2>/dev/null || echo "0"
    fi
}

# ─── Package Installation ─────────────────────────────────────────────────────

# Environment that makes every `brew` call non-interactive and quiet.
# HOMEBREW_ASK= overrides a user-exported HOMEBREW_ASK=1 (Homebrew treats any
# non-empty value as "ask before installing dependencies" → the `[y/n]` prompt).
# </dev/null is belt-and-suspenders so no prompt can ever block the install.
BREW_NONINTERACTIVE_ENV=(
    HOMEBREW_ASK=
    HOMEBREW_NO_AUTO_UPDATE=1
    HOMEBREW_NO_ENV_HINTS=1
    HOMEBREW_NO_INSTALL_CLEANUP=1
)

# Install package via Homebrew (macOS)
brew_install() {
    local pkg="$1"
    local cask="${2:-false}"

    if ! cmd_exists brew; then
        log_error "Homebrew not installed"
        return 1
    fi

    if [[ "$cask" == "true" ]]; then
        if ! is_cask_installed "$pkg"; then
            env "${BREW_NONINTERACTIVE_ENV[@]}" brew install --quiet --cask "$pkg" </dev/null 2>/dev/null \
                || log_warning "$pkg installation failed"
        fi
    else
        env "${BREW_NONINTERACTIVE_ENV[@]}" brew install --quiet "$pkg" </dev/null 2>/dev/null \
            || log_warning "$pkg installation failed"
    fi
}

# Check if apt package is installed
apt_is_installed() {
    dpkg -s "$1" &>/dev/null
}

# Install package via apt (Linux)
apt_install() {
    local pkg="$1"
    if apt_is_installed "$pkg"; then
        return 0
    fi
    sudo apt install -y "$pkg" 2>/dev/null || log_warning "$pkg installation via apt failed"
}

# Install package via mise (Linux)
mise_install() {
    local pkg="$1"
    if ! cmd_exists mise; then
        log_warning "mise not available for $pkg"
        return 1
    fi
    if mise where "$pkg" &>/dev/null; then
        return 0
    fi
    mise use -g "$pkg" || log_warning "$pkg installation via mise failed"
}

# Install multiple packages
# Usage: install_packages <manager> <pkg1> <pkg2> ...
# For apt: filters already-installed packages, installs remaining in one call
install_packages() {
    local manager="$1"
    shift

    if [[ "$manager" == "apt" ]]; then
        local missing=()
        for pkg in "$@"; do
            if ! apt_is_installed "$pkg"; then
                missing+=("$pkg")
            fi
        done
        if (( ${#missing[@]} == 0 )); then
            log_info "All packages already installed"
            return 0
        fi
        log_info "Installing ${#missing[@]} missing package(s): ${missing[*]}"
        sudo apt install -y "${missing[@]}" 2>/dev/null || log_warning "Some apt packages failed to install"
        return
    fi

    for pkg in "$@"; do
        case "$manager" in
            brew) brew_install "$pkg" ;;
            mise) mise_install "$pkg" ;;
        esac
    done
}

# ─── Parallelizable Install Functions ────────────────────────────────────────

install_gitleaks() {
    if is_installed gitleaks; then return 0; fi
    log_info "Installing gitleaks..."
    if is_macos; then
        brew_install gitleaks
    else
        local version arch tmpd
        version=$(curl -s https://api.github.com/repos/gitleaks/gitleaks/releases/latest | grep -o '"tag_name": "v[^"]*' | cut -d'v' -f2 || echo "8.24.3")
        case "$(uname -m)" in
            x86_64)  arch="x64" ;;
            aarch64) arch="arm64" ;;
            *)       log_warning "Unsupported architecture for gitleaks"; return 1 ;;
        esac
        tmpd=$(mktemp -d)
        mkdir -p "$HOME/.local/bin"
        curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${version}/gitleaks_${version}_linux_${arch}.tar.gz" -o "$tmpd/gitleaks.tar.gz" && \
        tar -xzf "$tmpd/gitleaks.tar.gz" -C "$tmpd" && \
        mv "$tmpd/gitleaks" "$HOME/.local/bin/" && \
        log_success "gitleaks $version installed" || { log_warning "gitleaks installation failed"; rm -rf "$tmpd"; return 1; }
        rm -rf "$tmpd"
    fi
}

install_sops() {
    if is_installed sops; then return 0; fi
    log_info "Installing sops..."
    if is_macos; then
        brew_install sops
    else
        local sops_ver sops_arch
        sops_ver=$(curl -s https://api.github.com/repos/getsops/sops/releases/latest | grep -o '"tag_name": "v[^"]*' | cut -d'v' -f2)
        sops_ver="${sops_ver:-3.9.4}"
        case "$(uname -m)" in
            x86_64)  sops_arch="amd64" ;;
            aarch64) sops_arch="arm64" ;;
            *)       log_warning "Unsupported architecture for sops"; return 1 ;;
        esac
        mkdir -p "$HOME/.local/bin"
        curl -fsSL "https://github.com/getsops/sops/releases/download/v${sops_ver}/sops-v${sops_ver}.linux.${sops_arch}" -o "$HOME/.local/bin/sops" && \
            chmod +x "$HOME/.local/bin/sops" && \
            log_success "sops $sops_ver installed" || { log_warning "sops installation failed"; return 1; }
    fi
}

install_age() {
    if is_installed age; then return 0; fi
    log_info "Installing age..."
    if is_macos; then
        brew_install age
    else
        local age_ver age_arch tmpd
        age_ver=$(curl -s https://api.github.com/repos/FiloSottile/age/releases/latest | grep -o '"tag_name": "v[^"]*' | cut -d'v' -f2)
        age_ver="${age_ver:-1.2.1}"
        case "$(uname -m)" in
            x86_64)  age_arch="amd64" ;;
            aarch64) age_arch="arm64" ;;
            *)       log_warning "Unsupported architecture for age"; return 1 ;;
        esac
        tmpd=$(mktemp -d)
        mkdir -p "$HOME/.local/bin"
        curl -fsSL "https://github.com/FiloSottile/age/releases/download/v${age_ver}/age-v${age_ver}-linux-${age_arch}.tar.gz" -o "$tmpd/age.tar.gz" && \
            tar -xzf "$tmpd/age.tar.gz" -C "$tmpd" && \
            mv "$tmpd/age/age" "$tmpd/age/age-keygen" "$HOME/.local/bin/" && \
            log_success "age $age_ver installed" || { log_warning "age installation failed"; rm -rf "$tmpd"; return 1; }
        rm -rf "$tmpd"
    fi
}

install_direnv() {
    if is_installed direnv; then return 0; fi
    log_info "Installing direnv..."
    if is_macos; then
        brew_install direnv
    else
        curl -sfL https://direnv.net/install.sh | bash 2>/dev/null || { log_warning "direnv installation failed"; return 1; }
    fi
}

# Rust toolchain (cargo) via rustup. macOS: official Homebrew formula (sha-pinned,
# reviewed) provides `rustup-init`; run it non-interactively. Linux: keep the upstream
# rustup installer but pin TLS (--proto '=https' --tlsv1.2) — no brew dependency.
# See claude/rules/supply-chain-security.md § curl|bash Installers.
install_rust_toolchain() {
    if is_installed cargo; then
        source "$HOME/.cargo/env" 2>/dev/null || true
        return 0
    fi
    log_info "Installing Rust toolchain (user-level, no root needed)..."
    if is_macos && cmd_exists brew; then
        # Official formula ships `rustup-init`; install the default stable toolchain.
        brew_install rustup
        if cmd_exists rustup-init; then
            rustup-init -y --quiet 2>/dev/null || log_warning "rustup-init failed"
        elif cmd_exists rustup; then
            rustup default stable 2>/dev/null || log_warning "rustup default stable failed"
        fi
    else
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --quiet
    fi
    source "$HOME/.cargo/env" 2>/dev/null || true
}

install_bws() {
    if is_installed bws; then return 0; fi
    log_info "Installing bws (Bitwarden Secrets Manager CLI)..."
    local bws_version="2.0.0" tmpd url
    tmpd=$(mktemp -d)
    mkdir -p "$HOME/.local/bin"
    if [[ "$(uname -s)" == "Darwin" ]]; then
        url="https://github.com/bitwarden/sdk-sm/releases/download/bws-v${bws_version}/bws-macos-universal-${bws_version}.zip"
    else
        local arch
        case "$(uname -m)" in
            x86_64)  arch="x86_64" ;;
            aarch64|arm64) arch="aarch64" ;;
            *)       log_warning "Unsupported architecture for bws"; rm -rf "$tmpd"; return 1 ;;
        esac
        url="https://github.com/bitwarden/sdk-sm/releases/download/bws-v${bws_version}/bws-${arch}-unknown-linux-gnu-${bws_version}.zip"
    fi
    if curl -fsSL "$url" -o "$tmpd/bws.zip" && \
       unzip -o "$tmpd/bws.zip" -d "$HOME/.local/bin/" && \
       chmod +x "$HOME/.local/bin/bws"; then
        log_success "bws installed"
    else
        log_warning "bws installation failed"
        rm -rf "$tmpd"
        return 1
    fi
    rm -rf "$tmpd"
}

install_claude_code() {
    if is_installed claude; then return 0; fi
    log_info "Installing Claude Code..."
    curl -fsSL https://claude.ai/install.sh | bash || { log_warning "Claude Code installation failed"; return 1; }
    # Alpine Linux dependencies
    if is_linux && cmd_exists apk; then
        apk add libgcc libstdc++ ripgrep 2>/dev/null || true
        export USE_BUILTIN_RIPGREP=0
    fi
    # Linux sandbox dependencies (bubblewrap + socat installed via apt in install.sh)
    if is_linux; then
        if cmd_exists bun; then
            bun add -g @anthropic-ai/sandbox-runtime &>/dev/null || log_warning "sandbox-runtime install failed"
        elif cmd_exists npm; then
            npm install -g @anthropic-ai/sandbox-runtime &>/dev/null || log_warning "sandbox-runtime install failed"
        else
            log_warning "No npm/bun — skipping sandbox-runtime (install manually)"
        fi
    fi
}

install_opencode() {
    if is_installed opencode; then return 0; fi
    log_info "Installing OpenCode..."
    # Official CORE Homebrew formula (NOT the anomalyco/tap) — see supply-chain-security.md
    if is_macos; then
        brew_install opencode
    elif cmd_exists bun; then
        bun add -g opencode-ai &>/dev/null || { log_warning "OpenCode failed"; return 1; }
    else
        log_warning "bun is required to install OpenCode on Linux; skipping"
        return 1
    fi
}

# Antigravity CLI (binary: `agy`) — Google's OFFICIAL successor to Gemini CLI
# (Gemini CLI consumer access ends 2026-06-18). Official cask, no third-party tap.
install_antigravity_cli() {
    if is_installed agy --version; then return 0; fi
    log_info "Installing Antigravity CLI (agy)..."
    if is_macos; then
        brew_install antigravity-cli true   # official cask
    else
        # Linux: Google ships a curl installer, but per supply-chain-security.md we
        # do NOT blind-pipe an unverified URL. Install manually on Linux.
        log_warning "Antigravity CLI on Linux: install manually — https://antigravity.google/docs/cli-features (skipping)"
        return 1
    fi
}

install_codex_cli() {
    if is_installed codex; then return 0; fi
    log_info "Installing Codex CLI..."
    if is_macos; then
        brew_install codex
    elif cmd_exists bun; then
        bun add -g @openai/codex &>/dev/null || { log_warning "Codex CLI failed"; return 1; }
    else
        log_warning "bun is required to install Codex CLI on Linux; skipping"
        return 1
    fi
}

# ─── Parallel Execution ──────────────────────────────────────────────────────

# Run multiple commands in parallel with grouped log replay.
# Usage: run_parallel "group label" "job_name|command_or_function" ...
# - Each job runs in a subshell with set +e, stdout+stderr captured to a temp log
# - Exit code captured via trap (always written, even on early exit)
# - After all jobs finish: replay each job's log grouped under its name
# - Print summary with pass/fail counts and list of failures
# - Sets PARALLEL_FAILURES array in caller's scope
# - Always returns 0 (continue-on-failure)
run_parallel() {
    local group_label="$1"
    shift

    local tmpdir
    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/parallel_run.XXXXXX")

    typeset -A pids
    local job_names=()

    log_info "$group_label..."

    for entry in "$@"; do
        local name="${entry%%|*}"
        local cmd="${entry#*|}"
        job_names+=("$name")

        (
            set +e
            trap 'echo $? > "'"$tmpdir/$name"'.exitcode"' EXIT
            eval "$cmd"
        ) &>"$tmpdir/$name.log" &
        pids[$name]=$!
    done

    # Wait for all jobs
    for name in "${job_names[@]}"; do
        wait ${pids[$name]} 2>/dev/null || true
    done

    # Replay logs and collect results
    local passed=0 failed=0
    PARALLEL_FAILURES=()

    for name in "${job_names[@]}"; do
        local rc=0
        [[ -f "$tmpdir/$name.exitcode" ]] && rc=$(<"$tmpdir/$name.exitcode")

        if [[ "$rc" -eq 0 ]]; then
            echo "  ── $name ──"
            (( ++passed ))
        else
            echo "  ── $name (FAILED) ──"
            PARALLEL_FAILURES+=("$name")
            (( ++failed ))
        fi
        cat "$tmpdir/$name.log" 2>/dev/null
    done

    # Summary
    if [[ $failed -gt 0 ]]; then
        log_warning "$group_label: $passed passed, $failed failed: ${PARALLEL_FAILURES[*]}"
    else
        log_success "$group_label: $passed/$passed completed"
    fi

    # Cleanup
    rm -rf "$tmpdir"
    return 0
}

# ─── ZSH Setup ────────────────────────────────────────────────────────────────

# Set ZSH as default shell if possible
set_zsh_default() {
    [[ "$SHELL" == *"zsh"* ]] && return 0

    local zsh_path
    zsh_path=$(which zsh 2>/dev/null)

    if [[ -x "$zsh_path" ]] && sudo -n true 2>/dev/null; then
        log_info "Setting ZSH as default shell..."
        grep -qxF "$zsh_path" /etc/shells 2>/dev/null || \
            echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
        chsh -s "$zsh_path"
        log_success "Default shell changed to ZSH"
    fi
}

# Clone a ZSH plugin
clone_zsh_plugin() {
    local repo="$1"
    local name="${2:-$(basename "$repo" .git)}"
    local target="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/$name"

    if [[ -d "$target" ]]; then
        log_info "$name already installed"
        return 0
    fi

    git clone --quiet "$repo" "$target" 2>/dev/null || log_warning "$name clone failed"
}

# Install oh-my-zsh and plugins
install_ohmyzsh() {
    local zsh_dir="$HOME/.oh-my-zsh"
    local zsh_custom="$zsh_dir/custom"

    if [[ -d "$zsh_dir" && "${FORCE_REINSTALL:-false}" != "true" ]]; then
        log_info "oh-my-zsh already installed (use FORCE_REINSTALL=true to reinstall)"
        return 0
    fi

    log_info "Installing oh-my-zsh..."
    rm -rf "$zsh_dir"
    # Unset ZSH so the official installer doesn't refuse when $ZSH points elsewhere
    # (e.g., RunPod containers where /root/.oh-my-zsh exists but HOME=/workspace)
    ZSH="$zsh_dir" sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

    log_info "Installing powerlevel10k theme..."
    git clone --quiet https://github.com/romkatv/powerlevel10k.git \
        "${zsh_custom}/themes/powerlevel10k" 2>/dev/null || log_warning "powerlevel10k failed"

    log_info "Installing zsh plugins..."
    clone_zsh_plugin "https://github.com/zsh-users/zsh-syntax-highlighting.git"
    clone_zsh_plugin "https://github.com/zsh-users/zsh-autosuggestions"
    clone_zsh_plugin "https://github.com/zsh-users/zsh-completions"
    clone_zsh_plugin "https://github.com/zsh-users/zsh-history-substring-search"
    clone_zsh_plugin "https://github.com/jirutka/zsh-shift-select.git" "zsh-shift-select"

    if [[ ! -d "$HOME/.tmux-themepack" ]]; then
        log_info "Installing tmux theme pack..."
        git clone --quiet https://github.com/jimeh/tmux-themepack.git "$HOME/.tmux-themepack" 2>/dev/null || log_warning "tmux-themepack clone failed"
    else
        log_info "tmux-themepack already installed"
    fi

    log_success "oh-my-zsh installation complete"
}

# ─── TPM (Tmux Plugin Manager) ───────────────────────────────────────────────

install_tpm() {
    local tpm_dir="$HOME/.tmux/plugins/tpm"
    if [[ -d "$tpm_dir" ]]; then
        log_info "TPM already installed"
        return 0
    fi
    log_info "Installing TPM (Tmux Plugin Manager)..."
    mkdir -p "$HOME/.tmux/plugins"
    git clone --quiet https://github.com/tmux-plugins/tpm "$tpm_dir" 2>/dev/null || {
        log_warning "TPM clone failed (no network?) — tmux will work without plugins"
        return 0
    }
    log_success "TPM installed"
}

# ─── GitHub CLI ───────────────────────────────────────────────────────────────

# Install and authenticate GitHub CLI
install_gh_cli() {
    if is_installed gh; then
        # Check authentication
        if gh auth status &>/dev/null; then
            log_info "gh already authenticated"
            return 0
        fi
    else
        log_info "Installing GitHub CLI..."
        if is_macos; then
            brew_install gh
        else
            apt_install gh || install_gh_from_release
        fi
    fi

    # Authenticate if not already
    if cmd_exists gh && ! gh auth status &>/dev/null; then
        if prompts_disabled; then
            log_warning "gh not authenticated — run 'gh auth login' later (needed for gist/secrets sync)"
        else
            echo ""
            echo "GitHub CLI needs authentication for secrets sync."
            echo "This will open a browser for OAuth login (no tokens needed)."
            echo ""
            gh auth login --web --git-protocol https || log_warning "gh auth failed - run 'gh auth login' manually"
        fi
    fi

    # Prefer SSH for git operations via gh
    if cmd_exists gh; then
        gh config set git_protocol ssh
    fi
}

# Fallback: Install gh from GitHub releases
install_gh_from_release() {
    log_info "Installing gh from GitHub releases..."
    local version arch

    version=$(curl -s https://api.github.com/repos/cli/cli/releases/latest | grep -o '"tag_name": "v[^"]*' | cut -d'v' -f2 || echo "2.62.0")

    case "$(uname -m)" in
        x86_64)  arch="amd64" ;;
        aarch64) arch="arm64" ;;
        *)       log_warning "Unsupported architecture for gh"; return 1 ;;
    esac

    mkdir -p "$HOME/.local/bin"
    curl -sSL "https://github.com/cli/cli/releases/download/v${version}/gh_${version}_linux_${arch}.tar.gz" -o /tmp/gh.tar.gz && \
    tar -xzf /tmp/gh.tar.gz -C /tmp && \
    mv "/tmp/gh_${version}_linux_${arch}/bin/gh" "$HOME/.local/bin/" && \
    rm -rf /tmp/gh.tar.gz "/tmp/gh_${version}_linux_${arch}"
}

# ─── Mise (Universal Version Manager) ─────────────────────────────────────────

install_mise() {
    if is_installed mise; then
        return 0
    fi

    log_info "Installing mise..."
    mkdir -p "$HOME/.local/bin"
    curl https://mise.run | sh
    export PATH="$HOME/.local/bin:$PATH"

    if cmd_exists mise; then
        eval "$(mise activate bash)"
        return 0
    fi

    log_warning "mise installation failed"
    return 1
}

# ─── User Management (Linux) ──────────────────────────────────────────────────

# Create non-root development user
create_dev_user() {
    if [[ $EUID -ne 0 ]]; then
        log_info "Skipping --create-user: not running as root"
        return 0
    fi

    local username="${DEV_USERNAME:-${DOTFILES_USERNAME:-$GIT_USER_NAME}}"
    username="${username:-yulong}"

    if id "$username" &>/dev/null; then
        log_info "User $username already exists"
        return 0
    fi

    log_info "Creating user: $username"
    local shell
    shell=$(command -v zsh || command -v bash)
    useradd -m -s "$shell" "$username"

    # Add to sudo group
    if getent group sudo &>/dev/null; then
        usermod -aG sudo "$username"
    elif getent group wheel &>/dev/null; then
        usermod -aG wheel "$username"
    fi

    # Enable passwordless sudo
    echo "$username ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$username"

    # Copy SSH keys if present
    if [[ -d /root/.ssh ]]; then
        cp -r /root/.ssh "/home/$username/"
        chown -R "$username:$username" "/home/$username/.ssh"
    fi

    log_success "User $username created. Switch with: su - $username"
}

# ─── Docker Installation (Linux) ─────────────────────────────────────────────

install_docker() {
    local docker_just_installed=false

    if ! is_installed docker; then
        docker_just_installed=true
        log_section "INSTALLING DOCKER 🐳"

        # Install prerequisites
        apt-get install -y ca-certificates curl gnupg 2>/dev/null || {
            log_warning "Could not install Docker prerequisites"
            return 1
        }

        # Add Docker's official GPG key
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null || {
            # Try Debian if Ubuntu fails
            curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null || {
                log_warning "Could not add Docker GPG key"
                return 1
            }
        }
        chmod a+r /etc/apt/keyrings/docker.gpg

        # Detect distro and add repository
        local distro version_codename
        if [[ -f /etc/os-release ]]; then
            # shellcheck source=/dev/null
            source /etc/os-release
            distro="${ID:-ubuntu}"
            version_codename="${VERSION_CODENAME:-$(lsb_release -cs 2>/dev/null || echo 'jammy')}"
        else
            distro="ubuntu"
            version_codename="jammy"
        fi

        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${distro} ${version_codename} stable" | \
            tee /etc/apt/sources.list.d/docker.list > /dev/null

        # Install Docker
        apt-get update -y 2>/dev/null
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || {
            log_warning "Docker installation failed"
            return 1
        }

        log_success "Docker installed successfully"
    fi

    # Add current user to docker group (avoids needing sudo)
    # This runs even if Docker was already installed, in case user wasn't added to group
    local current_user="${SUDO_USER:-$USER}"
    if [[ -n "$current_user" ]] && [[ "$current_user" != "root" ]]; then
        if ! groups "$current_user" 2>/dev/null | grep -q '\bdocker\b'; then
            usermod -aG docker "$current_user" 2>/dev/null || true
            log_success "Added $current_user to docker group"
            echo ""
            echo "  ⚠️  IMPORTANT: To use Docker without sudo, either:"
            echo "      • Log out and back in, OR"
            echo "      • Run: newgrp docker"
            echo ""
        fi
    fi

    if [[ "$docker_just_installed" == "true" ]]; then
        echo "  Start Docker daemon: sudo systemctl start docker"
        echo "  Verify installation:  docker run hello-world"
        echo ""
    fi
}

# ─── Secrets Sync ─────────────────────────────────────────────────────────────

# Ensure local public key is in authorized_keys (auto-add for convenience)
ensure_local_key_in_authorized_keys() {
    local auth_keys="$HOME/.ssh/authorized_keys"
    local pub_key=""
    local pub_key_file=""

    # Find first available public key
    for key_type in ed25519 ecdsa rsa; do
        if [[ -f "$HOME/.ssh/id_${key_type}.pub" ]]; then
            pub_key_file="$HOME/.ssh/id_${key_type}.pub"
            pub_key=$(cat "$pub_key_file")
            break
        fi
    done

    if [[ -z "$pub_key" ]]; then
        log_info "No local public key found - skipping auto-add"
        return 0
    fi

    # Extract just the key part (without comment) for comparison
    local key_data
    key_data=$(echo "$pub_key" | awk '{print $1" "$2}')

    mkdir -p "$HOME/.ssh"
    if [[ ! -f "$auth_keys" ]]; then
        touch "$auth_keys"
        chmod 600 "$auth_keys"
    fi

    # Check if key already present
    if grep -qF "$key_data" "$auth_keys" 2>/dev/null; then
        return 0
    fi

    # Add key with hostname comment
    local hostname
    hostname=$(hostname -s 2>/dev/null || echo "unknown")
    local key_with_comment="${key_data} # ${hostname}"

    echo "$key_with_comment" >> "$auth_keys"
    log_info "  + Added local key ($hostname) to authorized_keys"
}

# Sync secrets bidirectionally with GitHub gist
# Bidirectional sync with GitHub gist (SSH config, authorized_keys, git identity)
# WARNING: Secret gists are unlisted, not encrypted — anyone with the URL can read them.
# Do NOT add secrets (API keys, private keys, tokens) to this sync.
sync_gist() {
    local gist_id="${GIST_SYNC_ID:-3cc239f160a2fe8c9e6a14829d85a371}"

    if ! gh auth status &>/dev/null 2>&1; then
        log_warning "gh not authenticated - run 'gh auth login' to sync gist"
        return 1
    fi

    local gist_data
    gist_data=$(gh api "/gists/$gist_id" 2>/dev/null) || {
        log_warning "Failed to fetch gist - check network or gist ID"
        return 1
    }

    # Get gist updated_at timestamp
    # Note: Use printf or here-string, NOT echo - echo interprets \n in JSON content
    local gist_updated_at
    gist_updated_at=$(python3 -c "
import sys, json
from datetime import datetime
data = json.load(sys.stdin)
ts = datetime.fromisoformat(data['updated_at'].replace('Z', '+00:00'))
print(int(ts.timestamp()))
" <<< "$gist_data" 2>/dev/null)

    if [[ -z "$gist_updated_at" ]]; then
        log_warning "Failed to parse gist timestamp - skipping sync"
        return 1
    fi

    # Helper functions
    get_gist_file() {
        python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data['files'].get('$1', {}).get('content', ''))
" <<< "$gist_data" 2>/dev/null
    }

    gist_has_file() {
        python3 -c "
import sys, json
data = json.load(sys.stdin)
print('yes' if '$1' in data['files'] else 'no')
" <<< "$gist_data" 2>/dev/null
    }

    local changes_made=false

    # Ensure local key is in authorized_keys before syncing
    ensure_local_key_in_authorized_keys

    # Sync SSH config
    log_info "Syncing SSH config..."
    sync_file "$HOME/.ssh/config" "config" "$gist_id" "$gist_updated_at" && changes_made=true

    # Sync authorized_keys (union merge — never drop keys across machines)
    log_info "Syncing authorized_keys..."
    sync_authorized_keys_union "$gist_id" "$gist_updated_at" && changes_made=true

    # Sync user.conf (git identity)
    log_info "Syncing git identity..."
    sync_file "$DOT_DIR/config/user.conf" "user.conf" "$gist_id" "$gist_updated_at" && changes_made=true

    if [[ "$changes_made" == "true" ]]; then
        log_success "Gist sync complete"
    else
        log_success "Gist already in sync"
    fi
}

# Push a local file to gist, creating or updating the named entry.
# gh gist edit --add only creates new files; PATCH updates existing ones.
# Content is passed via stdin (jq --rawfile) to avoid exposing it in process args.
# Usage: gist_push_file <gist_id> <local_path> <gist_filename>
gist_push_file() {
    local gist_id="$1" local_path="$2" gist_filename="$3"
    jq -n --arg name "$gist_filename" --rawfile c "$local_path" \
        '{files: {($name): {content: $c}}}' \
    | gh api --method PATCH "/gists/$gist_id" --input - &>/dev/null
}

# Sync authorized_keys with union merge: keys are only ever added, never deleted.
# A key missing from local doesn't mean it was revoked — it might just be a new machine.
# Usage: sync_authorized_keys_union <gist_id> <gist_updated_at_epoch>
sync_authorized_keys_union() {
    local gist_id="$1"
    local gist_updated_at="$2"
    local local_path="$HOME/.ssh/authorized_keys"

    local gist_content
    gist_content=$(get_gist_file "authorized_keys")

    # Case 1: local missing → pull from gist
    if [[ ! -f "$local_path" ]]; then
        if [[ -n "$gist_content" ]]; then
            mkdir -p "$(dirname "$local_path")"
            printf '%s\n' "$gist_content" > "$local_path"
            chmod 600 "$local_path"
            log_info "  ↓ Pulled authorized_keys from gist (local was missing)"
            return 0
        fi
        return 1
    fi

    # Case 2: gist missing → push local
    if [[ -z "$gist_content" ]]; then
        gist_push_file "$gist_id" "$local_path" "authorized_keys"
        log_info "  ↑ Pushed authorized_keys to gist (gist was missing)"
        return 0
    fi

    # Get local file birthtime to distinguish "fresh install" from "intentional edit"
    local local_birthtime=0
    if is_macos; then
        local_birthtime=$(stat -f %SB -t %s "$local_path" 2>/dev/null || echo 0)
    else
        local_birthtime=$(stat --format=%W "$local_path" 2>/dev/null || echo 0)
        # Fall back to mtime if birthtime unsupported (returns 0)
        [[ "$local_birthtime" == "0" ]] && local_birthtime=$(stat --format=%Y "$local_path" 2>/dev/null || echo 0)
    fi
    local age_days=0
    [[ "$local_birthtime" -gt 0 ]] && age_days=$(( ( $(date +%s) - local_birthtime ) / 86400 ))
    local age_label="${age_days}d old"

    local local_content
    local_content=$(cat "$local_path")

    if [[ "$local_content" == "$gist_content" ]]; then
        log_info "  ✓ authorized_keys in sync"
        return 1
    fi

    # Union merge via Python: deduplicate by key blob, use the older file as the base
    # (its structure/comments are authoritative; the newer file's unique keys and
    # comments are merged in — same-blob comments are unioned comma-separated).
    local merged
    merged=$(GIST_CONTENT="$gist_content" LOCAL_CONTENT="$local_content" \
        python3 - "$local_birthtime" "$gist_updated_at" <<'PYEOF'
import os, sys

local_birth = int(sys.argv[1])
gist_ts     = int(sys.argv[2])

def parse(content):
    """Return (entries_in_order, blob_set).
    Each entry is (blob_or_None, key_type, comment, raw_line).
    blob_or_None: key blob for key lines, None for blank/# comment lines.
    comment: text after the blob (may be ''); None for non-key lines.
    Intra-file duplicates (by blob) are silently dropped (first wins).
    """
    seen, entries = set(), []
    for line in content.splitlines():
        s = line.strip()
        if s and not s.startswith('#'):
            parts = s.split()
            if len(parts) >= 2:
                blob = parts[1]
                if blob not in seen:
                    seen.add(blob)
                    entries.append((blob, parts[0], ' '.join(parts[2:]), line))
                continue  # silently drop intra-file dups
        entries.append((None, None, None, line))
    return entries, seen

def merge_comments(a, b):
    """Union two comment strings, comma-separated, dedup, drop empty tokens.
    Ensures commented always beats uncommented: 'laptop' + '' → 'laptop'.
    """
    seen, out = set(), []
    for token in ','.join(filter(None, [a, b])).split(','):
        token = token.strip()
        if token and token not in seen:
            seen.add(token)
            out.append(token)
    return ', '.join(out)

gist_entries,  gist_blobs  = parse(os.environ['GIST_CONTENT'])
local_entries, local_blobs = parse(os.environ['LOCAL_CONTENT'])

# Older file = canonical base; newer file's unique keys and comments are merged in
if local_birth > 0 and local_birth < gist_ts:
    base_entries, base_blobs = local_entries, local_blobs
    other_entries, other_blobs = gist_entries, gist_blobs
else:
    base_entries, base_blobs = gist_entries, gist_blobs
    other_entries, other_blobs = local_entries, local_blobs

# Build comment lookup for the other file (blob -> comment string)
other_comment = {blob: comment for blob, _, comment, _ in other_entries if blob}

# Render base file; merge in comments from the other file for matching blobs
lines = []
for blob, key_type, comment, raw_line in base_entries:
    if blob is None:
        lines.append(raw_line)  # blank or # comment line — preserve as-is
    else:
        new_comment = merge_comments(comment, other_comment.get(blob, ''))
        lines.append(f'{key_type} {blob} {new_comment}' if new_comment else f'{key_type} {blob}')

# Strip trailing blanks before appending extra keys
while lines and not lines[-1].strip():
    lines.pop()

# Append unique keys from the other file (blobs absent from base)
extra = [(blob, key_type, comment) for blob, key_type, comment, _ in other_entries
         if blob and blob not in base_blobs]
if extra:
    lines.append('')
    for blob, key_type, comment in extra:
        lines.append(f'{key_type} {blob} {comment}' if comment else f'{key_type} {blob}')

print('\n'.join(lines))
PYEOF
)

    if [[ -z "$merged" ]]; then
        log_warning "  authorized_keys union merge failed, falling back to last-modified-wins"
        sync_file "$local_path" "authorized_keys" "$gist_id" "$gist_updated_at"
        return
    fi

    local local_count gist_count merged_count
    local_count=$(printf '%s\n' "$local_content" | grep -cE '^(ssh-|ecdsa-|sk-)' || true)
    gist_count=$(printf '%s\n' "$gist_content"   | grep -cE '^(ssh-|ecdsa-|sk-)' || true)
    merged_count=$(printf '%s\n' "$merged"        | grep -cE '^(ssh-|ecdsa-|sk-)' || true)

    local changed=false

    if [[ "$merged" != "$local_content" ]]; then
        printf '%s\n' "$merged" > "$local_path"
        chmod 600 "$local_path"
        log_info "  ↕ Updated local authorized_keys (${local_count}→${merged_count} keys; local file is $age_label)"
        changed=true
    fi

    if [[ "$merged" != "$gist_content" ]]; then
        local tmp_ak="${TMPDIR:-/tmp}/authorized_keys_union_$$"
        printf '%s\n' "$merged" > "$tmp_ak"
        gist_push_file "$gist_id" "$tmp_ak" "authorized_keys"
        rm -f "$tmp_ak"
        log_info "  ↑ Pushed merged authorized_keys to gist (gist had $gist_count keys, merged=$merged_count)"
        changed=true
    fi

    [[ "$changed" == "true" ]]
}

# Sync a single file with gist
# Usage: sync_file <local_path> <gist_filename> <gist_id> <gist_updated_at>
sync_file() {
    local local_path="$1"
    local gist_filename="$2"
    local gist_id="$3"
    local gist_updated_at="$4"

    local gist_exists
    gist_exists=$(gist_has_file "$gist_filename")

    if [[ ! -f "$local_path" ]]; then
        if [[ "$gist_exists" == "yes" ]]; then
            mkdir -p "$(dirname "$local_path")"
            get_gist_file "$gist_filename" > "$local_path"
            [[ "$gist_filename" == "config" || "$gist_filename" == "authorized_keys" ]] && chmod 600 "$local_path"
            # Preserve mtime to match gist's updated_at
            if is_macos; then
                touch -t "$(date -r "$gist_updated_at" +%Y%m%d%H%M.%S)" "$local_path"
            else
                touch -d "@$gist_updated_at" "$local_path"
            fi
            log_info "  ↓ Pulled $gist_filename from gist (local was missing)"
            return 0
        fi
        return 1
    fi

    if [[ "$gist_exists" == "no" ]]; then
        gist_push_file "$gist_id" "$local_path" "$gist_filename"
        log_info "  ↑ Pushed $gist_filename to gist (gist was missing)"
        return 0
    fi

    # Both exist - compare
    local local_mtime gist_content local_content
    local_mtime=$(get_mtime "$local_path")
    gist_content=$(get_gist_file "$gist_filename")
    local_content=$(cat "$local_path")

    if [[ "$local_content" != "$gist_content" ]]; then
        if [[ "$local_mtime" -gt "$gist_updated_at" ]]; then
            gist_push_file "$gist_id" "$local_path" "$gist_filename"
            log_info "  ↑ Pushed $gist_filename to gist (local newer)"
        else
            printf '%s\n' "$gist_content" > "$local_path"
            [[ "$gist_filename" == "config" || "$gist_filename" == "authorized_keys" ]] && chmod 600 "$local_path"
            # Preserve mtime to match gist's updated_at (prevents false "local newer" on next sync)
            if is_macos; then
                touch -t "$(date -r "$gist_updated_at" +%Y%m%d%H%M.%S)" "$local_path"
            else
                touch -d "@$gist_updated_at" "$local_path"
            fi
            log_info "  ↓ Pulled $gist_filename from gist (gist newer)"
        fi
        return 0
    fi

    log_info "  ✓ $gist_filename in sync"
    return 1
}

# ─── Git Configuration ────────────────────────────────────────────────────────

# Deploy git configuration with conflict resolution
deploy_git_config() {
    log_info "Deploying git configuration..."

    # Deploy global gitignore (composed from universal + research patterns)
    # Git sees both; search tools (rg, fd, Claude Code) see only universal.
    if [[ -f "$DOT_DIR/config/ignore/gitignore_base" ]] && [[ -f "$DOT_DIR/config/ignore/gitignore_research" ]]; then
        cat "$DOT_DIR/config/ignore/gitignore_base" "$DOT_DIR/config/ignore/gitignore_research" > "$HOME/.gitignore_global"
        log_success "Deployed ~/.gitignore_global (universal + research)"
    elif [[ -f "$DOT_DIR/config/ignore/gitignore_base" ]]; then
        cp "$DOT_DIR/config/ignore/gitignore_base" "$HOME/.gitignore_global"
        log_success "Deployed ~/.gitignore_global (universal only)"
    fi

    # Deploy search tool ignore files (universal only, symlinked for auto-update)
    if [[ -f "$DOT_DIR/config/ignore/gitignore_base" ]]; then
        # ripgrep + Claude Code: symlink universal ignore
        ln -sf "$DOT_DIR/config/ignore/gitignore_base" "$HOME/.ignore_global"
        log_success "Symlinked ~/.ignore_global"

        # fd: symlink to same file
        local fd_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/fd"
        mkdir -p "$fd_config_dir"
        ln -sf "$DOT_DIR/config/ignore/gitignore_base" "$fd_config_dir/ignore"
        log_success "Symlinked $fd_config_dir/ignore"

        # ripgrep config: skip git's global ignore, use universal-only ignore file
        if cmd_exists rg; then
            local rg_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/ripgrep"
            mkdir -p "$rg_config_dir"
            printf '%s\n' "--no-ignore-global" "--ignore-file" "$HOME/.ignore_global" > "$rg_config_dir/config"
            log_success "Deployed $rg_config_dir/config"
        fi
    fi

    # Load user config if exists
    if [[ -f "$DOT_DIR/config/user.conf" ]]; then
        source "$DOT_DIR/config/user.conf"
        GIT_USER_EMAIL="${GIT_USER_EMAIL:-$GIT_USER_EMAIL}"
        GIT_USER_NAME="${GIT_USER_NAME:-$GIT_USER_NAME}"
        log_info "Using git identity from config/user.conf"
    fi

    # Git settings to apply
    typeset -A git_settings=(
        ["user.email"]="$GIT_USER_EMAIL"
        ["user.name"]="$GIT_USER_NAME"
        ["push.autoSetupRemote"]="true"
        ["push.default"]="simple"
        ["init.defaultBranch"]="main"
        ["core.excludesfile"]="~/.gitignore_global"
        ["merge.conflictstyle"]="zdiff3"
        ["rerere.enabled"]="true"
        ["rerere.autoUpdate"]="true"
        ["pull.rebase"]="true"
        ["rebase.autoStash"]="true"
        ["rebase.autoSquash"]="true"
        ["fetch.prune"]="true"
        ["fetch.pruneTags"]="true"
        ["alias.lg"]="log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"
    )

    # Check for conflicts
    local conflicts=()
    for key in "${(k)git_settings[@]}"; do
        local existing=$(git config --global "$key" 2>/dev/null || echo "")
        local new="${git_settings[$key]}"
        if [[ -n "$existing" && "$existing" != "$new" ]]; then
            conflicts+=("$key|$existing|$new")
        fi
    done

    # Handle conflicts
    if [[ ${#conflicts[@]} -gt 0 ]]; then
        echo ""
        log_warning "Git config conflicts detected:"
        echo ""
        for conflict in "${conflicts[@]}"; do
            IFS='|' read -r key existing new <<< "$conflict"
            echo "  [$key]"
            echo "    Current:  $existing"
            echo "    New:      $new"
            echo ""
        done

        # Unattended/non-interactive: keep existing values (safe default — your
        # machine's settings win), apply only the non-conflicting ones.
        if prompts_disabled; then
            log_info "Non-interactive: keeping existing git values, applying non-conflicting..."
            apply_nonconflicting_git_settings "${conflicts[@]}"
            log_success "Git configuration deployed"
            return 0
        fi

        echo "Options:"
        echo "  [K]eep all existing values"
        echo "  [U]se all new values from dotfiles"
        echo "  [S]kip git config deployment"
        echo ""
        read -p "Choose [K/U/S]: " -n 1 -r choice
        echo ""

        case "$choice" in
            [Kk])
                log_info "Keeping existing values, applying non-conflicting..."
                apply_nonconflicting_git_settings "${conflicts[@]}"
                ;;
            [Uu])
                log_info "Using all new values..."
                apply_all_git_settings
                ;;
            *)
                log_info "Skipping git config deployment"
                return 0
                ;;
        esac
    else
        log_info "No conflicts, applying all settings..."
        apply_all_git_settings
    fi

    log_success "Git configuration deployed"
}

apply_all_git_settings() {
    git config --global user.email "$GIT_USER_EMAIL"
    git config --global user.name "$GIT_USER_NAME"
    git config --global push.autoSetupRemote true
    git config --global push.default simple
    git config --global init.defaultBranch main
    git config --global core.excludesfile "~/.gitignore_global"
    git config --global alias.lg "log --color --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"
}

apply_nonconflicting_git_settings() {
    local conflicts=("$@")
    local conflict_keys=()

    for conflict in "${conflicts[@]}"; do
        IFS='|' read -r key _ _ <<< "$conflict"
        conflict_keys+=("$key")
    done

    # Apply settings not in conflict list
    for key in user.email user.name push.autoSetupRemote push.default init.defaultBranch core.excludesfile alias.lg; do
        local is_conflict=false
        for ck in "${conflict_keys[@]}"; do
            [[ "$key" == "$ck" ]] && is_conflict=true && break
        done
        if ! $is_conflict; then
            local existing
            existing=$(git config --global "$key" 2>/dev/null || echo "")
            [[ -z "$existing" ]] && git config --global "$key" "${git_settings[$key]}"
        fi
    done
}

# ─── Editor Settings ──────────────────────────────────────────────────────────

# Deploy VSCode/Cursor/Antigravity settings
deploy_editor_settings() {
    local settings_file="$DOT_DIR/config/vscode_settings.json"

    if [[ ! -f "$settings_file" ]]; then
        log_warning "VSCode settings not found at $settings_file"
        return 1
    fi

    # Determine paths
    local vscode_dir cursor_dir antigravity_dir
    if is_macos; then
        vscode_dir="$HOME/Library/Application Support/Code/User"
        cursor_dir="$HOME/Library/Application Support/Cursor/User"
        antigravity_dir="$HOME/Library/Application Support/Antigravity/User"
    else
        vscode_dir="$HOME/.config/Code/User"
        cursor_dir="$HOME/.config/Cursor/User"
        antigravity_dir=""  # macOS only
    fi

    local deployed=false

    # Deploy to VSCode
    if [[ -d "$vscode_dir" ]]; then
        merge_json_settings "$settings_file" "$vscode_dir/settings.json" "VSCode"
        install_editor_extensions "code" "$DOT_DIR/config/vscode_extensions.txt"
        deployed=true
    fi

    # Deploy to Cursor
    if [[ -d "$cursor_dir" ]]; then
        merge_json_settings "$settings_file" "$cursor_dir/settings.json" "Cursor"
        install_editor_extensions "cursor" "$DOT_DIR/config/vscode_extensions.txt"
        deployed=true
    fi

    # Deploy to Antigravity (macOS-only VSCode fork by Google)
    if [[ -n "$antigravity_dir" && -d "$antigravity_dir" ]]; then
        merge_json_settings "$settings_file" "$antigravity_dir/settings.json" "Antigravity"
        # CLI not in PATH by default — use full path if available
        local ag_cli="/Applications/Antigravity.app/Contents/Resources/app/bin/antigravity"
        if [[ -x "$ag_cli" ]]; then
            install_editor_extensions "$ag_cli" "$DOT_DIR/config/vscode_extensions.txt"
        elif cmd_exists antigravity; then
            install_editor_extensions "antigravity" "$DOT_DIR/config/vscode_extensions.txt"
        else
            log_info "Antigravity CLI not found, skipping extensions"
        fi
        deployed=true
    fi

    if ! $deployed; then
        log_info "No editor (VSCode, Cursor, or Antigravity) found — skipping editor settings"
        return 0
    fi
}

# Merge JSON settings (existing takes precedence)
merge_json_settings() {
    local source="$1"
    local target="$2"
    local name="$3"

    if [[ ! -f "$target" ]]; then
        cp "$source" "$target"
        log_success "Deployed $name settings (new)"
        return 0
    fi

    python3 - "$source" "$target" <<'MERGE'
import json, sys
with open(sys.argv[1]) as f: dotfiles = json.load(f)
with open(sys.argv[2]) as f: existing = json.load(f)
# Deep merge: scalars/objects → existing wins; arrays → dotfiles wins (dotfiles is source of truth)
merged = {}
all_keys = set(dotfiles) | set(existing)
for k in all_keys:
    if k not in dotfiles:
        merged[k] = existing[k]
    elif k not in existing:
        merged[k] = dotfiles[k]
    elif isinstance(dotfiles[k], list):
        merged[k] = dotfiles[k]  # dotfiles wins for arrays
    else:
        merged[k] = existing[k]  # existing wins for scalars/objects
with open(sys.argv[2], 'w') as f: json.dump(merged, f, indent=4); f.write('\n')
MERGE

    log_success "Merged $name settings (existing preserved, arrays from dotfiles)"
}

# Sync editor extensions: install missing, uninstall unlisted (concurrent, up to 8 at a time)
install_editor_extensions() {
    local cli="$1"
    local extensions_file="$2"
    local max_jobs="${3:-8}"

    if ! cmd_exists "$cli"; then
        log_info "$cli CLI not found, skipping extensions"
        return 0
    fi

    if [[ ! -f "$extensions_file" ]]; then
        return 0
    fi

    # Collect wanted extension IDs (lowercased for case-insensitive comparison)
    typeset -a ext_ids
    typeset -A wanted_map
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        local id="${line// /}"
        ext_ids+=("$id")
        wanted_map[${id:l}]=1
    done < "$extensions_file"

    [[ ${#ext_ids[@]} -eq 0 ]] && return 0

    # ── Install missing extensions ──
    log_info "Syncing ${#ext_ids[@]} extensions (${max_jobs} concurrent)..."

    local tmpdir="${TMPDIR:-/tmp}/ext_install_$$"
    mkdir -p "$tmpdir"

    printf '%s\n' "${ext_ids[@]}" | xargs -P "$max_jobs" -I{} \
        sh -c "'$cli' --install-extension '{}' --force >/dev/null 2>&1 && touch '$tmpdir/{}'"

    local install_count
    install_count=$(find "$tmpdir" -type f 2>/dev/null | wc -l | tr -d ' ')
    rm -rf "$tmpdir"

    [[ $install_count -gt 0 ]] && log_success "Synced $install_count extension(s)"

    # ── Uninstall unlisted extensions ──
    typeset -a installed
    installed=($("$cli" --list-extensions 2>/dev/null | tr -d '\r'))

    typeset -a to_remove
    for ext in "${installed[@]}"; do
        [[ -z "$ext" ]] && continue
        if [[ -z "${wanted_map[${ext:l}]}" ]]; then
            to_remove+=("$ext")
        fi
    done

    if [[ ${#to_remove[@]} -gt 0 ]]; then
        # Safety: refuse to bulk-remove more extensions than we track (truncated file?)
        if [[ ${#to_remove[@]} -gt ${#ext_ids[@]} ]]; then
            log_warning "Would remove ${#to_remove[@]} extensions (more than ${#ext_ids[@]} tracked). Skipping as safety check."
            return 0
        fi

        log_info "Removing ${#to_remove[@]} unlisted extension(s): ${to_remove[*]}"
        local tmpdir_rm="${TMPDIR:-/tmp}/ext_remove_$$"
        mkdir -p "$tmpdir_rm"

        printf '%s\n' "${to_remove[@]}" | xargs -P "$max_jobs" -I{} \
            sh -c "'$cli' --uninstall-extension '{}' >/dev/null 2>&1 && touch '$tmpdir_rm/{}'"

        local remove_count
        remove_count=$(find "$tmpdir_rm" -type f 2>/dev/null | wc -l | tr -d ' ')
        rm -rf "$tmpdir_rm"

        [[ $remove_count -gt 0 ]] && log_success "Removed $remove_count extension(s)"
    fi
}

# ─── CLI Argument Parsing ─────────────────────────────────────────────────────

# Parse CLI arguments and override config
# Usage: parse_args "$@"
parse_args() {
    # --only accumulator (deferred two-pass parsing)
    typeset -a _only_components
    _only_components=()
    local _only_mode=false

    while (( $# )); do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            --profile=*)
                if [[ "$_only_mode" == true ]]; then
                    echo "Error: --only cannot be mixed with profile or component flags" >&2
                    exit 1
                fi
                apply_profile "${1#*=}"
                ;;
            --force|--force-reinstall)
                FORCE_REINSTALL=true
                ;;
            --append)
                DEPLOY_APPEND=true
                ;;
            --ascii=*)
                DEPLOY_ASCII_FILE="${1#*=}"
                ;;
            --aliases=*)
                IFS=',' read -r -a DEPLOY_ALIASES <<< "${1#*=}"
                ;;
            --minimal)
                if [[ "$_only_mode" == true ]]; then
                    echo "Error: --only cannot be mixed with profile or component flags" >&2
                    exit 1
                fi
                apply_profile "minimal"
                ;;
            --server)
                if [[ "$_only_mode" == true ]]; then
                    echo "Error: --only cannot be mixed with profile or component flags" >&2
                    exit 1
                fi
                apply_profile "server"
                ;;
            --personal)
                if [[ "$_only_mode" == true ]]; then
                    echo "Error: --only cannot be mixed with profile or component flags" >&2
                    exit 1
                fi
                apply_profile "personal"
                ;;
            --default)
                if [[ "$_only_mode" == true ]]; then
                    echo "Error: --only cannot be mixed with profile or component flags" >&2
                    exit 1
                fi
                apply_profile "server"
                ;;
            --no-defaults)
                if [[ "$_only_mode" == true ]]; then
                    echo "Error: --only cannot be mixed with profile or component flags" >&2
                    exit 1
                fi
                apply_profile "minimal"
                ;;
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
            --non-interactive)
                # Skip ALL interactivity incl. the component menu; use defaults.
                # Must be exported so child processes (e.g. app-picker) honor it.
                NON_INTERACTIVE=true
                export NON_INTERACTIVE
                ;;
            --unattended|--yes|-y)
                # The component menu stays the ONE interactive step; everything
                # after it runs with safe defaults (gh auth deferred, git
                # conflicts keep existing, sudo cached once up front).
                ASSUME_DEFAULTS=true
                export ASSUME_DEFAULTS
                ;;
            --no-*)
                if [[ "$_only_mode" == true ]]; then
                    echo "Error: --only cannot be mixed with profile or component flags" >&2
                    exit 1
                fi
                # Disable a component: --no-zsh, --no-claude, etc.
                local component="${1#--no-}"
                component="$(printf '%s' "$component" | tr '[:lower:]' '[:upper:]')"
                component="${component//-/_}"  # dashes to underscores
                typeset -g "INSTALL_${component}=false"
                typeset -g "DEPLOY_${component}=false"
                ;;
            --*)
                if [[ "$_only_mode" == true ]]; then
                    echo "Error: --only cannot be mixed with profile or component flags" >&2
                    exit 1
                fi
                # Enable a component: --zsh, --claude, etc.
                local component="${1#--}"
                component="$(printf '%s' "$component" | tr '[:lower:]' '[:upper:]')"
                component="${component//-/_}"
                typeset -g "INSTALL_${component}=true"
                typeset -g "DEPLOY_${component}=true"
                ;;
            *)
                log_warning "Unknown argument: $1"
                ;;
        esac
        shift
    done

    # Deferred --only apply: validate components, then set minimal + enable selected
    if [[ "$_only_mode" == true ]]; then
        # Build _known_components from registries (lowercase, no hardcoded list to drift)
        local _known_components=()
        local _entry _name _var
        for _entry in "${INSTALL_REGISTRY[@]}" "${DEPLOY_REGISTRY[@]}"; do
            _name="${_entry%%|*}"
            _var="${_name//-/_}"  # lowercase with underscores (matches validation lookup)
            if (( ! ${_known_components[(Ie)$_var]} )); then
                _known_components+=("$_var")
            fi
        done

        for _comp in "${_only_components[@]}"; do
            _comp="${_comp// /}"
            [[ -z "$_comp" ]] && continue
            local _comp_lower="${_comp:l}"
            _comp_lower="${_comp_lower//-/_}"
            if (( ! ${_known_components[(Ie)$_comp_lower]} )); then
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
}
