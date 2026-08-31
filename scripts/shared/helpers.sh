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
# Sections carry a counter and the run's elapsed time, so "is it stuck?" is
# answerable at a glance — the question that made silent steps read as hangs.
# DOTFILES_SECTION_TOTAL (optional) turns the counter into "n/total".
typeset -g DOTFILES_SECTION_N=0
typeset -g DOTFILES_RUN_START=${DOTFILES_RUN_START:-$SECONDS}
log_section() {
    DOTFILES_SECTION_N=$((DOTFILES_SECTION_N + 1))
    local counter="$DOTFILES_SECTION_N"
    [[ -n "${DOTFILES_SECTION_TOTAL:-}" ]] && counter="${counter}/${DOTFILES_SECTION_TOTAL}"
    local elapsed=$((SECONDS - DOTFILES_RUN_START))
    printf '\n───────── [%s] %s (%dm%02ds) ─────────\n' \
        "$counter" "$*" "$((elapsed / 60))" "$((elapsed % 60))"
}

# Run a long, quiet command with a live spinner + elapsed seconds on a TTY, so
# it never looks hung. Output is captured and replayed on failure only.
#
# Leaves NO scrollback behind: the spinner redraws one line in place with \r and
# erases it (\033[K) before printing the single result line. It ticks once a
# second rather than faster, which also keeps it cheap over mosh — mosh
# coalesces frames, so a fast spinner would only burn bandwidth for frames
# nobody sees. Opt out with DOTFILES_NO_PROGRESS=1, and TERM=dumb (or any
# non-TTY: pipes, cron, CI) takes the plain path automatically.
#
# Usage: run_with_progress "Label" <cmd> [args...]
run_with_progress() {
    local label="$1"; shift
    local logfile; logfile=$(mktemp "${TMPDIR:-/tmp}/progress.XXXXXX")

    if ! [[ -t 1 ]] || [[ "${DOTFILES_NO_PROGRESS:-0}" == "1" ]] || [[ "${TERM:-}" == "dumb" ]]; then
        log_info "${label}..."
        "$@" >"$logfile" 2>&1
        local rc=$?
        (( rc != 0 )) && cat "$logfile" >&2
        rm -f "$logfile"
        return $rc
    fi

    "$@" >"$logfile" 2>&1 &
    local pid=$! start=$SECONDS i=0
    local frames='|/-\'
    while kill -0 "$pid" 2>/dev/null; do
        printf '\r  %s %s (%ds)' "${frames[$((i % 4 + 1))]}" "$label" "$((SECONDS - start))"
        i=$((i + 1))
        sleep 1
    done
    wait "$pid"
    local rc=$?
    printf '\r\033[K'
    if (( rc == 0 )); then
        log_success "${label} ($((SECONDS - start))s)"
    else
        log_warning "${label} failed after $((SECONDS - start))s"
        cat "$logfile" >&2
    fi
    rm -f "$logfile"
    return $rc
}

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
    mkdir -p "${DOT_DIR}/custom_bins"
    local tmp="${bin}.tmp.$$"

    # HTTPS + TLS 1.2 only; never pipe-to-shell — download to temp, then verify.
    # Deadlines are mandatory here: this runs at the top of both scripts, before
    # anything is printed but one log line, so an untimed fetch reads as a hang.
    # Wrapped in the spinner because this is the very first thing either script
    # does: a silent pause here is what a stall looks like to whoever is
    # watching, even when it is only a slow download.
    if ! run_with_progress "Fetching prebuilt claude-tools (${asset})" \
        curl --proto '=https' --tlsv1.2 -fsSL \
        --connect-timeout 10 --max-time 120 --retry 2 --retry-max-time 120 \
        "$url" -o "$tmp"; then
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
    # A cold Rust build is minutes long. It used to run --quiet, which made the
    # top of every install indistinguishable from a hang; cargo's own progress
    # now shows, and a deadline bounds it. This is the stall that outlived
    # several rounds of prompt fixes, because it is not a prompt.
    log_info "Building claude-tools from source (fallback) — a cold build takes a few minutes..."
    ( cd "${DOT_DIR}/tools/claude-tools" \
        && run_with_timeout "${DOTFILES_BUILD_TIMEOUT:-900}" cargo build --release ) || {
        log_warning "claude-tools build failed or exceeded its deadline — continuing with defaults"
        return 1
    }
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
    # A TTY is not proof a human is watching it: launched in tmux, from an agent
    # pty, or simply walked away from, this menu would wait forever at the very
    # top of the run. The deadline makes an unattended run proceed with whatever
    # is pre-checked (the profile's set, plus any config.local.sh delta), which
    # is exactly what --non-interactive would have installed.
    #
    # `|| rc=$?` is load-bearing, not decoration: both scripts run under
    # `set -euo pipefail`, and in zsh a failing command substitution in a plain
    # assignment aborts the script THERE — verified, exit 124 with nothing
    # printed. Without this, the 124 branch below was unreachable and an
    # unattended TTY run died silently after the timeout having installed
    # nothing, which is the exact scenario the deadline was added to rescue.
    local rc=0
    result=$(run_with_timeout "${DOTFILES_MENU_TIMEOUT:-60}" \
        claude-tools select --title "Select ${mode} components" --items "$items_file") || rc=$?
    if (( rc == 124 )); then
        log_warning "Component menu unanswered for ${DOTFILES_MENU_TIMEOUT:-60}s — continuing with the default selection"
        rm -f "$items_file"
        return 0
    fi
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

