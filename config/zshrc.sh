CONFIG_DIR=$(dirname $(realpath ${(%):-%x}))
DOT_DIR=${CONFIG_DIR:h}

# User-customizable directory locations (override in ~/.zshenv or config/secrets.sh)
CODE_DIR="${CODE_DIR:-$HOME/code}"           # Primary code projects
WRITING_DIR="${WRITING_DIR:-$HOME/writing}"  # Writing projects (papers, notes)
SCRATCH_DIR="${SCRATCH_DIR:-$HOME/scratch}"  # Temporary experimentation
PROJECTS_DIR="${PROJECTS_DIR:-$HOME/projects}"  # General projects
VAULT_DIR="${VAULT_DIR:-$HOME/vault}"        # Personal vault (research artifacts, notes)

# Homebrew (Apple Silicon): prepend so /opt/homebrew/bin beats /usr/bin.
# Uses brew shellenv (not add_to_path) because /opt/homebrew/bin is already
# appended late by macOS path_helper, which would make add_to_path a no-op.
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Homebrew (Linuxbrew): CLI tools (rg, fd, eza, bat, ...) live here on Linux.
# Activated EARLY on purpose: config/modern_tools.sh (sourced below) gates its
# eza/bat/fd/rg aliases on `command -v`, and the vivid LS_COLORS block does the
# same, so brew must be on PATH before them. Precedence is re-asserted at the
# bottom of this file, after the add_to_path/cargo prepends.
# HOMEBREW_PREFIX guard: a deployed ~/.zshrc may already carry a manual
# `brew shellenv` line above the source line — skip re-activation then.
if [[ -x /home/linuxbrew/.linuxbrew/bin/brew && -z "$HOMEBREW_PREFIX" ]]; then
  eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# Instant prompt
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi
export TERM="xterm-256color"
# mosh (through 1.4.0) garbles 24-bit truecolor SGR escapes — background colors
# smear and foreground text becomes invisible (mobile-shell/mosh#649, #1333).
# Advertise truecolor only off-mosh; under mosh leave COLORTERM unset so apps
# fall back to 256-color, which mosh renders correctly.
_under_mosh() {
  local p=$PPID comm
  while (( p > 1 )); do
    if [[ -r /proc/$p/comm ]]; then          # Linux: no fork
      comm=$(</proc/$p/comm)
      [[ $comm == mosh-server ]] && return 0
      p=${$(grep -m1 '^PPid:' /proc/$p/status 2>/dev/null)//[^0-9]/}
    else                                      # macOS/BSD fallback
      comm=$(ps -o comm= -p $p 2>/dev/null) || return 1
      [[ $comm == *mosh-server* ]] && return 0
      p=${$(ps -o ppid= -p $p 2>/dev/null)//[^0-9]/}
    fi
    [[ -z $p || $p == 0 ]] && return 1
  done
  return 1
}
if _under_mosh; then
  unset COLORTERM
else
  export COLORTERM="truecolor"
fi
unfunction _under_mosh

# Editor — reads from macos_default_apps.conf (single source of truth)
_fa_conf="$DOT_DIR/config/macos_default_apps.conf"
if [[ -f "$_fa_conf" ]]; then
  # Source only the EDITOR_CLI* variables (fast, no array eval)
  EDITOR_CLI=$(sed -n 's/^EDITOR_CLI="\(.*\)"/\1/p' "$_fa_conf" | head -1)
  EDITOR_CLI_SSH=$(sed -n 's/^EDITOR_CLI_SSH="\(.*\)"/\1/p' "$_fa_conf" | head -1)
fi
if [[ -n $SSH_CONNECTION ]]; then
  export EDITOR="${EDITOR_CLI_SSH:-edit}"
else
  export EDITOR="${EDITOR_CLI:-cursor --wait}"
fi
export VISUAL="$EDITOR"
unset _fa_conf EDITOR_CLI EDITOR_CLI_SSH

# Claude Code tmpdir - avoid root-owned /tmp/claude issues
if [[ -n "$TMPDIR" && -w "$TMPDIR" ]]; then
    # Explicit TMPDIR takes priority (cloud environments, user preference)
    export CLAUDE_CODE_TMPDIR="$TMPDIR/claude"
elif [[ -d "/run/user/$(id -u)" && -w "/run/user/$(id -u)" ]]; then
    # Linux: XDG runtime dir (per-user tmpfs, mode 0700)
    export CLAUDE_CODE_TMPDIR="/run/user/$(id -u)/claude"
else
    # Fallback: home dir (always writable, survives reboots)
    export CLAUDE_CODE_TMPDIR="$HOME/tmp/claude"
fi

# RunPod/container: allow Claude Code bypass-permissions as root
if [[ "$(id -u)" == "0" ]] && { [[ -n "$RUNPOD_POD_ID" ]] || [[ -d /workspace ]]; }; then
    export IS_SANDBOX=1
fi

ZSH_DISABLE_COMPFIX=true
ZSH_THEME="powerlevel10k/powerlevel10k"
ZSH=$HOME/.oh-my-zsh

plugins=(zsh-autosuggestions zsh-syntax-highlighting zsh-completions zsh-history-substring-search zsh-shift-select)

# oh-my-zsh's lib/grep.zsh + custom/*.zsh(N) use bare glob qualifiers; re-sourcing
# can leave bareglobqual off (residual state from a prior load) causing "no matches found".
# Setting it here makes `source ~/.zshrc` safe to run in an already-running shell.
setopt bareglobqual
if [ -f "$ZSH/oh-my-zsh.sh" ]; then
  source "$ZSH/oh-my-zsh.sh"
fi
# Disable AUTO_CD (oh-my-zsh's lib/directories.zsh enables it) — require explicit cd
unsetopt AUTO_CD
# Source all themed alias files (config/aliases/*.sh)
for _aliases_file in "$CONFIG_DIR"/aliases/*.sh; do
  # shellcheck source=/dev/null
  source "$_aliases_file"
done
unset _aliases_file
[ -f $CONFIG_DIR/secrets.sh ] && source $CONFIG_DIR/secrets.sh
source $CONFIG_DIR/ssh_setup.sh
source $CONFIG_DIR/p10k.zsh
source $CONFIG_DIR/extras.sh
source $CONFIG_DIR/modern_tools.sh
source $CONFIG_DIR/key_bindings.sh
source $CONFIG_DIR/ssh_themes.sh
source $CONFIG_DIR/completions.sh
add_to_path "${DOT_DIR}/custom_bins"

# Machine auto-registration: prompt once on unregistered machines (interactive shells only)
if [[ -o interactive && ! -f "${HOME}/.cache/machine-register-prompted" ]]; then
  _machine_registry="${DOT_DIR}/config/machines.conf"
  _machine_id=""
  if [[ -f /etc/machine-id ]]; then
    _machine_id=$(cat /etc/machine-id)
  elif command -v ioreg >/dev/null 2>&1; then
    _machine_id=$(ioreg -rd1 -c IOPlatformExpertDevice 2>/dev/null | awk -F'"' '/IOPlatformUUID/{print $4}' | tr '[:upper:]' '[:lower:]')
  fi
  if [[ -n "$_machine_id" && -f "$_machine_registry" ]] && ! grep -q "^${_machine_id}|" "$_machine_registry" 2>/dev/null; then
    printf '\n🆕 Unregistered machine detected (hostname: %s)\n' "${HOST:-$(hostname -s)}"
    printf '   Run \033[1mmachine-register\033[0m to name this machine for prompt/statusline display.\n\n'
    mkdir -p "${HOME}/.cache"
    touch "${HOME}/.cache/machine-register-prompted"
  fi
  unset _machine_registry _machine_id
fi

# Add ~/.local/bin to PATH (for Claude Code, gh, gitleaks, uv tools)
add_to_path "$HOME/.local/bin"

# bun - fast JavaScript runtime and package manager (preferred on Linux)
[[ -d "$HOME/.bun/bin" ]] && add_to_path "$HOME/.bun/bin"

# Add plotting library to PYTHONPATH (anthro_colors, petriplot)
if [[ -d "$HOME/.local/lib/plotting" ]]; then
    export PYTHONPATH="$HOME/.local/lib/plotting:${PYTHONPATH}"
fi

# LS_COLORS — use vivid with catppuccin-mocha theme (matches Ghostty terminal theme)
# Fixes unreadable directory colors (default ow=34;42 is blue-on-green)
if command -v vivid &>/dev/null; then
    export LS_COLORS="$(vivid generate catppuccin-mocha)"
fi

# ripgrep config — skip git's global ignore (has research patterns), use universal-only ignore
[[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/ripgrep/config" ]] && \
    export RIPGREP_CONFIG_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/ripgrep/config"

# Source uv environment if installed
[ -f "$HOME/.local/bin/env" ] && source "$HOME/.local/bin/env"

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
if [ -d "$HOME/.cargo" ]; then
  . "$HOME/.cargo/env"
fi

# Linuxbrew precedence, re-asserted last. The shellenv near the top of this file
# runs BEFORE the add_to_path calls and ~/.cargo/env, each of which prepends —
# without this, brew's tools would sit below ~/.cargo/bin, ~/.local/bin and
# ~/.bun/bin, flipping the order a deployed shell has today (brew's gitui and
# just currently win over cargo's and uv's). Re-running `brew shellenv` cannot
# fix it: it emits no PATH export once the prefix is already on PATH. Linuxbrew
# only — macOS ordering is left to path_helper + the /opt/homebrew shellenv.
if [[ -n "$HOMEBREW_PREFIX" && "$HOMEBREW_PREFIX" == /home/linuxbrew/* ]]; then
  path=("$HOMEBREW_PREFIX/bin" "$HOMEBREW_PREFIX/sbin" ${${path:#$HOMEBREW_PREFIX/bin}:#$HOMEBREW_PREFIX/sbin})
fi

# zoxide (smarter cd - use 'z' command, not replacing cd)
command -v zoxide &> /dev/null && eval "$(zoxide init zsh)"

# direnv — auto-load .envrc per-directory (SOPS secrets, env vars)
command -v direnv &>/dev/null && eval "$(direnv hook zsh)"

if [ -d "$HOME/.local/bin/micromamba" ]; then
  export MAMBA_EXE="$HOME/.local/bin/micromamba"
  export MAMBA_ROOT_PREFIX="$HOME/micromamba"
  __mamba_setup="$("$MAMBA_EXE" shell hook --shell zsh --root-prefix "$MAMBA_ROOT_PREFIX" 2> /dev/null)"
  if [ $? -eq 0 ]; then
      eval "$__mamba_setup"
  else
      alias micromamba="$MAMBA_EXE"  # Fallback on help from mamba activate
  fi
  unset __mamba_setup
fi

if command -v ask-sh &> /dev/null; then
  ASK_SH_OPENAI_API_KEY=$(cat $HOME/.openai_api_key 2>/dev/null)
  ASK_SH_OPENAI_MODEL=gpt-4o-mini
  eval "$(ask-sh --init)"
fi

# Reset terminal modes that may be left enabled after ungraceful process exit
# (e.g., SSH disconnect while running mouse-enabled app like tmux/vim/htop)
# _reset_terminal_modes_soft: safe for precmd (no alt screen exit — that can wipe display)
# _reset_terminal_modes: full reset including alt screen, for manual fix-term / sshc
_reset_terminal_modes_soft() {
    [[ -t 1 ]] || return
    local reset=''
    reset+='\e[?1000l'  # mouse click tracking
    reset+='\e[?1002l'  # mouse button-event tracking
    reset+='\e[?1003l'  # mouse any-event tracking
    reset+='\e[?1006l'  # SGR mouse mode (the 35M sequences)
    reset+='\e[?1007l'  # alternate scroll mode (scroll → arrow keys)
    reset+='\e[?1004l'  # focus event reporting
    reset+='\e[?2004l'  # bracketed paste mode
    reset+='\e[?1l'     # application cursor keys
    reset+='\e[?66l'    # application keypad mode
    reset+='\e[?25h'    # cursor visible
    reset+='\e(B'       # ASCII charset
    printf "$reset"
}
_reset_terminal_modes() {
    _reset_terminal_modes_soft
    [[ -t 1 ]] && printf '\e[?1049l'  # exit alternate screen buffer
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd _reset_terminal_modes_soft
# Exit alt screen once at shell startup (recovers scrollback after SSH disconnect;
# mid-session kill -9 of alt-screen apps needs manual fix-term)
_reset_terminal_modes

# Only display ASCII art in interactive shells
if [[ -o interactive ]]; then
  cat $CONFIG_DIR/start.txt
fi

fs() {
    # Check if user is asking for help
    if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
        find-session --help
        return
    fi
    # Run find-session in shell mode and evaluate the output
    eval "$(find-session --shell "$@" | sed '/^$/d')"
}

# Auto-activate .venv on shell startup (same as cd behavior)
activate_venv