# ─── Deadlines ────────────────────────────────────────────────────────────────
# The installers must never stall: every network fetch and every prompt carries
# a deadline, so an unattended run (tmux pane, agent pty, cron) fails loudly in
# minutes instead of hanging at hour zero.

# Network fetch with deadlines. Drop-in for `curl -fsSL` — extra curl args pass
# through (-o, --retry overrides, headers). 10s to connect, two retries on
# transient failures, and 300s OVERALL.
#
# --retry-max-time is what makes "overall" true. Per `man curl`, --max-time is
# "the maximum time that you allow each transfer to take", and "if you enable
# retrying the transfer (--retry) then the maximum time counter is reset each
# time the transfer is retried" — so --max-time 300 --retry 2 is three
# transfers, up to ~900s, three times the number this comment used to claim.
# --retry-max-time bounds the whole sequence.
fetch() {
    curl -fsSL --connect-timeout 10 --max-time 300 --retry 2 --retry-max-time 300 "$@"
}

# Every apt/dpkg call must bound its wait for the lock. On a fresh box
# unattended-upgrades holds it at boot, and DEBIAN_FRONTEND does nothing about
# that — apt just waits, forever, with no output. One definition so a new call
# site cannot quietly omit it.
APT_LOCK_OPT=(-o "DPkg::Lock::Timeout=${APT_LOCK_TIMEOUT:-120}")

# Run a command under a deadline where the platform allows it. timeout(1) is
# coreutils — present on Linux, absent on stock macOS (until `core` installs
# coreutils, which provides no unprefixed `timeout` anyway) — so this degrades
# to running without a deadline rather than failing. --foreground keeps TTY
# prompts (sudo, TUIs) able to read the terminal. Exit 124 means the deadline
# fired.
run_with_timeout() {
    local _secs="$1"; shift
    if [[ "$_secs" == "0" ]]; then
        "$@"   # 0 disables the deadline (test hook, and an explicit opt-out)
    elif cmd_exists timeout; then
        timeout --foreground "$_secs" "$@"
    elif cmd_exists gtimeout; then
        gtimeout --foreground "$_secs" "$@"
    else
        _watchdog_run "$_secs" "$@"
    fi
}

# Deadline without coreutils. This exists for exactly one situation, and it is
# not a rare one: a FRESH Mac. macOS ships no `timeout`, and `gtimeout` arrives
# only with coreutils — which install.sh installs *after* the component menu and
# the sudo prompt have already run. Falling back to running unbounded there
# would leave the first run on every new Mac, the run most likely to be watched
# by nobody, with no deadline at all.
#
# Why backgrounding is safe here despite the command needing a TTY: scripts run
# with job control off, so `cmd &` does NOT put the child in a new process
# group. It stays in the terminal's foreground group and can still read the
# terminal — SIGTTIN only strikes a background *process group*. Interactive
# shells (job control on) would behave differently, which is why this is a
# script-only helper.
#
# Returns 124 on expiry, matching timeout(1), because callers switch on it.
_watchdog_run() {
    local _secs="$1"; shift
    # zsh points a BACKGROUNDED job's stdin at /dev/null even when the shell's
    # own stdin is a terminal, and `<&0` does not undo it (both measured under
    # a pty). The process-group reasoning above is correct but says nothing
    # about stdin, so the fresh-Mac fallback was handing the component menu and
    # chsh's PAM prompt an instant EOF — the two things on this path that must
    # read the user. Re-attach the controlling terminal explicitly.
    if [[ -t 0 ]]; then
        "$@" </dev/tty &
    else
        "$@" &
    fi
    local _pid=$! _waited=0
    while (( _waited < _secs )); do
        kill -0 "$_pid" 2>/dev/null || break
        sleep 1
        _waited=$((_waited + 1))
    done
    if kill -0 "$_pid" 2>/dev/null; then
        kill -TERM "$_pid" 2>/dev/null || true
        sleep 1
        kill -KILL "$_pid" 2>/dev/null || true
        wait "$_pid" 2>/dev/null
        return 124
    fi
    wait "$_pid"
}

# Cache sudo credentials once, up front, so privileged steps later in the run
# don't block on a password prompt mid-install. A background keepalive refreshes
# the timestamp until the calling script exits. No-op if sudo is already cached,
# unavailable, or there's no TTY to prompt on. (sudo's password is the one prompt
# with no software default, so it's the only interaction we cache rather than
# skip — the component menu aside.)
front_load_sudo() {
    cmd_exists sudo || return 0
    [[ -t 0 ]] || return 0
    sudo -n true 2>/dev/null && return 0   # already cached — no prompt needed
    log_info "Some steps need administrator access — caching sudo credentials up front."
    # A TTY is no proof anyone is watching it (tmux pane, agent pty), so the
    # prompt itself carries a deadline; unanswered, sudo-needing steps skip.
    # DOTFILES_PROMPT_TIMEOUT: seconds (0 disables the deadline; tests shrink it).
    run_with_timeout "${DOTFILES_PROMPT_TIMEOUT:-60}" sudo -v || { log_warning "sudo prompt unanswered — privileged steps will be skipped"; return 0; }
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

# Like is_installed, but an executable inside an active Python environment
# (virtualenv or conda/micromamba) does not count — used for persistent global
# tools (uv tool install), where an env-local binary vanishes once the
# environment is deactivated.
is_installed_global() {
    # NB: not named "path" — in zsh that variable is tied to $PATH and
    # assigning it clobbers command lookup for the rest of the function.
    local resolved envroot
    resolved=$(command -v "$1" 2>/dev/null) || return 1
    for envroot in "${VIRTUAL_ENV:-}" "${CONDA_PREFIX:-}"; do
        if [[ -n "$envroot" && "$resolved" == "${envroot}"/* ]]; then
            return 1
        fi
    done
    is_installed "$@"
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
        local backup="${filepath}.backup.$(date -u +%Y-%m-%d_%H-%M-%S)"
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

# Install package via Homebrew (macOS and Linuxbrew)
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
    sudo apt install -y "${APT_LOCK_OPT[@]}" "$pkg" 2>/dev/null || log_warning "$pkg installation via apt failed"
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
        # DPkg::Lock::Timeout bounds the wait for the dpkg lock, which
        # DEBIAN_FRONTEND does not touch: on a fresh box running
        # unattended-upgrades at boot, apt otherwise blocks indefinitely.
        sudo apt install -y "${APT_LOCK_OPT[@]}" "${missing[@]}" 2>/dev/null \
            || log_warning "Some apt packages failed to install"
        return
    fi

    for pkg in "$@"; do
        case "$manager" in
            brew) brew_install "$pkg" ;;
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
        # Deadlines on both halves: the fetch, and the script it pipes to bash
        # (an installer that stalls hangs the run just as hard as a stalled curl).
        fetch https://direnv.net/install.sh 2>/dev/null \
            | run_with_timeout "${DOTFILES_INSTALLER_TIMEOUT:-300}" bash 2>/dev/null \
            || { log_warning "direnv installation failed or timed out"; return 1; }
    fi
}

# Rust toolchain (cargo) via rustup. macOS: official Homebrew formula (sha-pinned,
# reviewed) provides `rustup-init`; run it non-interactively. Linux: keep the upstream
# rustup installer but pin TLS (--proto '=https' --tlsv1.2) — no brew dependency.
# See claude/rules/safety.md § curl|bash Installers.
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
        curl --proto '=https' --tlsv1.2 -sSf --connect-timeout 10 --max-time 300 --retry 2 --retry-max-time 300 \
            https://sh.rustup.rs | run_with_timeout "${DOTFILES_INSTALLER_TIMEOUT:-600}" sh -s -- -y --quiet
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
    fetch https://claude.ai/install.sh \
        | run_with_timeout "${DOTFILES_INSTALLER_TIMEOUT:-300}" bash \
        || { log_warning "Claude Code installation failed or timed out"; return 1; }
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
    # Official CORE Homebrew formula (NOT the anomalyco/tap) — see claude/rules/safety.md
    #
    # Homebrew FIRST on Linux too, not just macOS: homebrew-core's `opencode`
    # ships arm64_linux and x86_64_linux bottles, and a bottle has no lifecycle
    # script for `ignore-scripts=true` to block. The bun route does:
    # opencode-ai declares `"postinstall": "node ./postinstall.mjs"`, and with
    # scripts ignored (as policy requires) the installed shim refuses to run at
    # all — "Error: opencode-ai's postinstall script was not run." That was the
    # live state of this box on 2026-08-28.
    if cmd_exists brew; then
        brew_install opencode
    elif cmd_exists bun; then
        # Still supported, and still compliant: bun installs the real binaries
        # as platform optionalDependencies, so only the shim is broken, not the
        # program. custom_bins/opencode finds the platform binary directly —
        # no lifecycle script is run and no guard is bypassed.
        bun add -g opencode-ai &>/dev/null || { log_warning "OpenCode failed"; return 1; }
        log_info "OpenCode via bun: its own shim is inert under ignore-scripts;"
        log_info "  custom_bins/opencode wraps the platform binary instead."
    else
        log_warning "OpenCode needs brew or bun; skipping"
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
        # Linux: Google ships a curl installer, but per claude/rules/safety.md we
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
        # QUOTED deliberately: in zsh an unquoted $! on the RHS of an
        # array-subscript assignment is not expanded — the map stores the
        # literal string "$!", every later `kill -0` fails, and the bounded
        # wait below silently becomes dead code.
        pids[$name]="$!"
    done

    # Bounded wait. A bare `wait` means ONE hung child (an untimed fetch, a
    # stuck package manager) hangs the entire run with no indication of which
    # job is stuck. The deadline is enforced here rather than around `eval`
    # because the jobs call helper functions that only exist in this shell.
    local _job_deadline=$((SECONDS + ${DOTFILES_JOB_TIMEOUT:-600}))
    for name in "${job_names[@]}"; do
        local _pid=${pids[$name]}
        while kill -0 "$_pid" 2>/dev/null && (( SECONDS < _job_deadline )); do
            sleep 0.5
        done
        if kill -0 "$_pid" 2>/dev/null; then
            log_warning "$name exceeded ${DOTFILES_JOB_TIMEOUT:-600}s — terminating it"
            # Descendants first: the job's real work runs as a grandchild of
            # this subshell (`eval "$cmd"`), so killing only $_pid leaves it
            # running and orphaned — measured, not assumed. Job control is off
            # in scripts, so the children do not form their own process group
            # and `kill -- -$_pid` is not available.
            pkill -TERM -P "$_pid" 2>/dev/null || true
            kill -TERM "$_pid" 2>/dev/null || true
            sleep 1
            pkill -KILL -P "$_pid" 2>/dev/null || true
            kill -KILL "$_pid" 2>/dev/null || true
            [[ -f "$tmpdir/$name.exitcode" ]] || echo 124 > "$tmpdir/$name.exitcode"
        fi
        wait "$_pid" 2>/dev/null || true
    done

    # Replay logs and collect results
    local passed=0 failed=0
    PARALLEL_FAILURES=()

    for name in "${job_names[@]}"; do
        # Absent exitcode means the job did not finish normally — killed
        # before its EXIT trap ran, or no temp dir at all. Defaulting that to 0
        # reported a still-running job as PASSED.
        local rc=124
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
        # chsh prompts PAM for the USER's password on Linux even when
        # passwordless sudo works, so it runs only attended and with a
        # deadline — a TTY nobody is watching must not hang the install.
        if ! [[ -t 0 ]]; then
            log_warning "Skipping default-shell change (no TTY for chsh's password prompt) — run: chsh -s $zsh_path"
            return 0
        fi
        log_info "Setting ZSH as default shell..."
        grep -qxF "$zsh_path" /etc/shells 2>/dev/null || \
            echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
        if run_with_timeout "${DOTFILES_PROMPT_TIMEOUT:-60}" chsh -s "$zsh_path"; then
            log_success "Default shell changed to ZSH"
        else
            log_warning "chsh unanswered or failed — run: chsh -s $zsh_path"
        fi
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
    # Fetch BEFORE deleting, and check it. `sh -c "$(fetch …)"` in argument
    # position does not trip errexit: a failed fetch yields an empty string, sh
    # runs nothing and exits 0. Combined with the old ordering — rm -rf first —
    # a transient network failure under FORCE_REINSTALL deleted a working
    # oh-my-zsh and "installed" nothing, silently, and the p10k clone into the
    # empty tree hid it.
    local _omz_installer
    if ! _omz_installer=$(fetch https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh) \
       || [[ -z "$_omz_installer" ]]; then
        log_warning "Could not fetch the oh-my-zsh installer — leaving $zsh_dir untouched"
        return 1
    fi
    rm -rf "$zsh_dir"
    # Unset ZSH so the official installer doesn't refuse when $ZSH points elsewhere
    # (e.g., RunPod containers where /root/.oh-my-zsh exists but HOME=/workspace)
    ZSH="$zsh_dir" run_with_timeout "${DOTFILES_INSTALLER_TIMEOUT:-300}" \
        sh -c "$_omz_installer" "" --unattended

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

# True if we can run privileged apt/dpkg steps without an interactive prompt:
# either we're root, or sudo is available with cached/passwordless credentials.
can_sudo() {
    [[ $EUID -eq 0 ]] && return 0
    cmd_exists sudo && sudo -n true 2>/dev/null
}

# Install current gh from the official GitHub apt repo (cli.github.com), so apt
# manages updates. Needs /etc/apt write access — gate behind can_sudo. Returns
# nonzero on any failure so the caller can fall back to the release binary.
install_gh_from_apt_repo() {
    log_info "Installing gh from official GitHub apt repo..."
    local SUDO=""; [[ $EUID -ne 0 ]] && SUDO="sudo"
    cmd_exists wget || $SUDO apt-get install -y "${APT_LOCK_OPT[@]}" wget 2>/dev/null
    $SUDO mkdir -p -m 755 /etc/apt/keyrings || return 1
    wget -nv --timeout=10 --tries=2 -O- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | $SUDO tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null || return 1
    $SUDO chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | $SUDO tee /etc/apt/sources.list.d/github-cli.list > /dev/null || return 1
    $SUDO apt update "${APT_LOCK_OPT[@]}" 2>/dev/null && $SUDO apt install gh -y "${APT_LOCK_OPT[@]}" 2>/dev/null
}

# Install and authenticate GitHub CLI
# True if installed gh is older than 2.40 (the cutoff below the flags we rely on,
# e.g. --git-protocol on `gh auth login`). jammy's apt ships 2.4.0 → too old.
gh_too_old() {
    cmd_exists gh || return 1
    local ver major minor
    ver="$(gh --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"
    [[ -z "$ver" ]] && return 0  # unparseable → treat as too old, force upgrade
    major="${ver%%.*}"; minor="${ver#*.}"; minor="${minor%%.*}"
    (( major > 2 )) && return 1
    (( major == 2 && minor >= 40 )) && return 1
    return 0
}

# Install a current gh on Linux. Prefer the official GitHub apt repo when we can
# write to /etc/apt (root/sudo) so apt manages updates; otherwise drop to the
# no-sudo release binary in ~/.local/bin. Never use jammy's stale apt package.
install_gh_linux() {
    if can_sudo; then
        install_gh_from_apt_repo || install_gh_from_release
    else
        install_gh_from_release
    fi
}

install_gh_cli() {
    if is_installed gh && ! gh_too_old; then
        # Modern gh present — check authentication only
        if gh auth status &>/dev/null; then
            log_info "gh already authenticated"
            return 0
        fi
    else
        if is_installed gh; then
            log_info "Upgrading outdated GitHub CLI ($(gh --version 2>/dev/null | head -1))..."
        else
            log_info "Installing GitHub CLI..."
        fi
        if is_macos; then
            brew_install gh
        else
            install_gh_linux
        fi
    fi

    # GitHub auth is deferred, never blocking the install on browser OAuth. The
    # component menu is the only interactive step; finish auth afterwards via
    # auth-setup (or `gh auth login`), which gist/secrets sync needs.
    if cmd_exists gh && ! gh auth status &>/dev/null; then
        log_warning "gh not authenticated — run 'auth-setup' (or 'gh auth login') for gist/secrets sync"
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

# ─── Node.js LTS (global runtime, NOT a brew tool on Linux) ───────────────────

# Node is a RUNTIME that other tools shebang against (e.g. obsidian-headless's
# `ob` → #!/usr/bin/env node), so it must resolve on a global PATH that
# systemd/cron contexts see — which Linuxbrew's shell-activated prefix does not.
# Install it globally: NodeSource's setup_lts.x on Linux (the *current LTS* line
# — only even/LTS majors, never an odd "Current" release), brew on macOS; never
# Linuxbrew, which here manages interactive leaf-CLIs only (fzf, bat, …).
#
# The skip-guard floor is the *live* latest-LTS major fetched from nodejs.org
# (fallback 24 = Krypton if offline), NOT a hardcoded number. That keeps two
# promises: never Current (setup_lts.x) and never EOL (an older node always
# fails the guard and gets converged up to current LTS). Consequence: after an
# LTS rollover, re-running install.sh force-upgrades the major (e.g. 24→26) — so
# native modules (better-sqlite3) must be rebuilt against the new ABI afterward.
install_node() {
    # Current LTS major from nodejs.org; dist index is newest-first and r['lts']
    # is the codename (truthy) for LTS releases, false otherwise.
    local want
    want=$(curl -fsSL https://nodejs.org/dist/index.json 2>/dev/null \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(next(r['version'] for r in d if r['lts'])[1:].split('.')[0])" 2>/dev/null)
    [[ "$want" =~ ^[0-9]+$ ]] || want=24
    if is_installed node && (( $(node -v | cut -d. -f1 | tr -d 'v') >= want )); then
        return 0
    fi
    log_info "Installing Node ${want} LTS..."
    if is_macos; then
        brew_install node
        return 0
    fi
    # Linux: NodeSource setup_lts.x adds the repo + runs apt update. Its script
    # can exit non-zero *after* configuring the repo, so we do NOT gate the
    # install on its exit code — doing so once left a box on stock Ubuntu node.
    # Install unconditionally; apt resolves the NodeSource candidate (a higher
    # version than Ubuntu's, so an already-installed nodejs is upgraded in place).
    local SUDO=""; [[ $EUID -ne 0 ]] && SUDO="sudo"
    # An ARRAY, not "$SUDO -E": as root $SUDO is empty and the word simply
    # disappears, leaving `-E bash -`, i.e. an attempt to run a command called
    # `-E`. Measured: `timeout: failed to run command '-E'`, rc 127, swallowed
    # by the `|| log_warning` below — so the NodeSource repo was never added
    # and apt then installed stock Ubuntu node. `-E` is a sudo flag and has no
    # meaning without sudo. This is the README's cloud path (root over ssh).
    local -a _node_setup
    if [[ -n "$SUDO" ]]; then
        _node_setup=(sudo -E bash -)
    else
        _node_setup=(bash -)
    fi
    fetch https://deb.nodesource.com/setup_lts.x \
        | run_with_timeout "${DOTFILES_INSTALLER_TIMEOUT:-300}" "${_node_setup[@]}" \
        || log_warning "NodeSource setup script exited non-zero (repo may still be configured) — continuing"
    $SUDO apt-get install -y "${APT_LOCK_OPT[@]}" nodejs || log_warning "Node install via apt failed — install Node LTS manually"
}

# ─── Linuxbrew (CLI tool manager on Linux) ────────────────────────────────────

# Homebrew is the single source of modern CLI leaf-tools on Linux as well as
# macOS. Two cases both have to end with brew on PATH, and missing the second is
# the subtle one: on a machine where Linuxbrew is already installed, install.sh
# still runs BEFORE the new ~/.zshrc (with its shellenv line) is deployed, so
# `brew` may exist on disk while `cmd_exists brew` is false. Every later
# brew_install would then fail. So activate whenever the binary is present,
# whether or not this call installed it.
LINUXBREW_PREFIX="/home/linuxbrew/.linuxbrew"

install_linuxbrew() {
    if ! is_macos && [[ ! -x "$LINUXBREW_PREFIX/bin/brew" ]]; then
        # Homebrew's installer aborts as root ("Don't run this as root!") on
        # anything it does not detect as a container — /.dockerenv,
        # /run/.containerenv or a docker/kubepods/actions_job cgroup marker. On a
        # plain cloud VM SSH'd into as root (README's cloud path) the install
        # therefore cannot succeed, and every brew-managed tool would be skipped
        # behind a generic "installation failed" warning. Name the cause instead.
        if [[ $EUID -eq 0 ]] \
           && [[ ! -e /.dockerenv && ! -e /run/.containerenv ]] \
           && ! grep -qE '(docker|kubepods|actions_job)' /proc/1/cgroup 2>/dev/null; then
            log_warning "Homebrew refuses to install as root on a non-container host, so the brew-managed CLI tools will be skipped."
            log_warning "  Re-run install.sh as a non-root user (or use --create-user first), then re-run to pick them up."
            return 1
        fi
        log_info "Installing Homebrew (Linuxbrew)..."
        # NONINTERACTIVE=1 skips the installer's "Press RETURN to continue"
        # prompt; install.sh keeps stdin on the TTY for the component menu, so
        # the installer cannot auto-detect non-interactive mode on its own.
        # Both halves need a deadline: the fetch, and the installer it feeds.
        # An installer that stalls hangs the run exactly as hard as a stalled
        # download, and this one runs before anything else on a fresh box.
        local _brew_installer
        if _brew_installer=$(fetch https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh); then
            NONINTERACTIVE=1 run_with_timeout "${DOTFILES_INSTALLER_TIMEOUT:-900}" \
                /bin/bash -c "$_brew_installer" \
                || log_warning "Homebrew (Linuxbrew) installation failed"
        else
            log_warning "Could not fetch the Homebrew installer"
        fi
    fi

    if ! cmd_exists brew && [[ -x "$LINUXBREW_PREFIX/bin/brew" ]]; then
        eval "$("$LINUXBREW_PREFIX/bin/brew" shellenv)"
    fi

    if cmd_exists brew; then
        return 0
    fi

    log_warning "brew not available after bootstrap — skipping brew-managed tools"
    return 1
}

# ─── bun (global JS CLI package manager) ──────────────────────────────────────

# Single installer shared by install.sh and scripts/cleanup/setup_ai_update.sh.
# Exports BUN_INSTALL/PATH into the CALLING shell so the very next `bun add -g`
# resolves without waiting for a new login shell.
install_bun() {
    if cmd_exists bun; then
        return 0
    fi

    if ! cmd_exists curl; then
        log_warning "curl is required to install bun"
        return 1
    fi

    log_info "Installing bun..."
    fetch https://bun.sh/install \
        | run_with_timeout "${DOTFILES_INSTALLER_TIMEOUT:-300}" bash \
        || log_warning "bun installation failed"

    export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
    export PATH="$BUN_INSTALL/bin:$PATH"

    if ! cmd_exists bun; then
        log_warning "bun still not found after install"
        return 1
    fi
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
        apt-get install -y "${APT_LOCK_OPT[@]}" ca-certificates curl gnupg 2>/dev/null || {
            log_warning "Could not install Docker prerequisites"
            return 1
        }

        # Add Docker's official GPG key
        install -m 0755 -d /etc/apt/keyrings
        fetch https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null || {
            # Try Debian if Ubuntu fails
            fetch https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg 2>/dev/null || {
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
        apt-get update -y "${APT_LOCK_OPT[@]}" 2>/dev/null
        apt-get install -y "${APT_LOCK_OPT[@]}" docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || {
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

    # Locate the merge script (same directory as this file, fallback to DOT_DIR)
    local _merge_script
    _merge_script="$(cd "$(dirname "${BASH_SOURCE[0]:-$DOT_DIR/scripts/shared}")" 2>/dev/null && pwd)/merge_authorized_keys.py"
    [[ -f "$_merge_script" ]] || _merge_script="$DOT_DIR/scripts/shared/merge_authorized_keys.py"

    local local_content
    local_content=$(cat "$local_path")

    # mtime-based age label (diagnostic only — not used for base selection)
    local _local_mtime age_days age_label
    _local_mtime=$(stat --format=%Y "$local_path" 2>/dev/null \
                   || stat -f %m "$local_path" 2>/dev/null || echo 0)
    age_days=0
    [[ "$_local_mtime" -gt 0 ]] && age_days=$(( ( $(date +%s) - _local_mtime ) / 86400 ))
    age_label="${age_days}d old"

    # C2: fold authorized_keys_restored if present (RunPod/container pattern)
    # On hetzner this branch never fires (file doesn't exist).
    local _restored_path="$HOME/.ssh/authorized_keys_restored"
    if [[ -f "$_restored_path" ]]; then
        local _tmp_pre _tmp_rst _folded
        _tmp_pre="${TMPDIR:-/tmp}/ak_pre_$$"
        _tmp_rst="${TMPDIR:-/tmp}/ak_rst_$$"
        printf '%s' "$local_content" > "$_tmp_pre"
        cp "$_restored_path" "$_tmp_rst"
        _folded=$(python3 "$_merge_script" "$_tmp_pre" "$_tmp_rst" 2>/dev/null)
        rm -f "$_tmp_pre" "$_tmp_rst"
        if [[ -n "$_folded" ]]; then
            local_content="$_folded"
            mv "$_restored_path" "${_restored_path}.bak"
            log_info "  ↕ Folded authorized_keys_restored into local (archived to .bak)"
        fi
    fi

    if [[ "$local_content" == "$gist_content" ]]; then
        log_info "  ✓ authorized_keys in sync"
        return 1
    fi

    # Union merge: local is always the canonical base.
    # Only genuinely new keys from the gist are added; keys disabled (line-commented)
    # in local remain suppressed even if the gist still lists them as active.
    local merged _tmp_local _tmp_gist
    _tmp_local="${TMPDIR:-/tmp}/ak_local_$$"
    _tmp_gist="${TMPDIR:-/tmp}/ak_gist_$$"
    printf '%s' "$local_content" > "$_tmp_local"
    printf '%s' "$gist_content"  > "$_tmp_gist"
    merged=$(python3 "$_merge_script" "$_tmp_local" "$_tmp_gist" 2>/dev/null)
    rm -f "$_tmp_local" "$_tmp_gist"

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

    # Handle conflicts without prompting: keep existing values (your machine's
    # settings win) and apply only the non-conflicting ones. The component menu
    # is the script's only interactive step; override conflicting keys by hand
    # afterwards if you want the dotfiles values instead.
    if [[ ${#conflicts[@]} -gt 0 ]]; then
        echo ""
        log_warning "Git config conflicts — keeping your existing values:"
        for conflict in "${conflicts[@]}"; do
            IFS='|' read -r key existing new <<< "$conflict"
            echo "  [$key] keeping: $existing   (dotfiles: $new)"
        done
        apply_nonconflicting_git_settings "${conflicts[@]}"
        log_success "Git configuration deployed (conflicting keys left unchanged)"
        return 0
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
        if [[ -z "${wanted_map[${ext:l}]-}" ]]; then
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

# ─── Worktree Guard ───────────────────────────────────────────────────────────

# Abort if DOT_DIR is a linked git worktree rather than the main checkout.
#
# DOT_DIR resolves from the script's own location, so running install.sh or
# deploy.sh from a worktree bakes the worktree path into ~/.claude and ~20 other
# user-level symlinks plus every launchd/cron job. The worktree is then deleted
# by cwrm/cwclean, and gitignored runtime state (plugin registry, credentials)
# only ever exists in the main checkout — so Claude Code silently loses its
# plugins and asks for a fresh login.
#
# Canonicalise a path printed by `git rev-parse --git-dir` / `--git-common-dir`.
# Those print relative to the -C directory unless already absolute, and older
# git echoes an unrecognised option back verbatim — resolving through `cd`
# turns every one of those cases into empty output, which the caller treats as
# "detection failed" rather than "not a worktree".
_resolve_git_dir() {
    local path="$1"
    [[ -z "$path" ]] && return 0
    [[ "$path" != /* ]] && path="$DOT_DIR/$path"
    (cd "$path" 2>/dev/null && pwd -P)
}

# Usage: guard_not_worktree "$0" "$@"
guard_not_worktree() {
    local invoked_as="$1"; shift

    local arg
    for arg in "$@"; do
        case "$arg" in
            --allow-worktree|-h|--help) return 0 ;;
        esac
    done

    local script_name
    script_name="$(basename "$invoked_as")"

    # Not a git repo at all (tarball or curl|bash install) — nothing to guard.
    git -C "$DOT_DIR" rev-parse --git-dir >/dev/null 2>&1 || return 0

    # A linked worktree has its own .git dir distinct from the shared common dir.
    # Both queries return paths relative to DOT_DIR when not already absolute;
    # canonicalise so the comparison is not defeated by symlinks or `..`.
    local git_dir common_dir
    git_dir="$(_resolve_git_dir "$(git -C "$DOT_DIR" rev-parse --git-dir 2>/dev/null)")"
    common_dir="$(_resolve_git_dir "$(git -C "$DOT_DIR" rev-parse --git-common-dir 2>/dev/null)")"

    # Inside a repo but detection failed — old git without --git-common-dir, a
    # safe.directory rejection, an unreadable path. Fail closed: an unusable
    # probe is exactly the case where an unnoticed worktree deploy does damage.
    if [[ -z "$git_dir" || -z "$common_dir" ]]; then
        cat >&2 <<EOF

✗ Refusing to run $script_name: cannot tell whether DOT_DIR is a git worktree.

  DOT_DIR:
    $DOT_DIR

  \`git rev-parse --git-dir / --git-common-dir\` did not return a usable path.
  Running from a worktree would repoint ~/.claude and ~20 other user-level
  symlinks at a directory cwrm/cwclean will later delete, so this refuses
  rather than guesses.

  If this is the main checkout, pass --allow-worktree.

EOF
        exit 1
    fi

    [[ "$git_dir" == "$common_dir" ]] && return 0

    local main_checkout
    main_checkout="$(dirname "$common_dir")"

    cat >&2 <<EOF

✗ Refusing to run $script_name from a git worktree.

  DOT_DIR resolved to the worktree:
    $DOT_DIR

  Running from here would repoint ~/.claude and ~20 other user-level symlinks
  at this worktree, and bake its path into scheduled jobs. Removing the
  worktree later would break all of them.

  Run from the main checkout instead (absolute path matters):
    $main_checkout/$script_name $*

  To override anyway, pass --allow-worktree.

EOF
    exit 1
}

# ─── CLI Argument Parsing ─────────────────────────────────────────────────────

# Parse CLI arguments and override config
# Usage: parse_args "$@"
parse_args() {
    # --only accumulator (deferred two-pass parsing)
    typeset -a _only_components
    _only_components=()
    local _only_mode=false

    # Components the user named with an explicit `--no-<x>`. A component that must
    # UNINSTALL when deselected cannot read DEPLOY_<X>=false to decide that:
    # --only and --minimal set every other component false too, so an unrelated
    # `--only vim` would tear down installed jobs it never mentioned. "Not
    # selected" and "explicitly refused" are different questions; this answers
    # the second. Names are uppercased with underscores, as DEPLOY_<X> is.
    typeset -ga EXPLICIT_OPT_OUTS
    EXPLICIT_OPT_OUTS=()

    # The mirror image, and it answers a question DEPLOY_<X>=true cannot: "did the
    # user ask for this on THIS invocation?" The resolved boolean conflates a CLI
    # flag with a profile default and with a persistent config.local.sh override,
    # which is sourced before parse_args runs. A component that grants standing
    # permission to do something destructive must key off provenance, not off the
    # resolved value - otherwise a one-time `DEPLOY_X=true` written into
    # config.local.sh years ago silently re-consents on every later plain deploy.
    # Populated by the `--<x>` branch and by --only, which names components just
    # as explicitly. Currently read only by the hide-idle-apps escalation token.
    typeset -ga EXPLICIT_OPT_INS
    EXPLICIT_OPT_INS=()

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
            --allow-worktree)
                # Consumed by guard_not_worktree before parse_args runs.
                # Accepted here as a no-op so it composes with --only.
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
            --cloud)
                if [[ "$_only_mode" == true ]]; then
                    echo "Error: --only cannot be mixed with profile or component flags" >&2
                    exit 1
                fi
                apply_profile "cloud"
                ;;
            --personal|--devbox)
                if [[ "$_only_mode" == true ]]; then
                    echo "Error: --only cannot be mixed with profile or component flags" >&2
                    exit 1
                fi
                apply_profile "devbox"
                ;;
            --standard|--agent|--bare)
                # Explicit cases: the --* catch-all below would otherwise mangle
                # a profile name into a bogus DEPLOY_<NAME> component.
                if [[ "$_only_mode" == true ]]; then
                    echo "Error: --only cannot be mixed with profile or component flags" >&2
                    exit 1
                fi
                apply_profile "${1#--}"
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
                # Skip the component menu and install the default component set.
                # The menu is the script's only prompt — everything after it
                # already runs with safe defaults — so this is the sole knob.
                # Exported so child processes (e.g. app-picker) honor it.
                NON_INTERACTIVE=true
                export NON_INTERACTIVE
                ;;
            --allow-worktree-deploy)
                # Opt out of deploy.sh's worktree guard. Not a component, so it
                # needs its own case — the --* catch-all below would both mangle
                # it into a DEPLOY_* variable and collide with --only.
                ALLOW_WORKTREE_DEPLOY=true
                export ALLOW_WORKTREE_DEPLOY
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
                EXPLICIT_OPT_OUTS+=("$component")
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
                EXPLICIT_OPT_INS+=("$component")
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
            # Naming a component in --only is as explicit as `--<x>`, so it counts
            # as fresh opt-in. Note apply_profile("minimal") above set everything
            # false first, so only the named components land here.
            EXPLICIT_OPT_INS+=("$_comp_upper")
        done
    fi
}
